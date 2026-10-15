import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_geometry.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/nuvo_button.dart';
import '../../../../core/widgets/nuvo_focused_stage.dart';
import '../../../../core/widgets/nuvo_loading_indicator.dart';
import '../../../../core/widgets/nuvo_rep_pulse.dart';
import '../../ai/camera_image_converter.dart';
import '../../ai/motion_model_resolver.dart';
import '../../ai/motion_v2/diagnostics/motion_diagnostic_session.dart';
import '../../ai/motion_v2/engine/motion_v2_onnx_encoder.dart';
import '../../ai/motion_v2/motion_v2_models.dart';
import '../../ai/motion_v2/motion_v2_native_runtime.dart';
import '../../ai/motion_v2/pose_quality.dart';
import '../../ai/motion_v2/pose_track.dart';
import '../../data/ai_motion_models.dart';
import '../../ai/custom_pose/custom_pose_sequence_runtime.dart';
import '../../ai/custom_pose/custom_pose_verifier_spec.dart';
import '../../ai/custom_pose/normalized_pose.dart';
import '../../ai/custom_pose/pose_calibration_flow.dart';
import '../../ai/custom_pose/pose_stream_controller.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../ai/motion_session/motion_session_providers.dart';
import '../race_controller.dart';
import 'learned_custom_movement_provider.dart';
import 'learned_movement_preview.dart';
import 'pose_skeleton_overlay.dart';

const bool kNuvoDiagnosticsEnabled = bool.fromEnvironment('NUVO_DIAGNOSTICS');
const _debugFixtureFeatureId = 'angle.left_hip';

/// Arguments passed by the race composer when it opens Teach Nuvo as its
/// required training stage. When [movementName] is set the screen skips its own
/// name step and opens straight on "Example 1 of 3".
class TeachMovementArgs {
  const TeachMovementArgs({required this.movementName, this.unit});
  final String movementName;
  final String? unit;
}

class TeachMovementScreen extends ConsumerStatefulWidget {
  const TeachMovementScreen({
    super.key,
    this.seedReadyFixture = false,
    this.args,
  });

  final bool seedReadyFixture;

  /// Non-null when launched from the race composer. Carries the movement name
  /// (already collected) so the user isn't asked for it twice, and the screen
  /// returns its [CustomPoseVerifierSpec] via `Navigator.pop`.
  final TeachMovementArgs? args;

  bool get returnsSpec => args != null;

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
  final _poseStream = PoseStreamController();
  CameraController? _cameraController;
  List<CameraDescription> _cameras = const [];
  CameraDescription? _selectedCamera;
  String? _nameError;
  bool _cameraReady = false;
  bool _cameraBusy = false;
  bool _imageStreamStarting = false;
  bool _disposed = false;
  bool _testingVerifier = false;
  bool _cameraInterruptedDuringTest = false;
  bool _debugReadyFixture = false;
  bool _navigating = false;
  CustomPoseSequenceRuntime? _customRuntime;
  CustomPoseRuntimeUpdate? _customUpdate;
  CustomPoseRuntimeResult? _customTestResult;
  CustomPoseVerifierSpec? _debugSpec;
  final List<Map<String, dynamic>> _runtimeDiagnostics = [];
  Timer? _uiUpdateTimer;
  Timer? _skeletonExpiryTimer;
  static const int _testTarget = 5;
  static const int _skeletonHoldMs = 900;
  static const int _uiThrottleMs = 100;
  final _skeletonHold = SkeletonFrameHold(
    holdDuration: const Duration(milliseconds: _skeletonHoldMs),
  );
  bool _learnedWrittenToProvider = false;

  // Raw pose-stream capture — one list of NuvoPoseFrames per accepted demo.
  // Feeds Motion V2 (learn) + the fixture export in the debug report.
  final List<List<NuvoPoseFrame>> _rawDemos = [];
  // Untrimmed copies for the V2 learner — segmentAction finds the active
  // region itself, and a slow lead-in (walk to the bar) must not be cut.
  final List<List<NuvoPoseFrame>> _v2Demos = [];
  List<NuvoPoseFrame> _rawCurrent = [];
  int _rawAcceptedSnapshot = 0;

  // ── Diagnostic session recorder (behind NUVO_DIAGNOSTICS) ──────────────────
  DateTime? _sessionStart;
  // per-demo: unsmoothed + smoothed frame pairs and the tracking snapshot.
  final List<Map<String, dynamic>> _demoDiag = [];
  final List<NuvoPoseFrame> _diagCaptureRaw = [];
  final List<NuvoPoseFrame> _diagCaptureSmoothed = [];
  // live test
  final List<Map<String, dynamic>> _liveTestFrames = [];
  final List<Map<String, dynamic>> _matchTrace = [];
  DateTime? _liveTestStart;
  final Map<String, List<int>> _latencyMs = {};
  int _framesReceived = 0;
  int _framesProcessed = 0;
  String? _savedSessionId;
  String? _savedSessionPath;

  // ── Deterministic teach flow ───────────────────────────────────────────────
  // The user drives every step: Record → Stop → Save example, ×3, then an
  // explicit "Learn movement" tap. Nothing auto-builds and nothing navigates
  // until the user taps "Use this movement" on the learned screen.
  static const int _requiredExamples = 3;
  // Examples the user has explicitly confirmed with "Save example".
  int _confirmedExamples = 0;
  // A recording just stopped and was accepted — waiting on "Save example".
  bool _awaitingExampleSave = false;
  // The user tapped "Learn movement"; build is running.
  bool _learnRequested = false;

  // ── Motion V2 — the default custom-motion engine (on-device ONNX) ────────
  MotionV2NativeRuntime? _v2;
  TaughtMotionV2Spec? _v2Spec;
  bool _v2Learning = false;
  String? _v2Error;
  MotionV2RuntimeResult _v2Result = MotionV2RuntimeResult.empty;
  int _v2Count = 0;
  final List<NuvoPoseFrame> _v2Batch = [];
  bool _v2Busy = false;
  static const int _v2BatchSize = 4;

  // ── Temporal pose tracking (smoothing + readiness hysteresis + motion start).
  // The user taps Record first; the track decides when useful capture begins.
  final PoseTrack _track = PoseTrack();
  // Record tapped, waiting for the track to become READY (no frames saved yet).
  bool _preparing = false;
  // ~1s of smoothed frames kept so the movement's opening isn't lost.
  final List<NuvoPoseFrame> _preRoll = [];
  static const int _preRollCap = 18;

  // ── Live camera-readiness guidance (shared PoseQuality evaluator) ───────────
  PoseQuality _captureQuality = PoseQuality.noFrame;
  // Rough capture-quality counters for the diagnostic report.
  int _poseFrameCount = 0;
  int _poseFrameValid = 0;
  DateTime? _firstPoseAt;
  SelfValidationReport? _selfValidation;
  // The last frames of a failed live attempt, kept as a replayable fixture.
  List<NuvoPoseFrame> _lastFailedAttemptFrames = const [];
  final List<NuvoPoseFrame> _v2AttemptWindow = [];

  /// Set when the V2 engine itself could not run on this device (its native
  /// runtime or model failed to load) — not a problem with the user's examples.
  /// Teaching then continues on the V1 matcher instead of dead-ending.
  bool _v2Unavailable = false;

  /// The centred "here's what happens" screen shown before the camera opens.
  bool _introPending = false;

  /// Motion V2 is the default; V1 when forced for troubleshooting, or when V2
  /// proved unavailable on this device.
  bool get _useMotionV2 => !kMotionV1Forced && !_v2Unavailable;

  CustomPoseVerifierSpec? get _effectiveSpec =>
      _debugReadyFixture ? _debugSpec : _flow.verifierSpec;
  // Diagnostics are an explicit opt-in tool, never part of the normal custom
  // movement experience and never available in a release build.
  bool get _showDiagnostics => kNuvoDiagnosticsEnabled && !kReleaseMode;

