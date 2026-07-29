import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../ai/local_motion_signature.dart';
import '../ai/pose_detector_service.dart';
import '../data/ai_motion_models.dart';
import '../data/race_models.dart';
import '../data/universal_proof_rule.dart';
import '../domain/race_draft.dart';
import 'race_controller.dart';

class TeachNuvoArgs {
  const TeachNuvoArgs({required this.draft, required this.actionName});

  final RaceDraft draft;
  final String actionName;
}

enum _TeachStep { clean, reject, review }

class TeachNuvoScreen extends ConsumerStatefulWidget {
  const TeachNuvoScreen({super.key, required this.args});

  final TeachNuvoArgs args;

  @override
  ConsumerState<TeachNuvoScreen> createState() => _TeachNuvoScreenState();
}

class _TeachNuvoScreenState extends ConsumerState<TeachNuvoScreen> {
  final _poseDetector = PoseDetectorService();
  CameraController? _cameraController;
  List<CameraDescription> _cameras = const [];
  CameraDescription? _selectedCamera;
  _TeachStep _step = _TeachStep.clean;
  bool _loadingCamera = true;
  bool _switchingCamera = false;
  bool _busy = false;
  String? _message;
  List<NuvoPoseFrame> _positiveFrames = const [];
  List<NuvoPoseFrame> _negativeFrames = const [];
  UniversalProofRule? _rule;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    unawaited(_stopImageStream());
    _cameraController?.dispose();
    unawaited(_poseDetector.dispose());
    super.dispose();
  }

  Future<void> _initializeCamera([CameraDescription? preferred]) async {
    await _stopImageStream();
    final oldController = _cameraController;
    CameraController? nextController;
    var oldControllerDisposed = false;
    if (mounted) {
      setState(() {
        _loadingCamera = true;
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
          _loadingCamera = false;
          _message = 'No camera is available.';
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
        _loadingCamera = false;
        _message = _stepCopy;
      });
    } catch (error) {
      if (!oldControllerDisposed) await oldController?.dispose();
      await nextController?.dispose();
      if (!mounted) return;
      setState(() {
        _cameraController = null;
        _loadingCamera = false;
        _message = _cameraErrorMessage(error);
      });
    }
  }

  Future<void> _flipCamera() async {
    if (_busy || _loadingCamera || _switchingCamera || _cameras.length < 2) {
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

  Future<List<NuvoPoseFrame>> _recordPoseClip() async {
    final controller = _cameraController;
    if (_loadingCamera ||
        _switchingCamera ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.isStreamingImages) {
      return const [];
    }
    final camera = _selectedCamera;
    if (camera == null) return const [];

    final frames = <NuvoPoseFrame>[];
    await controller.startImageStream((image) async {
      final frame = await _poseDetector.processCameraImage(
        image: image,
        camera: camera,
        deviceOrientation: controller.value.deviceOrientation,
      );
      if (frame != null && frame.points.length >= 6) frames.add(frame);
    });
    await Future<void>.delayed(const Duration(milliseconds: 3600));
    await _stopImageStream();
    return frames;
  }

  Future<void> _stopImageStream() async {
    final controller = _cameraController;
    if (controller != null &&
        controller.value.isInitialized &&
        controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
  }

  Future<void> _captureClean() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = 'Recording a clean motion clip.';
    });
    try {
      final frames = await _recordPoseClip();
      if (frames.length < 6) throw StateError('not_enough_pose_frames');
      setState(() {
        _positiveFrames = frames;
        _step = _TeachStep.reject;
        _message = _stepCopy;
      });
    } catch (_) {
      setState(() => _message = 'Nuvo missed that capture. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _captureRejectAndBuild() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = 'Recording a reject motion clip.';
    });
    try {
      final frames = await _recordPoseClip();
      if (frames.length < 4) throw StateError('not_enough_pose_frames');
      setState(() {
        _negativeFrames = frames;
        _message = 'Nuvo is building the local motion signature.';
      });
      await _buildRule();
    } catch (_) {
      setState(() => _message = 'Nuvo missed that capture. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buildRule() async {
    final signature = LocalMotionSignature.fromFrames(
      actionName: widget.args.actionName,
      cleanFrames: _positiveFrames,
      rejectFrames: _negativeFrames,
    );
    final rule = UniversalProofRule(
      version: 'nuvo-universal-rule-v1',
      unit: widget.args.actionName,
      countRule:
          'Count one ${widget.args.actionName} when the taught motion reaches its finish shape and then resets.',
      rejectRule:
          'Reject partial movement, poor framing, repeated end poses, and motion that matches the reject clip.',
      framingTip: 'Keep the same camera angle and show the full body.',
      promptText:
          'Use the local motion signature for ${widget.args.actionName}. Do not require video upload.',
      confidenceThreshold: 0.62,
      motionSignature: signature,
    );
    if (!mounted) return;
    setState(() {
      _rule = rule;
      _step = _TeachStep.review;
      _message = _ruleIsValid(rule)
          ? 'Nuvo learned the proof rule.'
          : 'Nuvo needs another example.';
    });
  }

  Future<void> _startRace() async {
    final rule = _rule;
    if (_busy || rule == null || !_ruleIsValid(rule)) return;
    setState(() {
      _busy = true;
      _message = 'Starting race.';
    });
    try {
      final race = await _createRace(rule);
      if (!mounted) return;
      final wantsInvite = widget.args.draft.visibility == 'invite_code';
      context.go(wantsInvite ? '/race/${race.id}/invite' : '/race/${race.id}');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Race could not start. Try again.';
      });
    }
  }

  Future<Race> _createRace(UniversalProofRule rule) {
    final payload = widget.args.draft.toCreatePayload();
    final description = rule.encodeForDescription(
      visibleDescription:
          'Nuvo AI universal proof: ${rule.countRule} ${rule.rejectRule}',
    );
    return ref
        .read(raceControllerProvider.notifier)
        .createRace(
          title: payload['title'] as String,
          description: description,
          category: payload['category'] as String,
          goalType: payload['goalType'] as String,
          targetValue: payload['targetValue'] as int,
          unit: payload['unit'] as String,
          proofRequirement: payload['proofRequirement'] as String,
          proofReviewMode: payload['proofReviewMode'] as String,
          visibility: payload['visibility'] as String,
          aiActivityType: payload['aiActivityType'] as String,
          activityId: payload['activityId'] as String,
          metric: payload['metric'] as String,
          format: payload['format'] as String,
          recurrence: payload['recurrence'] as String,
          targetUnit: payload['targetUnit'] as String,
          proofMode: payload['proofMode'] as String,
        );
  }

  void _retakeExamples() {
    setState(() {
      _step = _TeachStep.clean;
      _positiveFrames = const [];
      _negativeFrames = const [];
      _rule = null;
      _message = _stepCopy;
    });
  }

  bool _ruleIsValid(UniversalProofRule rule) =>
      rule.countRule.trim().length >= 8 &&
      rule.rejectRule.trim().length >= 8 &&
      rule.framingTip.trim().isNotEmpty &&
      rule.promptText.contains('actionComplete') &&
      rule.confidenceThreshold >= 0.5 &&
      rule.confidenceThreshold <= 0.95;

  String get _stepTitle => switch (_step) {
    _TeachStep.clean => 'Record one clean count',
    _TeachStep.reject => 'Record what should not count',
    _TeachStep.review => 'Nuvo learned ${widget.args.actionName}',
  };

  String get _stepCopy => switch (_step) {
    _TeachStep.clean =>
      'Do one ${widget.args.actionName} exactly how it should count.',
    _TeachStep.reject => 'Show something close that should not count.',
    _TeachStep.review => 'Review the proof rule before the race starts.',
  };

  String get _primaryLabel => switch (_step) {
    _TeachStep.clean => 'Record clean clip',
    _TeachStep.reject => 'Record reject clip',
    _TeachStep.review => 'Start race',
  };

  VoidCallback? get _primaryAction {
    if (_loadingCamera || _switchingCamera || _busy) return null;
    return switch (_step) {
      _TeachStep.clean => _captureClean,
      _TeachStep.reject => _captureRejectAndBuild,
      _TeachStep.review =>
        _rule != null && _ruleIsValid(_rule!) ? _startRace : null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;
    final showCamera =
        _step != _TeachStep.review &&
        controller != null &&
        controller.value.isInitialized;

    return Scaffold(
      backgroundColor: NuvoColors.page,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NuvoPrimaryButton(
                label: _busy ? 'Working' : _primaryLabel,
                icon: _step == _TeachStep.review
                    ? Icons.flag_rounded
                    : Icons.camera_alt_rounded,
                expand: true,
                loading: _busy,
                onPressed: _primaryAction,
              ),
              if (_step == _TeachStep.review) ...[
                const SizedBox(height: 10),
                NuvoOutlineButton(
                  label: 'Retake examples',
                  icon: Icons.replay_rounded,
                  expand: true,
                  onPressed: _busy ? null : _retakeExamples,
                ),
              ],
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(
                children: [
                  NuvoBackButton(
                    onPressed: () => safePopOrGo(context, '/races/new'),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Teach Nuvo', style: AppTextStyles.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.args.draft.targetValue} ${widget.args.actionName}',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: NuvoColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_cameras.length > 1 && _step != _TeachStep.review)
                    IconButton.filled(
                      onPressed: _busy || _loadingCamera || _switchingCamera
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
                  child: _step == _TeachStep.review
                      ? _RuleReview(
                          rule: _rule,
                          valid: _rule == null ? false : _ruleIsValid(_rule!),
                        )
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            if (_loadingCamera)
                              const Center(
                                child: CircularProgressIndicator(
                                  color: NuvoColors.white,
                                ),
                              )
                            else if (showCamera)
                              _CameraStagePreview(controller: controller)
                            else
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(28),
                                  child: Text(
                                    _message ?? 'Camera is not ready.',
                                    textAlign: TextAlign.center,
                                    style: AppTextStyles.bodyLarge.copyWith(
                                      color: NuvoColors.white,
                                    ),
                                  ),
                                ),
                              ),
                            Positioned(
                              left: 14,
                              right: 14,
                              top: 14,
                              child: _StepPill(label: _stepTitle),
                            ),
                            Positioned(
                              left: 14,
                              right: 14,
                              bottom: 14,
                              child: _CoachBar(label: _message ?? _stepCopy),
                            ),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
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

class _RuleReview extends StatelessWidget {
  const _RuleReview({required this.rule, required this.valid});

  final UniversalProofRule? rule;
  final bool valid;

  @override
  Widget build(BuildContext context) {
    final rule = this.rule;
    if (rule == null) {
      return const Center(
        child: CircularProgressIndicator(color: NuvoColors.white),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepPill(label: valid ? 'Rule ready' : 'Needs another example'),
          const SizedBox(height: 18),
          Text(
            'Counts when',
            style: AppTextStyles.labelLarge.copyWith(color: NuvoColors.success),
          ),
          const SizedBox(height: 6),
          Text(
            rule.countRule,
            style: AppTextStyles.headlineMedium.copyWith(
              color: NuvoColors.white,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 18),
          _RuleLine(title: 'Does not count', body: rule.rejectRule),
          const SizedBox(height: 12),
          _RuleLine(title: 'Best frame', body: rule.framingTip),
          const SizedBox(height: 12),
          _RuleLine(
            title: 'Confidence',
            body: '${(rule.confidenceThreshold * 100).round()}% minimum',
          ),
        ],
      ),
    );
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

class _RuleLine extends StatelessWidget {
  const _RuleLine({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NuvoColors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(NuvoRadii.md),
        border: Border.all(color: NuvoColors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.labelMedium.copyWith(
              color: NuvoColors.white.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            body,
            style: AppTextStyles.bodyMedium.copyWith(
              color: NuvoColors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepPill extends StatelessWidget {
  const _StepPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: NuvoColors.white.withValues(alpha: 0.12),
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
      ),
    );
  }
}

class _CoachBar extends StatelessWidget {
  const _CoachBar({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NuvoColors.navy.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(NuvoRadii.md),
        border: Border.all(color: NuvoColors.white.withValues(alpha: 0.16)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: AppTextStyles.titleMedium.copyWith(color: NuvoColors.white),
      ),
    );
  }
}
