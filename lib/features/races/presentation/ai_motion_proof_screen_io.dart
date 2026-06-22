import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../auth/data/auth_api.dart';
import '../ai/camera_image_converter.dart';
import '../ai/motion_validators.dart';
import '../ai/pose_detector_service.dart';
import '../data/ai_motion_models.dart';
import '../domain/motion_activity_catalog.dart';
import 'race_controller.dart';

class AiMotionProofScreen extends ConsumerStatefulWidget {
  const AiMotionProofScreen({super.key, required this.raceId});

  final String raceId;

  @override
  ConsumerState<AiMotionProofScreen> createState() =>
      _AiMotionProofScreenState();
}

class _AiMotionProofScreenState extends ConsumerState<AiMotionProofScreen>
    with WidgetsBindingObserver {
  final _poseDetector = PoseDetectorService();
  MotionValidator _validator = createMotionValidator(
    AiMotionActivity.jumpingJacks,
    10,
  );

  AiMotionActivity _activity = AiMotionActivity.jumpingJacks;
  CameraController? _cameraController;
  List<CameraDescription> _cameras = const [];
  CameraDescription? _selectedCamera;
  AiMotionProofStatus _status = AiMotionProofStatus.setup;
  AiMotionResult? _result;
  String? _message;
  bool _disposed = false;
  Timer? _recordingTimer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadRace();
  }

  Future<void> _loadRace() async {
    try {
      final race = await ref
          .read(raceControllerProvider.notifier)
          .getRaceDetail(widget.raceId);
      if (!mounted) return;
      final activity = AiMotionActivity.fromBackendValue(
        race.effectiveAiActivityType,
      );
      final target = race.targetValue ?? 10;
      setState(() {
        _activity = activity;
        _validator = createMotionValidator(activity, target);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Race details could not load. Jumping jacks proof is ready.';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _stopCamera();
    } else if (state == AppLifecycleState.resumed &&
        _status == AiMotionProofStatus.cameraReady) {
      _initializeCamera(camera: _selectedCamera);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _recordingTimer?.cancel();
    _stopCamera();
    _poseDetector.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera({CameraDescription? camera}) async {
    setState(() {
      _status = AiMotionProofStatus.processing;
      _message = null;
      _result = null;
    });

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _status = AiMotionProofStatus.cameraError;
            _message = 'No camera is available on this device.';
          });
        }
        return;
      }

      final selected = camera ?? _preferredCamera(_cameras);
      _selectedCamera = selected;
      await _cameraController?.dispose();
      final controller = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.nv21,
      );
      _cameraController = controller;
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);

      if (!mounted || _disposed) return;
      setState(() => _status = AiMotionProofStatus.cameraReady);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _isPermissionError(e)
            ? AiMotionProofStatus.permissionDenied
            : AiMotionProofStatus.cameraError;
        _message = _isPermissionError(e)
            ? 'Camera access is needed to verify your reps. Enable it in Settings.'
            : 'Camera could not start. ${e.description ?? e.code}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = AiMotionProofStatus.cameraError;
        _message = "Camera couldn't start. Try again.";
      });
    }
  }

  CameraDescription _preferredCamera(List<CameraDescription> cameras) {
    return cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
  }

  Future<void> _toggleCamera() async {
    if (_cameras.length < 2 || _status == AiMotionProofStatus.recording) {
      return;
    }
    final current = _selectedCamera;
    final next = _cameras.firstWhere(
      (camera) => camera.name != current?.name,
      orElse: () => _preferredCamera(_cameras),
    );
    await _initializeCamera(camera: next);
  }

  Future<void> _startRecording() async {
    final controller = _cameraController;
    final camera = _selectedCamera;
    if (controller == null ||
        camera == null ||
        !controller.value.isInitialized) {
      return;
    }

    _validator.start();
    _elapsed = Duration.zero;
    setState(() {
      _status = AiMotionProofStatus.recording;
      _message = null;
      _result = null;
    });

    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _status == AiMotionProofStatus.recording) {
        setState(() => _elapsed += const Duration(seconds: 1));
      }
    });

    try {
      await controller.startImageStream((image) {
        _handleCameraFrame(image, camera, controller.value.deviceOrientation);
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _status = AiMotionProofStatus.cameraError;
        _message = 'Recording could not start. ${e.description ?? e.code}';
      });
    }
  }

  Future<void> _handleCameraFrame(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation orientation,
  ) async {
    if (_disposed || _status != AiMotionProofStatus.recording) return;
    try {
      final frame = await _poseDetector.processCameraImage(
        image: image,
        camera: camera,
        deviceOrientation: orientation,
      );
      if (_disposed || _status != AiMotionProofStatus.recording) return;
      if (frame == null) return;
      _validator.update(frame);
      if (mounted) setState(() {});
    } on CameraImageConversionException catch (e) {
      if (!mounted) return;
      setState(() {
        _status = AiMotionProofStatus.cameraError;
        _message = e.message;
      });
      await _stopImageStream();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = AiMotionProofStatus.cameraError;
        _message = 'Detection failed. Try again.';
      });
      await _stopImageStream();
    }
  }

  Future<void> _finishRecording() async {
    if (_status != AiMotionProofStatus.recording) return;
    setState(() => _status = AiMotionProofStatus.processing);
    _recordingTimer?.cancel();
    await _stopImageStream();
    await Future<void>.delayed(const Duration(milliseconds: 250));

    final result = _validator.finish();
    if (!mounted) return;
    setState(() {
      _result = result;
      _status = result.isVerified
          ? AiMotionProofStatus.aiVerified
          : AiMotionProofStatus.aiFailed;
      _message = null;
    });
  }

  Future<void> _submitVerifiedProof() async {
    final result = _result;
    if (result == null || !result.isVerified) return;
    setState(() {
      _status = AiMotionProofStatus.submitting;
      _message = null;
    });
    try {
      await ref
          .read(raceControllerProvider.notifier)
          .submitAiMotionProof(widget.raceId, result: result);
      if (!mounted) return;
      setState(() => _status = AiMotionProofStatus.submitted);
      context.go('/race/${widget.raceId}');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _status = AiMotionProofStatus.aiVerified;
        _message = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = AiMotionProofStatus.aiVerified;
        _message = 'Verified proof could not be submitted. Try again.';
      });
    }
  }

  Future<void> _recordAgain() async {
    _recordingTimer?.cancel();
    await _stopImageStream();
    setState(() {
      _result = null;
      _message = null;
      _elapsed = Duration.zero;
      _status = _cameraController?.value.isInitialized == true
          ? AiMotionProofStatus.cameraReady
          : AiMotionProofStatus.setup;
    });
  }

  Future<void> _stopImageStream() async {
    final controller = _cameraController;
    if (controller != null &&
        controller.value.isInitialized &&
        controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
  }

  Future<void> _stopCamera() async {
    _recordingTimer?.cancel();
    await _stopImageStream();
    await _cameraController?.dispose();
    _cameraController = null;
  }

  bool _isPermissionError(CameraException e) =>
      e.code == 'CameraAccessDenied' ||
      e.code == 'CameraAccessDeniedWithoutPrompt' ||
      e.code == 'CameraAccessRestricted';

  // Show premium result panels instead of camera for terminal states.
  bool get _isResultState =>
      _status == AiMotionProofStatus.aiVerified ||
      _status == AiMotionProofStatus.aiFailed;

  int get _targetValue => _validator.targetValue;

  int get _currentValue => _validator.currentValue;

  String get _targetLabel {
    final definition = motionActivityForBackendValue(_activity.backendValue);
    return definition?.targetLabel(_targetValue) ??
        '$_targetValue ${_activity.label}';
  }

  String get _counterLabel {
    final definition = motionActivityForBackendValue(_activity.backendValue);
    return definition?.counterLabel(_currentValue, _targetValue) ??
        '$_currentValue / $_targetValue';
  }

  String get _cameraInstruction =>
      motionActivityForBackendValue(
        _activity.backendValue,
      )?.cameraInstruction ??
      'Full body front view';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NuvoColors.page,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          child: Column(mainAxisSize: MainAxisSize.min, children: _actions()),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Compact inline header: back button left, title right ──────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  NuvoBackButton(
                    onPressed: () =>
                        safePopOrGo(context, '/race/${widget.raceId}/proof'),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Verify reps', style: AppTextStyles.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          _activity == AiMotionActivity.plankHold
                              ? 'Hold plank for $_targetValue seconds.'
                              : 'Nuvo will count your $_targetLabel.',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: NuvoColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Setup card (setup state only) ────────────────────────────
            if (_status == AiMotionProofStatus.setup) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _setupCard(),
              ),
              const SizedBox(height: 10),
            ],

            // ── Camera / result stage — Expanded fills remaining space ───
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _isResultState ? _resultPanel() : _cameraPanel(),
              ),
            ),

            // ── Compact status hint (camera-ready / error / processing) ──
            if (!_isResultState &&
                _status != AiMotionProofStatus.setup &&
                _status != AiMotionProofStatus.recording) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _statusHint(),
              ),
            ],

            // ── Submission error message (result states only) ─────────────
            if (_message != null && _isResultState) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _errorMessage(_message!),
              ),
            ],

            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _setupCard() {
    final items = [
      'Place your iPhone 6–8 feet away.',
      _cameraInstruction,
      _activity == AiMotionActivity.plankHold
          ? 'Only valid plank posture time counts.'
          : 'Keep the movement clear and controlled.',
      'Use good lighting.',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NuvoColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1207152B),
            blurRadius: 0,
            offset: Offset(3, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Set up your shot', style: AppTextStyles.titleMedium),
          const SizedBox(height: 8),
          for (final item in items) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: NuvoColors.blue,
                  size: 14,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    item,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.muted,
                    ),
                  ),
                ),
              ],
            ),
            if (item != items.last) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _cameraPanel() {
    final controller = _cameraController;
    final showPreview = controller != null && controller.value.isInitialized;

    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.navy,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0xB007152B),
            blurRadius: 0,
            offset: Offset(5, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showPreview)
            _cameraPreview(controller)
          else
            Container(
              color: NuvoColors.navy,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(28),
              child: Text(
                _cameraPlaceholderText,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: NuvoColors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          Positioned(
            left: 14,
            right: 14,
            top: 14,
            child: Row(
              children: [
                _pill(
                  _status == AiMotionProofStatus.recording
                      ? (_currentValue >= _targetValue
                            ? _counterLabel
                            : 'Recording')
                      : 'Target: $_targetLabel',
                  color: _status == AiMotionProofStatus.recording
                      ? (_currentValue >= _targetValue
                            ? NuvoColors.success
                            : const Color(0xFFE8304A))
                      : NuvoColors.blue,
                ),
                const Spacer(),
                _visibilityPill(),
                const SizedBox(width: 8),
                if (_cameras.length > 1 &&
                    _status != AiMotionProofStatus.recording)
                  IconButton.filled(
                    onPressed: _toggleCamera,
                    style: IconButton.styleFrom(
                      backgroundColor: NuvoColors.white.withValues(alpha: 0.9),
                      foregroundColor: NuvoColors.navy,
                    ),
                    icon: const Icon(Icons.cameraswitch_rounded),
                  ),
              ],
            ),
          ),
          Positioned.fill(child: IgnorePointer(child: _bodyGuideOverlay())),
          if (_status == AiMotionProofStatus.recording)
            Positioned(left: 14, right: 14, bottom: 14, child: _recordingHud()),
        ],
      ),
    );
  }

  Widget _cameraPreview(CameraController controller) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return CameraPreview(controller);

    // Camera preview size is landscape even while the app is locked portrait.
    // Swap dimensions and let BoxFit.cover crop naturally without distortion.
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: previewSize.height,
        height: previewSize.width,
        child: CameraPreview(controller),
      ),
    );
  }

  Widget _bodyGuideOverlay() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(34, 76, 34, 72),
      child: CustomPaint(
        painter: _BodyGuidePainter(),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: NuvoColors.navy.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: NuvoColors.white.withValues(alpha: 0.18),
              ),
            ),
            child: Text(
              'Keep full body inside',
              style: AppTextStyles.labelSmall.copyWith(
                color: NuvoColors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Premium verified result panel.
  Widget _resultPanel() {
    final result = _result;
    final isVerified = _status == AiMotionProofStatus.aiVerified;

    if (isVerified) {
      return Container(
        decoration: BoxDecoration(
          color: NuvoColors.navy,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0xB007152B),
              blurRadius: 0,
              offset: Offset(5, 6),
            ),
          ],
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.verified_rounded,
                  color: NuvoColors.blue,
                  size: 68,
                ),
                const SizedBox(height: 18),
                Text(
                  'Verified',
                  style: AppTextStyles.headlineLarge.copyWith(
                    color: NuvoColors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$_targetLabel detected',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: NuvoColors.white.withValues(alpha: 0.78),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Reps verified. Leaderboard is updating.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: NuvoColors.white.withValues(alpha: 0.50),
                  ),
                ),
                if (result != null) ...[
                  const SizedBox(height: 22),
                  _metric(
                    'Confidence',
                    '${(result.confidence * 100).round()}%',
                    dark: true,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    // Failed / coaching state.
    final detected = result?.detectedReps ?? 0;
    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.icyBlue,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: NuvoColors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: NuvoColors.border, width: 2),
                ),
                child: const Icon(
                  Icons.refresh_rounded,
                  color: NuvoColors.muted,
                  size: 30,
                ),
              ),
              const SizedBox(height: 18),
              Text('Try again', style: AppTextStyles.headlineLarge),
              const SizedBox(height: 10),
              Text(
                _activity == AiMotionActivity.plankHold
                    ? 'Nuvo counted $detected valid seconds out of $_targetValue.'
                    : 'Nuvo detected $detected clean ${_activity.label} out of $_targetValue.',
                style: AppTextStyles.bodyLarge.copyWith(
                  color: NuvoColors.muted,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Keep the camera view clear and try again.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: NuvoColors.muted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recordingHud() {
    final targetReached = _currentValue >= _targetValue;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NuvoColors.navy.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NuvoColors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              targetReached ? 'Target reached — tap Done' : _counterLabel,
              style: AppTextStyles.titleLarge.copyWith(color: NuvoColors.white),
            ),
          ),
          Text(
            _formatElapsed(_elapsed),
            style: AppTextStyles.labelLarge.copyWith(color: NuvoColors.white),
          ),
        ],
      ),
    );
  }

  Widget _statusHint() {
    final title = switch (_status) {
      AiMotionProofStatus.cameraReady => 'Frame your body',
      AiMotionProofStatus.processing => 'Checking proof...',
      AiMotionProofStatus.permissionDenied => 'Camera permission needed',
      AiMotionProofStatus.cameraError => 'Camera issue',
      AiMotionProofStatus.submitting => 'Submitting proof...',
      AiMotionProofStatus.submitted => 'Proof submitted',
      AiMotionProofStatus.needsReview => 'Needs review',
      _ => '',
    };
    final body =
        _message ??
        switch (_status) {
          AiMotionProofStatus.cameraReady =>
            'Nuvo will check body visibility while recording.',
          AiMotionProofStatus.processing => 'Nuvo is checking your proof.',
          AiMotionProofStatus.permissionDenied =>
            'Enable camera access in Settings to verify your reps.',
          AiMotionProofStatus.cameraError => 'Try again.',
          AiMotionProofStatus.submitting =>
            'Saving verified proof to the race.',
          AiMotionProofStatus.submitted =>
            'Leaderboard progress is refreshing.',
          AiMotionProofStatus.needsReview => 'This proof needs manual review.',
          _ => '',
        };

    if (title.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NuvoColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C07152B),
            blurRadius: 0,
            offset: Offset(2, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: AppTextStyles.titleMedium),
          const SizedBox(height: 2),
          Text(
            body,
            style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _errorMessage(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEEF1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFE5484D).withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        message,
        style: AppTextStyles.bodySmall.copyWith(color: const Color(0xFFE5484D)),
      ),
    );
  }

  List<Widget> _actions() {
    final loading =
        _status == AiMotionProofStatus.processing ||
        _status == AiMotionProofStatus.submitting;

    return switch (_status) {
      AiMotionProofStatus.setup => [
        NuvoPrimaryButton(
          label: 'Start camera',
          icon: Icons.camera_alt_rounded,
          expand: true,
          loading: loading,
          onPressed: loading ? null : _initializeCamera,
        ),
        const SizedBox(height: 12),
        NuvoOutlineButton(
          label: 'Back',
          expand: true,
          onPressed: () => safePopOrGo(context, '/race/${widget.raceId}/proof'),
        ),
      ],
      AiMotionProofStatus.cameraReady => [
        NuvoPrimaryButton(
          label: 'Record proof',
          icon: Icons.videocam_rounded,
          expand: true,
          onPressed: _startRecording,
        ),
      ],
      AiMotionProofStatus.recording => [
        NuvoPrimaryButton(
          label: 'Done',
          icon: Icons.check_rounded,
          expand: true,
          onPressed: _finishRecording,
        ),
        const SizedBox(height: 12),
        NuvoOutlineButton(
          label: 'Cancel',
          expand: true,
          onPressed: _recordAgain,
        ),
      ],
      AiMotionProofStatus.aiVerified => [
        NuvoPrimaryButton(
          label: 'Submit verified proof',
          icon: Icons.verified_rounded,
          expand: true,
          onPressed: _submitVerifiedProof,
        ),
        const SizedBox(height: 12),
        NuvoOutlineButton(
          label: 'Record again',
          icon: Icons.replay_rounded,
          expand: true,
          onPressed: _recordAgain,
        ),
      ],
      AiMotionProofStatus.aiFailed ||
      AiMotionProofStatus.permissionDenied ||
      AiMotionProofStatus.cameraError => [
        NuvoPrimaryButton(
          label: 'Record again',
          icon: Icons.replay_rounded,
          expand: true,
          onPressed: _recordAgain,
        ),
        const SizedBox(height: 12),
        NuvoGhostButton(
          label: 'Log manually',
          expand: true,
          onPressed: () => safePopOrGo(context, '/race/${widget.raceId}/proof'),
        ),
      ],
      _ => [
        NuvoPrimaryButton(
          label: loading ? 'Checking proof' : 'Start camera',
          expand: true,
          loading: loading,
          onPressed: null,
        ),
      ],
    };
  }

  Widget _pill(String label, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: NuvoColors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _visibilityPill() {
    final recording = _status == AiMotionProofStatus.recording;
    final visible = _validator.fullBodyVisible;
    final targetReached = _currentValue >= _targetValue;

    final label = recording && targetReached
        ? 'Target reached'
        : recording && visible
        ? 'Tracking'
        : recording
        ? 'Full body needed'
        : 'Frame body';
    final color = recording && targetReached
        ? NuvoColors.success
        : recording && visible
        ? NuvoColors.blue
        : NuvoColors.navy;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: NuvoColors.white.withValues(alpha: 0.14)),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: NuvoColors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _metric(String label, String value, {bool dark = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: dark
            ? NuvoColors.white.withValues(alpha: 0.12)
            : NuvoColors.icyBlue,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$label: $value',
        style: AppTextStyles.labelSmall.copyWith(
          color: dark ? NuvoColors.white : NuvoColors.navy,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String get _cameraPlaceholderText {
    if (_status == AiMotionProofStatus.processing) return 'Starting camera...';
    return 'Place your iPhone 6–8 feet away.\n$_cameraInstruction.';
  }

  String _formatElapsed(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _BodyGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cornerPaint = Paint()
      ..color = NuvoColors.white.withValues(alpha: 0.9)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final guidePaint = Paint()
      ..color = NuvoColors.white.withValues(alpha: 0.24)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;

    const corner = 34.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(28),
    );
    canvas.drawRRect(rect, guidePaint);

    final centerX = size.width / 2;
    final headCenter = Offset(centerX, size.height * 0.18);
    canvas.drawCircle(headCenter, size.width * 0.075, guidePaint);
    canvas.drawLine(
      Offset(centerX, size.height * 0.26),
      Offset(centerX, size.height * 0.58),
      guidePaint,
    );
    canvas.drawLine(
      Offset(centerX - size.width * 0.22, size.height * 0.36),
      Offset(centerX + size.width * 0.22, size.height * 0.36),
      guidePaint,
    );
    canvas.drawLine(
      Offset(centerX, size.height * 0.58),
      Offset(centerX - size.width * 0.18, size.height * 0.84),
      guidePaint,
    );
    canvas.drawLine(
      Offset(centerX, size.height * 0.58),
      Offset(centerX + size.width * 0.18, size.height * 0.84),
      guidePaint,
    );

    final path = Path()
      ..moveTo(0, corner)
      ..lineTo(0, 0)
      ..lineTo(corner, 0)
      ..moveTo(size.width - corner, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, corner)
      ..moveTo(size.width, size.height - corner)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width - corner, size.height)
      ..moveTo(corner, size.height)
      ..lineTo(0, size.height)
      ..lineTo(0, size.height - corner);
    canvas.drawPath(path, cornerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
