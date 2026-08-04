import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_geometry.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/nuvo_button.dart';
import '../../ai/camera_image_converter.dart';
import '../../ai/custom_pose/custom_pose_sequence_runtime.dart';
import '../../ai/custom_pose/custom_pose_verifier_spec.dart';
import '../../ai/custom_pose/normalized_pose.dart';
import '../../ai/custom_pose/pose_calibration_flow.dart';
import '../../ai/custom_pose/pose_normalizer.dart';
import '../../ai/pose_detector_service.dart';
import '../../data/ai_motion_models.dart';
import 'learned_custom_movement_provider.dart';

const _debugFixtureFeatureId = 'angle.left_hip';

class TeachMovementScreen extends ConsumerStatefulWidget {
  const TeachMovementScreen({super.key, this.seedReadyFixture = false});

  final bool seedReadyFixture;

  @override
  ConsumerState<TeachMovementScreen> createState() =>
      _TeachMovementScreenState();
}

class _TeachMovementScreenState extends ConsumerState<TeachMovementScreen>
    with WidgetsBindingObserver {
  final _nameController = TextEditingController();
  final _raceTitleController = TextEditingController();
  final _raceTargetController = TextEditingController(text: '10');
  late final SingleSessionTeachingCapture _flow;
  final _poseDetector = PoseDetectorService();
  final _normalizer = const PoseNormalizer();
  CameraController? _cameraController;
  List<CameraDescription> _cameras = const [];
  CameraDescription? _selectedCamera;
  String? _nameError;
  bool _cameraReady = false;
  bool _cameraBusy = false;
  bool _disposed = false;
  bool _testingVerifier = false;
  bool _cameraInterruptedDuringTest = false;
  bool _debugReadyFixture = false;
  CustomPoseSequenceRuntime? _customRuntime;
  CustomPoseRuntimeUpdate? _customUpdate;
  CustomPoseRuntimeResult? _customTestResult;
  CustomPoseVerifierSpec? _debugSpec;
  NuvoPoseFrame? _latestFrame;
  static const int _testTarget = 1;
  bool _learnedWrittenToProvider = false;

  CustomPoseVerifierSpec? get _effectiveSpec =>
      _debugReadyFixture ? _debugSpec : _flow.verifierSpec;

  @override
  void initState() {
    super.initState();
    _flow = SingleSessionTeachingCapture(
      onChanged: _onFlowChanged,
    );
    WidgetsBinding.instance.addObserver(this);
    if (kDebugMode && widget.seedReadyFixture) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _seedDebugReadyFixture();
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _nameController.dispose();
    _raceTitleController.dispose();
    _raceTargetController.dispose();
    _stopCamera();
    _poseDetector.dispose();
    _customRuntime?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      if (_flow.stage == TeachMovementStage.capturing) {
        _flow.markInterrupted();
      }
      if (_testingVerifier) {
        _cameraInterruptedDuringTest = true;
        _stopVerifierTest();
      }
      _stopCamera();
    } else if (state == AppLifecycleState.resumed &&
        _flow.stage != TeachMovementStage.name) {
      _initializeCamera(camera: _selectedCamera);
    }
  }

  Future<void> _initializeCamera({CameraDescription? camera}) async {
    if (_cameraBusy) return;
    setState(() {
      _cameraBusy = true;
    });
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _setCameraError('No camera is available on this device.');
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
      setState(() {
        _cameraReady = true;
        _cameraBusy = false;
      });
      await _startImageStream();
    } on CameraException catch (e) {
      _setCameraError(
        _isPermissionError(e)
            ? 'Camera access is needed to teach a movement.'
            : 'Camera could not start. ${e.description ?? e.code}',
      );
    } catch (_) {
      _setCameraError("Camera couldn't start. Try again.");
    }
  }

  Future<void> _startImageStream() async {
    final controller = _cameraController;
    final camera = _selectedCamera;
    if (controller == null ||
        camera == null ||
        !controller.value.isInitialized ||
        controller.value.isStreamingImages) {
      return;
    }
    await controller.startImageStream((image) {
      _handleFrame(image, camera, controller.value.deviceOrientation);
    });
  }

  Future<void> _handleFrame(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation orientation,
  ) async {
    if (_disposed || !_cameraReady) return;
    try {
      final frame = await _poseDetector.processCameraImage(
        image: image,
        camera: camera,
        deviceOrientation: orientation,
      );
      if (!mounted || _disposed || frame == null) return;
      final pose = _normalizer.normalize(frame);
      _flow.addFrame(pose, frame.createdAt);
      _latestFrame = _flow.isBodyVisiblePose(pose) ? frame : null;
      if (_testingVerifier) {
        final update = _customRuntime?.update(frame);
        _customUpdate = update?.customPoseUpdate;
        if (_customUpdate?.completed == true && _customTestResult == null) {
          _completeVerifierTest();
        }
      }
      setState(() {});
    } on CameraImageConversionException catch (e) {
      _flow.message = e.message;
      await _stopImageStream();
      if (mounted) setState(() {});
    } catch (_) {
      _flow.message = 'Pose detection failed. Try again.';
      await _stopImageStream();
      if (mounted) setState(() {});
    }
  }

  CameraDescription _preferredCamera(List<CameraDescription> cameras) {
    return cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
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
    await _stopImageStream();
    await _cameraController?.dispose();
    _cameraController = null;
    _cameraReady = false;
  }

  void _setCameraError(String message) {
    if (!mounted || _disposed) return;
    setState(() {
      _cameraReady = false;
      _cameraBusy = false;
      _flow.message = message;
    });
  }

  bool _isPermissionError(CameraException e) =>
      e.code == 'CameraAccessDenied' ||
      e.code == 'CameraAccessDeniedWithoutPrompt' ||
      e.code == 'CameraAccessRestricted';

  Future<void> _submitName() async {
    final error = _flow.setMovementName(_nameController.text);
    if (error != null) {
      setState(() => _nameError = error);
      return;
    }
    setState(() {
      _nameError = null;
    });
    await _initializeCamera();
  }

  void _onFlowChanged() {
    final spec = _effectiveSpec;
    if (spec != null && !_learnedWrittenToProvider) {
      _learnedWrittenToProvider = true;
      ref.read(learnedCustomMovementProvider.notifier).state = LearnedCustomMovement(
        verifierSpec: spec,
        learnedAt: DateTime.now(),
      );
    }
    if (mounted) setState(() {});
  }

  void _restart() {
    _flow.restart();
    _raceTitleController.clear();
    _raceTargetController.text = '10';
    _customRuntime?.dispose();
    _customRuntime = null;
    _customUpdate = null;
    _customTestResult = null;

    _testingVerifier = false;

    _cameraInterruptedDuringTest = false;
    _debugReadyFixture = false;
    _debugSpec = null;
    _learnedWrittenToProvider = false;
    ref.read(learnedCustomMovementProvider.notifier).state = null;
    _latestFrame = null;
    _ensureCameraStream();
    setState(() {});
  }

  void _changeName() {
    _flow.resetToName();
    _nameController.clear();
    _raceTitleController.clear();
    _raceTargetController.text = '10';
    _customRuntime?.dispose();
    _customRuntime = null;
    _customUpdate = null;
    _customTestResult = null;

    _testingVerifier = false;

    _cameraInterruptedDuringTest = false;
    _debugReadyFixture = false;
    _debugSpec = null;
    _learnedWrittenToProvider = false;
    ref.read(learnedCustomMovementProvider.notifier).state = null;
    _latestFrame = null;
    _stopCamera();
    setState(() {});
  }

  void _resetStartPose() {
    _flow.resetStartPose();
    _latestFrame = null;
    _ensureCameraStream();
    setState(() {});
  }

  void _removeLastAccepted() {
    _flow.removeLastAccepted();

    setState(() {});
  }

  void _clearExamples() {
    _flow.clearExamples();

    _customRuntime?.dispose();
    _customRuntime = null;
    _customUpdate = null;
    _customTestResult = null;
    _ensureCameraStream();
    setState(() {});
  }

  void _ensureCameraStream() {
    if (!_cameraReady && _flow.stage != TeachMovementStage.name) {
      _initializeCamera(camera: _selectedCamera);
    } else if (_cameraReady && _flow.stage != TeachMovementStage.name) {
      _startImageStream();
    }
  }

  void _startVerifierTest() async {
    final spec = _effectiveSpec;
    if (spec == null || _testingVerifier) return;
    final runtime = CustomPoseSequenceRuntime(spec: spec, target: _testTarget)..start();
    _customRuntime?.dispose();
    _customRuntime = runtime;
    _customUpdate = runtime.lastUpdate;
    _customTestResult = null;

    _cameraInterruptedDuringTest = false;
    setState(() {
      _testingVerifier = true;
    });
    if (!_cameraReady) {
      await _initializeCamera(camera: _selectedCamera);
    } else {
      await _startImageStream();
    }
  }

  void _stopVerifierTest() {
    final runtime = _customRuntime;
    final result = runtime?.customResult();
    setState(() {
      _customTestResult = result;
      _testingVerifier = false;
    });
  }

  void _completeVerifierTest() {
    final runtime = _customRuntime;
    if (runtime == null || !_testingVerifier) return;
    final result = runtime.customResult();
    final passed =
        result.isVerified &&
        !_cameraInterruptedDuringTest &&
        result.validFrames > 0 &&
        result.validFrames / result.framesAnalyzed >= 0.55;
    if (passed && _raceTitleController.text.trim().isEmpty) {
      _raceTitleController.text = _flow.movementName;
    }
    setState(() {
      _customTestResult = result;
      _testingVerifier = false;
    });
  }

  void _seedDebugReadyFixture() {
    final spec = _debugCustomVerifierSpec();
    final result = const CustomPoseRuntimeResult(
      verifierType: customPoseVerifierType,
      verifierVersion: customPoseVerifierSpecSchemaVersion,
      movementName: 'Simulator Custom Movement',
      measurementType: customPoseMeasurementType,
      count: 5,
      target: 5,
      verificationStatus: 'custom_verified',
      confidence: 0.95,
      framesAnalyzed: 24,
      validFrames: 22,
      durationMs: 4200,
      completionEvents: 5,
      invalidAttemptCount: 0,
      finalFailureReason: null,
    );
    _flow.setMovementName(spec.movementName);
    _debugReadyFixture = true;
    _debugSpec = spec;
    _learnedWrittenToProvider = true;
    ref.read(learnedCustomMovementProvider.notifier).state = LearnedCustomMovement(
      verifierSpec: spec,
      learnedAt: DateTime.now(),
    );
    setState(() {
      _customTestResult = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            NuvoBackButton(onPressed: () => context.pop()),
            const SizedBox(height: 18),
            Text('Teach Nuvo', style: AppTextStyles.headlineLarge),
            const SizedBox(height: 6),
            Text(
              'Teach Nuvo the movement, test it, then create a race.',
              style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
            ),
            const SizedBox(height: 20),
            if (_testingVerifier)
              _testingStep()
            else if (_flow.stage == TeachMovementStage.name && !_debugReadyFixture)
              _nameStep()
            else if (_flow.stage == TeachMovementStage.learned ||
                _flow.stage == TeachMovementStage.failed ||
                _debugReadyFixture)
              _summaryStep()
            else
              _cameraStep(),
          ],
        ),
      ),
    );
  }

  Widget _nameStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _nameController,
          maxLength: 40,
          decoration: InputDecoration(
            labelText: 'Movement name',
            hintText: 'Overhead knee touch',
            errorText: _nameError,
          ),
        ),
        const SizedBox(height: 14),
        NuvoPrimaryButton(
          label: 'Continue',
          expand: true,
          onPressed: _submitName,
        ),
      ],
    );
  }

  Widget _testingStep() {
    final controller = _cameraController;
    final showPreview = controller != null && controller.value.isInitialized;
    final status = _nuvoTestStatus(update: _customUpdate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _statusPill(),
        const SizedBox(height: 12),
        _cameraPreviewCard(showPreview),
        const SizedBox(height: 16),
        Text(
          status,
          style: AppTextStyles.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _flow.message,
          style: AppTextStyles.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),
        NuvoPrimaryButton(
          label: 'Stop test',
          expand: true,
          onPressed: _stopVerifierTest,
        ),
        if (kDebugMode) ...[
          const SizedBox(height: 12),
          _debugPanel(),
        ],
      ],
    );
  }

  Widget _cameraStep() {
    final controller = _cameraController;
    final showPreview = controller != null && controller.value.isInitialized;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _statusPill(),
        const SizedBox(height: 12),
        _cameraPreviewCard(showPreview),
        const SizedBox(height: 16),
        Text(
          _flow.message,
          style: AppTextStyles.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        _progressDots(),
        const SizedBox(height: 8),
        _progressText(),
        const SizedBox(height: 20),
        _cameraActionButton(),
        const SizedBox(height: 12),
        _secondaryActionButton(),
        if (kDebugMode) ...[
          const SizedBox(height: 14),
          _debugPanel(),
        ],
      ],
    );
  }

  Widget _statusPill() {
    final (label, color) = switch (_flow.stage) {
      TeachMovementStage.setup => ('Ready to start', NuvoColors.muted),
      TeachMovementStage.countdown => ('Get ready', NuvoColors.muted),
      TeachMovementStage.startPose => ('Waiting for start', NuvoColors.muted),
      TeachMovementStage.readyToRecord => (
          _flow.bodyVisible ? 'Ready' : 'Step into frame',
          _flow.bodyVisible ? NuvoColors.white : NuvoColors.danger
        ),
      TeachMovementStage.recording => ('Recording', NuvoColors.white),
      TeachMovementStage.building => ('Learning', NuvoColors.muted),
      _ => ('', NuvoColors.muted),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: NuvoColors.navy,
          borderRadius: BorderRadius.circular(NuvoRadii.md),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(color: color),
        ),
      ),
    );
  }

  Widget _progressText() {
    final accepted = _flow.acceptedCount;
    const needed = 2;
    return Text(
      '$accepted of $needed examples saved',
      style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
      textAlign: TextAlign.center,
    );
  }

  Widget _captureControls() {
    final stage = _flow.stage;
    final canRemoveLast = _flow.acceptedCount > 0 &&
        (stage == TeachMovementStage.readyToRecord ||
            stage == TeachMovementStage.recording);
    final canClear = (_flow.acceptedCount > 0 ||
            _flow.rejectedDemonstrations.isNotEmpty) &&
        (stage == TeachMovementStage.readyToRecord ||
            stage == TeachMovementStage.recording);
    final showResetStart = _flow.startPose != null &&
        (stage == TeachMovementStage.readyToRecord ||
            stage == TeachMovementStage.recording);
    if (!canRemoveLast && !canClear && !showResetStart) {
      return const SizedBox.shrink();
    }
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      children: [
        if (canRemoveLast) _smallButton('Remove last', _removeLastAccepted),
        if (canClear) _smallButton('Clear examples', _clearExamples),
        if (showResetStart)
          _smallButton('Reteach start pose', _resetStartPose),
      ],
    );
  }

  Widget _smallButton(String label, VoidCallback onPressed) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.navy),
      ),
    );
  }

  Widget _cameraPreviewCard(bool showPreview) {
    final controller = _cameraController;
    return Container(
      height: 420,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: NuvoColors.navy,
        borderRadius: BorderRadius.circular(NuvoRadii.hero),
      ),
      child: showPreview && controller != null
          ? _cameraPreview(controller)
          : Center(
              child: Text(
                _flow.message.isNotEmpty
                    ? _flow.message
                    : 'Starting camera...',
                style: AppTextStyles.bodyLarge.copyWith(
                  color: NuvoColors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ),
    );
  }

  Widget _cameraPreview(CameraController controller) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return CameraPreview(controller);

    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: previewSize.height,
        height: previewSize.width,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(controller),
            Positioned.fill(
              child: CustomPaint(
                painter: _PoseSkeletonPainter(frame: _latestFrame),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressDots() {
    final filled = _flow.acceptedCount;
    final dots = List.generate(3, (index) {
      final filledDot = index < filled;
      return Container(
        width: 12,
        height: 12,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filledDot ? NuvoColors.white : NuvoColors.navy,
        ),
      );
    });
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: dots,
    );
  }

  Widget _cameraActionButton() {
    final stage = _flow.stage;
    if (stage == TeachMovementStage.startPose) {
      return const NuvoPrimaryButton(
        label: 'Hold still',
        expand: true,
        onPressed: null,
      );
    }
    if (stage == TeachMovementStage.recording) {
      return NuvoPrimaryButton(
        label: 'Stop',
        expand: true,
        onPressed: _flow.stopRecordingExample,
      );
    }
    if (stage == TeachMovementStage.building) {
      return const Center(child: CircularProgressIndicator());
    }
    if (stage == TeachMovementStage.readyToRecord) {
      final canRecord = _cameraReady && _flow.canRecordNextExample;
      if (_flow.lastExampleRejected) {
        return NuvoPrimaryButton(
          label: 'Record again',
          expand: true,
          onPressed: canRecord ? _flow.startRecordingExample : null,
        );
      }
      final count = _flow.savedExampleCount;
      if (count < _flow.requiredExampleCount) {
        return NuvoPrimaryButton(
          label: 'Record example ${count + 1}',
          expand: true,
          onPressed: canRecord ? _flow.startRecordingExample : null,
        );
      }
      return NuvoPrimaryButton(
        label: 'Learn movement',
        expand: true,
        onPressed: _flow.canLearn ? _flow.buildWhenReady : null,
      );
    }
    return NuvoOutlineButton(
      label: 'Start over',
      expand: true,
      onPressed: _restart,
    );
  }

  Widget _secondaryActionButton() {
    if (_flow.stage != TeachMovementStage.readyToRecord) {
      return const SizedBox.shrink();
    }
    final NuvoOutlineButton? extra;
    if (_flow.lastExampleRejected &&
        _flow.savedExampleCount >= _flow.requiredExampleCount) {
      extra = NuvoOutlineButton(
        label: 'Learn movement',
        expand: true,
        onPressed: _flow.canLearn ? _flow.buildWhenReady : null,
      );
    } else if (_flow.canRecordExtraExample) {
      extra = NuvoOutlineButton(
        label: 'Record one more',
        expand: true,
        onPressed: (_cameraReady && _flow.canRecordNextExample)
            ? _flow.startRecordingExample
            : null,
      );
    } else {
      extra = null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (extra != null) ...[
          extra,
          const SizedBox(height: 8),
        ],
        _captureControls(),
      ],
    );
  }

  Widget _debugPanel() {
    final accepted = _flow.acceptedDemonstrations;
    final rejected = _flow.rejectedDemonstrations;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NuvoColors.navy,
        borderRadius: BorderRadius.circular(NuvoRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DEBUG', style: AppTextStyles.bodySmall),
          Text('stage: ${_flow.stage.name}'),
          Text('attempts: ${_flow.acceptedCount + _flow.rejectedDemonstrations.length}'),
          Text('accepted: ${accepted.map((d) => d.index).toList()}'),
          Text('rejected: ${rejected.map((d) => d.rejectionReason).toList()}'),
          Text('similarity: ${_flow.lastSimilarity?.toStringAsFixed(2) ?? '-'}'),
          Text('last rejection: ${_flow.lastRejection ?? '-'}'),
          Text('build failure: ${_flow.lastBuildFailure ?? '-'}'),
        ],
      ),
    );
  }

  Widget _summaryStep() {
    final spec = _effectiveSpec;
    final movementName = _flow.movementName;
    final testResult = _customTestResult;
    final canUseMovement = spec != null;
    final testLabel = testResult == null
        ? 'Test movement'
        : 'Test again';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          movementName,
          style: AppTextStyles.titleLarge,
        ),
        const SizedBox(height: 8),
        if (_flow.stage == TeachMovementStage.learned || _debugReadyFixture) ...[
          Text(
            'Movement learned',
            style: AppTextStyles.bodyLarge.copyWith(
              color: NuvoColors.success,
            ),
          ),
          const SizedBox(height: 16),
          if (testResult != null) ...[
            _testResultStatus(testResult),
            const SizedBox(height: 14),
          ],
          if (spec != null)
            NuvoPrimaryButton(
              label: testLabel,
              expand: true,
              onPressed: _startVerifierTest,
            ),
          if (canUseMovement) ...[
            const SizedBox(height: 12),
            NuvoOutlineButton(
              label: 'Use this movement',
              expand: true,
              onPressed: _goToRaceCreation,
            ),
          ],
        ] else ...[
          Text(
            _flow.message,
            style: AppTextStyles.bodyLarge.copyWith(
              color: NuvoColors.danger,
            ),
          ),
        ],
        const SizedBox(height: 14),
        NuvoPrimaryButton(
          label: 'Retry teaching',
          expand: true,
          onPressed: _restart,
        ),
        const SizedBox(height: 12),
        NuvoOutlineButton(
          label: 'Change name',
          expand: true,
          onPressed: _changeName,
        ),
      ],
    );
  }

  Widget _testResultStatus(CustomPoseRuntimeResult result) {
    final matched = result.isVerified;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: matched ? NuvoColors.success.withValues(alpha: 0.08) : NuvoColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(NuvoRadii.md),
      ),
      child: Text(
        matched ? 'Matched' : 'Try again',
        style: AppTextStyles.titleMedium.copyWith(
          color: matched ? NuvoColors.success : NuvoColors.danger,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  void _goToRaceCreation() {
    final spec = _effectiveSpec;
    if (spec == null) return;
    context.push('/races/new');
  }

  String _nuvoTestStatus({CustomPoseRuntimeUpdate? update, CustomPoseRuntimeResult? result}) {
    if (result != null) {
      return result.isVerified ? 'Matched' : 'Try again';
    }
    final guidance = update?.guidance;
    final state = update?.state;
    if (guidance == null) return 'Ready';
    return switch (guidance) {
      'Ready' => (state == CustomPoseRuntimeState.matchingSequence ||
              state == CustomPoseRuntimeState.completionCandidate)
          ? 'Keep going'
          : 'Ready',
      'Step back' => 'Move into position',
      'Move into the starting position' => 'Move into position',
      'Hold the starting position' => 'Ready',
      'Begin the movement' => 'Do the movement',
      'Movement incomplete' => 'Try again',
      'Return to your starting position' => 'Keep going',
      'Keep your full body visible' => 'Keep your full body visible',
      _ => guidance,
    };
  }
}

class _PoseSkeletonPainter extends CustomPainter {
  _PoseSkeletonPainter({this.frame});

  final NuvoPoseFrame? frame;

  @override
  void paint(Canvas canvas, Size size) {
    final points = frame?.points;
    if (points == null || points.isEmpty) return;

    final jointPaint = Paint()
      ..color = NuvoColors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;

    final bonePaint = Paint()
      ..color = NuvoColors.white.withValues(alpha: 0.55)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    Offset toOffset(NuvoPosePoint point) =>
        Offset(point.x * size.width, point.y * size.height);

    for (final pair in _skeletonBones) {
      final a = points[pair.a];
      final b = points[pair.b];
      if (a == null || b == null) continue;
      canvas.drawLine(toOffset(a), toOffset(b), bonePaint);
    }

    for (final entry in points.entries) {
      final point = entry.value;
      if (point.likelihood < 0.5) continue;
      canvas.drawCircle(toOffset(point), 4.5, jointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PoseSkeletonPainter old) =>
      old.frame != frame;
}

class _Bone {
  const _Bone(this.a, this.b);

  final String a;
  final String b;
}

const _skeletonBones = <_Bone>[
  _Bone('leftShoulder', 'rightShoulder'),
  _Bone('leftShoulder', 'leftElbow'),
  _Bone('leftElbow', 'leftWrist'),
  _Bone('rightShoulder', 'rightElbow'),
  _Bone('rightElbow', 'rightWrist'),
  _Bone('leftShoulder', 'leftHip'),
  _Bone('rightShoulder', 'rightHip'),
  _Bone('leftHip', 'rightHip'),
  _Bone('leftHip', 'leftKnee'),
  _Bone('leftKnee', 'leftAnkle'),
  _Bone('rightHip', 'rightKnee'),
  _Bone('rightKnee', 'rightAnkle'),
  _Bone('leftWrist', 'leftThumb'),
  _Bone('leftWrist', 'leftIndex'),
  _Bone('leftWrist', 'leftPinky'),
  _Bone('rightWrist', 'rightThumb'),
  _Bone('rightWrist', 'rightIndex'),
  _Bone('rightWrist', 'rightPinky'),
];

CustomPoseVerifierSpec _debugCustomVerifierSpec() {
  const startFeature = PoseFeatureValue(
    value: 0.35,
    confidence: 0.95,
    valid: true,
    kind: 'angle',
  );
  const finishFeature = PoseFeatureValue(
    value: 0.72,
    confidence: 0.95,
    valid: true,
    kind: 'angle',
  );
  final startPose = _debugPose(startFeature);
  final finishPose = _debugPose(finishFeature);
  return CustomPoseVerifierSpec(
    schemaVersion: customPoseVerifierSpecSchemaVersion,
    verifierType: customPoseVerifierType,
    movementName: 'Simulator Custom Movement',
    measurementType: customPoseMeasurementType,
    startPose: startPose,
    completionPose: finishPose,
    completionStrategy: CustomPoseCompletionStrategy.completionAtTerminalPose,
    canonicalSequence: const [
      PoseTemplateFrame(
        position: 0,
        features: {
          _debugFixtureFeatureId: PoseTemplateFeature(
            value: 0.35,
            confidence: 0.95,
            reliability: 0.95,
            allowedVariation: 0.25,
            contributingDemonstrationCount: 3,
            kind: 'angle',
          ),
        },
      ),
      PoseTemplateFrame(
        position: 1,
        features: {
          _debugFixtureFeatureId: PoseTemplateFeature(
            value: 0.72,
            confidence: 0.95,
            reliability: 0.95,
            allowedVariation: 0.25,
            contributingDemonstrationCount: 3,
            kind: 'angle',
          ),
        },
      ),
    ],
    requiredFeatureIds: const [_debugFixtureFeatureId],
    activeFeatureIds: const [_debugFixtureFeatureId],
    sequenceSimilarityThreshold: 0.55,
    completionSimilarityThreshold: 0.6,
    resetSimilarityThreshold: 0.5,
    minimumValidFeatureRatio: 0.7,
    minimumVisibility: 0.5,
    cooldownMs: 600,
    expectedSequenceFrameCount: 2,
    calibrationSummary: const CustomPoseCalibrationSummary(
      sourceCalibrationSchemaVersion: 1,
      demonstrationCount: 3,
      selectedActiveFeatureCount: 1,
      requiredFeatureCount: 1,
      canonicalSequenceLength: 2,
      pairwiseSimilarityScores: {'1-2': 0.93, '1-3': 0.92, '2-3': 0.94},
      overallConsistencyScore: 0.93,
      lowestPairwiseSimilarityScore: 0.92,
      sequenceSimilarityThreshold: 0.55,
      completionSimilarityThreshold: 0.6,
      resetSimilarityThreshold: 0.5,
      minimumValidFeatureRatio: 0.7,
      minimumVisibility: 0.5,
      cooldownMs: 600,
      completionStrategy: CustomPoseCompletionStrategy.completionAtTerminalPose,
      builderVersion: 'debug-fixture-v1',
    ),
  )..validate();
}

NormalizedPose _debugPose(PoseFeatureValue feature) => NormalizedPose(
  schemaVersion: normalizedPoseSchemaVersion,
  landmarks: const {
    'leftShoulder': NormalizedPoseLandmark(
      x: -0.2,
      y: -0.4,
      z: 0,
      confidence: 0.95,
      valid: true,
    ),
    'rightShoulder': NormalizedPoseLandmark(
      x: 0.2,
      y: -0.4,
      z: 0,
      confidence: 0.95,
      valid: true,
    ),
    'leftHip': NormalizedPoseLandmark(
      x: -0.18,
      y: 0,
      z: 0,
      confidence: 0.95,
      valid: true,
    ),
    'rightHip': NormalizedPoseLandmark(
      x: 0.18,
      y: 0,
      z: 0,
      confidence: 0.95,
      valid: true,
    ),
    'leftKnee': NormalizedPoseLandmark(
      x: -0.12,
      y: 0.45,
      z: 0,
      confidence: 0.95,
      valid: true,
    ),
  },
  features: PoseFeatureVector({_debugFixtureFeatureId: feature}),
  originX: 0,
  originY: 0,
  scale: 1,
  originReference: 'debug_fixture',
  scaleReference: 'debug_fixture',
  validLandmarkCount: 5,
  validFeatureCount: 1,
);
