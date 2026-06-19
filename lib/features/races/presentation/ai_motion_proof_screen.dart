import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
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
import '../ai/jumping_jack_counter.dart';
import '../ai/pose_detector_service.dart';
import '../data/ai_motion_models.dart';
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
  static const _targetReps = 10;

  final _poseDetector = PoseDetectorService();
  final _counter = JumpingJackCounter(targetReps: _targetReps);

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
            ? 'Camera permission is needed for AI Motion Proof. You can still use manual proof.'
            : 'Camera could not start. ${e.description ?? e.code}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = AiMotionProofStatus.cameraError;
        _message = 'Camera could not start. Try again or use manual proof.';
      });
    }
  }

  CameraDescription _preferredCamera(List<CameraDescription> cameras) {
    return cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
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

    _counter.start();
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
      _counter.analyze(frame);
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
        _message = 'Pose detector failed. Try again or use manual proof.';
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

    final result = _counter.finish();
    if (!mounted) return;
    setState(() {
      _result = result;
      _status = result.isVerified
          ? AiMotionProofStatus.aiVerified
          : AiMotionProofStatus.aiFailed;
      _message = result.isVerified
          ? '$_targetReps jumping jacks detected.'
          : 'Nuvo detected ${result.detectedReps} clean reps out of $_targetReps.';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton.filledTonal(
                onPressed: () =>
                    safePopOrGo(context, '/race/${widget.raceId}/proof'),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Text('AI Motion Proof', style: AppTextStyles.headlineLarge),
            const SizedBox(height: 6),
            Text(
              'Do $_targetReps jumping jacks. Place your iPhone 6-8 feet away and keep your full body in frame.',
              style: AppTextStyles.bodyLarge.copyWith(color: NuvoColors.muted),
            ),
            const SizedBox(height: 20),
            _cameraPanel(),
            const SizedBox(height: 18),
            _statusPanel(),
            if (kDebugMode) ...[const SizedBox(height: 12), _debugPanel()],
            const SizedBox(height: 20),
            ..._actions(),
          ],
        ),
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
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (showPreview)
              CameraPreview(controller)
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
                        ? 'Recording'
                        : 'Target: $_targetReps reps',
                    color: _status == AiMotionProofStatus.recording
                        ? const Color(0xFFE8304A)
                        : NuvoColors.blue,
                  ),
                  const Spacer(),
                  if (_cameras.length > 1 &&
                      _status != AiMotionProofStatus.recording)
                    IconButton.filled(
                      onPressed: _toggleCamera,
                      style: IconButton.styleFrom(
                        backgroundColor: NuvoColors.white.withValues(
                          alpha: 0.9,
                        ),
                        foregroundColor: NuvoColors.navy,
                      ),
                      icon: const Icon(Icons.cameraswitch_rounded),
                    ),
                ],
              ),
            ),
            if (_status == AiMotionProofStatus.recording)
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: _recordingHud(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _recordingHud() {
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
              'Detected: ${_counter.detectedReps} / $_targetReps',
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

  Widget _statusPanel() {
    final result = _result;
    final title = switch (_status) {
      AiMotionProofStatus.setup => 'Set up your shot',
      AiMotionProofStatus.cameraReady => 'Camera ready',
      AiMotionProofStatus.recording =>
        _counter.fullBodyVisible
            ? 'Full body visible'
            : 'Nuvo cannot see your full body yet.',
      AiMotionProofStatus.processing => 'Processing proof...',
      AiMotionProofStatus.aiVerified => 'Verified',
      AiMotionProofStatus.aiFailed => 'Try again',
      AiMotionProofStatus.permissionDenied => 'Camera permission needed',
      AiMotionProofStatus.cameraError => 'Camera issue',
      AiMotionProofStatus.submitting => 'Submitting proof...',
      AiMotionProofStatus.submitted => 'Proof submitted',
      AiMotionProofStatus.needsReview => 'Needs review',
    };
    final body =
        _message ??
        switch (_status) {
          AiMotionProofStatus.setup =>
            'Stand facing the camera. Use good lighting and keep arms and feet in frame.',
          AiMotionProofStatus.cameraReady =>
            'Tap Record when your full body is visible.',
          AiMotionProofStatus.recording =>
            'Step back and keep your arms and feet in frame.',
          AiMotionProofStatus.processing =>
            'The local pose detector is checking your reps.',
          AiMotionProofStatus.aiVerified =>
            '${result?.detectedReps ?? _targetReps} jumping jacks detected.',
          AiMotionProofStatus.aiFailed =>
            'Keep your full body in frame and try again.',
          AiMotionProofStatus.permissionDenied =>
            'You can still use manual proof.',
          AiMotionProofStatus.cameraError => 'Try again or use manual proof.',
          AiMotionProofStatus.submitting =>
            'Saving verified proof to the race.',
          AiMotionProofStatus.submitted =>
            'Leaderboard progress is refreshing.',
          AiMotionProofStatus.needsReview => 'This proof needs manual review.',
        };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.titleLarge),
          const SizedBox(height: 6),
          Text(
            body,
            style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
          ),
          if (result != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metric(
                  'Detected',
                  '${result.detectedReps}/${result.targetReps}',
                ),
                _metric('Confidence', '${(result.confidence * 100).round()}%'),
                _metric(
                  'Frames',
                  '${result.validPoseFrames}/${result.framesAnalyzed}',
                ),
              ],
            ),
          ],
        ],
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
          label: 'Record',
          icon: Icons.fiber_manual_record_rounded,
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
        NuvoOutlineButton(
          label: 'Use manual proof',
          icon: Icons.edit_note_rounded,
          expand: true,
          onPressed: () => safePopOrGo(context, '/race/${widget.raceId}/proof'),
        ),
      ],
      _ => [
        NuvoPrimaryButton(
          label: loading ? 'Working' : 'Start camera',
          expand: true,
          loading: loading,
          onPressed: null,
        ),
      ],
    };
  }

  Widget _debugPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NuvoColors.icyBlue,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Text(
        'frames: ${_counter.framesAnalyzed}  valid: ${_counter.validPoseFrames}  state: ${_counter.currentState.name}  reps: ${_counter.detectedReps}  confidence: ${(_counter.confidence * 100).round()}%',
        style: AppTextStyles.labelSmall.copyWith(color: NuvoColors.navy),
      ),
    );
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

  Widget _metric(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: NuvoColors.icyBlue,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$label: $value',
        style: AppTextStyles.labelSmall.copyWith(color: NuvoColors.navy),
      ),
    );
  }

  String get _cameraPlaceholderText {
    if (_status == AiMotionProofStatus.processing) return 'Starting camera...';
    return 'Place your iPhone 6-8 feet away. Keep your full body in frame.';
  }

  String _formatElapsed(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