  @override
  void initState() {
    super.initState();
    _flow = SingleSessionTeachingCapture(onChanged: _onFlowChanged);
    WidgetsBinding.instance.addObserver(this);
    // Retry teach sessions that failed to upload on a previous run.
    unawaited(ref.read(teachSessionUploadQueueProvider).flush());
    if (kDebugMode && widget.seedReadyFixture) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _seedDebugReadyFixture();
      });
      return;
    }
    // Launched from the composer with the movement already named — skip our own
    // name step and open straight on "Example 1 of 3".
    final preset = widget.args?.movementName.trim() ?? '';
    if (preset.isNotEmpty) {
      _nameController.text = preset;
      _introPending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // The camera opens from the intro's Start button, not automatically.
        if (_flow.setMovementName(preset) != null) {
          setState(() => _introPending = false);
        }
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // Seal the teach session — the abandoned/failed ones are often the most
    // useful diagnostic. 'used' already finalized on the Use tap, so this is
    // a no-op on the happy path.
    _finalizeTeachSession(
      outcome:
          _v2Error != null ||
              _flow.lastBuildFailure != null ||
              (_selfValidation != null && !_selfValidation!.passed)
          ? 'failed'
          : (_effectiveSpec != null || _v2Spec != null)
          ? 'learned'
          : 'abandoned',
    );
    WidgetsBinding.instance.removeObserver(this);
    _nameController.dispose();
    _raceTitleController.dispose();
    _raceTargetController.dispose();
    _stopCamera();
    _poseStream.dispose();
    _customRuntime?.dispose();
    _v2?.dispose();
    _skeletonExpiryTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      if (_flow.stage == TeachMovementStage.recording ||
          _flow.stage == TeachMovementStage.holdStill ||
          _flow.stage == TeachMovementStage.capturing) {
        _flow.markInterrupted();
      }
      if (_testingVerifier) {
        _cameraInterruptedDuringTest = true;
        _stopVerifierTest();
      }
      _stopCamera();
    } else if (state == AppLifecycleState.resumed &&
        !_introPending &&
        _flow.stage != TeachMovementStage.name) {
      _initializeCamera(camera: _selectedCamera);
    }
  }

  Future<void> _initializeCamera({CameraDescription? camera}) async {
    if (_cameraBusy || _disposed) return;
    _cameraBusy = true;
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _setCameraError('No camera is available on this device.');
        return;
      }
      final selected = camera ?? _preferredCamera(_cameras);
      _selectedCamera = selected;
      _syncCaptureDeviceInfo(selected);
      await _stopImageStream();
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
    } finally {
      _cameraBusy = false;
    }
  }

  Future<void> _startImageStream() async {
    final controller = _cameraController;
    final camera = _selectedCamera;
    if (controller == null ||
        camera == null ||
        _imageStreamStarting ||
        !controller.value.isInitialized ||
        controller.value.isStreamingImages) {
      return;
    }
    _imageStreamStarting = true;
    try {
      await controller.startImageStream((image) {
        _handleFrame(image, camera, controller.value.deviceOrientation);
      });
    } finally {
      _imageStreamStarting = false;
    }
  }

  Future<void> _handleFrame(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation orientation,
  ) async {
    if (_disposed || !_cameraReady) return;
    _framesReceived++;
    try {
      final update = await _poseStream.processCameraImage(
        image: image,
        camera: camera,
        deviceOrientation: orientation,
      );
      if (!mounted || _disposed) return;
      final now = DateTime.now();
      _sessionStart ??= now;
      if (update.skipped) {
        _expireSkeletonIfNeeded(now);
        _requestSetState();
        return;
      }
      final rawFrame = update.frame;
      final pose = update.pose;
      // Feed the temporal tracker every frame (null = a detector miss) so
      // readiness hysteresis, smoothing and motion-start stay continuous.
      final frame = _track.update(rawFrame, now);
      if (frame == null || pose == null) {
        _flow.markFrameMissing();
        if (!_testingVerifier) _captureQuality = _track.quality;
        _maybeAutoStartCapture(now);
        _expireSkeletonIfNeeded(now);
        _requestSetState();
        return;
      }
      _flow.addFrame(pose, frame.createdAt);
      _poseFrameCount++;
      _framesProcessed++;
      _firstPoseAt ??= now;
      if (rawFrame != null) _recordDiagFrame(now, rawFrame, frame);

      if (!_testingVerifier) {
        _captureQuality = _track.quality;
        if (_track.quality.trackable) _poseFrameValid++;
        // rolling pre-roll of smoothed frames (the movement's opening)
        _preRoll.add(frame);
        if (_preRoll.length > _preRollCap) _preRoll.removeAt(0);
        _maybeAutoStartCapture(now);
      }

      if ((_showDiagnostics || _useMotionV2) &&
          _flow.stage == TeachMovementStage.recording) {
        _rawCurrent.add(frame);
      }
      if (_flow.isBodyVisiblePose(pose)) {
        _skeletonHold.show(frame, now);
        _scheduleSkeletonExpiry();
      } else {
        _expireSkeletonIfNeeded(now);
      }
      if (_testingVerifier) {
        if (_useMotionV2 && _v2Spec != null) {
          _v2Batch.add(frame);
          unawaited(_pumpMotionV2());
        } else {
          final update = _customRuntime?.update(frame);
          _customUpdate = update?.customPoseUpdate;
          _recordRuntimeDiagnostic(_customUpdate);
          if (_customUpdate?.completed == true && _customTestResult == null) {
            _completeVerifierTest();
          }
        }
      }
      _requestSetState();
    } on CameraImageConversionException catch (e) {
      _flow.message = e.message;
      _skeletonHold.clear();
      await _stopImageStream();
      _requestSetState();
    } catch (_) {
      _flow.message = 'Pose detection failed. Try again.';
      _skeletonHold.clear();
      await _stopImageStream();
      _requestSetState();
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
    if (controller == null ||
        !controller.value.isInitialized ||
        !controller.value.isStreamingImages) {
      return;
    }
    try {
      await controller.stopImageStream();
    } on CameraException catch (_) {
      // The stream may already be stopped or the controller may be closing.
    }
  }

  Future<void> _stopCamera() async {
    await _stopImageStream();
    try {
      await _cameraController?.dispose();
    } on CameraException catch (_) {
      // Already disposed or controller failed.
    }
    _cameraController = null;
    _cameraReady = false;
    _cameraBusy = false;
    _imageStreamStarting = false;
    _poseStream.reset();
    _skeletonHold.clear();
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = null;
    _skeletonExpiryTimer?.cancel();
    _skeletonExpiryTimer = null;
    _flow.markFrameMissing();
  }

  void _requestSetState() {
    if (_disposed || !mounted) return;
    if (_uiUpdateTimer?.isActive == true) return;
    _uiUpdateTimer = Timer(const Duration(milliseconds: _uiThrottleMs), () {
      _uiUpdateTimer = null;
      if (mounted && !_disposed) setState(() {});
    });
  }

  void _setCameraError(String message) {
    if (!mounted || _disposed) return;
    _skeletonHold.clear();
    _flow.markFrameMissing();
    setState(() {
      _cameraReady = false;
      _flow.message = message;
    });
  }

  void _expireSkeletonIfNeeded(DateTime now) {
    _skeletonHold.expire(now);
  }

  void _scheduleSkeletonExpiry() {
    _skeletonExpiryTimer?.cancel();
    _skeletonExpiryTimer = Timer(
      const Duration(milliseconds: _skeletonHoldMs + 20),
      () {
        if (_disposed || !mounted) return;
        _expireSkeletonIfNeeded(DateTime.now());
        _requestSetState();
      },
    );
  }

  bool _isPermissionError(CameraException e) =>
      e.code == 'CameraAccessDenied' ||
      e.code == 'CameraAccessDeniedWithoutPrompt' ||
      e.code == 'CameraAccessRestricted';

  Future<void> _switchCamera() async {
    if (_cameraBusy || _cameras.length < 2) return;
    final current = _selectedCamera;
    final next = _cameras.firstWhere(
      (camera) => camera.lensDirection != current?.lensDirection,
      orElse: () => _cameras.first,
    );
    if (next == current) return;
    await _stopCamera();
    await _initializeCamera(camera: next);
  }

  /// "Record example N" — always pressable. Enters PREPARING; the camera is
  /// live and tracking, but nothing is saved yet. The user can be standing too
  /// close / out of frame here — guidance coaches them into position.
  void _startRecording() {
    _rawCurrent = [];
    _preRoll.clear();
    _rawAcceptedSnapshot = _flow.acceptedCount;
    _track.armForCapture();
    setState(() => _preparing = true);
  }

  /// Auto-transition PREPARING → capturing once the temporal tracker is READY.
  void _maybeAutoStartCapture(DateTime now) {
    if (!_preparing || _flow.stage == TeachMovementStage.recording) return;
    if (!_track.isReady) return;
    _preparing = false;
    _rawAcceptedSnapshot = _flow.acceptedCount;
    _flow.startRecordingExample();
    // Seed with the pre-roll (minus this frame — the normal path adds it) so
    // the movement's opening isn't lost even if Record was tapped late.
    _rawCurrent = _preRoll.length > 1
        ? List.of(_preRoll.sublist(0, _preRoll.length - 1))
        : <NuvoPoseFrame>[];
  }

  void _cancelPreparing() {
    setState(() => _preparing = false);
    _preRoll.clear();
  }

  void _finishRecording() {
    if (_preparing) {
      _cancelPreparing();
      return;
    }
    _flow.stopRecordingExample();
    final accepted = _flow.acceptedCount > _rawAcceptedSnapshot;
    if ((_showDiagnostics || _useMotionV2) && accepted) {
      final trimmed = _autoTrimSetup(_rawCurrent);
      if (trimmed.length >= 4) _rawDemos.add(trimmed);
      if (_rawCurrent.length >= 4) {
        _v2Demos.add(List<NuvoPoseFrame>.of(_rawCurrent));
      }
      _snapshotDemoDiag(trimmed);
      _snapshotTeachSession();
    }
    _rawCurrent = [];
    _preRoll.clear();
    // Deterministic: an accepted recording waits for an explicit "Save example"
    // tap. Nothing auto-builds — the user taps "Learn movement" after 3 saves.
    setState(() => _awaitingExampleSave = accepted);
  }

  /// Drop the "walking into position / settling" frames before the movement
  /// actually started. Keeps ~0.3s of lead-in. Forgiving: if no motion-start
  /// was detected, return the buffer unchanged (the V2 learner segments too).
  List<NuvoPoseFrame> _autoTrimSetup(List<NuvoPoseFrame> frames) {
    final startedAt = _track.motionStartedAt;
    if (startedAt == null || frames.length < 8) return List.of(frames);
    final cutoff = startedAt.subtract(const Duration(milliseconds: 300));
    var first = frames.indexWhere((f) => f.createdAt.isAfter(cutoff));
    if (first <= 0) return List.of(frames);
    first = math.min(first, frames.length - 6); // never trim to almost nothing
    return frames.sublist(first);
  }

  void _saveExample() {
    _confirmedExamples = _flow.acceptedCount;
    setState(() => _awaitingExampleSave = false);
  }

  void _redoExample() {
    _flow.removeLastAccepted();
    if (_rawDemos.length > _confirmedExamples) _rawDemos.removeLast();
    if (_v2Demos.length > _confirmedExamples) _v2Demos.removeLast();
    _rawAcceptedSnapshot = _flow.acceptedCount;
    setState(() => _awaitingExampleSave = false);
  }

  void _learnMovement() {
    if (_confirmedExamples < _requiredExamples || !_flow.canLearn) return;
    setState(() => _learnRequested = true);
    _flow.buildWhenReady();
    if (_useMotionV2) unawaited(_learnMotionV2());
  }

  // ── Motion V2 — on-device learn ──────────────────────────────────────────
  Future<void> _learnMotionV2() async {
    if (_v2Learning || _rawDemos.length < 2) return;
    setState(() {
      _v2Learning = true;
      _v2Error = null;
    });
    // System B: give the encoder the remote-model delivery path for this
    // session. Unset it falls back to last-known-good / bundled.
    final controller = ref.read(raceControllerProvider.notifier);
    MotionV2OnnxEncoder.configureModelSource(
      MotionV2ModelSource(
        resolveModel: (family) =>
            controller.getCurrentMotionModel(family: family),
        fetchArtifact: (v) => controller.getMotionModelArtifact(v),
      ),
    );
    final runtime = MotionV2NativeRuntime();
    try {
      final spec = await runtime.learn(
        movementName: _flow.movementName.isEmpty
            ? 'Custom movement'
            : _flow.movementName,
        demos: (_v2Demos.isNotEmpty ? _v2Demos : _rawDemos)
            .map((d) => List<NuvoPoseFrame>.of(d))
            .toList(),
      );
      await _v2?.dispose();
      _v2 = runtime;
      _selfValidation = runtime.lastSelfValidation;
      if (!mounted) return;
      // V2's encoder just proved the demos are one learnable movement. If V1's
      // pairwise-consistency heuristic rejected them anyway, rebuild V1 under
      // independent evidence — its own spec self-validation still arbitrates.
      // Without this, "Let's try that again" fires on a teach V2 got right.
      final v1ConsistencyRejected =
          _flow.verifierSpec == null && _flow.lastFailureWasConsistency;
      if (v1ConsistencyRejected && (_selfValidation?.passed ?? false)) {
        _flow.retryBuildLenient();
      }
      setState(() {
        _v2Spec = spec;
        _v2Learning = false;
      });
      _syncLearnedProvider();
      _snapshotTeachSession();
    } on MotionV2LearnException catch (e) {
      // Self-validation failed — the spec is junk. Keep the report for the
      // debug bundle, show the user something actionable.
      _selfValidation = e.report;
      await runtime.dispose();
      if (!mounted) return;
      setState(() {
        _v2Error = e.message.startsWith('NOT_ENOUGH_MOTION')
            ? 'Nuvo could not see the movement — try a fuller rep with your '
                  'whole body in frame.'
            : "Let's record that again — the three examples were too "
                  'different for Nuvo to learn from.';
        _v2Learning = false;
      });
      _snapshotTeachSession();
    } on MotionV2Exception catch (e) {
      await runtime.dispose();
      if (!mounted) return;
      setState(() {
        _v2Error = e.message;
        _v2Learning = false;
      });
    } catch (e) {
      // Not a MotionV2Exception: the engine could not run at all (e.g. the
      // ONNX Runtime library failed to load). Don't show the user a raw
      // native error or ask them to re-record — fall back to the V1 matcher,
      // which the teaching flow has already been building in parallel.
      debugPrint('Motion V2 unavailable, falling back to V1: $e');
      try {
        await runtime.dispose();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _v2Unavailable = true;
        _v2Error = null;
        _v2Learning = false;
      });
    }
  }

  Future<void> _pumpMotionV2() async {
    if (_v2Busy || _v2Batch.length < _v2BatchSize || _v2 == null) return;
    _v2Busy = true;
    final batch = List<NuvoPoseFrame>.of(_v2Batch);
    _v2Batch.clear();
    _v2AttemptWindow.addAll(batch);
    if (_v2AttemptWindow.length > 90) {
      _v2AttemptWindow.removeRange(0, _v2AttemptWindow.length - 90);
    }
    try {
      final r = await _v2!.update(batch);
      if (!mounted || !_testingVerifier) return;
      final firedRep = r.newRep;
      // Keep the frames of a failed attempt as a replayable fixture.
      if (r.attempt.outcome == MotionAttemptOutcome.failed) {
        _lastFailedAttemptFrames = List<NuvoPoseFrame>.of(_v2AttemptWindow);
      } else if (r.attempt.outcome == MotionAttemptOutcome.success ||
          r.state == MotionV2RuntimeState.neutral) {
        _v2AttemptWindow.clear();
      }
      _recordMatchWindow(r);
      _latencyMs
          .putIfAbsent('encoder+matcher', () => [])
          .add(r.inferenceLatency.inMilliseconds);
      setState(() {
        _v2Result = r;
        if (firedRep) _v2Count = r.count;
      });
      if (firedRep) HapticFeedback.lightImpact();
    } on MotionV2Exception catch (e) {
      if (mounted) setState(() => _v2Error = e.message);
    } finally {
      _v2Busy = false;
    }
  }

  void _cancelRecording() {
    _rawCurrent = [];
    _flow.cancelRecordingExample();
  }

  static Map<String, dynamic> _serializeRawFrame(NuvoPoseFrame frame) {
    return {
      't': frame.createdAt.millisecondsSinceEpoch,
      'w': frame.imageWidth,
      'h': frame.imageHeight,
      'points': {
        for (final e in frame.points.entries)
          e.key: [e.value.x, e.value.y, e.value.z, e.value.likelihood],
      },
    };
  }

  // ── Teach session recording ───────────────────────────────────────────────
  // Always on (bounded): the artifact carries the data the offline evaluator
  // replays — demos, both matcher specs, self-validation, the live-test trace.
  // Upload is consent-gated at finalize; the NUVO_DIAGNOSTICS flag only gates
  // the debug UI and the manual share actions now.

  int _sessionMs(DateTime t) => t.difference(_sessionStart ?? t).inMilliseconds;

  void _recordDiagFrame(
    DateTime now,
    NuvoPoseFrame raw,
    NuvoPoseFrame smoothed,
  ) {
    if (_testingVerifier) {
      if (_liveTestFrames.length > 900) return;
      _liveTestFrames.add({
        't': _sessionMs(now),
        'raw': _serializeRawFrame(raw)['points'],
        'smoothed': _serializeRawFrame(smoothed)['points'],
        'readiness': _track.quality.readiness.name,
        'energy': _track.articulationEnergy,
      });
    } else if (_preparing || _flow.stage == TeachMovementStage.recording) {
      if (_diagCaptureRaw.length > 900) return;
      _diagCaptureRaw.add(raw);
      _diagCaptureSmoothed.add(smoothed);
    }
  }

  void _recordMatchWindow(MotionV2RuntimeResult r) {
    final now = DateTime.now();
    final proto = <double>[];
    final traj = <double>[];
    final votes = <bool>[];
    for (final p in r.perReference) {
      proto.add((p['proto'] as num?)?.toDouble() ?? -1);
      traj.add((p['traj'] as num?)?.toDouble() ?? -1);
      votes.add(p['matches'] == true);
    }
    _matchTrace.add(
      MotionDiagMatchWindow(
        tMs: _sessionMs(now),
        bufferFrames: r.bufferFrames,
        protoDist: proto,
        trajDist: traj,
        votesList: votes,
        separation: r.separation,
        motionProgress: r.motionProgress,
        decision: r.decision,
        confidence: r.confidence,
        state: r.state.name,
        newRep: r.newRep,
        count: r.count,
        inferenceMs: r.inferenceLatency.inMilliseconds,
      ).toJson(),
    );
    if (_matchTrace.length > 600) _matchTrace.removeAt(0);
  }

  void _snapshotDemoDiag(List<NuvoPoseFrame> trimmed) {
    if (_diagCaptureRaw.isEmpty) return;
    final raw = List<NuvoPoseFrame>.of(_diagCaptureRaw);
    final sm = List<NuvoPoseFrame>.of(_diagCaptureSmoothed);
    final start = raw.first.createdAt, end = raw.last.createdAt;
    final durMs = end.difference(start).inMilliseconds;
    _demoDiag.add({
      'index': _demoDiag.length + 1,
      'startMs': _sessionMs(start),
      'endMs': _sessionMs(end),
      'rawFrameCount': raw.length,
      'trimmedFrameCount': trimmed.length,
      'estFps': durMs <= 0 ? 0.0 : (raw.length - 1) * 1000 / durMs,
      'tracking': _track.toDiagnosticsJson(),
      'segmentation': {
        'motionStarted': _track.motionStarted,
        'motionStartedAtMs': _track.motionStartedAt == null
            ? null
            : _sessionMs(_track.motionStartedAt!),
        'preRollFrames': _preRoll.length,
        'trimmedFromStart': raw.length - trimmed.length,
      },
      'rawFrames': [for (final f in raw) _serializeRawFrame(f)],
      'smoothedFrames': [for (final f in sm) _serializeRawFrame(f)],
    });
    _diagCaptureRaw.clear();
    _diagCaptureSmoothed.clear();
  }

  Map<String, double> _latencyStats(List<int> xs) {
    if (xs.isEmpty) return const {};
    final s = List<int>.of(xs)..sort();
    double pct(double p) => s[(p * (s.length - 1)).round()].toDouble();
    return {
      'avg': s.reduce((a, b) => a + b) / s.length,
      'p50': pct(0.5),
      'p95': pct(0.95),
      'max': s.last.toDouble(),
      'n': s.length.toDouble(),
    };
  }

  /// Which matcher ran this teach's learn/test — `v1_fallback` means the V2
  /// engine could not run on this device at all (native load failure), so the
  /// cloud triage can split "user examples were bad" from "the engine broke".
  String get _teachEngine =>
      _v2Unavailable ? 'v1_fallback' : (_useMotionV2 ? 'v2' : 'v1');

  NuvoMotionDiagnosticSession _buildDiagnosticSession({
    String? outcome,
    String? failureStage,
    String failureReason = '',
  }) {
    final now = DateTime.now();
    final id = NuvoMotionDiagnosticSession.newId(
      now,
      const Uuid().v4().replaceAll('-', '').substring(0, 6),
    );
    final demos = <MotionDiagDemo>[
      for (final d in _demoDiag)
        MotionDiagDemo(
          index: d['index'] as int,
          startMs: d['startMs'] as int,
          endMs: d['endMs'] as int,
          rawFrameCount: d['rawFrameCount'] as int,
          trimmedFrameCount: d['trimmedFrameCount'] as int,
          estFps: (d['estFps'] as num).toDouble(),
          tracking: d['tracking'] as Map<String, dynamic>,
          segmentation: d['segmentation'] as Map<String, dynamic>,
          frames: [
            for (var i = 0; i < (d['rawFrames'] as List).length; i++)
              MotionDiagFrame(
                tMs: ((d['rawFrames'] as List)[i]['t'] as num).toInt(),
                raw: {
                  for (final e
                      in ((d['rawFrames'] as List)[i]['points'] as Map).entries)
                    e.key as String: [
                      for (final x in e.value as List) (x as num).toDouble(),
                    ],
                },
                smoothed: i < (d['smoothedFrames'] as List).length
                    ? {
                        for (final e
                            in ((d['smoothedFrames'] as List)[i]['points']
                                    as Map)
                                .entries)
                          e.key as String: [
                            for (final x in e.value as List)
                              (x as num).toDouble(),
                          ],
                      }
                    : null,
              ),
          ],
        ),
    ];

    MotionDiagLiveTest? live;
    if (_liveTestStart != null) {
      live = MotionDiagLiveTest(
        startMs: _sessionMs(_liveTestStart!),
        endMs: _sessionMs(now),
        finalCount: _v2Count,
        finalAttempt: _v2Result.attempt.toJson()
          ..addAll({
            'lastDecision': _v2Result.decision,
            'lastVotes': _v2Result.votes,
            'lastSeparation': _v2Result.separation,
          }),
        matchTrace: [
          for (final m in _matchTrace)
            MotionDiagMatchWindow(
              tMs: m['t'] as int,
              bufferFrames: m['buffer'] as int,
              protoDist: [
                for (final x in m['proto'] as List) (x as num).toDouble(),
              ],
              trajDist: [
                for (final x in m['traj'] as List) (x as num).toDouble(),
              ],
              votesList: [for (final x in m['voteList'] as List) x as bool],
              separation: (m['separation'] as num?)?.toDouble(),
              motionProgress: (m['progress'] as num).toDouble(),
              decision: m['decision'] as String,
              confidence: (m['confidence'] as num).toDouble(),
              state: m['state'] as String,
              newRep: m['newRep'] == true,
              count: m['count'] as int,
              inferenceMs: (m['inferenceMs'] as num).toInt(),
            ),
        ],
        frames: [
          for (final f in _liveTestFrames)
            MotionDiagFrame(
              tMs: f['t'] as int,
              raw: {
                for (final e in (f['raw'] as Map).entries)
                  e.key as String: [
                    for (final x in e.value as List) (x as num).toDouble(),
                  ],
              },
              smoothed: {
                for (final e in (f['smoothed'] as Map).entries)
                  e.key as String: [
                    for (final x in e.value as List) (x as num).toDouble(),
                  ],
              },
              readiness: f['readiness'] as String?,
              articulationEnergy: (f['energy'] as num?)?.toDouble(),
            ),
        ],
      );
    }

    // The V1 half — the spec a created race actually verifies with, the
    // builder's feature/threshold diagnostics, and the V1 live-test verdict.
    // Without this the replay can only ever judge V2, never the shipped path.
    final v1Spec = _effectiveSpec;
    final v1Test = _customTestResult;
    final v2LiveTest = _useMotionV2 && _v2Spec != null;
    final liveTestMatched = _liveTestStart == null
        ? null
        : v2LiveTest
        ? _v2Result.matched
        : v1Test?.isVerified;
    final v1 = {
      if (v1Spec != null) 'spec': v1Spec.toJson(),
      'build': _flow.debugReport(),
      if (v1Test != null) 'testResult': v1Test.toJson(),
      if (_runtimeDiagnostics.isNotEmpty)
        'runtimeDiagnostics': _runtimeDiagnostics,
      'buildFailure': ?_flow.lastBuildFailure,
    };

    return NuvoMotionDiagnosticSession(
      sessionId: id,
      timestamp: now,
      meta: {
        'appVersion': const String.fromEnvironment(
          'NUVO_APP_VERSION',
          defaultValue: 'dev',
        ),
        'gitCommit': const String.fromEnvironment(
          'NUVO_GIT_COMMIT',
          defaultValue: 'unknown',
        ),
        'platform': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
        'buildMode': kReleaseMode
            ? 'release'
            : kProfileMode
            ? 'profile'
            : 'debug',
        'motionV2Schema': _v2Spec?.json['schema'],
        'encoder': _v2?.encoderId ?? 'release_action',
        'onnxAsset': 'assets/models/motion_v2_encoder.onnx',
        'modelRelease': MotionV2OnnxEncoder.activeModelVersion,
        'modelChecksum': MotionV2OnnxEncoder.activeModelChecksum,
        'modelSource': MotionV2OnnxEncoder.activeModelSource,
        'matcher': 'multi_reference/schema4',
        'normalization': 'root_scale_normalize',
        'diagSchema': kMotionDiagSchema,
        if (_v2Unavailable) 'v2Unavailable': true,
        'liveTestMatched': ?liveTestMatched,
        'poseFrameCount': _poseFrameCount,
        'poseFrameValid': _poseFrameValid,
      },
      teaching: demos,
      selfValidation: _selfValidation?.toJson(),
      spec: _v2Spec?.toJson(),
      v1: v1,
      liveTest: live,
      performance: {
        'framesReceived': _framesReceived,
        'framesProcessed': _framesProcessed,
        'framesDropped': _framesReceived - _framesProcessed,
        'stages': {
          for (final e in _latencyMs.entries) e.key: _latencyStats(e.value),
        },
      },
      movementName: _flow.movementName,
      outcome:
          outcome ?? (_effectiveSpec != null ? 'learned' : 'abandoned'),
      engine: _teachEngine,
      failureStage: failureStage,
      failureReason: failureReason,
      durationMs: _sessionStart == null
          ? 0
          : now.difference(_sessionStart!).inMilliseconds,
    );
  }

  /// Upload the teach session as it stands after a step (demo recorded, V2
  /// learned, live test done).
  void _snapshotTeachSession() => _finalizeTeachSession(
    outcome: _effectiveSpec != null ? 'learned' : 'abandoned',
    snapshot: true,
  );

  /// Seal the teach session and hand it to the upload queue — consent-gated
  /// exactly like verification sessions. Idempotent: [outcome] is only sent
  /// the first time, so a "used" finalize wins over the dispose-path one.
  bool _teachSessionFinalized = false;

  void _finalizeTeachSession({required String outcome, bool snapshot = false}) {
    if (_teachSessionFinalized) return;
    // A snapshot uploads the session as it stands (same id, server upserts) so
    // each teach step is visible even if the screen never reaches its end.
    if (!snapshot) _teachSessionFinalized = true;

    // Where did it stop being happy? The stage tells the triage whether the
    // user gave up recording, the V1 builder failed, V2 learning failed, or
    // the live test couldn't match.
    final String? failureStage;
    final String failureReason;
    if (outcome == 'used' || outcome == 'learned') {
      failureStage = null;
      failureReason = '';
    } else if (_v2Error != null ||
        _selfValidation != null && _selfValidation!.passed == false) {
      failureStage = 'v2_learn';
      failureReason = _selfValidation != null && !_selfValidation!.passed
          ? 'self_validation_failed'
          : 'v2_learn_error';
    } else if (_flow.lastBuildFailure != null) {
      failureStage = 'v1_build';
      failureReason = _flow.lastBuildFailure!;
    } else if (_customTestResult != null && !_customTestResult!.isVerified) {
      failureStage = 'live_test';
      failureReason = 'test_not_matched';
    } else if (outcome == 'abandoned' && _demoDiag.isEmpty) {
      return; // never recorded anything — nothing worth uploading
    } else {
      failureStage = 'recording';
      failureReason = '';
    }

    final session = _buildDiagnosticSession(
      outcome: outcome,
      failureStage: failureStage,
      failureReason: failureReason,
    );
    // Telemetry must never break the app — this also runs inside dispose(),
    // where a provider edge should degrade to "not uploaded", not a crash.
    try {
      final consented =
          ref.read(authControllerProvider).user?.motionTrainingConsent == true;
      if (!consented) return;
      // Fire-and-forget: staging + upload happen off the UI path, identical
      // to verification sessions (a failure just retries on the next flush).
      unawaited(
        ref
            .read(teachSessionUploadQueueProvider)
            .enqueueRaw(
              sessionId: session.sessionId,
              metadata: session.metadata(),
              gzipBytes: session.toGzipBytes(),
            ),
      );
    } catch (e) {
      debugPrint('teach session upload skipped: $e');
    }
  }

  Future<void> _copyMotionV2Log() async {
    final text = _buildDiagnosticSession().toLogText();
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Motion V2 log copied.')));
    }
  }

  Future<void> _saveDiagnosticSession() async {
    try {
      final session = _buildDiagnosticSession();
      final bytes = session.toGzipBytes();
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${session.sessionId}.json.gz');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      setState(() {
        _savedSessionId = session.sessionId;
        _savedSessionPath = file.path;
      });
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/gzip')],
        subject: 'Nuvo Motion V2 session ${session.sessionId}',
        text:
            'Motion V2 diagnostic session ${session.sessionId} '
            '(${(bytes.length / 1024).toStringAsFixed(0)} KB gz)',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  Future<void> _submitName() async {
    final error = _flow.setMovementName(_nameController.text);
    if (error != null) {
      setState(() => _nameError = error);
      return;
    }
    setState(() {
      _nameError = null;
      _introPending = true;
    });
  }

  void _onFlowChanged() {
    _syncLearnedProvider();
    _requestSetState();
  }

  void _syncLearnedProvider() {
    final spec = _effectiveSpec;
    final v2 = _v2Spec;
    if (spec == null && v2 == null) return;
    // Don't rewrite an already-learned movement until the V2 spec lands — the
    // race prefers V2 and the provider is what carries it into race creation.
    if (_learnedWrittenToProvider && v2 == null) return;
    _learnedWrittenToProvider = true;
    ref.read(learnedCustomMovementProvider.notifier).state =
        LearnedCustomMovement(
          verifierSpec: spec,
          motionV2Spec: v2,
          learnedAt: DateTime.now(),
        );
  }

  void _resetTeachFlags() {
    _confirmedExamples = 0;
    _awaitingExampleSave = false;
    _learnRequested = false;
    _v2Spec = null;
    _v2Learning = false;
    _v2Error = null;
    _rawAcceptedSnapshot = 0;
    _selfValidation = null;
    _lastFailedAttemptFrames = const [];
    _v2AttemptWindow.clear();
    _poseFrameCount = 0;
    _poseFrameValid = 0;
    _firstPoseAt = null;
    _preparing = false;
    _preRoll.clear();
    _track.reset();
    _demoDiag.clear();
    _diagCaptureRaw.clear();
    _diagCaptureSmoothed.clear();
    _liveTestFrames.clear();
    _matchTrace.clear();
    _latencyMs.clear();
    _liveTestStart = null;
    _savedSessionId = null;
    _savedSessionPath = null;
    _framesReceived = 0;
    _framesProcessed = 0;
    _sessionStart = null;
    // A retried teach is a NEW session — without this, a 'used'/'failed'
    // finalize earlier in the screen's life would swallow it.
    _teachSessionFinalized = false;
  }

  void _restart() {
    _flow.restart();
    _resetTeachFlags();
    _raceTitleController.clear();
    _raceTargetController.text = '10';
    _customRuntime?.dispose();
    _customRuntime = null;
    _customUpdate = null;
    _customTestResult = null;
    _runtimeDiagnostics.clear();
    _rawDemos.clear();
    _v2Demos.clear();
    _rawCurrent = [];

    _testingVerifier = false;

    _cameraInterruptedDuringTest = false;
    _debugReadyFixture = false;
    _debugSpec = null;
    _learnedWrittenToProvider = false;
    ref.read(learnedCustomMovementProvider.notifier).state = null;
    _skeletonHold.clear();
    _ensureCameraStream();
    setState(() {});
  }

  void _changeName() {
    // The composer owns the movement name — go back there to change it.
    if (widget.returnsSpec) {
      if (context.canPop()) context.pop();
      return;
    }
    _flow.resetToName();
    _resetTeachFlags();
    _nameController.clear();
    _raceTitleController.clear();
    _raceTargetController.text = '10';
    _customRuntime?.dispose();
    _customRuntime = null;
    _customUpdate = null;
    _customTestResult = null;
    _runtimeDiagnostics.clear();
    _rawDemos.clear();
    _v2Demos.clear();
    _rawCurrent = [];

    _testingVerifier = false;

    _cameraInterruptedDuringTest = false;
    _debugReadyFixture = false;
    _debugSpec = null;
    _learnedWrittenToProvider = false;
    ref.read(learnedCustomMovementProvider.notifier).state = null;
    _skeletonHold.clear();
    _stopCamera();
    setState(() {});
  }

  void _resetStartPose() {
    _flow.resetStartPose();
    _skeletonHold.clear();
    _ensureCameraStream();
    setState(() {});
  }

  void _removeLastAccepted() {
    _flow.removeLastAccepted();

    setState(() {});
  }

  void _clearExamples() {
    _flow.clearExamples();
    _resetTeachFlags();

    _customRuntime?.dispose();
    _customRuntime = null;
    _customUpdate = null;
    _customTestResult = null;
    _runtimeDiagnostics.clear();
    _rawDemos.clear();
    _v2Demos.clear();
    _rawCurrent = [];
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
    if (_testingVerifier) return;
    _track.reset();
    _preparing = false;
    _preRoll.clear();
    _liveTestStart = DateTime.now();
    _liveTestFrames.clear();
    _matchTrace.clear();
    _latencyMs.clear();
    _savedSessionId = null;

    if (_useMotionV2 && _v2Spec != null) {
      _customUpdate = null;
      _v2Count = 0;
      _v2Batch.clear();
      _v2Result = MotionV2RuntimeResult.empty;
      try {
        await _v2!.reset();
        await _v2!.load(_v2Spec!);
      } on MotionV2Exception catch (e) {
        if (mounted) setState(() => _v2Error = e.message);
        return;
      }
    } else {
      final spec = _effectiveSpec;
      if (spec == null) return;
      final runtime = CustomPoseSequenceRuntime(spec: spec, target: _testTarget)
        ..start();
      _customRuntime?.dispose();
      _customRuntime = runtime;
      _customUpdate = runtime.lastUpdate;
      _runtimeDiagnostics.clear();
      _recordRuntimeDiagnostic(_customUpdate);
    }
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
    _v2Batch.clear();
    setState(() {
      _customTestResult = result;
      _testingVerifier = false;
    });
    _snapshotTeachSession();
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
    _snapshotTeachSession();
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
    ref.read(learnedCustomMovementProvider.notifier).state =
        LearnedCustomMovement(verifierSpec: spec, learnedAt: DateTime.now());
    setState(() {
      _customTestResult = result;
    });
  }

  bool get _isSummaryStage =>
      _flow.stage == TeachMovementStage.learned ||
      _flow.stage == TeachMovementStage.failed ||
      _flow.stage == TeachMovementStage.building ||
      _learnRequested ||
      _debugReadyFixture;

  @override
  Widget build(BuildContext context) {
    // The camera is the product. Capture + live-test run full-screen, matching
    // the verification camera (`ai_motion_proof_screen_io`). Naming and the
    // learned/summary screens stay on the light sheet.
    if (_introPending && !_debugReadyFixture) return _introScaffold();
    final immersive =
        !_debugReadyFixture &&
        (_testingVerifier ||
            (_flow.stage != TeachMovementStage.name && !_isSummaryStage));
    return immersive ? _immersiveScaffold() : _sheetScaffold();
  }

  Widget _teachScrim({required bool top}) => IgnorePointer(
    child: Align(
      alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
      child: Container(
        height: top ? 160 : 300,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: top ? Alignment.topCenter : Alignment.bottomCenter,
            end: top ? Alignment.bottomCenter : Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.55),
              Colors.black.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _sheetScaffold() {
    final naming =
        _flow.stage == TeachMovementStage.name && !_debugReadyFixture;
    return _stageScaffold(naming ? _nameStage() : _summaryStage());
  }

  /// Every non-camera Teach screen: one centred stage with a back arrow.
  Widget _stageScaffold(Widget stage) {
    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: stage),
            Positioned(
              top: 8,
              left: 12,
              child: NuvoBackButton(onPressed: () => context.pop()),
            ),
          ],
        ),
      ),
    );
  }

  /// Shown first when Teach Nuvo opens — before the camera — so nobody is
  /// dropped into a live camera without knowing what to do.
  Widget _introScaffold() {
    final name = _flow.movementName.trim();
    return _stageScaffold(
      NuvoFocusedStage(
        icon: Icons.videocam_rounded,
        title: name.isEmpty ? 'Teach Nuvo' : 'Teach Nuvo $name',
        body:
            'Nuvo learns by watching. Do it 3 times, then Nuvo counts every '
            'rep for you.',
        content: const _TeachSteps(),
        primaryLabel: 'Start',
        onPrimary: _startFromIntro,
        links: [('Not now', () => context.pop())],
      ),
    );
  }

  Future<void> _startFromIntro() async {
    setState(() => _introPending = false);
    await _initializeCamera();
  }

  Widget _nameStage() {
    return NuvoFocusedStage(
      icon: Icons.edit_rounded,
      title: 'Name your movement',
      body: 'What should Nuvo call it?',
      content: TextField(
        controller: _nameController,
        maxLength: 40,
        textAlign: TextAlign.center,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(hintText: 'Overhead knee touch', errorText: _nameError),
        onSubmitted: (_) => _submitName(),
      ),
      primaryLabel: 'Continue',
      onPrimary: _submitName,
    );
  }

  /// Building / failed / learned — one centred message and one clear action.
  Widget _summaryStage() {
    final v2 = _useMotionV2 && !_debugReadyFixture &&
        (_v2Spec != null ||
            _v2Learning ||
            _learnRequested ||
            _v2Error != null ||
            _effectiveSpec == null);
    final name = _flow.movementName.trim().isEmpty
        ? 'your movement'
        : _flow.movementName.trim();
    final spec = _effectiveSpec;
    final bool learned;
    final bool building;
    if (v2) {
      // "Learned" means there is something to USE. The race verifies with the
      // V2 spec — the matcher that learned and live-tested the demos — so a
      // learned V2 spec is sufficient on its own; a V1 spec may also exist
      // (consistency-lenient rebuild) and rides along for diagnostics only.
      learned = _v2Spec != null;
      building =
          _flow.stage == TeachMovementStage.building ||
          _v2Learning ||
          (_v2Spec != null &&
              spec == null &&
              _flow.stage != TeachMovementStage.failed) ||
          (_learnRequested &&
              !learned &&
              _v2Error == null &&
              _flow.stage != TeachMovementStage.failed);
    } else {
      learned = _flow.stage == TeachMovementStage.learned || _debugReadyFixture;
      building = _flow.stage == TeachMovementStage.building;
    }
    final failed = !learned && !building;
    // Seal + upload the moment the failure is shown — a failed teach is a
    // terminal session and the most diagnostic-rich one. Waiting for the V2
    // learn to settle first so its error/self-validation lands in the record.
    if (failed && !_v2Learning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _finalizeTeachSession(outcome: 'failed');
      });
    }
    final testResult = _customTestResult;
    final matched =
        testResult != null && testResult.verificationStatus == 'custom_verified';
    final failedTest = testResult != null && !matched;
    final extras = <Widget>[
      if (learned && !v2 && spec != null) LearnedMovementPreview(spec: spec),
      if (learned && testResult != null) _testResultStatus(testResult),
      if (_showDiagnostics && v2) _motionV2DebugPanel(),
      if (_showDiagnostics && !v2) _debugPanel(),
    ];
    final child = extras.isEmpty
        ? null
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final w in extras) ...[w, const SizedBox(height: 12)],
            ],
          );

    if (building) {
      return NuvoFocusedStage(
        busy: true,
        title: 'Learning $name',
        body: 'This only takes a few seconds.',
        content: child,
      );
    }
    if (failed) {
      return NuvoFocusedStage(
        icon: Icons.refresh_rounded,
        accent: NuvoColors.warning,
        title: "Let's try that again",
        body: _v2Error ??
            (_flow.message.isNotEmpty
                ? _flow.message
                : 'That was hard to read. Record it again.'),
        content: child,
        primaryLabel: 'Try again',
        onPrimary: _restart,
        links: [('Change name', _changeName)],
      );
    }
    return NuvoFocusedStage(
      icon: Icons.check_circle_rounded,
      accent: NuvoColors.success,
      title: 'Nuvo can count $name',
      body: testResult == null
          ? 'Use it now, or test it once first to make sure it recognises you.'
          : null,
      content: child,
      // Using the movement is the point; testing is optional. Only a test
      // that did NOT match makes "Test again" the lead action.
      primaryLabel: failedTest ? 'Test again' : 'Use this movement',
      onPrimary: failedTest
          ? _startVerifierTest
          : (_navigating ? null : _goToRaceCreation),
      secondaryLabel: failedTest
          ? 'Use this movement'
          : (testResult == null ? 'Test it' : 'Test again'),
      onSecondary: failedTest
          ? (_navigating ? null : _goToRaceCreation)
          : _startVerifierTest,
      links: [
        ('Retry teaching', _restart),
        ('Change name', _changeName),
      ],
    );
  }

  /// Full-screen camera surface with controls layered over it.
  Widget _immersiveScaffold() {
    final controller = _cameraController;
    final ready = controller != null && controller.value.isInitialized;
    final testing = _testingVerifier;
    final v2 = _useMotionV2 && _v2Spec != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            _cameraPreview(controller)
          else
            Center(
              child: Text(
                _flow.message.isNotEmpty ? _flow.message : 'Starting camera…',
                style: AppTextStyles.bodyLarge.copyWith(
                  color: NuvoColors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          _teachScrim(top: true),
          _teachScrim(top: false),

          // Top row: back + movement name.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Row(
                children: [
                  _immersiveIcon(Icons.arrow_back_rounded, () {
                    if (testing) {
                      _stopVerifierTest();
                    } else if (context.canPop()) {
                      context.pop();
                    }
                  }),
                  const SizedBox(width: 10),
                  Flexible(
                    child: _immersivePill(
                      testing
                          ? 'Testing "${_flow.movementName}"'
                          : 'Teach "${_flow.movementName}"',
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom controls.
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: testing
                      ? _immersiveTestControls(v2)
                      : _immersiveCaptureControls(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One large, high-confidence instruction over the camera. Pose problems win
  /// (you can't recognise a movement you can't track), then movement feedback.
  Widget _bigGuidance(String text, {Color? color}) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: (color ?? NuvoColors.navy).withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(NuvoRadii.md),
      ),
      child: Text(
        text.toUpperCase(),
        textAlign: TextAlign.center,
        style: AppTextStyles.titleLarge.copyWith(color: NuvoColors.white),
      ),
    );
  }

  List<Widget> _immersiveCaptureControls() {
    final recording = _flow.stage == TeachMovementStage.recording;
    // PREPARING → coach into position ("MOVE BACK" … "READY"). While recording
    // and before motion starts → "READY — DO THE MOVEMENT". Otherwise the
    // header carries it.
    String guide = '';
    Color guideColor = NuvoColors.danger;
    if (_preparing) {
      if (_track.isReady) {
        guide = 'Ready — start the movement';
        guideColor = NuvoColors.success;
      } else {
        guide = _track.quality.guidance;
        guideColor = _track.quality.readiness == PoseReadiness.unstable
            ? NuvoColors.blue
            : NuvoColors.danger;
      }
    } else if (recording && !_track.motionStarted) {
      guide = 'Ready — do the movement';
      guideColor = NuvoColors.success;
    } else if (recording && _track.motionStarted) {
      guide = 'Recording your movement';
      guideColor = NuvoColors.blue;
    }
    return [
      if (guide.isNotEmpty) ...[
        _bigGuidance(guide, color: guideColor),
        const SizedBox(height: 12),
      ],
      _teachProgressHeader(),
      const SizedBox(height: 16),
      _cameraActionButton(),
      const SizedBox(height: 10),
      _secondaryActionButton(),
      if (_showDiagnostics) ...[const SizedBox(height: 12), _debugPanel()],
    ];
  }

  List<Widget> _immersiveTestControls(bool v2) {
    final r = _v2Result;
    // Priority: pose problem → last attempt's feedback → "keep going" → status.
    String message;
    Color? color;
    if (v2 && r.poseReadiness != 'ready' && r.poseGuidance.isNotEmpty) {
      message = r.poseGuidance;
      color = NuvoColors.danger;
    } else if (v2 && r.attempt.outcome == MotionAttemptOutcome.inProgress) {
      message = 'Keep going';
      color = NuvoColors.blue;
    } else if (v2 &&
        r.attempt.outcome == MotionAttemptOutcome.failed &&
        r.attempt.userFeedback.isNotEmpty) {
      message = r.attempt.userFeedback;
      color = NuvoColors.danger;
    } else {
      message = v2 ? _v2StatusLabel() : _nuvoTestStatus(update: _customUpdate);
      color = null;
    }
    return [
      _bigGuidance(message, color: color),
      const SizedBox(height: 12),
      Center(
        child: NuvoRepPulse(
          count: v2 ? _v2Count : (_customUpdate?.count ?? 0),
          target: _testTarget,
          accent: NuvoColors.blue,
        ),
      ),
      const SizedBox(height: 14),
      NuvoPrimaryButton(
        label: 'Stop test',
        expand: true,
        onPressed: _stopVerifierTest,
      ),
      if (_showDiagnostics) ...[
        const SizedBox(height: 12),
        v2 ? _motionV2DebugPanel() : _debugPanel(),
      ],
    ];
  }

  Widget _immersiveIcon(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: NuvoColors.navy.withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: NuvoColors.white, size: 22),
      ),
    );
  }

  Widget _immersivePill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: NuvoColors.navy.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(NuvoRadii.md),
      ),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.white),
      ),
    );
  }


  String _v2StatusLabel() {
    if (_v2Error != null) return 'Couldn\'t read that movement';
    return switch (_v2Result.state) {
      MotionV2RuntimeState.warmingUp => 'Warming up…',
      MotionV2RuntimeState.matching => 'Matched',
      MotionV2RuntimeState.returning => 'Keep going',
      _ => 'Do the movement',
    };
  }

  Widget _motionV2DebugPanel() {
    final r = _v2Result;
    Text row(String s) => Text(
      s,
      style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.white),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NuvoColors.navy,
        borderRadius: BorderRadius.circular(NuvoRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MOTION V2',
            style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.blue),
          ),
          row(
            'runtime: native (onnxruntime)   encoder: ${_v2?.encoderLoaded == true ? 'loaded' : 'not loaded'}',
          ),
          row(
            'model: ${_v2?.encoderId ?? 'release_action'}   spec: ${_v2Spec?.encoder ?? '-'} v${_v2Spec?.version ?? '-'}',
          ),
          row(
            'frames buffered: ${r.bufferFrames}   last inference: ${r.inferenceLatency.inMilliseconds}ms',
          ),
          row(
            'last protoDist: ${r.protoDist?.toStringAsFixed(3) ?? '-'}   last trajSim: ${r.trajSim?.toStringAsFixed(3) ?? '-'}   last match: ${r.matched}',
          ),
          row(
            'matcher: ${r.votes}/3 references agreed   separation: ${r.separation?.toStringAsFixed(2) ?? '-'}   -> ${r.decision}',
          ),
          for (var i = 0; i < r.perReference.length; i++)
            row(
              '  ref $i: proto ${r.perReference[i]['proto']}  traj ${r.perReference[i]['traj']}  ${r.perReference[i]['matches'] == true ? 'MATCH' : 'no'}',
            ),
          row(
            'state: ${r.state.name}   count: ${r.count}   newRep: ${r.newRep}',
          ),
          row(
            'confidence: ${r.confidence.toStringAsFixed(2)}   progress: ${r.motionProgress.toStringAsFixed(2)}',
          ),
          row(
            'protoDist: ${r.protoDist?.toStringAsFixed(3) ?? '-'}  margin: ${r.protoMargin?.toStringAsFixed(2) ?? '-'}',
          ),
          row(
            'trajSim: ${r.trajSim?.toStringAsFixed(3) ?? '-'}   buffer: ${r.bufferFrames}f',
          ),
          row(
            'camera drift: ${r.rootDrift?.toStringAsFixed(3) ?? '-'}   scale spread: ${r.scaleSpread?.toStringAsFixed(3) ?? '-'} (removed before recognition)',
          ),
          row(
            'pose: ${r.poseReadiness}${r.poseGuidance.isEmpty ? '' : ' — ${r.poseGuidance}'}',
          ),
          row(
            'attempt: ${r.attempt.outcome.name}  maxProgress: ${r.attempt.maxProgress.toStringAsFixed(2)}'
            '${r.attempt.failureCategory == MotionFailureCategory.none ? '' : '  → ${r.attempt.failureCategory.name}'}',
          ),
          if (r.attempt.userFeedback.isNotEmpty)
            row('feedback: "${r.attempt.userFeedback}"'),
          if (r.attempt.primaryMismatchRegion != null)
            row('primary mismatch: ${r.attempt.primaryMismatchRegion}'),
          if (_selfValidation != null)
            row(
              'self-validation: ${_selfValidation!.passed ? 'passed' : 'FAILED'} '
              'demo=${_selfValidation!.perDemo} loo=${_selfValidation!.leaveOneOut}',
            ),
          if (_v2?.lastLearnProfile != null)
            row(
              'learn: ${_v2!.lastLearnProfile!.totalMs}ms '
              '(${_v2!.lastLearnProfile!.encoderPasses} encodes '
              '${_v2!.lastLearnProfile!.totalEncodeMs}ms, sv '
              '${_v2!.lastLearnProfile!.selfValidateMs}ms, loo '
              '${_v2!.lastLearnProfile!.looMs}ms)',
            ),
          row('encoder latency: ${r.inferenceLatency.inMilliseconds}ms'),
          if (_v2Error != null) row('error: $_v2Error'),
          if (_savedSessionId != null) ...[
            row('session saved: $_savedSessionId'),
            if (_savedSessionPath != null)
              row('  -> ${_savedSessionPath!.split('/').last}'),
          ],
          const SizedBox(height: 8),
          NuvoOutlineButton(
            label: 'Copy Motion V2 Log',
            expand: true,
            onPressed: _copyMotionV2Log,
          ),
          if (kNuvoDiagnosticsEnabled) ...[
            const SizedBox(height: 8),
            NuvoOutlineButton(
              label: 'Save Diagnostic Session',
              expand: true,
              onPressed: _saveDiagnosticSession,
            ),
          ],
          const SizedBox(height: 8),
          NuvoOutlineButton(
            label: 'Copy raw debug JSON',
            expand: true,
            onPressed: _copyMotionV2Debug,
          ),
          if (kNuvoDiagnosticsEnabled &&
              _lastFailedAttemptFrames.isNotEmpty) ...[
            const SizedBox(height: 8),
            NuvoOutlineButton(
              label:
                  'Copy failed-attempt fixture (${_lastFailedAttemptFrames.length}f)',
              expand: true,
              onPressed: _copyFailedAttemptFixture,
            ),
          ],
        ],
      ),
    );
  }

  /// The full structured diagnostic bundle — enough to answer "which stage
  /// failed" without guessing (see docs/agents/13 PART 12).
  Map<String, dynamic> _motionV2DebugReport() {
    final r = _v2Result;
    final period = _firstPoseAt == null || _poseFrameCount < 2
        ? null
        : DateTime.now().difference(_firstPoseAt!).inMilliseconds /
              math.max(1, _poseFrameCount - 1);
    return {
      'captureQuality': {
        'poseFrameCount': _poseFrameCount,
        'trackableFrameRatio': _poseFrameCount == 0
            ? 0
            : _poseFrameValid / _poseFrameCount,
        'estFrameIntervalMs': period,
        'estFps': period == null || period <= 0 ? null : 1000 / period,
        'current': _captureQuality.toJson(),
        'rootTranslationMagnitude': r.rootDrift,
        'scaleChangeFraction': r.scaleSpread,
      },
      'tracking': _track.toDiagnosticsJson()
        ..addAll({'preparing': _preparing, 'preRollFrames': _preRoll.length}),
      'teaching': {
        'demoCount': _rawDemos.length,
        'demoFrameCounts': [for (final d in _rawDemos) d.length],
        'schema': _v2Spec?.json['schema'],
        'referenceCount': (_v2Spec?.json['references'] as List?)?.length,
        'demoRegionActivity': _v2Spec?.json['region_activity'],
        'demoLengths': _v2Spec?.json['demo_lengths'],
        'demoActiveVel': _v2Spec?.json['demo_active_vel'],
        'protoSpread': _v2Spec?.json['proto_spread'],
        'trajSpread': _v2Spec?.json['traj_spread'],
        'protoSpreadMax': _v2Spec?.json['proto_spread_max'],
        'trajSpreadMax': _v2Spec?.json['traj_spread_max'],
        'selfValidation': _selfValidation?.toJson(),
      },
      'liveAttempt': r.attempt.toJson()
        ..addAll({
          'lastState': r.state.name,
          'lastConfidence': r.confidence,
          'lastProtoMargin': r.protoMargin,
          'lastTrajSim': r.trajSim,
          'count': _v2Count,
        }),
      'inference': {
        'model': _v2?.encoderId ?? 'release_action',
        'runtime': 'onnxruntime (native)',
        'encoderLoaded': _v2?.encoderLoaded ?? false,
        'lastInferenceMs': r.inferenceLatency.inMilliseconds,
        'bufferFrames': r.bufferFrames,
      },
      'error': _v2Error,
    };
  }

  Future<void> _copyMotionV2Debug() async {
    final bundle = {
      'report': _motionV2DebugReport(),
      'spec': _v2Spec?.toJson(),
      'lastResult': _v2Result.toDiagnosticsJson(),
      if (kNuvoDiagnosticsEnabled && _lastFailedAttemptFrames.isNotEmpty)
        'failedAttemptFixture': _failedAttemptFixture(),
    };
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(bundle)),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Motion V2 debug copied.')));
    }
  }

  /// Everything needed to replay a failed attempt offline: raw pose frames,
  /// the taught spec, the attempt boundaries + outcome, runtime diagnostics.
  Map<String, dynamic> _failedAttemptFixture() => {
    'schema': 'motion_v2_failed_attempt/1',
    'movementName': _flow.movementName,
    'expectedOutcome': 'match',
    'spec': _v2Spec?.toJson(),
    'attempt': _v2Result.attempt.toJson(),
    'diagnostics': _motionV2DebugReport(),
    'rawFrames': [
      for (final f in _lastFailedAttemptFrames) _serializeRawFrame(f),
    ],
    'demos': [
      for (final d in _rawDemos) [for (final f in d) _serializeRawFrame(f)],
    ],
  };

  Future<void> _copyFailedAttemptFixture() async {
    await Clipboard.setData(
      ClipboardData(
        text: const JsonEncoder.withIndent(
          '  ',
        ).convert(_failedAttemptFixture()),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed-attempt fixture copied.')),
      );
    }
  }

  // ignore: unused_element
  Widget _statusPill() {
    final (label, color) = switch (_flow.stage) {
      TeachMovementStage.setup => ('Ready to start', NuvoColors.muted),
      TeachMovementStage.countdown => ('Get ready', NuvoColors.muted),
      TeachMovementStage.startPose => ('Waiting for start', NuvoColors.muted),
      TeachMovementStage.readyToRecord => ('Ready', NuvoColors.white),
      TeachMovementStage.holdStill => ('Hold still', NuvoColors.white),
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

  // ignore: unused_element
  Widget _progressText() {
    final accepted = _flow.acceptedCount;
    final needed = _flow.requiredExampleCount;
    return Text(
      '$accepted of $needed examples saved',
      style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
      textAlign: TextAlign.center,
    );
  }

  // ignore: unused_element
  Widget _captureControls() {
    final stage = _flow.stage;
    final canRemoveLast =
        _flow.acceptedCount > 0 &&
        (stage == TeachMovementStage.readyToRecord ||
            stage == TeachMovementStage.recording);
    final canClear =
        (_flow.acceptedCount > 0 || _flow.rejectedDemonstrations.isNotEmpty) &&
        (stage == TeachMovementStage.readyToRecord ||
            stage == TeachMovementStage.recording);
    final showResetStart =
        _flow.startPose != null &&
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
        if (showResetStart) _smallButton('Reteach start pose', _resetStartPose),
      ],
    );
  }

  Widget _smallButton(String label, VoidCallback onPressed) {
    return NuvoTertiaryButton(label: label, small: true, onPressed: onPressed);
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
              child: PoseSkeletonOverlay(
                frame: _skeletonHold.frame,
                sourceSize: Size(previewSize.height, previewSize.width),
                mirrorX: PoseSkeletonPreviewTransform.shouldMirrorX(
                  lensDirection: _selectedCamera?.lensDirection,
                  platform: defaultTargetPlatform,
                ),
              ),
            ),
            if (_cameras.length > 1)
              Positioned(
                top: 12,
                right: 12,
                child: GestureDetector(
                  onTap: _switchCamera,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: NuvoColors.navy.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.flip_camera_ios,
                      color: NuvoColors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
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
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: dots);
  }

  Widget _teachProgressHeader() {
    final String title;
    final String? sub;
    if (_flow.stage == TeachMovementStage.building || _learnRequested) {
      title = 'Learning your movement…';
      sub = null;
    } else if (_awaitingExampleSave) {
      title = 'Example ${_flow.acceptedCount} recorded';
      sub = 'Save it, or redo if that one felt wrong.';
    } else if (_confirmedExamples >= _requiredExamples) {
      title = '$_requiredExamples of $_requiredExamples examples saved';
      sub = 'Tap Learn movement when you\'re ready.';
    } else if (_preparing) {
      title = 'Example ${_confirmedExamples + 1} of $_requiredExamples';
      sub = _track.isReady
          ? 'Ready — start the movement'
          : _track.quality.guidance;
    } else if (_flow.stage == TeachMovementStage.recording) {
      title = _track.motionStarted
          ? 'Recording your movement'
          : 'Ready — do the movement';
      sub = _track.motionStarted
          ? 'Tap Stop when you\'re done.'
          : 'Perform it once, then tap Stop.';
    } else {
      title = 'Example ${_confirmedExamples + 1} of $_requiredExamples';
      sub = _flow.lastExampleRejected
          ? _flow.message
          : 'Tap Record, do the movement once, then Stop.';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: NuvoColors.navy.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(NuvoRadii.md),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: AppTextStyles.titleMedium.copyWith(color: NuvoColors.white),
            textAlign: TextAlign.center,
          ),
          if (sub != null) ...[
            const SizedBox(height: 6),
            Text(
              sub,
              style: AppTextStyles.bodySmall.copyWith(
                color: NuvoColors.white.withValues(alpha: 0.75),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _cameraActionButton() {
    final stage = _flow.stage;
    if (_preparing || stage == TeachMovementStage.recording) {
      return NuvoPrimaryButton(
        label: 'Stop',
        expand: true,
        onPressed: _finishRecording,
      );
    }
    if (stage == TeachMovementStage.building || _learnRequested) {
      return const Center(child: NuvoLoadingIndicator());
    }
    if (_awaitingExampleSave) {
      return NuvoPrimaryButton(
        label: 'Save example',
        expand: true,
        onPressed: _saveExample,
      );
    }
    if (_confirmedExamples >= _requiredExamples) {
      return NuvoPrimaryButton(
        label: 'Learn movement',
        expand: true,
        onPressed: _flow.canLearn ? _learnMovement : null,
      );
    }
    if (stage == TeachMovementStage.readyToRecord) {
      // Always pressable — the user gets into position AFTER tapping Record.
      return NuvoPrimaryButton(
        label: 'Record example ${_confirmedExamples + 1}',
        expand: true,
        onPressed: _cameraReady ? _startRecording : null,
      );
    }
    return NuvoOutlineButton(
      label: 'Start over',
      expand: true,
      onPressed: _restart,
    );
  }

  Widget _secondaryActionButton() {
    if (_preparing || _flow.stage == TeachMovementStage.recording) {
      return NuvoOutlineButton(
        label: 'Cancel',
        expand: true,
        onPressed: () {
          if (_preparing) {
            _cancelPreparing();
          } else {
            _cancelRecording();
          }
        },
      );
    }
    if (_awaitingExampleSave) {
      return NuvoOutlineButton(
        label: 'Redo this example',
        expand: true,
        onPressed: _redoExample,
      );
    }
    return const SizedBox.shrink();
  }

  void _syncCaptureDeviceInfo(CameraDescription camera) {
    _flow.setCaptureDeviceInfo(
      cameraLensDirection: camera.lensDirection.name,
      orientation: 'portraitUp',
      deviceNote: '${Platform.operatingSystem}_${defaultTargetPlatform.name}',
    );
  }

  void _recordRuntimeDiagnostic(CustomPoseRuntimeUpdate? update) {
    if (!_showDiagnostics || update == null) return;
    final next = update.toDiagnosticsJson();
    final previous = _runtimeDiagnostics.isEmpty
        ? null
        : _runtimeDiagnostics.last;
    final previousProgress =
        (previous?['sequenceProgress'] as num?)?.toDouble() ?? -1;
    final shouldRecord =
        previous == null ||
        previous['state'] != next['state'] ||
        previous['count'] != next['count'] ||
        previous['currentTemplateIndex'] != next['currentTemplateIndex'] ||
        previous['frameNoAdvanceReason'] != next['frameNoAdvanceReason'] ||
        (previousProgress - update.sequenceProgress).abs() >= 0.01;
    if (!shouldRecord) return;
    if (_runtimeDiagnostics.length >= 160) {
      _runtimeDiagnostics.removeAt(0);
    }
    _runtimeDiagnostics.add(next);
  }

  Map<String, dynamic> _debugMovementReport() {
    final streamState = _poseStream.state;
    final result = _customTestResult;
    final spec = _effectiveSpec;
    return {
      'generatedAtIso8601': DateTime.now().toUtc().toIso8601String(),
      'teaching': _flow.debugReport(),
      // Replayable fixtures — paste into test/motion_qa/fixtures/custom/ to
      // re-run the V1 builder / runtime offline against a real capture.
      if (_flow.currentCalibration() != null)
        'calibrationFixture': _flow.currentCalibration()!.toJson(),
      if (spec != null) 'learnedSpecFixture': spec.toJson(),
      // Raw pose stream per demo — the Motion V2 input (tools/motion_v2).
      // Image-normalized landmarks, NOT V1-normalized. points: {name:[x,y,z,likelihood]}.
      if (_rawDemos.isNotEmpty)
        'rawStreamFixture': {
          'movementName': _flow.movementName,
          'schema': 1,
          'demos': _rawDemos
              .map((d) => d.map(_serializeRawFrame).toList())
              .toList(),
        },
      'poseStream': {
        'framesReceived': streamState.framesReceived,
        'framesProcessed': streamState.framesProcessed,
        'framesDropped': streamState.framesDropped,
        'emptyPoseCount': streamState.emptyPoseCount,
        'detectorBusy': streamState.detectorBusy,
        'lastGoodPoseAt': streamState.lastGoodPoseAt?.toUtc().toIso8601String(),
      },
      'test': {
        'testing': _testingVerifier,
        'cameraInterruptedDuringTest': _cameraInterruptedDuringTest,
        if (_customUpdate != null)
          'latestUpdate': _customUpdate!.toDiagnosticsJson(),
        'runtimeTrace': List.unmodifiable(_runtimeDiagnostics),
        if (result != null)
          'runtimeResult': {
            'isVerified': result.isVerified,
            'count': result.count,
            'target': result.target,
            'framesAnalyzed': result.framesAnalyzed,
            'validFrames': result.validFrames,
          },
        if (result != null) 'result': result.toJson(),
      },
      'mirror': _mirrorDiagnostics(),
    };
  }

  Map<String, dynamic> _mirrorDiagnostics() {
    final camera = _selectedCamera;
    final controller = _cameraController;
    final previewSize = controller?.value.previewSize;
    final mirrorX = PoseSkeletonPreviewTransform.shouldMirrorX(
      lensDirection: camera?.lensDirection,
      platform: defaultTargetPlatform,
    );
    final frame = _skeletonHold.frame;
    Map<String, dynamic>? wristPosition(String id) {
      final point = frame?.points[id];
      if (point == null || previewSize == null) return null;
      final screen = PoseSkeletonCoordinateMapper.map(
        point: point,
        sourceSize: Size(previewSize.height, previewSize.width),
        canvasSize: Size(previewSize.height, previewSize.width),
        mirrorX: mirrorX,
      );
      return {
        'x': double.parse(screen.dx.toStringAsFixed(2)),
        'y': double.parse(screen.dy.toStringAsFixed(2)),
      };
    }

    return {
      'cameraLensDirection': camera?.lensDirection.name ?? 'unknown',
      'platform': defaultTargetPlatform.name,
      'previewMirrorDecision': mirrorX,
      'skeletonXMirrored': mirrorX,
      'sampleLeftWristScreenPosition': wristPosition('leftWrist'),
      'sampleRightWristScreenPosition': wristPosition('rightWrist'),
      'frontCameraPreviewAndSkeletonAgree':
          camera?.lensDirection == CameraLensDirection.front
          ? mirrorX ==
                PoseSkeletonPreviewTransform.shouldMirrorX(
                  lensDirection: CameraLensDirection.front,
                  platform: defaultTargetPlatform,
                )
          : true,
    };
  }

  Future<void> _copyDebugReport() async {
    if (!_showDiagnostics) return;
    final pretty = const JsonEncoder.withIndent(
      '  ',
    ).convert(_debugMovementReport());
    debugPrint(pretty, wrapWidth: 1024);
    await Clipboard.setData(ClipboardData(text: pretty));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Debug report copied.')));
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
          Text(
            'attempts: ${_flow.acceptedCount + _flow.rejectedDemonstrations.length}',
          ),
          Text('accepted: ${accepted.map((d) => d.index).toList()}'),
          Text('rejected: ${rejected.map((d) => d.rejectionReason).toList()}'),
          Text('body: ${_flow.debugBodyInfo}'),
          Text(
            'similarity: ${_flow.lastSimilarity?.toStringAsFixed(2) ?? '-'}',
          ),
          Text('last rejection: ${_flow.lastRejection ?? '-'}'),
          Text('build failure: ${_flow.lastBuildFailure ?? '-'}'),
          const SizedBox(height: 8),
          NuvoOutlineButton(
            label: 'Copy debug report',
            expand: true,
            onPressed: _copyDebugReport,
          ),
        ],
      ),
    );
  }



  Widget _testResultStatus(CustomPoseRuntimeResult result) {
    final matched = result.isVerified;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: matched
            ? NuvoColors.success.withValues(alpha: 0.08)
            : NuvoColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(NuvoRadii.md),
      ),
      child: Text(
        matched
            ? "Nuvo recognized your movement. You're ready to use it."
            : "Nuvo couldn't match that. Try again.",
        style: AppTextStyles.titleMedium.copyWith(
          color: matched ? NuvoColors.success : NuvoColors.danger,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Future<void> _goToRaceCreation() async {
    final spec = _effectiveSpec;
    final v2Spec = _v2Spec;
    if ((spec == null && v2Spec == null) || _navigating) return;
    setState(() => _navigating = true);
    _finalizeTeachSession(outcome: 'used');

    // Launched from the composer as its training stage → hand the specs back
    // and let the composer resume. Never push a second composer.
    if (widget.returnsSpec) {
      context.pop(
        LearnedCustomMovement(
          verifierSpec: spec,
          motionV2Spec: v2Spec,
          learnedAt: DateTime.now(),
        ),
      );
      return;
    }

    _syncLearnedProvider();

    try {
      await context.push('/races/new');
    } finally {
      if (mounted) setState(() => _navigating = false);
    }
  }

  String _nuvoTestStatus({
    CustomPoseRuntimeUpdate? update,
    CustomPoseRuntimeResult? result,
  }) {
    if (result != null) {
      return result.isVerified ? 'Matched' : 'Try again';
    }
    final guidance = update?.guidance;
    final state = update?.state;
    if (guidance == null) return 'Ready';
    return switch (guidance) {
      'Ready' =>
        (state == CustomPoseRuntimeState.matchingSequence ||
                state == CustomPoseRuntimeState.completionCandidate)
            ? 'Keep going'
            : 'Ready',
      'Step back' => 'Move back',
      'Move into the starting position' => 'Get in position',
      'Hold the starting position' => 'Ready',
      'Begin the movement' => 'Start the movement',
      'Movement incomplete' => 'Try again',
      'Return to your starting position' => 'Keep going',
      'Keep your full body visible' => 'Get fully in frame',
      _ => 'Ready',
    };
  }
}

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


/// The three things to know before recording — shown on the Teach intro.
class _TeachSteps extends StatelessWidget {
  const _TeachSteps();

  static const _steps = [
    'Prop your phone up so your whole body is in frame.',
    'Do one rep, then stop. Do that 3 times.',
    'Test it, then race with it.',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _steps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: NuvoColors.blue.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.blue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _steps[i],
                    style: AppTextStyles.bodyMedium.copyWith(color: colors.ink),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
