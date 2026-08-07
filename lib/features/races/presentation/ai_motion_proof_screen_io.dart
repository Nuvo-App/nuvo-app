import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../ai/camera_image_converter.dart';
import '../ai/custom_pose/custom_pose_sequence_runtime.dart';
import '../ai/pose_detector_service.dart';
import '../ai/verifier_runtime.dart';
import '../data/ai_motion_models.dart';
import '../domain/camera_verification_resolver.dart';
import '../domain/motion_activity_catalog.dart';
import 'board_moved_screen.dart';
import 'custom_pose/pose_skeleton_overlay.dart';
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
  final _runtimeResolver = const VerifierRuntimeResolver();
  VerifierRuntime _runtime = PresetPoseVerifierRuntime.defaultRuntime();

  AiMotionActivity _activity = AiMotionActivity.pushUps;
  String _metric = 'reps';
  int _raceTotalBefore = 0;
  int? _raceTargetValue;
  String? _clientSubmissionId;
  CameraController? _cameraController;
  List<CameraDescription> _cameras = const [];
  CameraDescription? _selectedCamera;
  AiMotionProofStatus _status = AiMotionProofStatus.setup;
  AiMotionResult? _result;
  CustomPoseRuntimeResult? _customResult;
  bool _isCustom = false;
  String? _customMovementName;
  CustomPoseRuntimeUpdate? _customUpdate;
  String? _message;
  bool _disposed = false;
  Timer? _recordingTimer;
  Duration _elapsed = Duration.zero;
  int _debugFrameCount = 0;
  bool _autoSubmitScheduled = false;

  // ── Live pose skeleton ──────────────────────────────────────────────────────
  static const _skeletonHoldMs = 900;
  final _skeletonHold = SkeletonFrameHold(
    holdDuration: const Duration(milliseconds: _skeletonHoldMs),
  );
  Timer? _skeletonExpiryTimer;
  bool _switchingCamera = false;

  // ── Live rep feedback ───────────────────────────────────────────────────────
  // Purely presentational. These only ever mirror the count the validator has
  // already awarded — they never add to it or influence verification.
  int _lastCountedValue = 0;
  int _repFlashSeq = 0;
  int _repFlashDelta = 0;
  String _repFlashPhrase = '';
  DateTime? _repFlashAt;
  final _phraseRandom = Random();
  String? _lastPhrase;
  bool _targetCelebrated = false;
  int _targetCelebrationSeq = 0;

  /// Rep-by-rep encouragement, picked at random so it never feels scripted.
  static const _repPhrases = [
    'Nice job',
    'Good job',
    'Keep going',
    'Clean rep',
    "That's it",
    'Strong',
    'Keep it up',
    'Locked in',
    'Looking good',
    'Smooth',
    'Dialed in',
    'Nice and clean',
    'Crushing it',
    'You got this',
    'On fire',
    'Too easy',
    'Boom',
  ];

  /// Louder copy for the last few reps before the finish line.
  static const _homeStretchPhrases = [
    'Almost there',
    'Nearly done',
    'Finish it',
    'One more push',
    'Final stretch',
    'Almost home',
  ];

  /// Random phrase that avoids repeating the previous one back-to-back.
  String _nextPhrase(List<String> pool) {
    if (pool.length == 1) return pool.first;
    String phrase;
    do {
      phrase = pool[_phraseRandom.nextInt(pool.length)];
    } while (phrase == _lastPhrase);
    _lastPhrase = phrase;
    return phrase;
  }

  /// Hold movements score in seconds, so a per-second "+1" would be noise.
  bool get _usesRepFlash =>
      _isCustom || _activity != AiMotionActivity.plankHold;

  /// Short decaying pulse used to thicken the skeleton the instant a rep lands.
  double get _skeletonGlow {
    final at = _repFlashAt;
    if (at == null) return 0;
    final ms = DateTime.now().difference(at).inMilliseconds;
    if (ms >= 320) return 0;
    return 1 - (ms / 320);
  }

  void _resetRepFlash() {
    _lastCountedValue = 0;
    _repFlashSeq = 0;
    _repFlashDelta = 0;
    _repFlashPhrase = '';
    _repFlashAt = null;
    _lastPhrase = null;
    _targetCelebrated = false;
    _targetCelebrationSeq = 0;
  }

  void _scheduleSkeletonExpiry() {
    _skeletonExpiryTimer?.cancel();
    _skeletonExpiryTimer = Timer(
      const Duration(milliseconds: _skeletonHoldMs + 60),
      () {
        if (!mounted || _disposed) return;
        if (_skeletonHold.expire(DateTime.now())) setState(() {});
      },
    );
  }

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
      final eligibility = resolveCameraVerification(race);
      final userId = ref.read(authControllerProvider).user?.id;
      final myPart = userId == null ? null : race.participantFor(userId);
      debugLogCameraVerificationDecision(
        race,
        eligibility,
        routeAction: 'ai_motion_screen_loaded',
      );
      if (!eligibility.isCameraVerifiable) {
        setState(() {
          _status = AiMotionProofStatus.unsupportedMovement;
          _message = eligibility.unsupportedMessage;
        });
        return;
      }
      final raceTarget = race.targetValue;
      final alreadyDone = myPart?.progressValue ?? 0;
      final isCustom = race.isCustomVerifierRace;
      final target = isCustom
          ? (raceTarget != null && raceTarget > 0
                ? (raceTarget - alreadyDone).clamp(1, raceTarget)
                : 1)
          : race.format == 'first_to_goal'
          ? (raceTarget != null && raceTarget > 0
                ? (raceTarget - alreadyDone).clamp(1, raceTarget)
                : eligibility.movementDefinition?.defaultTarget ?? 1)
          : raceTarget ?? eligibility.movementDefinition?.defaultTarget ?? 1;
      final resolution = _runtimeResolver.resolve(
        eligibility: eligibility,
        explicitVerifierType:
            isCustom ? VerifierType.customPoseSequence.id : null,
      );
      if (!resolution.canCreateRuntime) {
        setState(() {
          _status = AiMotionProofStatus.unsupportedMovement;
          _message = eligibility.unsupportedMessage;
        });
        return;
      }
      final VerifierRuntime runtime;
      if (isCustom) {
        runtime = resolution.createRuntime(
          target: target,
          customSpec: race.customVerifierSpec!,
        );
      } else {
        runtime = resolution.createRuntime(target: target);
      }
      setState(() {
        _runtime = runtime;
        _isCustom = isCustom;
        _customMovementName = isCustom ? race.customActivityName : null;
        _customUpdate = null;
        _result = null;
        _customResult = null;
        if (!isCustom) {
          _activity = runtime.movement.activity;
        }
        _metric = race.metric ?? 'reps';
        _raceTotalBefore = myPart?.progressValue ?? 0;
        _raceTargetValue = race.targetValue;
      });
      // Skip redundant pre-camera panel — go straight to camera
      _initializeCamera();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Race details could not load. Start when ready.';
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
    _skeletonExpiryTimer?.cancel();
    _stopCamera();
    _poseDetector.dispose();
    super.dispose();
  }

  /// [keepImmersive] keeps the full-screen camera layout mounted instead of
  /// dropping to the processing panel — used when flipping the lens so the
  /// screen does not visibly rebuild itself.
  Future<void> _initializeCamera({
    CameraDescription? camera,
    bool keepImmersive = false,
  }) async {
    setState(() {
      if (!keepImmersive) _status = AiMotionProofStatus.processing;
      _message = null;
      _result = null;
    });

    try {
      // Enumerating cameras is a platform round-trip; only do it once.
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }
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
    // Re-entrancy guard: rapid taps used to stack initializations and stall.
    if (_switchingCamera ||
        _cameras.length < 2 ||
        _status == AiMotionProofStatus.recording) {
      return;
    }
    final current = _selectedCamera;
    final next = _cameras.firstWhere(
      (camera) => camera.name != current?.name,
      orElse: () => _preferredCamera(_cameras),
    );
    HapticFeedback.selectionClick();
    setState(() => _switchingCamera = true);
    try {
      await _initializeCamera(camera: next, keepImmersive: true);
    } finally {
      if (mounted && !_disposed) setState(() => _switchingCamera = false);
    }
  }

  Future<void> _startRecording() async {
    final controller = _cameraController;
    final camera = _selectedCamera;
    if (controller == null ||
        camera == null ||
        !controller.value.isInitialized) {
      return;
    }

    _runtime.start();
    _elapsed = Duration.zero;
    _debugFrameCount = 0;
    _resetRepFlash();
    _skeletonHold.clear();
    _debugLog(
      _isCustom
          ? 'verificationStarted custom=${_customMovementName ?? 'custom'} '
            'mode=camera target=${_runtime.targetValue}'
          : 'verificationStarted movement=${_runtime.movement.type.name} '
            'mode=camera target=${_runtime.targetValue}',
    );
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
      final output = _runtime.update(frame);
      if (_isCustom) {
        _customUpdate = output.customPoseUpdate;
      }
      _skeletonHold.show(frame, DateTime.now());
      _scheduleSkeletonExpiry();
      // Mirror a newly awarded rep as live feedback. Reads the validator's
      // count; never modifies it.
      if (_usesRepFlash && output.count > _lastCountedValue) {
        _repFlashDelta = output.count - _lastCountedValue;
        _lastCountedValue = output.count;
        _repFlashSeq++;
        _repFlashAt = DateTime.now();

        final remaining = _targetValue - output.count;
        _repFlashPhrase = remaining > 0 && remaining <= 3
            ? _nextPhrase(_homeStretchPhrases)
            : _nextPhrase(_repPhrases);
        HapticFeedback.lightImpact();
      }
      // Finish line reached — fire once per recording.
      if (!_targetCelebrated &&
          _targetValue > 0 &&
          output.count >= _targetValue) {
        _targetCelebrated = true;
        _targetCelebrationSeq++;
        HapticFeedback.heavyImpact();
      }
      _debugFrameCount++;
      if (_debugFrameCount == 1 || _debugFrameCount % 15 == 0) {
        _debugLog(
          _isCustom
              ? 'validatorState=${output.validatorState} '
                'custom=${_customMovementName ?? 'custom'} '
                'count=${output.count} '
                'confidence=${output.confidence.toStringAsFixed(2)} '
                'failedRule=${output.failedRuleReason.isEmpty ? 'none' : output.failedRuleReason} '
                'debug=${output.debugValues}'
              : 'validatorState=${output.validatorState} '
                'movement=${output.selectedMovement.type.name} '
                'count=${output.count} holdSeconds=${output.holdSeconds} '
                'confidence=${output.confidence.toStringAsFixed(2)} '
                'failedRule=${output.failedRuleReason.isEmpty ? 'none' : output.failedRuleReason} '
                'debug=${output.debugValues}',
        );
      }
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

    final verifierResult = _runtime.finish();
    if (_isCustom) {
      final result = verifierResult.customPoseResult;
      if (result == null) {
        if (!mounted) return;
        setState(() {
          _status = AiMotionProofStatus.unsupportedMovement;
          _message = 'This custom movement cannot be submitted as proof yet.';
        });
        return;
      }
      _debugLog(
        'verificationFinished custom=${_customMovementName ?? 'custom'} '
        'value=${result.count} '
        'confidence=${result.confidence.toStringAsFixed(2)} '
        'status=${result.verificationStatus} '
        'failedRule=${_runtime.failedRuleReason.isEmpty ? 'none' : _runtime.failedRuleReason}',
      );
      if (!mounted) return;
      setState(() {
        _customResult = result;
        _result = null;
        _status = result.isVerified
            ? AiMotionProofStatus.aiVerified
            : AiMotionProofStatus.aiFailed;
        _message = null;
      });
      if (result.isVerified) _scheduleAutoSubmit();
      return;
    }
    final result = verifierResult.aiMotionResult;
    if (result == null) {
      if (!mounted) return;
      setState(() {
        _status = AiMotionProofStatus.unsupportedMovement;
        _message = 'This movement cannot be submitted as proof yet.';
      });
      return;
    }
    _debugLog(
      'verificationFinished movement=${_runtime.movement.type.name} '
      'value=${result.detectedReps} '
      'confidence=${result.confidence.toStringAsFixed(2)} '
      'status=${result.verificationStatus} '
      'failedRule=${_runtime.failedRuleReason.isEmpty ? 'none' : _runtime.failedRuleReason}',
    );
    if (!mounted) return;
    setState(() {
      _result = result;
      _status = result.isVerified
          ? AiMotionProofStatus.aiVerified
          : AiMotionProofStatus.aiFailed;
      _message = null;
    });
    if (result.isVerified) _scheduleAutoSubmit();
  }

  void _scheduleAutoSubmit() {
    if (_autoSubmitScheduled) return;
    _autoSubmitScheduled = true;
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted || _disposed || _status != AiMotionProofStatus.aiVerified) {
        return;
      }
      _submitVerifiedProof();
    });
  }

  Future<void> _submitVerifiedProof() async {
    if (_isCustom) {
      final result = _customResult;
      if (result == null || !result.isVerified) return;
      setState(() {
        _status = AiMotionProofStatus.submitting;
        _message = null;
      });
      try {
        final clientSubmissionId = _clientSubmissionId ?? const Uuid().v4();
        _clientSubmissionId = clientSubmissionId;
        final race = await ref
            .read(raceControllerProvider.notifier)
            .submitCustomPoseProof(
              widget.raceId,
              result: result,
              clientSubmissionId: clientSubmissionId,
            );
        if (!mounted) return;
        setState(() => _status = AiMotionProofStatus.submitted);
        final submission = race.submissionResult;
        context.go(
          '/race/${widget.raceId}/board-moved',
          extra: BoardMovedArgs(
            raceId: widget.raceId,
            raceName: race.title,
            value: submission?.verifiedValue ?? result.count,
            unit: race.metric ?? _metric,
            status: result.verificationStatus,
            rankBefore: submission?.previousRank,
            rankAfter: submission?.newRank,
            peoplePassed: submission?.peoplePassed,
          ),
        );
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
      return;
    }

    final result = _result;
    if (result == null || !result.isVerified) return;
    setState(() {
      _status = AiMotionProofStatus.submitting;
      _message = null;
    });
    try {
      final clientSubmissionId = _clientSubmissionId ?? const Uuid().v4();
      _clientSubmissionId = clientSubmissionId;
      final race = await ref
          .read(raceControllerProvider.notifier)
          .submitAiMotionProof(
            widget.raceId,
            result: result,
            clientSubmissionId: clientSubmissionId,
            metric: _metric,
          );
      if (!mounted) return;
      setState(() => _status = AiMotionProofStatus.submitted);
      final submission = race.submissionResult;
      context.go(
        '/race/${widget.raceId}/board-moved',
        extra: BoardMovedArgs(
          raceId: widget.raceId,
          raceName: race.title,
          value: submission?.verifiedValue ?? result.detectedReps,
          unit: race.metric ?? _metric,
          status: result.verificationStatus,
          rankBefore: submission?.previousRank,
          rankAfter: submission?.newRank,
          peoplePassed: submission?.peoplePassed,
        ),
      );
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
      _customResult = null;
      _customUpdate = null;
      _message = null;
      _elapsed = Duration.zero;
      _autoSubmitScheduled = false;
      _clientSubmissionId = null;
      _resetRepFlash();
      _skeletonHold.clear();
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

  void _debugLog(String message) {
    assert(() {
      debugPrint('[NuvoVerify] $message');
      return true;
    }());
  }

  // Show premium result panels instead of camera for terminal states.
  bool get _isResultState =>
      _status == AiMotionProofStatus.aiVerified ||
      _status == AiMotionProofStatus.aiFailed ||
      _status == AiMotionProofStatus.submitting ||
      _status == AiMotionProofStatus.submitted;

  int get _targetValue => _runtime.targetValue;

  int get _currentValue => _runtime.currentValue;

  String get _targetLabel {
    if (_isCustom) return '$_targetValue reps';
    final definition = motionActivityForBackendValue(_activity.backendValue);
    return definition?.targetLabel(_targetValue) ??
        '$_targetValue ${_activity.label}';
  }

  String get _counterLabel {
    if (_isCustom) return '$_currentValue / $_targetValue';
    final definition = motionActivityForBackendValue(_activity.backendValue);
    return definition?.counterLabel(_currentValue, _targetValue) ??
        '$_currentValue / $_targetValue';
  }

  String get _raceTotalLabel {
    final total = _raceTotalBefore + _currentValue;
    final target = _raceTargetValue;
    final metricLabel = _isCustom
        ? _metric
        : motionActivityForBackendValue(_activity.backendValue)?.metric.label ??
            _metric;
    if (target != null && target > 0) {
      return '$total / $target $metricLabel race total';
    }
    return '$total $metricLabel race total';
  }

  String get _movementTitle =>
      _isCustom
          ? (_customMovementName ?? 'Custom movement')
          : motionActivityForBackendValue(_activity.backendValue)?.title ??
              _activity.label;

  String get _cameraInstruction =>
      _isCustom
          ? 'Perform ${_customMovementName ?? 'the movement'} with your whole body visible.'
          : motionActivityForBackendValue(
                _activity.backendValue,
              )?.cameraInstruction ??
              'Full body front view';

  /// True while a live preview is on screen. In that case the camera takes the
  /// whole screen instead of sitting in an inset card.
  bool get _isImmersiveCamera {
    // Stay immersive across a lens flip so the layout does not thrash.
    if (_switchingCamera) return true;
    final controller = _cameraController;
    return controller != null &&
        controller.value.isInitialized &&
        (_status == AiMotionProofStatus.cameraReady ||
            _status == AiMotionProofStatus.recording);
  }

  @override
  Widget build(BuildContext context) {
    if (_isImmersiveCamera) return _immersiveCameraScaffold();
    if (_isResultState) return _immersiveResultScaffold();

    return Scaffold(
      backgroundColor: NuvoColors.page,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
          child: Column(mainAxisSize: MainAxisSize.min, children: _actions()),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Compact inline header: back button left, title right ──────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
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
                        Text(_movementTitle, style: AppTextStyles.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          _activity == AiMotionActivity.plankHold
                              ? 'Hold until the timer finishes.'
                              : 'Camera will count $_targetLabel.',
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
            const SizedBox(height: 10),

            // ── Camera / result stage — Expanded fills remaining space ───
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _status == AiMotionProofStatus.setup
                    ? _loadingPanel()
                    : _cameraPanel(),
              ),
            ),

            // ── Compact status hint (camera-ready / error / processing) ──
            if (!_isResultState &&
                _status != AiMotionProofStatus.setup &&
                _status != AiMotionProofStatus.recording &&
                _status != AiMotionProofStatus.unsupportedMovement) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _statusHint(),
              ),
            ],

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Edge-to-edge camera. Every control floats over the preview so the
  /// movement being verified gets the entire screen.
  Widget _immersiveCameraScaffold() {
    final controller = _cameraController;
    final ready = controller != null && controller.value.isInitialized;
    final recording = _status == AiMotionProofStatus.recording;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            _cameraPreview(controller)
          else
            const ColoredBox(color: Colors.black),

          // Live pose skeleton, drawn straight over the preview.
          if (ready && recording)
            Positioned.fill(child: _skeletonOverlay(controller)),

          // Scrims so floating controls stay legible over any background.
          const IgnorePointer(child: _EdgeScrim(fromTop: true, extent: 200)),
          const IgnorePointer(child: _EdgeScrim(fromTop: false, extent: 320)),

          if (!recording)
            Positioned.fill(child: IgnorePointer(child: _bodyGuideOverlay())),

          // Rep burst sits dead centre of the full screen.
          if (recording && _repFlashSeq > 0)
            Positioned.fill(
              child: IgnorePointer(child: Center(child: _repFlashOverlay())),
            ),

          if (recording && _targetCelebrationSeq > 0)
            Positioned.fill(child: _targetReachedOverlay()),

          if (_switchingCamera)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: CircularProgressIndicator(
                    color: NuvoColors.white,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),

          // Top controls.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Row(
                children: [
                  _immersiveIconButton(
                    icon: Icons.arrow_back_rounded,
                    onPressed: () =>
                        safePopOrGo(context, '/race/${widget.raceId}/proof'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _pill(
                        recording ? _raceTotalLabel : 'Goal: $_targetLabel',
                        color: recording
                            ? (_currentValue >= _targetValue
                                  ? NuvoColors.success
                                  : NuvoColors.danger)
                            : NuvoColors.blue,
                      ),
                    ),
                  ),
                  _visibilityPill(),
                  if (_cameras.length > 1 && !recording) ...[
                    const SizedBox(width: 8),
                    _immersiveIconButton(
                      icon: Icons.cameraswitch_rounded,
                      onPressed: _switchingCamera ? null : _toggleCamera,
                    ),
                  ],
                ],
              ),
            ),
          ),

          if (kDebugMode && _isCustom && recording)
            Positioned(
              left: 14,
              right: 14,
              top: 110,
              child: _customDebugOverlay(),
            ),

          // Bottom HUD + actions.
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (recording) ...[
                      _recordingHud(),
                      const SizedBox(height: 12),
                    ],
                    ..._actions(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Live skeleton over the preview. Pulses thicker the moment a rep lands and
  /// turns green once the finish line is reached.
  Widget _skeletonOverlay(CameraController controller) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return const SizedBox.shrink();
    final targetReached = _targetValue > 0 && _currentValue >= _targetValue;

    return PoseSkeletonOverlay(
      frame: _skeletonHold.frame,
      sourceSize: Size(previewSize.height, previewSize.width),
      mirrorX: PoseSkeletonPreviewTransform.shouldMirrorX(
        lensDirection: _selectedCamera?.lensDirection,
        platform: defaultTargetPlatform,
      ),
      color: targetReached ? NuvoColors.success : NuvoColors.white,
      glow: _skeletonGlow,
    );
  }

  /// One-shot "finish line reached" moment, fired the instant the validator's
  /// count hits the target. Recording keeps running so extra reps still count.
  Widget _targetReachedOverlay() {
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, -0.35),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: BoxDecoration(
            color: NuvoColors.success,
            borderRadius: BorderRadius.circular(NuvoRadii.pill),
            boxShadow: AppShadows.hardMedium,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                color: NuvoColors.white,
                size: 26,
              ),
              const SizedBox(width: 10),
              Text(
                'Finish line reached',
                style: AppTextStyles.titleLarge.copyWith(
                  color: NuvoColors.white,
                ),
              ),
            ],
          ),
        )
            .animate(key: ValueKey(_targetCelebrationSeq))
            .scale(
              begin: const Offset(0.6, 0.6),
              end: const Offset(1, 1),
              duration: 420.ms,
              curve: Curves.elasticOut,
            )
            .fadeIn(duration: 160.ms)
            .then(delay: 1500.ms)
            .fadeOut(duration: 420.ms),
      ),
    );
  }

  Widget _immersiveIconButton({
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return IconButton.filled(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.45),
        foregroundColor: NuvoColors.white,
      ),
      icon: Icon(icon),
    );
  }

  Widget _loadingPanel() {
    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.navy,
        borderRadius: BorderRadius.circular(NuvoRadii.hero),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          color: NuvoColors.white,
          strokeWidth: 2,
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
        borderRadius: BorderRadius.circular(NuvoRadii.hero),
        boxShadow: AppShadows.heroShadow,
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
                      ? _raceTotalLabel
                      : 'Goal: $_targetLabel',
                  color: _status == AiMotionProofStatus.recording
                      ? (_currentValue >= _targetValue
                            ? NuvoColors.success
                            : NuvoColors.danger)
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
          if (_status != AiMotionProofStatus.recording)
            Positioned.fill(child: IgnorePointer(child: _bodyGuideOverlay())),
          if (_status == AiMotionProofStatus.recording)
            Positioned(left: 14, right: 14, bottom: 14, child: _recordingHud()),
          if (_status == AiMotionProofStatus.recording && _repFlashSeq > 0)
            Positioned(left: 0, right: 0, bottom: 92, child: _repFlashOverlay()),
          if (kDebugMode && _isCustom && _status == AiMotionProofStatus.recording)
            Positioned(left: 14, right: 14, top: 80, child: _customDebugOverlay()),
        ],
      ),
    );
  }

  // Full-screen dark result moment for terminal verification states.
  Widget _immersiveResultScaffold() {
    return Scaffold(
      backgroundColor: NuvoColors.navy,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(
                children: [
                  NuvoBackButton(
                    onPressed: () =>
                        safePopOrGo(context, '/race/${widget.raceId}/proof'),
                  ),
                ],
              ),
            ),
            Expanded(child: _resultPanel()),
            if (_message != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _errorMessage(_message!),
              ),
              const SizedBox(height: 8),
            ],
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _actions(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _customDebugOverlay() {
    final update = _customUpdate;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: NuvoColors.navy.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(NuvoRadii.md),
      ),
      child: DefaultTextStyle(
        style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('state: ${update?.state.name ?? '--'}'),
            Text('count: ${update?.count ?? 0} / ${update?.target ?? _targetValue}'),
            Text('sequence: ${(update?.sequenceProgress ?? 0).toStringAsFixed(2)}'),
            Text('similarity: ${(update?.currentSimilarity ?? 0).toStringAsFixed(2)}'),
            Text('valid features: ${(update?.validFeatureRatio ?? 0).toStringAsFixed(2)}'),
            if (update?.failureReason != null)
              Text('reset: ${update!.failureReason}', style: const TextStyle(color: NuvoColors.danger)),
          ],
        ),
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
    final isRecording = _status == AiMotionProofStatus.recording;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 44),
      child: CustomPaint(
        painter: _BodyGuidePainter(),
        child: isRecording
            ? const SizedBox.expand()
            : Center(
                child: Text(
                  'Step into frame',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.white.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
      ),
    );
  }

  // Premium verified result panel.
  Widget _resultPanel() {
    final result = _result;
    final customResult = _customResult;
    final isVerified =
        _status == AiMotionProofStatus.aiVerified ||
        _status == AiMotionProofStatus.submitting ||
        _status == AiMotionProofStatus.submitted;

    if (isVerified) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                    Icons.verified_rounded,
                    color: NuvoColors.blue,
                    size: 80,
                  )
                  .animate()
                  .scale(
                    begin: const Offset(0.4, 0.4),
                    end: const Offset(1.0, 1.0),
                    duration: 320.ms,
                    curve: Curves.easeOutBack,
                  )
                  .fadeIn(duration: 200.ms, curve: Curves.easeOut),
              const SizedBox(height: 18),
              Text(
                    _isCustom
                        ? '+${_customCountedLabel(customResult)}'
                        : '+${_countedLabel(result)}',
                    style: AppTextStyles.displayLarge.copyWith(
                      color: NuvoColors.white,
                    ),
                  )
                  .animate(delay: 80.ms)
                  .slideY(
                    begin: 0.14,
                    end: 0,
                    duration: 260.ms,
                    curve: Curves.easeOutCubic,
                  )
                  .fadeIn(duration: 220.ms, curve: Curves.easeOut),
              const SizedBox(height: 8),
              Text(
                _status == AiMotionProofStatus.submitted
                    ? 'Race updated'
                    : _status == AiMotionProofStatus.submitting
                    ? 'Adding to your race\u2026'
                    : 'Camera verified',
                style: AppTextStyles.bodyLarge.copyWith(
                  color: NuvoColors.white.withValues(alpha: 0.78),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Failed / coaching state.
    final detected = _isCustom
        ? (customResult?.count ?? 0)
        : (result?.detectedReps ?? 0);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: NuvoColors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.refresh_rounded,
                color: NuvoColors.navy,
                size: 36,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Try again',
              style: AppTextStyles.displaySmall.copyWith(
                color: NuvoColors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isCustom
                  ? 'Detected $detected clean ${customResult?.movementName ?? _customMovementName ?? 'reps'} out of $_targetValue.'
                  : _activity == AiMotionActivity.plankHold
                  ? 'Counted $detected valid seconds out of $_targetValue.'
                  : 'Detected $detected clean ${_activity.label} out of $_targetValue.',
              style: AppTextStyles.bodyLarge.copyWith(
                color: NuvoColors.white.withValues(alpha: 0.78),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Keep the camera view clear and try again.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: NuvoColors.white.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        )
            .animate()
            .fadeIn(duration: 240.ms, curve: Curves.easeOut)
            .scale(
              begin: const Offset(0.96, 0.96),
              end: const Offset(1, 1),
              duration: 280.ms,
              curve: Curves.easeOutCubic,
            ),
      ),
    );
  }

  /// "+1 · Nice job" burst shown the moment the validator awards a rep.
  /// Keyed on [_repFlashSeq] so each counted rep replays the animation.
  Widget _repFlashOverlay() {
    const shadows = [
      Shadow(color: Color(0xB3000000), blurRadius: 18, offset: Offset(0, 3)),
    ];

    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '+$_repFlashDelta',
            style: AppTextStyles.displayLarge.copyWith(
              fontSize: 200,
              height: 0.9,
              color: NuvoColors.white,
              shadows: shadows,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: NuvoColors.blue,
              borderRadius: BorderRadius.circular(NuvoRadii.pill),
            ),
            child: Text(
              _repFlashPhrase,
              style: AppTextStyles.titleLarge.copyWith(
                color: NuvoColors.white,
              ),
            ),
          ),
        ],
      )
          .animate(key: ValueKey(_repFlashSeq))
          .fadeIn(duration: 110.ms)
          .scale(
            begin: const Offset(0.65, 0.65),
            end: const Offset(1, 1),
            duration: 260.ms,
            curve: Curves.easeOutBack,
          )
          .slideY(
            begin: 0.35,
            end: -0.35,
            duration: 820.ms,
            curve: Curves.easeOutCubic,
          )
          .fadeOut(delay: 420.ms, duration: 380.ms),
    );
  }

  Widget _recordingHud() {
    final targetReached = _currentValue >= _targetValue;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NuvoColors.navy.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(NuvoRadii.md),
        border: Border.all(color: NuvoColors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              targetReached
                  ? 'Set ready. $_raceTotalLabel'
                  : 'Keep going. $_counterLabel',
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
      AiMotionProofStatus.cameraReady =>
        'Place your whole body inside the frame.',
      AiMotionProofStatus.processing => 'Checking move...',
      AiMotionProofStatus.permissionDenied => 'Camera permission needed',
      AiMotionProofStatus.cameraError => 'Camera issue',
      AiMotionProofStatus.submitting => 'Updating your race...',
      AiMotionProofStatus.submitted => 'Race updated',
      AiMotionProofStatus.needsReview => 'Try again',
      AiMotionProofStatus.unsupportedMovement => 'Unsupported movement',
      _ => '',
    };
    final body =
        _message ??
        switch (_status) {
          AiMotionProofStatus.cameraReady =>
            _activity == AiMotionActivity.plankHold
                ? 'Hold for $_targetLabel. Camera tracks your time.'
                : 'Camera will count $_targetLabel. Do clean reps.',
          AiMotionProofStatus.processing => 'Checking your move…',
          AiMotionProofStatus.permissionDenied =>
            'Enable camera access in Settings to verify your reps.',
          AiMotionProofStatus.cameraError => 'Try again.',
          AiMotionProofStatus.submitting => 'Saving your move to the race.',
          AiMotionProofStatus.submitted => 'Heading back to the race.',
          AiMotionProofStatus.needsReview => 'Try again.',
          AiMotionProofStatus.unsupportedMovement =>
            'This movement cannot be camera verified yet.',
          _ => '',
        };

    if (title.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(NuvoRadii.md),
        border: Border.all(color: NuvoColors.border),
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
        color: NuvoColors.danger.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(NuvoRadii.md),
        border: Border.all(color: NuvoColors.danger.withValues(alpha: 0.45)),
      ),
      child: Text(
        message,
        style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.white),
      ),
    );
  }

  List<Widget> _actions() {
    final loading =
        _status == AiMotionProofStatus.processing ||
        _status == AiMotionProofStatus.submitting;

    return switch (_status) {
      AiMotionProofStatus.setup => [const SizedBox.shrink()],
      AiMotionProofStatus.unsupportedMovement => [
        NuvoOutlineButton(
          label: 'Back',
          expand: true,
          onPressed: () => safePopOrGo(context, '/race/${widget.raceId}/proof'),
        ),
      ],
      AiMotionProofStatus.cameraReady => [
        NuvoPrimaryButton(
          label: 'Start recording',
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
          label: 'Add to race',
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
      AiMotionProofStatus.submitting => [const SizedBox.shrink()],
      AiMotionProofStatus.submitted => [const SizedBox.shrink()],
      AiMotionProofStatus.aiFailed ||
      AiMotionProofStatus.permissionDenied ||
      AiMotionProofStatus.cameraError => [
        NuvoPrimaryButton(
          label: 'Record again',
          icon: Icons.replay_rounded,
          expand: true,
          onPressed: _recordAgain,
        ),
      ],
      _ => [
        NuvoPrimaryButton(
          label: loading ? 'Checking move' : 'Begin',
          expand: true,
          loading: loading,
          onPressed: null,
        ),
      ],
    };
  }

  Widget _pill(String label, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(NuvoRadii.pill),
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
    final visible = _runtime.fullBodyVisible;
    final targetReached = _currentValue >= _targetValue;

    final label = recording && targetReached
        ? 'Target complete'
        : recording && visible
        ? 'Keep going'
        : recording
        ? 'Step back into frame'
        : 'Get in position';
    final color = recording && targetReached
        ? NuvoColors.success
        : recording && visible
        ? NuvoColors.blue
        : NuvoColors.navy;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(NuvoRadii.pill),
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

  String get _cameraPlaceholderText {
    if (_status == AiMotionProofStatus.unsupportedMovement) {
      return 'This movement cannot be camera verified yet.';
    }
    if (_status == AiMotionProofStatus.processing) return 'Starting camera...';
    return 'Place your whole body inside the frame.\n$_cameraInstruction.';
  }

  String _formatElapsed(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _countedLabel(AiMotionResult? result) {
    final value = result?.detectedReps ?? _targetValue;
    if (_activity == AiMotionActivity.plankHold) return '$value seconds';
    final unit = switch (_activity) {
      AiMotionActivity.pushUps => 'pushups',
      AiMotionActivity.squats => 'squats',
      AiMotionActivity.jumpingJacks => 'jumping jacks',
      AiMotionActivity.lunges => 'lunges',
      _ => _activity.label,
    };
    return '$value $unit';
  }

  String _customCountedLabel(CustomPoseRuntimeResult? result) {
    final value = result?.count ?? _targetValue;
    return '$value ${result?.movementName ?? _customMovementName ?? 'reps'}';
  }
}

/// Top/bottom gradient scrim that keeps floating controls readable over the
/// live camera feed.
class _EdgeScrim extends StatelessWidget {
  const _EdgeScrim({required this.fromTop, required this.extent});

  final bool fromTop;
  final double extent;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: fromTop ? Alignment.topCenter : Alignment.bottomCenter,
      child: SizedBox(
        height: extent,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: fromTop ? Alignment.topCenter : Alignment.bottomCenter,
              end: fromTop ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: fromTop ? 0.62 : 0.78),
                Colors.black.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BodyGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(16),
    );
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(rect, paint);

    // Horizontal reference line
    final centerY = size.height / 2;
    canvas.drawLine(
      Offset(size.width * 0.22, centerY),
      Offset(size.width * 0.78, centerY),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
