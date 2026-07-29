import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../ai/live_proof_engine.dart';
import '../ai/pose_detector_service.dart';
import '../ai/universal_live_proof_validator.dart';
import '../data/race_models.dart';
import '../data/universal_proof_rule.dart';
import '../domain/motion_activity.dart';
import 'board_moved_screen.dart';
import 'race_controller.dart';

class UniversalAiProofScreen extends ConsumerStatefulWidget {
  const UniversalAiProofScreen({super.key, required this.raceId});

  final String raceId;

  @override
  ConsumerState<UniversalAiProofScreen> createState() =>
      _UniversalAiProofScreenState();
}

class _UniversalAiProofScreenState extends ConsumerState<UniversalAiProofScreen>
    with WidgetsBindingObserver {
  final _uuid = const Uuid();
  final _poseDetector = PoseDetectorService();
  CameraController? _cameraController;
  List<CameraDescription> _cameras = const [];
  CameraDescription? _selectedCamera;
  Timer? _popTimer;
  Race? _race;
  LiveProofEngine? _engine;
  bool _loading = true;
  bool _recording = false;
  bool _submitting = false;
  bool _readingFrame = false;
  bool _switchingCamera = false;
  String? _message;
  int _popAmount = 0;
  int _popSequence = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _popTimer?.cancel();
    unawaited(_stopImageStream());
    _cameraController?.dispose();
    unawaited(_poseDetector.dispose());
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final race = await ref
          .read(raceControllerProvider.notifier)
          .getRaceDetail(widget.raceId);
      final rule = UniversalProofRule.fromDescription(race.description);
      final definition = universalLiveProofActivityDefinition(
        activityId: race.activityId ?? race.aiActivityType ?? 'universal_ai',
        title: race.displayTitle,
        metric: RaceMetric.reps,
        unit: rule?.unit ?? 'actions',
        defaultTarget: race.targetValue ?? 1,
        proofPrompt: _proofPrompt(race),
        minimumConfidence: rule?.confidenceThreshold ?? 0.72,
        motionSignature: rule?.motionSignature,
      );
      final engine = LiveProofEngine(
        activity: definition,
        targetValue: race.targetValue ?? definition.defaultTarget,
      );
      if (!mounted) return;
      setState(() {
        _race = race;
        _engine = engine;
      });
      await _initializeCamera();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Nuvo AI proof could not load.';
        _loading = false;
      });
    }
  }

  Future<void> _initializeCamera([CameraDescription? preferred]) async {
    await _stopImageStream();
    final oldController = _cameraController;
    CameraController? nextController;
    var oldControllerDisposed = false;
    if (mounted) {
      setState(() {
        _loading = true;
        _cameraController = null;
      });
    }
    try {
      final cameras = _cameras.isEmpty ? await availableCameras() : _cameras;
      if (!mounted) {
        await oldController?.dispose();
        oldControllerDisposed = true;
        return;
      }
      if (cameras.isEmpty) {
        await oldController?.dispose();
        oldControllerDisposed = true;
        setState(() {
          _message = 'No camera is available.';
          _loading = false;
        });
        return;
      }
      _cameras = cameras;
      final selected =
          preferred ??
          cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.back,
            orElse: () => cameras.first,
          );
      await oldController?.dispose();
      oldControllerDisposed = true;
      if (!mounted) return;
      final controller = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.nv21,
      );
      nextController = controller;
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _selectedCamera = selected;
        _message ??= 'Camera is ready.';
        _loading = false;
      });
    } catch (error) {
      if (!oldControllerDisposed) await oldController?.dispose();
      await nextController?.dispose();
      if (!mounted) return;
      setState(() {
        _cameraController = null;
        _message = _cameraErrorMessage(error);
        _loading = false;
      });
    }
  }

  Future<void> _flipCamera() async {
    if (_loading ||
        _recording ||
        _readingFrame ||
        _switchingCamera ||
        _cameras.length < 2) {
      return;
    }
    final current = _selectedCamera;
    final next = _cameras.firstWhere(
      (camera) => camera.name != current?.name,
      orElse: () => _cameras.first,
    );
    setState(() {
      _switchingCamera = true;
      _message = 'Switching camera.';
    });
    try {
      await _initializeCamera(next);
    } finally {
      if (mounted) setState(() => _switchingCamera = false);
    }
  }

  void _start() {
    final engine = _engine;
    final controller = _cameraController;
    if (engine == null ||
        controller == null ||
        !controller.value.isInitialized ||
        _loading ||
        _switchingCamera ||
        _recording) {
      return;
    }
    engine.start();
    setState(() {
      _recording = true;
      _message = 'Nuvo is reading your motion on this phone.';
      _popAmount = 0;
    });
    controller
        .startImageStream((image) {
          _handlePoseFrame(image, controller);
        })
        .catchError((Object error) {
          if (!mounted) return;
          setState(() {
            _recording = false;
            _message = 'Recording could not start.';
          });
        });
  }

  Future<void> _handlePoseFrame(
    CameraImage image,
    CameraController controller,
  ) async {
    final engine = _engine;
    if (!_recording ||
        _readingFrame ||
        engine == null ||
        !controller.value.isInitialized ||
        _switchingCamera) {
      return;
    }
    final camera = _selectedCamera;
    if (camera == null) return;
    _readingFrame = true;
    try {
      final frame = await _poseDetector.processCameraImage(
        image: image,
        camera: camera,
        deviceOrientation: controller.value.deviceOrientation,
      );
      if (frame == null) return;
      final previous = engine.currentValue;
      final update = engine.updatePose(frame);
      if (engine.currentValue > previous) {
        _showPop(engine.currentValue - previous);
      }
      if (mounted) {
        setState(() {
          _message = update.feedback;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Nuvo missed that frame. Keep going.');
      }
    } finally {
      _readingFrame = false;
    }
  }

  Future<void> _finish() async {
    if (_submitting) return;
    await _stopImageStream();
    final race = _race;
    final engine = _engine;
    if (race == null || engine == null) return;
    final result = engine.finish();
    if (!result.isVerified) {
      setState(() {
        _recording = false;
        _message =
            'Nuvo counted ${result.value} of ${result.targetValue}. Run it back with a clearer frame.';
      });
      return;
    }
    setState(() => _submitting = true);
    try {
      final updatedRace = await ref
          .read(raceRepositoryProvider)
          .submitUniversalAiProof(
            race.id,
            clientSubmissionId: _uuid.v4(),
            activityType: result.activityId,
            metric: race.metric ?? 'reps',
            value: result.value,
            targetValue: result.targetValue,
            confidence: result.confidence,
            verificationStatus: result.verificationStatus,
            verificationSummary: result.verificationSummary,
            framesAnalyzed: result.framesAnalyzed,
            validSignalFrames: result.validSignalFrames,
            durationMs: result.durationMs,
            validatorVersion: result.validatorVersion,
          );
      ref.read(raceControllerProvider.notifier).upsertRace(updatedRace);
      if (!mounted) return;
      final submission = updatedRace.submissionResult;
      context.go(
        '/race/${race.id}/board-moved',
        extra: BoardMovedArgs(
          raceId: race.id,
          raceName: updatedRace.displayTitle,
          value: submission?.verifiedValue ?? result.value,
          unit: updatedRace.unit,
          status: 'ai_verified',
          rankBefore: submission?.previousRank,
          rankAfter: submission?.newRank,
          peoplePassed: submission?.peoplePassed,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _message = 'Proof could not move the board. Try again.';
      });
    }
  }

  Future<void> _stopImageStream() async {
    final controller = _cameraController;
    if (controller != null &&
        controller.value.isInitialized &&
        controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
  }

  void _showPop(int amount) {
    _popTimer?.cancel();
    setState(() {
      _popAmount = amount;
      _popSequence++;
    });
    _popTimer = Timer(const Duration(milliseconds: 1250), () {
      if (mounted) setState(() => _popAmount = 0);
    });
  }

  String _proofPrompt(Race race) {
    final rule = UniversalProofRule.fromDescription(race.description);
    if (rule != null) return rule.promptText;
    final description = race.description?.trim();
    if (description != null && description.isNotEmpty) {
      return description
          .replaceAll(
            RegExp(
              '$universalProofRuleStart.*$universalProofRuleEnd',
              dotAll: true,
            ),
            '',
          )
          .trim();
    }
    return 'Count one clean action for this race: ${race.displayTitle}.';
  }

  @override
  Widget build(BuildContext context) {
    final race = _race;
    final engine = _engine;
    final controller = _cameraController;
    final current = engine?.currentValue ?? 0;
    final target = engine?.targetValue ?? race?.targetValue ?? 1;

    return Scaffold(
      backgroundColor: NuvoColors.page,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: _recording
              ? NuvoPrimaryButton(
                  label: _submitting ? 'Moving board' : 'Lock proof',
                  icon: Icons.check_rounded,
                  expand: true,
                  loading: _submitting,
                  onPressed: _submitting ? null : _finish,
                )
              : NuvoPrimaryButton(
                  label: 'Start Nuvo AI Proof',
                  icon: Icons.auto_awesome_rounded,
                  expand: true,
                  onPressed: _loading || _switchingCamera || controller == null
                      ? null
                      : _start,
                ),
        ),
      ),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Row(
                    children: [
                      NuvoBackButton(
                        onPressed: () => safePopOrGo(
                          context,
                          '/race/${widget.raceId}/proof',
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Nuvo AI Proof',
                              style: AppTextStyles.titleLarge,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              race?.displayTitle ??
                                  'Sample frames. Count clean actions.',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: NuvoColors.muted,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (_cameras.length > 1)
                        IconButton.filled(
                          onPressed:
                              _loading ||
                                  _recording ||
                                  _readingFrame ||
                                  _switchingCamera
                              ? null
                              : _flipCamera,
                          style: IconButton.styleFrom(
                            backgroundColor: NuvoColors.navy,
                            foregroundColor: NuvoColors.white,
                          ),
                          icon: const Icon(Icons.cameraswitch_rounded),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      decoration: BoxDecoration(
                        color: NuvoColors.navy,
                        borderRadius: BorderRadius.circular(NuvoRadii.hero),
                        boxShadow: AppShadows.heroShadow,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_loading)
                            const Center(
                              child: CircularProgressIndicator(
                                color: NuvoColors.white,
                              ),
                            )
                          else if (controller != null &&
                              controller.value.isInitialized)
                            _CameraStagePreview(controller: controller)
                          else
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(28),
                                child: Text(
                                  _message ?? 'Camera is not ready.',
                                  style: AppTextStyles.bodyLarge.copyWith(
                                    color: NuvoColors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          Positioned(
                            left: 14,
                            right: 14,
                            top: 14,
                            child: Row(
                              children: [
                                _pill('$current / $target actions'),
                                const Spacer(),
                                _pill(_readingFrame ? 'Reading' : 'Ready'),
                              ],
                            ),
                          ),
                          Positioned(
                            left: 14,
                            right: 14,
                            bottom: 14,
                            child: _coachBar(
                              _message ??
                                  'Keep the action in frame. Nuvo checks every few seconds.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
            if (_recording && _popAmount > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: _UniversalPlusPop(
                    key: ValueKey(_popSequence),
                    amount: _popAmount,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: NuvoColors.navy.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(NuvoRadii.pill),
        border: Border.all(color: NuvoColors.white.withValues(alpha: 0.16)),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: NuvoColors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _coachBar(String label) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NuvoColors.navy.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(NuvoRadii.md),
        border: Border.all(color: NuvoColors.white.withValues(alpha: 0.16)),
      ),
      child: Text(
        label,
        style: AppTextStyles.titleMedium.copyWith(color: NuvoColors.white),
        textAlign: TextAlign.center,
      ),
    );
  }

  String _cameraErrorMessage(Object error) {
    if (error is CameraException) {
      final detail = error.description ?? error.code;
      return detail.trim().isEmpty
          ? 'Camera could not start.'
          : 'Camera could not start: $detail';
    }
    return 'Camera could not start.';
  }
}

class _CameraStagePreview extends StatelessWidget {
  const _CameraStagePreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return CameraPreview(controller);
    final portraitSize = Size(previewSize.height, previewSize.width);
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: portraitSize.width,
            height: portraitSize.height,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }
}

class _UniversalPlusPop extends StatelessWidget {
  const _UniversalPlusPop({super.key, required this.amount});

  final int amount;
  static const _green = Color(0xFF20C66B);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: NuvoColors.navy.withValues(alpha: 0.18),
      alignment: Alignment.center,
      child:
          Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
                decoration: BoxDecoration(
                  color: _green,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: NuvoColors.navy, width: 4),
                  boxShadow: const [
                    BoxShadow(
                      color: NuvoColors.navy,
                      blurRadius: 0,
                      offset: Offset(8, 8),
                    ),
                  ],
                ),
                child: Text(
                  '+$amount',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.displayLarge.copyWith(
                    color: NuvoColors.white,
                    fontSize: 116,
                    fontWeight: FontWeight.w900,
                    height: 0.88,
                    letterSpacing: 0,
                  ),
                ),
              )
              .animate()
              .slideY(
                begin: 0.45,
                end: 0,
                duration: 300.ms,
                curve: Curves.easeOutBack,
              )
              .scale(
                begin: const Offset(0.78, 0.78),
                end: const Offset(1, 1),
                duration: 300.ms,
                curve: Curves.easeOutBack,
              )
              .fadeIn(duration: 160.ms)
              .then(delay: 900.ms)
              .fadeOut(duration: 180.ms),
    );
  }
}
