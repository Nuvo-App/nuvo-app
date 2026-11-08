import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/demo/presentation_demo.dart';
import '../../../core/v13/v13.dart';
import '../../../core/widgets/rep_burst_controller.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../ai/camera_image_converter.dart';
import '../ai/custom_pose/custom_pose_sequence_runtime.dart';
import '../ai/basketball_shot_coordinator.dart';
import '../ai/cloud_basketball_object_dot_producer.dart';
import '../ai/motion_session/motion_session_artifact.dart';
import '../ai/motion_session/motion_session_providers.dart';
import '../ai/motion_session/motion_session_recorder.dart';
import '../ai/motion_model_artifact_integrity.dart';
import '../ai/object_composition_runtime.dart';
import '../ai/motion_v2/motion_v2_verifier_runtime.dart';
import '../ai/object_composition_spec.dart';
import '../ai/pose_detector_service.dart';
import '../ai/rep_event_diagnostics.dart';
import '../ai/remote_verifier_spec.dart';
import '../ai/verifier_runtime.dart';
import '../data/ai_motion_models.dart';
import '../data/motion_analysis_contract.dart';
import '../data/motion_capabilities.dart';
import '../data/motion_package_installer.dart';
import '../data/race_api.dart';
import '../data/race_models.dart';
import '../domain/camera_verification_resolver.dart';
import '../domain/motion_activity.dart';
import '../domain/motion_progress_presentation.dart';
import '../domain/motion_activity_catalog.dart';
import '../domain/race_display.dart';
import '../domain/race_mode_semantics.dart';
import '../domain/rep_inactivity_watch.dart';
import '../domain/timed_attempt_take.dart';
import '../../onboarding/presentation/first_use_guide.dart';
import 'board_moved_screen.dart';

import 'custom_pose/pose_skeleton_overlay.dart';
import 'motion_catalog_provider.dart';
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

  // The server-owned activity identity — for remote motions this is the raw
  // stable ID from the release spec (e.g. an id this build has no enum for).
  // Proof payloads and display must use this, never an enum fallback.
  // Blank until the race resolves: these used to default to pushups, so every
  // other motion flashed "Pushups" for the moments the session handshake and
  // package check took before the real activity arrived.
  String _activityId = '';
  String _activityLabel = '';
  String _metric = 'reps';
  int _raceTotalBefore = 0;
  int? _raceTargetValue;

  /// The race's competitive context — format, direction, banked score,
  /// score-to-beat — so the HUD can talk about the race, not just the count.
  VerifierRaceContext? _raceContext;
  String? _clientSubmissionId;
  CameraController? _cameraController;
  List<CameraDescription> _cameras = const [];
  CameraDescription? _selectedCamera;
  AiMotionProofStatus _status = AiMotionProofStatus.setup;
  AiMotionResult? _result;
  MotionAnalysisResult? _serverAnalysis;
  final List<NuvoPoseFrame> _capturedFrames = <NuvoPoseFrame>[];

  // ── Motion session telemetry ────────────────────────────────────────────────
  // Records the full attempt (landmarks + verifier decisions + result) into the
  // same gzip artifact the manual "share session" action produces, then hands
  // it to the non-blocking upload queue. Never gates the verification UI.
  MotionSessionRecorder? _session;
  MotionSessionArtifact? _lastArtifact;
  bool _sessionFinalized = false;
  // Mid-session snapshots: the same session id is re-uploaded (server upserts)
  // on every rep / state change, so a run that never reaches finish still
  // leaves its frames and events on the server.
  DateTime? _lastSnapshotAt;
  int _snapshotCount = 0;
  String _snapshotState = '';
  String _raceTitle = '';
  String _measurementType = 'repetitions';
  CustomPoseRuntimeResult? _customResult;
  bool _isCustom = false;

  /// True when the runtime emits custom-shape output — a custom-pose race OR
  /// a remote release carrying a learned motion_v2 spec. Drives which update/
  /// result fields the screen consumes; session kind + identity stay on
  /// [_isCustom] since a remote release isn't a user-taught custom movement.
  bool get _usesCustomRuntimeOutput =>
      _isCustom || _runtime.type == VerifierType.motionV2;
  String? _customMovementName;
  CustomPoseRuntimeUpdate? _customUpdate;
  String? _message;
  String? _verificationSessionId;
  String? _verificationReleaseId;
  String? _verificationReleaseChecksum;
  ({int value, double confidence, bool verified})? _sessionCompletionResult;
  Future<void>? _sessionCompletion;
  bool _verificationSessionCompleted = false;

  /// A proof request (and its optimistic board patch) is already running —
  /// a second tap / auto-submit must not start another.
  bool _submitInFlight = false;

  /// The board-moved celebration was pushed optimistically on top of this
  /// screen and is still waiting for the server to confirm the proof.
  bool _optimisticCelebrationOpen = false;

  /// Completes when POST /proof has returned (accepted or rejected). The
  /// /motion/analyze call and the motion-session artifact upload wait for it
  /// so they never compete with complete/proof on the wire. Only set for a
  /// verified result that is about to be submitted.
  Completer<void>? _proofSettled;

  /// Release whose package is pin-protected for the active session — the
  /// installer must never evict the bytes a live verifier depends on.
  String? _pinnedVerifierReleaseId;
  MotionPackageInstaller? _packageInstaller;
  CloudBasketballObjectDotProducer? _objectDotProducer;
  BasketballShotCoordinator? _basketballShot;
  ObjectCompositionSpec? _objectCompositionSpec;
  ObjectCompositionUpdate? _objectUpdate;
  bool _basketballPreflightFailed = false;
  bool _isProcessingVerificationFrame = false;
  DateTime? _lastObjectInferenceAt;
  static const _objectInferenceInterval = Duration(milliseconds: 140);
  NuvoPoseFrame? _lastObjectPose;
  DateTime? _lastObjectPoseAt;
  // Pose inference is the expensive part of the basketball pipeline. Keep
  // the wrist context fresh enough for the composition runtime, while letting
  // the object model inspect more camera frames during a fast shot.
  static const _objectPoseRefreshInterval = Duration(milliseconds: 320);
  int _objectCount = 0;
  double _objectConfidence = 0;
  bool _disposed = false;
  Timer? _recordingTimer;
  Duration _elapsed = Duration.zero;
  int _debugFrameCount = 0;
  bool _autoSubmitScheduled = false;

  // ── Timed battle take ────────────────────────────────────────────────────
  // A timed_attempt race with a declared duration runs a fixed-length take:
  // 3-2-1, a server-timed window counted down on the HUD, then the same
  // finish path as Done. Legacy timed races without a duration keep the
  // untimed flow — [_isTimedTake] is false for them.
  TimedAttemptTake? _timedTake;

  /// Bumped whenever a take is abandoned — an in-flight attempt-open for an
  /// older take cancels itself instead of stranding an open attempt.
  int _timedTakeSerial = 0;

  /// The open POST for the live take (retries inside) — awaited briefly
  /// before the proof send so the proof binds THIS attempt, not a fresh
  /// (mistimed) one the submit path would declare.
  Future<void>? _timedAttemptOpen;
  Timer? _countdownTimer;
  int? _attemptLimit;
  int _attemptsUsed = 0;

  // ── Rep inactivity prompt ────────────────────────────────────────────────
  // Rep takes only: 30 s without a counted rep asks "Are you still there?"
  // — a hold never arms it (stillness IS the attempt), a timed window
  // never arms it (the take already races a deadline), and the basketball
  // pipeline has its own shot flow. The clock anchors at take start so a
  // take that never lands rep one still asks.
  final _inactivityWatch = RepInactivityWatch();
  bool _inactivityPromptOpen = false;
  BuildContext? _inactivityDialogContext;

  /// False while the app isn't in the foreground — the prompt never fires
  /// (or queues) against a screen the athlete can't see.
  bool _appInForeground = true;

  bool get _isObjectComposition => _objectCompositionSpec != null;

  /// The take is a hold — stillness is the whole point, so the rep
  /// inactivity prompt must never apply to it.
  bool get _isHoldSession =>
      _measure == MotionMeasurementType.duration || _runtime.movement.isHold;

  /// Only an open-ended rep take gets the "Are you still there?" prompt —
  /// holds and timed windows are excluded by what they are, not by a flag.
  bool get _watchesRepInactivity =>
      !_isObjectComposition && !_isHoldSession && !_isTimedTake;

  /// Timed battles only: a `timed_attempt` race WITH a declared duration.
  /// Legacy timed races have no duration — they keep the untimed flow.
  bool get _isTimedTake =>
      _raceContext?.format == RaceFormat.timedAttempt &&
      (_raceContext?.attemptDurationSeconds ?? 0) > 0;

  /// The race's attempt limit leaves no room for another take. A null limit
  /// never blocks; usage comes from the server's viewer context, not a local
  /// count.
  bool get _attemptLimitReached => timedAttemptLimitReached(
    attemptLimit: _attemptLimit,
    attemptsUsed: _attemptsUsed,
  );

  /// "N of M attempts used" is shown before starting when a limit exists —
  /// for any attempt race, not just timed ones.
  bool get _attemptUsageShown =>
      _raceContext?.isAttemptBased == true && _attemptLimit != null;

  /// Seconds left in a timed take's window — the HUD counts this down, not
  /// up, while the attempt is live.
  Duration? get _timedRemaining {
    final left = _timedTake?.secondsRemaining;
    return left == null ? null : Duration(seconds: left);
  }

  bool _isLocalPresentationRace(Race race) {
    final user = ref.read(authControllerProvider).user;
    return isPresentationDemoUser(user) &&
        (isPresentationDemoRace(race.id) ||
            isPresentationDemoCreatedRace(race.id));
  }

  // ── Live pose skeleton ──────────────────────────────────────────────────────
  static const _skeletonHoldMs = 900;
  final _skeletonHold = SkeletonFrameHold(
    holdDuration: const Duration(milliseconds: _skeletonHoldMs),
  );
  Timer? _skeletonExpiryTimer;
  bool _switchingCamera = false;

  // ── Live rep feedback ───────────────────────────────────────────────────────
  // Purely presentational. These only ever mirror the count the validator has
  // already awarded — they never add to it or influence verification. The
  // recognition path (_handleCameraFrame -> _runtime.update) runs unconditionally
  // on every processed frame regardless of what any of this is doing; it never
  // awaits an animation or checks an "isAnimating" flag. One-way data flow:
  // motion engine -> rep events (output.count) -> this bookkeeping -> UI.
  DateTime? _repFlashAt;
  bool _targetCelebrated = false;
  int _targetCelebrationSeq = 0;

  // Burst/streak bookkeeping shared with NuvoRepPulse — reps landing within
  // the window grow the same "+N" burst instead of each restarting at +1.
  // Visual timing only; never fed back into recognition.
  final _burst = RepBurstController();
  int get _repFlashSeq => _burst.sequence;
  int get _streakCount => _burst.streakCount;

  // Diagnostics only (assert()-gated debug log below) — never read by
  // counting or the burst UI. Answers "was a rep missed by perception, or
  // just not shown?" from a device log.
  final _repEventLog = RepEventLog();

  // Live encouragement — rotating copy pools keyed on phase, streak,
  // elapsed time and milestone/new-best beats. Presentation only; a line
  // can never touch the count.
  final _encouragement = SessionEncouragement();
  MotionProgressPhase? _lastHudPhase;
  DateTime? _hudFlashUntil;
  bool _newBestFlashed = false;

  /// Distance presentation (milestone spacing / pace) for this race's scale.
  DistancePresentationPolicy get _distancePolicy =>
      DistancePresentationPolicy.forTarget(_raceTarget);

  /// Milestone bursts: reps always; a metre-scale distance sprint at the
  /// scale-appropriate checkpoint spacing (see [DistancePresentationPolicy]);
  /// never for a hold or a mile-scale run.
  bool get _usesRepFlash {
    if (_isDistanceRace) return _distancePolicy.usesMilestoneBursts;
    return _usesCustomRuntimeOutput ||
        (motionActivityForBackendValue(_activityId)?.isHold ??
                _measure == MotionMeasurementType.duration) !=
            true;
  }

  /// True when the athlete has hit 2+ reps inside the streak window.
  bool get _isOnStreak => _burst.isOnStreak;

  String get _streakLabel => _encouragement.streakLine(_streakCount);

  /// Short decaying pulse used to thicken the skeleton the instant a rep lands.
  double get _skeletonGlow {
    final at = _repFlashAt;
    if (at == null) return 0;
    final ms = DateTime.now().difference(at).inMilliseconds;
    if (ms >= 320) return 0;
    return 1 - (ms / 320);
  }

  void _resetRepFlash() {
    _repFlashAt = null;
    _targetCelebrated = false;
    _targetCelebrationSeq = 0;
    _burst.reset();
    _repEventLog.clear();
    _encouragement.reset();
    _lastHudPhase = null;
    _hudFlashUntil = null;
    _newBestFlashed = false;
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
    // Retry any motion sessions that failed to upload on a previous run.
    unawaited(ref.read(motionSessionUploadQueueProvider).flush());
    unawaited(ref.read(teachSessionUploadQueueProvider).flush());
    _loadRace();
  }

  Future<void> _loadRace() async {
    try {
      setState(() {
        _status = AiMotionProofStatus.processing;
        _message = null;
      });
      // Mint the verification session in parallel with the race-detail load:
      // the handshake does not depend on the race body, so it is no longer a
      // separate stage (and its failure is no longer a separate swallow
      // point — the submit gate re-mints when this comes back null).
      final loaded = await Future.wait<Object?>([
        ref.read(raceControllerProvider.notifier).getRaceDetail(widget.raceId),
        _mintVerificationSession(),
      ]);
      final race = loaded[0] as Race;
      final prefetchedHandshake = loaded[1] as VerificationSessionHandshake?;
      if (!mounted) return;
      final eligibility = resolveCameraVerification(
        race,
        remoteDefinitions: availableMotionActivities(
          ref.read(motionCatalogProvider).valueOrNull,
          ref.read(motionCapabilitiesProvider),
        ),
      );
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
      // Name the motion as soon as the race resolves — before the slower
      // session handshake and package check — so the title is never wrong.
      final early = eligibility.movementDefinition;
      if (early != null && !race.isCustomVerifierRace) {
        setState(() {
          _activityId = early.activityId;
          _activityLabel = early.title;
        });
      }
      final raceTarget = race.targetValue;
      final alreadyDone = myPart?.progressValue ?? 0;
      final isCustom = race.isCustomVerifierRace;
      // A session only carries a finish line when the format has one. First
      // to targets whatever is left to reach it; window and attempt formats
      // have no goal — the session counts everything, target stays null,
      // and the HUD shows the raw count instead of a fabricated "N / cap".
      final int? target = race.format == 'first_to_goal'
          ? (raceTarget != null && raceTarget > 0
                ? (raceTarget - alreadyDone).clamp(1, raceTarget)
                : isCustom
                ? 1
                : eligibility.movementDefinition?.defaultTarget ?? 1)
          : null;
      if (eligibility.objectCompositionSpec != null) {
        await _loadBasketballRelease(
          race: race,
          eligibility: eligibility,
          target: target,
          alreadyDone: alreadyDone,
        );
        return;
      }
      final resolution = _runtimeResolver.resolve(
        eligibility: eligibility,
        explicitVerifierType: isCustom ? race.verifierType : null,
      );
      if (!resolution.canCreateRuntime) {
        setState(() {
          _status = AiMotionProofStatus.unsupportedMovement;
          _message = eligibility.unsupportedMessage;
        });
        return;
      }
      // Every AI Motion Proof binds to a server verification session — the
      // proof only counts when the server can match it to a completed,
      // caller-owned session for this race. Remote-spec races additionally
      // pin the exact verifier release through the same handshake.
      RemoteVerifierSpec? sessionRemoteSpec;
      VerificationSessionHandshake? handshake = prefetchedHandshake;
      try {
        handshake ??= await ref
            .read(raceControllerProvider.notifier)
            .createVerificationSession(
              race.id,
              appVersion: 'local',
              appBuild: MotionCapabilities.appBuild,
              runtimeCapabilities: MotionCapabilities.current(),
            );
        _verificationSessionId = handshake.session.id;
        _verificationReleaseId = handshake.session.releaseId;
        _verificationReleaseChecksum = handshake.session.releaseChecksum;
      } catch (_) {
        // No session yet — proof submission fails closed (retry creates one).
        _debugLog('verificationSessionCreateFailed');
      }
      if (eligibility.remoteVerifierSpec != null && handshake != null) {
        final rawSpec = handshake.verifier['spec'];
        if (rawSpec is Map) {
          sessionRemoteSpec = RemoteVerifierSpec.fromJson(
            Map<String, dynamic>.from(rawSpec),
          );
        }
        // The session pins release id + checksum server-side; the package for
        // exactly that release must be verified on disk before the camera
        // starts. A package that fails integrity/missing-asset gates the
        // session — the race never runs against an unverifiable release.
        if (sessionRemoteSpec != null) {
          final installer = ref.read(motionPackageInstallerProvider);
          final install = await installer.ensureInstalled(
            sessionRemoteSpec,
            releaseChecksum: _verificationReleaseChecksum ?? '',
          );
          if (!install.runnable) {
            setState(() {
              _status = AiMotionProofStatus.unsupportedMovement;
              _message =
                  install.status == MotionPackageStatus.missingRequiredAsset ||
                      install.status == MotionPackageStatus.installPending
                  ? 'This verifier needs a download that could not finish yet.'
                  : 'This verifier package could not be verified on device.';
            });
            return;
          }
          installer.pin(sessionRemoteSpec.releaseId);
          _pinnedVerifierReleaseId = sessionRemoteSpec.releaseId;
          _packageInstaller = installer;
        }
      }
      final VerifierRuntime runtime;
      if (isCustom) {
        runtime = resolution.createRuntime(
          target: target,
          customSpec: race.customVerifierSpec,
          motionV2SpecOverride: race.customMotionV2Spec,
        );
      } else {
        runtime = resolution.createRuntime(
          target: target,
          remoteSpecOverride: sessionRemoteSpec,
        );
      }
      setState(() {
        _objectCompositionSpec = null;
        _objectUpdate = null;
        _basketballShot = null;
        _objectDotProducer?.dispose();
        _objectDotProducer = null;
        _runtime = runtime;
        _isCustom = isCustom;
        _customMovementName = isCustom
            ? race.customActivityName
            : resolution.motionV2Spec?.movementName;
        _customUpdate = null;
        _result = null;
        _customResult = null;
        if (!isCustom) {
          _activityId = runtime.movement.effectiveActivityId;
          _activityLabel = runtime.movement.title;
        }
        _metric = race.metric ?? 'reps';
        _raceTotalBefore = myPart?.progressValue ?? 0;
        _raceTargetValue = race.targetValue;
        _raceContext = VerifierRaceContext.forRace(race, userId);
        _raceTitle = race.title;
        _measurementType = raceMeasurementType(race).name;
        _attemptLimit = race.attemptLimit;
        _attemptsUsed = race.viewerContext?.attemptsUsed ?? 0;
      });
      // Skip redundant pre-camera panel — go straight to camera
      _initializeCamera();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        // Back to setup with the message attached — the status scaffold shows
        // it plus the Try again action instead of a spinner without a way out.
        _status = AiMotionProofStatus.setup;
        _message = 'Race details could not load. Start when ready.';
      });
    }
  }

  /// Session handshake started alongside the race-detail load. Never throws;
  /// null means "mint again later" (here once, then at submit).
  Future<VerificationSessionHandshake?> _mintVerificationSession() async {
    if (_isPresentationFixtureRace) return null;
    try {
      return await ref
          .read(raceControllerProvider.notifier)
          .createVerificationSession(
            widget.raceId,
            appVersion: 'local',
            appBuild: MotionCapabilities.appBuild,
            runtimeCapabilities: MotionCapabilities.current(),
          );
    } catch (_) {
      _debugLog('verificationSessionCreateFailed');
      return null;
    }
  }

  Future<void> _loadBasketballRelease({
    required Race race,
    required CameraVerificationEligibility eligibility,
    required int? target,
    required int alreadyDone,
  }) async {
    final spec = eligibility.objectCompositionSpec!;
    _basketballPreflightFailed = false;
    try {
      final artifact = await ref
          .read(raceControllerProvider.notifier)
          .getMotionModelArtifact(spec.model.modelVersion);
      final bytes = artifact.bytes;
      if (bytes == null) {
        throw const FormatException('Basketball model artifact is not cached.');
      }
      final vetted = MotionModelArtifactIntegrity.verify(
        requestedModelVersion: spec.model.modelVersion,
        bytes: bytes,
        artifactModelVersion: artifact.modelVersion,
        expectedSha256: spec.model.artifactSha256,
      );
      final producer = await CloudBasketballObjectDotProducer.load(
        vetted,
        inputSize: spec.model.inputSize,
      );
      final localPresentationRace = _isLocalPresentationRace(race);
      final negotiated = spec;
      _objectDotProducer = producer;
      _basketballPreflightFailed = false;
      _basketballShot = BasketballShotCoordinator(
        runtime: BasketballShotRuntime(spec: negotiated),
      );
      if (!localPresentationRace) {
        final handshake = await ref
            .read(raceControllerProvider.notifier)
            .createVerificationSession(
              race.id,
              appVersion: 'local',
              appBuild: MotionCapabilities.appBuild,
              runtimeCapabilities: MotionCapabilities.current(
                objectDotProducer: producer,
              ),
            );
        final rawSpec = handshake.verifier['spec'];
        if (rawSpec is! Map) {
          producer.dispose();
          throw const FormatException('Basketball verifier spec is missing.');
        }
        final remoteSpec = ObjectCompositionSpec.fromJson(
          Map<String, dynamic>.from(rawSpec),
        );
        if (remoteSpec.releaseId != handshake.session.releaseId ||
            remoteSpec.model.modelVersion != spec.model.modelVersion ||
            remoteSpec.model.artifactSha256 != spec.model.artifactSha256) {
          producer.dispose();
          throw const FormatException('Basketball release identity changed.');
        }
        _verificationSessionId = handshake.session.id;
        _verificationReleaseId = handshake.session.releaseId;
        _verificationReleaseChecksum = handshake.session.releaseChecksum;
        _objectCompositionSpec = remoteSpec;
      } else {
        _objectCompositionSpec = negotiated;
      }
      if (!mounted) return;
      setState(() {
        _objectCompositionSpec = _objectCompositionSpec ?? negotiated;
        _objectUpdate = null;
        _objectCount = 0;
        _objectConfidence = 0;
        _isCustom = false;
        _customMovementName = null;
        _result = null;
        _customResult = null;
        _metric = race.metric ?? 'reps';
        _raceTotalBefore = alreadyDone;
        _raceTargetValue = race.targetValue ?? target;
        _raceContext = VerifierRaceContext.forRace(
          race,
          ref.read(authControllerProvider).user?.id,
        );
        _raceTitle = race.title;
        _measurementType = 'repetitions';
        _attemptLimit = race.attemptLimit;
        _attemptsUsed = race.viewerContext?.attemptsUsed ?? 0;
      });
      _initializeCamera();
    } catch (error) {
      _debugLog('basketballReleaseUnavailable error=$error');
      if (!mounted) return;
      setState(() {
        _basketballPreflightFailed = true;
        _status = AiMotionProofStatus.cameraError;
        _message = _basketballPreflightMessage(error);
      });
    }
  }

  String _basketballPreflightMessage(Object error) {
    if (error is ApiException) {
      if (error.statusCode == 401) {
        return 'Your session expired. Sign in again, then retry verification.';
      }
      if (error.statusCode == 409 || error.statusCode == 503) {
        return 'The basketball verifier is not ready for this race yet. Retry in a moment.';
      }
      return 'The verifier could not be prepared (${error.statusCode}). Retry.';
    }
    if (error is MotionModelArtifactIntegrityException) {
      return 'The verifier model failed its integrity check. Retry to download it again.';
    }
    if (error is FormatException) {
      return 'The verifier model could not be loaded. Retry the download.';
    }
    return 'Basketball verification could not start. Check your connection and retry.';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The inactivity clock is wall time — while the app is away nothing
    // counts and nothing should prompt either, so the check only runs
    // against a live, on-screen take.
    _appInForeground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.inactive) {
      // An interrupted 3-2-1 can't honestly start the window — drop the take
      // back to ready; the user restarts it from the camera preview. A live
      // take is released by _resumeInterruptedRecording on the way back.
      if (_timedTake?.countingDown == true) {
        unawaited(_releaseTimedAttempt());
      }
      final controller = _cameraController;
      if (controller != null && controller.value.isInitialized) {
        _stopCamera();
      }
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    final controller = _cameraController;
    if (controller != null && controller.value.isInitialized) return;
    if (_status == AiMotionProofStatus.recording) {
      unawaited(_resumeInterruptedRecording());
    } else if (_status == AiMotionProofStatus.cameraReady ||
        _status == AiMotionProofStatus.cameraError) {
      _initializeCamera(camera: _selectedCamera);
    }
  }

  /// The OS reclaimed the camera while the proof was backgrounded mid-take.
  /// The interrupted take cannot be completed honestly, so reset the attempt
  /// first, then reopen the camera at the ready state — never onto a dead
  /// preview.
  Future<void> _resumeInterruptedRecording() async {
    await _recordAgain();
    if (!mounted || _disposed) return;
    await _initializeCamera(camera: _selectedCamera);
  }

  @override
  void dispose() {
    _disposed = true;
    // Leaving with an unsubmitted timed take releases its open attempt —
    // a cancelled attempt never spends the limit.
    unawaited(_releaseTimedAttempt());
    _releaseProofSettled();
    // Catch attempts abandoned before server analysis resolved.
    _finalizeSession();
    WidgetsBinding.instance.removeObserver(this);
    _recordingTimer?.cancel();
    _countdownTimer?.cancel();
    _skeletonExpiryTimer?.cancel();
    _inactivityWatch.disarm();
    _dismissInactivityPrompt();
    _stopCamera();
    _objectDotProducer?.dispose();
    _poseDetector.dispose();
    final pinned = _pinnedVerifierReleaseId;
    if (pinned != null) _packageInstaller?.unpin(pinned);
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
        // Basketball adds a native 800x800 ONNX pass after pose detection.
        // Medium capture keeps source frames bounded and prevents native
        // inference from being overwhelmed on phones.
        _isObjectComposition ? ResolutionPreset.medium : ResolutionPreset.high,
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
    // Front camera first: most people prop the phone up and face it. The
    // switch-camera button still flips to the back one.
    return cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
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

    // A timed take runs its 3-2-1 first — a re-tap during it or a spent
    // attempt limit both stop here, before anything is declared.
    if (_isTimedTake) {
      if (_timedTake != null || _attemptLimitReached) return;
      _startTimedCountdown();
      return;
    }

    await _beginTake();
  }

  /// One take on a timed battle: 3-2-1 over the live preview, then the
  /// attempt opens on the server clock and the fixed window starts ticking.
  void _startTimedCountdown() {
    final serial = ++_timedTakeSerial;
    _timedTake = TimedAttemptTake(
      durationSeconds: _raceContext!.attemptDurationSeconds!,
      clientAttemptId: const Uuid().v4(),
    );
    setState(() {});
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _disposed || serial != _timedTakeSerial) {
        timer.cancel();
        return;
      }
      if (_timedTake?.tickCountdown() == true) {
        timer.cancel();
        unawaited(_beginTimedTake());
      }
      if (mounted) setState(() {});
    });
  }

  /// The countdown ended — open the server attempt (its `started_at` anchors
  /// the deadline, so it goes out now) and start recording into the window.
  Future<void> _beginTimedTake() async {
    final take = _timedTake;
    if (take == null) return;
    _timedAttemptOpen = _openTimedAttempt(take);
    await _beginTake();
    // The camera refused the take — release whatever the open declared so
    // the screen isn't stranded on a dead take with no way back.
    if (_status != AiMotionProofStatus.recording) {
      await _releaseTimedAttempt();
    }
  }

  /// POSTs the attempt open with the take's stable client id. Retried while
  /// the take is live — a retry reuses the same clientAttemptId, so it can
  /// never open a second attempt — and a 409 just means an attempt is
  /// already open, which binds this take's proof the same way.
  Future<void> _openTimedAttempt(TimedAttemptTake take) async {
    if (_isPresentationFixtureRace) return;
    final serial = _timedTakeSerial;
    // Grab the controller up front — if the take outlives the widget, ref
    // reads throw but this object keeps working.
    final controller = ref.read(raceControllerProvider.notifier);
    for (var i = 0; i < 3; i++) {
      if (_disposed || serial != _timedTakeSerial || _timedTake != take) {
        return;
      }
      try {
        final res = await controller.startAttempt(
          widget.raceId,
          clientAttemptId: take.clientAttemptId,
        );
        if (_disposed || serial != _timedTakeSerial || _timedTake != take) {
          // The take was abandoned while the open was on the wire — release
          // the attempt it just took so it can't sit open and block a retry.
          unawaited(_cancelServerAttempt(controller, res.attemptId));
          return;
        }
        take.markOpened(res.attemptId);
        return;
      } on ApiException catch (e) {
        // Already open — the existing attempt binds this take's proof.
        if (e.statusCode == 409) return;
      } catch (_) {
        // Transient — fall through to the next retry.
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }

  /// An abandoned take releases its open attempt — a cancelled attempt
  /// never counts against the limit, so leaving before the proof lands must
  /// not burn a slot. A proof already on the wire keeps its attempt.
  Future<void> _releaseTimedAttempt() async {
    if (_submitInFlight) return;
    _timedTakeSerial++;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    final take = _timedTake;
    _timedTake = null;
    _timedAttemptOpen = null;
    // The countdown timer that drives rebuilds is gone too — drop the
    // overlay/actions right away rather than on the next incidental tick.
    if (mounted && !_disposed) setState(() {});
    if (take == null || !take.needsRelease || _isPresentationFixtureRace) {
      return;
    }
    // Grab the controller now — once dispose() has run, ref reads throw but
    // this object still works, so the DELETE always gets out.
    final controller = ref.read(raceControllerProvider.notifier);
    await _cancelServerAttempt(controller, take.openAttemptId!);
  }

  /// Best-effort attempt cancel — a failure must never mask the action the
  /// user actually took (retry, back, dispose).
  Future<void> _cancelServerAttempt(
    RaceController controller,
    String attemptId,
  ) async {
    try {
      await controller.cancelAttempt(widget.raceId, attemptId);
    } catch (_) {
      _debugLog('timedAttemptCancelFailed');
    }
  }

  /// Every "leave this screen" path funnels here so an abandoned timed take
  /// releases its attempt instead of stranding it open until the deadline.
  void _leaveScreen() {
    unawaited(_releaseTimedAttempt());
    safePopOrGo(context, '/race/${widget.raceId}');
  }

  /// Actually begins a take — verifier, session recorder, frame stream. For
  /// a timed take this runs only after the 3-2-1, alongside the attempt open.
  Future<void> _beginTake() async {
    final controller = _cameraController;
    final camera = _selectedCamera;
    if (controller == null ||
        camera == null ||
        !controller.value.isInitialized) {
      return;
    }

    if (!_isObjectComposition) _runtime.start();
    // No POST …/start: `complete` accepts a session that is still `created`.
    _elapsed = Duration.zero;
    _debugFrameCount = 0;
    _capturedFrames.clear();
    _lastObjectPose = null;
    _lastObjectPoseAt = null;
    _lastObjectInferenceAt = null;
    _serverAnalysis = null;
    _sessionFinalized = false;
    _lastSnapshotAt = null;
    _snapshotCount = 0;
    _snapshotState = '';
    _session = MotionSessionRecorder(
      kind: _isCustom ? MotionSessionKind.custom : MotionSessionKind.preset,
      activityId: _isCustom
          ? (_customMovementName ?? 'custom')
          : _isObjectComposition
          ? (_objectCompositionSpec?.activityId ?? 'basketball_shot')
          : _activityId,
      activityTitle: _raceTitle.isEmpty
          ? (_customMovementName ?? _activityId)
          : _raceTitle,
      measurementType: _measurementType,
      raceId: widget.raceId,
      goalValue: _targetValue,
      goalUnit: _metric,
      modelVersion: _isObjectComposition
          ? (_objectCompositionSpec?.model.modelVersion ?? 'unknown')
          : 'mlkit-pose-base',
      verifierVersion: _isObjectComposition
          ? (_objectCompositionSpec?.releaseId ?? 'object_composition_v1')
          : 'nuvo-ai-motion-v2',
    )..start();
    if (_objectCompositionSpec != null) {
      _basketballShot = BasketballShotCoordinator(
        runtime: BasketballShotRuntime(spec: _objectCompositionSpec!),
        recorder: _session,
      );
    }
    _resetRepFlash();
    _poseDetector.resetDiagnostics();
    _skeletonHold.clear();
    _debugLog(
      _isObjectComposition
          ? 'verificationStarted movement=basketball_shot '
                'mode=camera target=$_targetValue'
          : _isCustom
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

    // Arm the inactivity clock at take start — a take that never lands a
    // rep asks too, not just one that went quiet mid-way.
    if (_watchesRepInactivity) {
      _inactivityWatch.arm(DateTime.now());
    } else {
      _inactivityWatch.disarm();
    }
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _status == AiMotionProofStatus.recording) {
        final hitZero = _timedTake?.tickWindow() ?? false;
        setState(() => _elapsed += const Duration(seconds: 1));
        // The declared attempt window is over — finish exactly as Done does.
        if (hitZero) unawaited(_finishRecording());
        _maybePromptRepInactivity();
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
    if (_isProcessingVerificationFrame) return;
    if (_isObjectComposition) {
      final now = DateTime.now();
      final last = _lastObjectInferenceAt;
      if (last != null && now.difference(last) < _objectInferenceInterval) {
        return;
      }
      _lastObjectInferenceAt = now;
    }
    _isProcessingVerificationFrame = true;
    try {
      final now = DateTime.now();
      NuvoPoseFrame? frame;
      var refreshedPose = true;
      if (_isObjectComposition &&
          _lastObjectPose != null &&
          _lastObjectPoseAt != null &&
          now.difference(_lastObjectPoseAt!) < _objectPoseRefreshInterval) {
        // Reusing a very recent wrist pose avoids serialising every object
        // inference behind ML Kit. This never runs concurrently with pose or
        // ONNX inference, so it preserves the crash fix in this pipeline.
        frame = _lastObjectPose;
        refreshedPose = false;
      } else {
        frame = await _poseDetector.processCameraImage(
          image: image,
          camera: camera,
          deviceOrientation: orientation,
        );
        if (frame != null && _isObjectComposition) {
          _lastObjectPose = frame;
          _lastObjectPoseAt = now;
        }
      }
      if (_disposed || _status != AiMotionProofStatus.recording) return;
      if (frame == null) return;
      // Keep a bounded landmark-only trace for server analysis and future
      // consented training. Camera pixels never leave the device.
      if (refreshedPose && _capturedFrames.length < 900) {
        _capturedFrames.add(frame);
      }
      if (_isObjectComposition) {
        final producer = _objectDotProducer;
        final coordinator = _basketballShot;
        if (producer == null || coordinator == null) return;
        final objectFrame = await producer.process(
          image: image,
          camera: camera,
          deviceOrientation: orientation,
          pose: frame,
          createdAt: now.toUtc(),
        );
        if (objectFrame == null ||
            _disposed ||
            _status != AiMotionProofStatus.recording) {
          return;
        }
        final objectOutput = coordinator.process(objectFrame);
        _objectUpdate = objectOutput;
        _objectCount = objectOutput.count;
        _objectConfidence = objectOutput.confidence;
        _session?.recordFrame(
          frame,
          validatorState: objectOutput.state.name,
          count: objectOutput.count,
          confidence: objectOutput.confidence,
          failedRuleReason: objectOutput.state == ObjectCompositionState.missed
              ? objectOutput.diagnostic
              : '',
        );
        if (mounted) setState(() {});
        return;
      }
      final output = _runtime.update(frame);
      _liveMetrics = output.debugValues;
      _session?.recordFrame(
        frame,
        validatorState: output.validatorState,
        count: output.count,
        confidence: output.confidence,
        failedRuleReason: output.failedRuleReason,
        debugValues: output.debugValues,
      );
      _maybeSnapshotSession(output.count, output.validatorState);
      final countedAt = _runtime.lastCountedAt;
      if (countedAt != null) _inactivityWatch.noteCounted(countedAt);
      if (_usesCustomRuntimeOutput) {
        _customUpdate = output.customPoseUpdate;
      }
      // A hold that stayed out of position past the break tolerance is
      // over — end the take exactly as Done does so what banked submits.
      if (output.holdBroken) {
        _debugLog('holdBroken state=${output.validatorState}');
        unawaited(_finishRecording());
        return;
      }
      _skeletonHold.show(frame, DateTime.now());
      _scheduleSkeletonExpiry();
      // Mirror a newly awarded rep as live feedback. Reads the validator's
      // count; never modifies it. This runs on every processed frame no
      // matter what the burst/pulse animation below is doing — recognition
      // never waits on presentation.
      if (_usesRepFlash) {
        // Reps: the validator's count. Distance sprint: how many scale-spaced
        // checkpoints the *real* cumulative estimate has crossed — the burst
        // reacts to a checkpoint, it doesn't claim a metre was measured.
        final milestone = _isDistanceRace
            ? _distancePolicy.milestonesCrossed(_displayedRaceProgress)
            : output.count;
        final event = _burst.update(milestone);
        if (event != null) {
          _repFlashAt = DateTime.now();
          _repEventLog.record(event);
          // Fire-and-forget — never awaited, never blocks the next frame.
          HapticFeedback.lightImpact();
        }
      }
      // Encouragement moments — a phase step flashes a milestone line,
      // crossing the score-to-beat flashes a new-best line. Presentation
      // only; it never feeds back into recognition.
      _updateEncouragementMoments();
      // Finish line reached — fire once per recording, and only in a mode
      // that has a finish line. Attempt races never "reach" one.
      if (!_targetCelebrated && _targetReachedNow) {
        _targetCelebrated = true;
        _targetCelebrationSeq++;
        HapticFeedback.heavyImpact();
        // A first-to session that crosses its remaining goal is done — stop
        // recording and run the exact finish/submit path the Done button
        // takes. _finishRecording's status guard keeps this once-only.
        unawaited(_finishRecording());
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
        // Frame-pipeline + rep-event diagnostics — the answer to "was a fast
        // rep lost by perception (framesDropped / low effectiveFps) or
        // presentation (check repEvents intervals against effectiveVerifierFPS)?"
        _debugLog(
          'framesReceived=${_poseDetector.framesReceived} '
          'framesProcessed=${_poseDetector.framesProcessed} '
          'framesDropped=${_poseDetector.framesDropped} '
          '(busy=${_poseDetector.framesDroppedBusy} '
          'throttle=${_poseDetector.framesDroppedThrottle}) '
          'effectiveVerifierFPS=${_poseDetector.effectiveFps.toStringAsFixed(1)} '
          'lastRepIntervalMs=${_repEventLog.lastIntervalMs ?? '-'} '
          'repEvents=[${_repEventLog.summary()}]',
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
    } finally {
      _isProcessingVerificationFrame = false;
    }
  }

  /// Milestone + new-best beats for the recording HUD's encouragement
  /// line. A phase step IS the milestone; [VerifierRaceContext]'s
  /// [VerifierRaceContext.beatsPersonalBest] is the new best. Each beat
  /// hands the HUD one line to hold for a few seconds, then the phase
  /// line comes back.
  void _updateEncouragementMoments() {
    final phase = motionProgressPhase(
      current: _displayedRaceProgress,
      target: _raceTarget,
    );
    final previous = _lastHudPhase;
    _lastHudPhase = phase;
    if (previous != null && phase != previous) {
      _encouragement.triggerMilestone();
      _hudFlashUntil = DateTime.now().add(const Duration(seconds: 4));
      return;
    }
    if (!_newBestFlashed &&
        (_raceContext?.beatsPersonalBest(_sessionContribution) ?? false)) {
      _newBestFlashed = true;
      _encouragement.triggerNewBest();
      _hudFlashUntil = DateTime.now().add(const Duration(seconds: 4));
    }
  }

  /// Once a second while a rep take is live: long enough without a counted
  /// rep asks whether the athlete is still there. The watch decides "quiet"
  /// — this only owns foreground gating and one-prompt-at-a-time.
  void _maybePromptRepInactivity() {
    if (!_appInForeground || _inactivityPromptOpen) return;
    if (!_inactivityWatch.isSilent(DateTime.now())) return;
    _inactivityWatch.markPrompted();
    unawaited(_showInactivityPrompt());
  }

  /// "Are you still there?" — Keep going re-arms the clock; Finish ends the
  /// take through [_finishRecording], the exact path Done takes. A null
  /// answer (the route was dismissed underneath) resolves as resume — the
  /// take was already over, or the user saw the prompt and kept moving.
  Future<void> _showInactivityPrompt() async {
    if (_inactivityPromptOpen || !mounted) return;
    _inactivityPromptOpen = true;
    final choice = await showDialog<RepInactivityChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        _inactivityDialogContext = dialogContext;
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: V13Card(
              radius: V13.radiusCardLg,
              shadow: V13.shadow6,
              padding: const EdgeInsets.all(V13.gapXxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Are you still there?',
                    style: V13.sectionHead,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: V13.gapSm),
                  Text(
                    'Nothing has counted for a bit. Keep the take going, or finish with what you have.',
                    style: V13.caption,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: V13.gapXl),
                  V13Button.primary(
                    label: 'Keep going',
                    fullWidth: true,
                    onPressed: () => Navigator.of(
                      dialogContext,
                    ).pop(RepInactivityChoice.keepGoing),
                  ),
                  const SizedBox(height: V13.gapSm),
                  V13Button.secondary(
                    label: 'Finish',
                    fullWidth: true,
                    onPressed: () => Navigator.of(
                      dialogContext,
                    ).pop(RepInactivityChoice.finish),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    _inactivityDialogContext = null;
    _inactivityPromptOpen = false;
    // The take may have ended while the prompt was up (finish line, timed
    // window, lifecycle) — only a still-recording take resolves a choice.
    if (!mounted || _disposed || _status != AiMotionProofStatus.recording) {
      return;
    }
    final resolution = _inactivityWatch.resolve(choice, DateTime.now());
    if (resolution == RepInactivityResolution.endTake) {
      unawaited(_finishRecording());
    }
  }

  /// The take is ending without the prompt's answer — drop the dialog so
  /// it can't hang over the result or the next take.
  void _dismissInactivityPrompt() {
    final dialogContext = _inactivityDialogContext;
    if (dialogContext != null && dialogContext.mounted) {
      Navigator.of(dialogContext).pop();
    }
    _inactivityDialogContext = null;
  }

  Future<void> _finishRecording() async {
    if (_status != AiMotionProofStatus.recording) return;
    setState(() => _status = AiMotionProofStatus.processing);
    _recordingTimer?.cancel();
    _inactivityWatch.disarm();
    _dismissInactivityPrompt();
    await _stopImageStream();
    await Future<void>.delayed(const Duration(milliseconds: 250));

    if (_isObjectComposition) {
      final update = _objectUpdate;
      final verified = update?.state == ObjectCompositionState.made;
      final value = _objectCount;
      if (!mounted) return;
      setState(() {
        _status = verified
            ? AiMotionProofStatus.aiVerified
            : AiMotionProofStatus.aiFailed;
        _message = verified
            ? null
            : 'The shot was not confirmed. Keep the ball and hoop visible and try again.';
      });
      _session?.recordEvent(
        'object_result',
        detail: verified ? 'made_basket' : (update?.diagnostic ?? 'no_result'),
        metrics: {'count': value.toDouble()},
      );
      if (verified) {
        _proofSettled = Completer<void>();
        unawaited(_awaitProofSettled().then((_) => _finalizeSession()));
      } else {
        _finalizeSession();
      }
      _sessionCompletionResult = (
        value: value,
        confidence: _objectConfidence,
        verified: verified,
      );
      _sessionCompletion = _completeVerificationSession();
      if (verified) _scheduleAutoSubmit();
      return;
    }

    // Drain in-flight V2 matcher evals so a rep that lands in the last
    // moment isn't dropped when the session ends.
    if (_runtime is MotionV2VerifierRuntime) {
      await (_runtime as MotionV2VerifierRuntime).drain();
    }
    final verifierResult = _runtime.finish();
    if (_usesCustomRuntimeOutput) {
      final result = verifierResult.customPoseResult;
      if (result == null) {
        if (!mounted) return;
        setState(() {
          _status = AiMotionProofStatus.unsupportedMovement;
          _message = 'This custom movement cannot be submitted as proof yet.';
        });
        return;
      }
      final acceptedResult = _acceptPartialCustomResult(result);
      _debugLog(
        'verificationFinished custom=${_customMovementName ?? 'custom'} '
        'value=${acceptedResult.count} '
        'confidence=${acceptedResult.confidence.toStringAsFixed(2)} '
        'status=${acceptedResult.verificationStatus} '
        'failedRule=${_runtime.failedRuleReason.isEmpty ? 'none' : _runtime.failedRuleReason}',
      );
      if (!mounted) return;
      setState(() {
        _customResult = acceptedResult;
        _result = null;
        _status = acceptedResult.isVerified
            ? AiMotionProofStatus.aiVerified
            : AiMotionProofStatus.aiFailed;
        _message = null;
      });
      if (acceptedResult.isVerified) _proofSettled = Completer<void>();
      unawaited(_analyzeCapturedMotion());
      _sessionCompletionResult = (
        value: acceptedResult.count,
        confidence: acceptedResult.confidence,
        verified: acceptedResult.isVerified,
      );
      _sessionCompletion = _completeVerificationSession();
      if (acceptedResult.isVerified) _scheduleAutoSubmit();
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
    final acceptedResult = _acceptPartialMotionResult(result);
    _debugLog(
      'verificationFinished movement=${_isObjectComposition ? 'basketball_shot' : _runtime.movement.type.name} '
      'value=${acceptedResult.detectedReps} '
      'confidence=${acceptedResult.confidence.toStringAsFixed(2)} '
      'status=${acceptedResult.verificationStatus} '
      'failedRule=${_runtime.failedRuleReason.isEmpty ? 'none' : _runtime.failedRuleReason}',
    );
    if (!mounted) return;
    setState(() {
      _result = acceptedResult;
      _status = acceptedResult.isVerified
          ? AiMotionProofStatus.aiVerified
          : AiMotionProofStatus.aiFailed;
      _message = null;
    });
    if (acceptedResult.isVerified) _proofSettled = Completer<void>();
    unawaited(_analyzeCapturedMotion());
    _sessionCompletionResult = (
      value: acceptedResult.detectedReps,
      confidence: acceptedResult.confidence,
      verified: acceptedResult.isVerified,
    );
    _sessionCompletion = _completeVerificationSession();
    if (acceptedResult.isVerified) _scheduleAutoSubmit();
  }

  /// Set once the server accepted the proof — stops background retries.
  bool _proofAccepted = false;

  Future<void> _completeVerificationSession() async {
    final result = _sessionCompletionResult;
    final sessionId = _verificationSessionId;
    final releaseId = _verificationReleaseId;
    final checksum = _verificationReleaseChecksum;
    if (result == null ||
        sessionId == null ||
        sessionId.isEmpty ||
        releaseId == null ||
        releaseId.isEmpty ||
        checksum == null ||
        checksum.isEmpty) {
      return;
    }
    // Transient failures are retried in the background (3 tries); the proof
    // request also carries `sessionResult`, so even if every try fails the
    // server can finish the session itself.
    final done = await ref
        .read(raceControllerProvider.notifier)
        .completeVerificationSessionWithRetry(
          sessionId,
          releaseId: releaseId,
          releaseChecksum: checksum,
          status: result.verified ? 'completed' : 'failed',
          resultValue: result.value,
          confidence: result.confidence,
          failureReason: result.verified
              ? null
              : _isObjectComposition
              ? (_objectUpdate?.diagnostic ?? 'shot_not_confirmed')
              : _runtime.failedRuleReason,
          shouldContinue: () => mounted && !_disposed && !_proofAccepted,
        );
    if (done && result.verified) _verificationSessionCompleted = true;
    if (!done) _debugLog('verificationSessionCompletionUnavailable');
  }

  /// The client's own account of the finished session, sent with the proof so
  /// the server can complete the session itself. Null when the release the
  /// session pinned is unknown (then the old complete-first gate applies).
  ProofSessionResult? _sessionResultForProof() {
    final result = _sessionCompletionResult;
    final sessionId = _verificationSessionId;
    final releaseId = _verificationReleaseId;
    final checksum = _verificationReleaseChecksum;
    if (result == null ||
        !result.verified ||
        sessionId == null ||
        sessionId.isEmpty ||
        releaseId == null ||
        releaseId.isEmpty ||
        checksum == null ||
        checksum.isEmpty) {
      return null;
    }
    return ProofSessionResult(
      releaseId: releaseId,
      releaseChecksum: checksum,
      resultValue: result.value,
      confidence: result.confidence,
    );
  }

  /// The server only accepts an AI Motion Proof bound to this user's
  /// completed verification session for this race — proof submission must
  /// never outrun session completion. If the background completion dropped,
  /// retry once here; complete is idempotent server-side. Fails closed: no
  /// completed session, no proof.
  Future<bool> _verificationSessionReadyForProof() async {
    if (_verificationSessionCompleted) return true;
    if (_verificationSessionId == null || _verificationSessionId!.isEmpty) {
      // The load-time handshake may have dropped (e.g. no network when the
      // camera opened) — mint the session now, then complete it.
      try {
        final handshake = await ref
            .read(raceControllerProvider.notifier)
            .createVerificationSession(
              widget.raceId,
              appVersion: 'local',
              appBuild: MotionCapabilities.appBuild,
              runtimeCapabilities: MotionCapabilities.current(
                objectDotProducer: _objectDotProducer,
              ),
            );
        _verificationSessionId = handshake.session.id;
        _verificationReleaseId = handshake.session.releaseId;
        _verificationReleaseChecksum = handshake.session.releaseChecksum;
      } catch (_) {
        _debugLog('verificationSessionCreateFailed');
        return false;
      }
    }
    // Give an in-flight completion a short head start, but never block the
    // proof on it: a slow or failed `complete` is covered by `sessionResult`.
    try {
      await _sessionCompletion?.timeout(const Duration(milliseconds: 1500));
    } on TimeoutException {
      // Still running in the background — carry on.
    }
    if (_verificationSessionCompleted) return true;
    // The proof carries sessionResult (release id + checksum + value): the
    // server completes the session itself, so a failed complete is not fatal.
    if (_sessionResultForProof() != null) return true;
    await _completeVerificationSession();
    return _verificationSessionCompleted;
  }

  /// Waits (bounded) for POST /proof to resolve before the non-critical
  /// background traffic — server motion analysis and the session artifact
  /// upload — is allowed onto the wire.
  Future<void> _awaitProofSettled() async {
    final settled = _proofSettled;
    if (settled == null || settled.isCompleted) return;
    await settled.future.timeout(const Duration(seconds: 60), onTimeout: () {});
  }

  void _releaseProofSettled() {
    final settled = _proofSettled;
    if (settled != null && !settled.isCompleted) settled.complete();
  }

  Future<void> _analyzeCapturedMotion() async {
    if (_capturedFrames.length < 2 || !mounted) return;
    await _awaitProofSettled();
    if (_disposed) return;
    try {
      final result = await ref
          .read(raceControllerProvider.notifier)
          .analyzeMotion(
            MotionAnalysisRequest(
              motionId: _isCustom
                  ? (_customMovementName ?? 'custom')
                  : _activityId,
              frames: List<NuvoPoseFrame>.unmodifiable(_capturedFrames),
              targetReps: (_targetValue ?? 0) > 0 ? _targetValue : null,
              durationMs: _elapsed.inMilliseconds,
            ),
          );
      if (mounted) setState(() => _serverAnalysis = result);
    } catch (error) {
      // Local ML Kit/validator results remain authoritative while the server
      // prototype is unavailable. This is expected during early development.
      _debugLog('serverMotionAnalysisUnavailable error=$error');
    } finally {
      _finalizeSession();
    }
  }

  /// Upload an in-progress copy of the session when the count or validator
  /// state changes (throttled to one per 3s). Never after the final seal —
  /// a late snapshot must not overwrite the finished artifact.
  void _maybeSnapshotSession(int count, String validatorState) {
    final session = _session;
    if (session == null || _sessionFinalized || _disposed) return;
    final changed = count != _snapshotCount || validatorState != _snapshotState;
    final now = DateTime.now();
    final last = _lastSnapshotAt;
    final due = last == null || now.difference(last).inSeconds >= 3;
    if (!(changed && due)) return;
    _snapshotCount = count;
    _snapshotState = validatorState;
    _lastSnapshotAt = now;
    try {
      final consented =
          ref.read(authControllerProvider).user?.motionTrainingConsent == true;
      if (!consented) return;
      unawaited(
        ref.read(motionSessionUploadQueueProvider).enqueue(session.build()),
      );
    } catch (e) {
      _debugLog('motionSessionSnapshotSkipped $e');
    }
  }

  /// Seal the recorded session and hand it to the upload queue. Idempotent —
  /// called after server analysis resolves, and again from [dispose] to catch
  /// attempts the athlete abandoned mid-verification (those are `incomplete`
  /// and often the most useful to inspect).
  MotionSessionArtifact? _finalizeSession() {
    final session = _session;
    if (session == null || _sessionFinalized) return null;
    _sessionFinalized = true;

    final MotionSessionOutcome outcome;
    if (_status == AiMotionProofStatus.aiVerified ||
        _status == AiMotionProofStatus.submitting ||
        _status == AiMotionProofStatus.submitted) {
      // The artifact is sealed after POST /proof, so a submitted proof is
      // still a verified session.
      outcome = MotionSessionOutcome.verified;
    } else if (_status == AiMotionProofStatus.aiFailed) {
      outcome = MotionSessionOutcome.failed;
    } else {
      outcome = MotionSessionOutcome.incomplete;
    }
    final detected = _isObjectComposition
        ? _objectCount
        : _usesCustomRuntimeOutput
        ? (_customResult?.count ?? 0)
        : (_result?.detectedReps ?? 0);
    final confidence = _isObjectComposition
        ? _objectConfidence
        : _usesCustomRuntimeOutput
        ? _customResult?.confidence
        : _result?.confidence;

    session.updatePipeline(
      framesReceived: _poseDetector.framesReceived,
      framesProcessed: _poseDetector.framesProcessed,
      effectiveFps: _poseDetector.effectiveFps,
    );
    session.finish(
      outcome: outcome,
      detectedValue: detected,
      confidence: confidence,
      failedRuleReason: _isObjectComposition
          ? (_objectUpdate?.diagnostic ?? '')
          : _runtime.failedRuleReason,
    );
    final server = _serverAnalysis;
    final artifact = session.build(
      serverAnalysis: server == null
          ? null
          : {
              'motionId': server.motionId,
              'verdict': server.verdict,
              'detectedReps': server.detectedReps,
              'confidence': server.confidence,
              'uncertainty': server.uncertainty,
              'failureReasons': server.failureReasons,
              'coaching': server.coaching,
              'modelVersion': server.modelVersion,
              'validatorVersion': server.validatorVersion,
              'framesAnalyzed': server.framesAnalyzed,
              'validPoseFrames': server.validPoseFrames,
              'durationMs': server.durationMs,
            },
    );
    _lastArtifact = artifact;
    // Consent gate — the motion-points dataset is opt-in. A non-consenting
    // account never stages an artifact for upload; the server refuses too,
    // so this also protects against a stale local flag.
    final consented =
        ref.read(authControllerProvider).user?.motionTrainingConsent == true;
    if (consented) {
      // Fire-and-forget: staging + upload happen off the UI path.
      unawaited(ref.read(motionSessionUploadQueueProvider).enqueue(artifact));
      _debugLog(
        'motionSessionQueued id=${artifact.sessionId} '
        'outcome=${outcome.wire} frames=${artifact.frames.length}',
      );
    } else {
      _debugLog(
        'motionSessionSkipped id=${artifact.sessionId} — motion contribution off',
      );
    }
    return artifact;
  }

  /// Manual export — the "Save Diagnostic Session" pathway for the preset
  /// verifier. Consumes the exact same [MotionSessionArtifact] the auto-upload
  /// queue does, so a shared file and a fetched cloud session are byte-identical.
  Future<void> _shareSession() async {
    final artifact = _lastArtifact ?? _finalizeSession() ?? _session?.build();
    if (artifact == null) return;
    try {
      final dir = await getTemporaryDirectory();
      final file = await artifact.writeGzip(dir.path);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/gzip')],
        text: artifact.toLogText(),
        subject: 'Nuvo motion session ${artifact.sessionId}',
      );
    } catch (e) {
      _debugLog('shareSession failed: $e');
    }
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

  bool get _isPresentationFixtureRace =>
      isPresentationDemoRace(widget.raceId) ||
      isPresentationDemoCreatedRace(widget.raceId);

  Future<void> _submitVerifiedProof() async {
    if (_submitInFlight) return;
    _submitInFlight = true;
    try {
      await _submitVerifiedProofOnce();
    } finally {
      _submitInFlight = false;
      // Whatever happened, the proof request is no longer on the wire: the
      // deferred motion analysis / artifact upload may go now.
      _releaseProofSettled();
    }
  }

  Future<void> _submitVerifiedProofOnce() async {
    // Local presentation fixtures have no server race and resolve in the
    // controller's demo path — they never need a verification session.
    // Everything else — preset and custom verifier alike — fails closed:
    // no session, no proof. (A session whose `complete` call failed is fine
    // as long as the proof carries `sessionResult`.)
    if (!_isPresentationFixtureRace &&
        !await _verificationSessionReadyForProof()) {
      if (!mounted) return;
      setState(() {
        _status = AiMotionProofStatus.aiVerified;
        _message =
            'Verification is still syncing. Check your connection and try again.';
      });
      return;
    }
    final sessionResult = _isPresentationFixtureRace
        ? null
        : _sessionResultForProof();
    final controller = ref.read(raceControllerProvider.notifier);

    if (_isObjectComposition) {
      if (_objectCount <= 0 || _status != AiMotionProofStatus.aiVerified) {
        return;
      }
      final count = _objectCount;
      await _sendProof(
        value: count,
        status: 'ai_verified',
        send: (clientSubmissionId) => controller.submitObjectCompositionProof(
          widget.raceId,
          activityId: _objectCompositionSpec!.activityId,
          clientSubmissionId: clientSubmissionId,
          metric: _metric,
          value: count,
          targetValue: _raceTarget,
          confidence: _objectConfidence,
          verificationSummary:
              'Confirmed $count made basketball shot${count == 1 ? '' : 's'} from dot-only object tracking.',
          validatorVersion: _objectCompositionSpec!.releaseId,
          framesAnalyzed: _session?.objectFrameCount ?? 0,
          durationMs: _elapsed.inMilliseconds,
          verificationSessionId: _verificationSessionId,
          sessionResult: sessionResult,
        ),
      );
      return;
    }
    if (_usesCustomRuntimeOutput) {
      final result = _customResult;
      if (result == null || !result.isVerified) return;
      await _sendProof(
        value: result.count,
        status: result.verificationStatus,
        send: (clientSubmissionId) => controller.submitCustomPoseProof(
          widget.raceId,
          result: result,
          clientSubmissionId: clientSubmissionId,
          verificationSessionId: _verificationSessionId,
          sessionResult: sessionResult,
        ),
      );
      return;
    }

    final result = _result;
    if (result == null || !result.isVerified) return;
    await _sendProof(
      value: result.detectedReps,
      status: 'ai_verified',
      send: (clientSubmissionId) => controller.submitAiMotionProof(
        widget.raceId,
        result: result,
        clientSubmissionId: clientSubmissionId,
        metric: _metric,
        verificationSessionId: _verificationSessionId,
        sessionResult: sessionResult,
      ),
    );
  }

  /// The request pipeline around submit: patch the cached board and open the
  /// celebration right away, send the proof (the repository retries timeouts
  /// and 5xx with the same clientSubmissionId), then reconcile with the
  /// returned race — or roll the patch back and show the server's message on
  /// this screen.
  Future<void> _sendProof({
    required int value,
    required String status,
    required Future<Race> Function(String clientSubmissionId) send,
  }) async {
    setState(() {
      _status = AiMotionProofStatus.submitting;
      _message = null;
    });
    final controller = ref.read(raceControllerProvider.notifier);
    final userId = ref.read(authControllerProvider).user?.id;
    // One id for the whole submission, reset only after success.
    final clientSubmissionId = _clientSubmissionId ?? const Uuid().v4();
    _clientSubmissionId = clientSubmissionId;

    final optimistic = (_isPresentationFixtureRace || userId == null)
        ? null
        : controller.applyOptimisticProof(widget.raceId, userId, value);
    if (optimistic != null) {
      _openOptimisticCelebration(optimistic, value, status);
    }
    // A timed take must bind ITS attempt — if the open is still on the wire,
    // give it a beat before the submit path's own ensure-open would declare
    // a fresh (mistimed) attempt.
    final pendingOpen = _timedAttemptOpen;
    if (pendingOpen != null) {
      try {
        await pendingOpen.timeout(const Duration(seconds: 4));
      } catch (_) {
        // Failed or still pending — the submit path's ensure-open is the
        // fallback; either way the proof is allowed to try.
      }
    }
    try {
      final race = await send(clientSubmissionId);
      _proofAccepted = true;
      _clientSubmissionId = null;
      _timedTake?.markSubmitted();
      if (!mounted) return;
      setState(() => _status = AiMotionProofStatus.submitted);
      if (!_optimisticCelebrationOpen) _goToCelebration(race, value, status);
    } on ApiException catch (e) {
      _proofRejected(e.message);
    } catch (_) {
      _proofRejected('Verified proof could not be submitted. Try again.');
    }
  }

  /// The controller has already rolled the optimistic patch back; surface the
  /// message here and take the celebration down if it is still on top.
  void _proofRejected(String message) {
    if (!mounted) return;
    final celebrationOpen = _optimisticCelebrationOpen;
    _optimisticCelebrationOpen = false;
    if (celebrationOpen && ModalRoute.of(context)?.isCurrent == false) {
      context.pop();
    }
    setState(() {
      _status = AiMotionProofStatus.aiVerified;
      _message = message;
    });
  }

  /// Pushed (not replaced) so a rejection can come back to this screen; the
  /// screen is removed with the rest of the stack when the celebration leaves.
  void _openOptimisticCelebration(
    OptimisticProofPatch patch,
    int value,
    String status,
  ) {
    if (!mounted) return;
    _optimisticCelebrationOpen = true;
    _advanceFirstRaceGuide();
    final race = patch.race;
    context.push(
      '/race/${widget.raceId}/board-moved',
      extra: BoardMovedArgs(
        raceId: widget.raceId,
        raceName: race.displayTitle,
        value: value,
        unit: race.unit,
        status: status,
        rankBefore: patch.rankBefore,
        rankAfter: patch.rankAfter,
        peoplePassed: patch.peoplePassed,
        aiMotionProof: true,
      ),
    );
  }

  void _advanceFirstRaceGuide() {
    // First-race guide: the coached story continues past the proof — the
    // celebration's continue lands on Profile where the earned progress is
    // pointed out before the guide completes. Only advances an armed guide.
    if (ref.read(firstRaceGuideProvider) == FirstRaceGuideStep.verifySetup) {
      ref.read(firstRaceGuideProvider.notifier).state =
          FirstRaceGuideStep.profileReward;
    }
  }

  void _goToCelebration(Race race, int value, String status) {
    if (!mounted) return;
    final uid = ref.read(authControllerProvider).user?.id;
    final proof = race.recentProofs.isNotEmpty ? race.recentProofs.first : null;
    _advanceFirstRaceGuide();
    context.pushReplacement(
      '/race/${widget.raceId}/board-moved',
      extra: BoardMovedArgs(
        raceId: widget.raceId,
        raceName: race.displayTitle,
        value: value,
        unit: race.unit,
        status: proof?.verificationStatus ?? status,
        rankBefore: proof?.rankBefore,
        rankAfter: proof?.rankAfter ?? rankForUser(race, uid),
        peoplePassed: proof?.peoplePassed,
        aiMotionProof: true,
      ),
    );
  }

  AiMotionResult _acceptPartialMotionResult(AiMotionResult result) {
    if (result.isVerified ||
        result.detectedReps <= 0 ||
        result.validPoseFrames <= 0 ||
        result.confidence < 0.58) {
      return result;
    }
    return AiMotionResult(
      activity: result.activity,
      targetReps: result.targetReps,
      detectedReps: result.detectedReps,
      confidence: result.confidence,
      verificationStatus: 'ai_verified',
      verificationSummary: _isDistanceRace
          ? 'Recorded ${formatMotionTarget(_measure, result.detectedReps, 'mi')}. You can continue this race later.'
          : 'Recorded ${result.detectedReps} ${result.activity.label}. You can continue this race later.',
      framesAnalyzed: result.framesAnalyzed,
      validPoseFrames: result.validPoseFrames,
      durationMs: result.durationMs,
      validatorVersion: result.validatorVersion,
    );
  }

  CustomPoseRuntimeResult _acceptPartialCustomResult(
    CustomPoseRuntimeResult result,
  ) {
    if (result.isVerified ||
        result.count <= 0 ||
        result.validFrames <= 0 ||
        result.confidence < 0.58) {
      return result;
    }
    return CustomPoseRuntimeResult(
      verifierType: result.verifierType,
      verifierVersion: result.verifierVersion,
      movementName: result.movementName,
      measurementType: result.measurementType,
      count: result.count,
      target: result.target,
      verificationStatus: 'custom_verified',
      confidence: result.confidence,
      framesAnalyzed: result.framesAnalyzed,
      validFrames: result.validFrames,
      durationMs: result.durationMs,
      completionEvents: result.completionEvents,
      invalidAttemptCount: result.invalidAttemptCount,
      finalFailureReason: null,
    );
  }

  Future<void> _recordAgain() async {
    // A timed take abandoned here releases its open attempt — cancelling
    // before submit never spends the limit.
    await _releaseTimedAttempt();
    _recordingTimer?.cancel();
    _inactivityWatch.disarm();
    _dismissInactivityPrompt();
    await _stopImageStream();
    if (_objectCompositionSpec != null) {
      _basketballShot = BasketballShotCoordinator(
        runtime: BasketballShotRuntime(spec: _objectCompositionSpec!),
        recorder: _session,
      );
    }
    setState(() {
      _result = null;
      _serverAnalysis = null;
      _capturedFrames.clear();
      _lastObjectPose = null;
      _lastObjectPoseAt = null;
      _lastObjectInferenceAt = null;
      _customResult = null;
      _customUpdate = null;
      _objectUpdate = null;
      _objectCount = 0;
      _objectConfidence = 0;
      _message = null;
      _elapsed = Duration.zero;
      _autoSubmitScheduled = false;
      _clientSubmissionId = null;
      _proofAccepted = false;
      _releaseProofSettled();
      _proofSettled = null;
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

  /// The verifier's own target — the REMAINING amount this session must reach
  /// to complete the race. Null when the format has no finish line: the
  /// session then counts everything and reports the raw count.
  int? get _targetValue => _isObjectComposition
      ? (_hasFinishTarget
            ? ((_raceTargetValue ?? 1) - _raceTotalBefore)
                  .clamp(1, 1000000)
                  .toInt()
            : null)
      : _runtime.targetValue;

  /// Only a format that scores against a finish line gets target-reached
  /// treatment — celebration, "goal" color states, the /target readout. A
  /// best-attempt race has nothing to reach; its session target is a
  /// machine value, never a finish line.
  bool get _hasFinishTarget => _raceContext?.format.usesScoreTarget ?? true;

  /// The session reached a real finish line — never true for attempt or
  /// deadline modes, where there is no session target to reach.
  bool get _targetReachedNow => sessionReachedFinishTarget(
    hasFinishTarget: _hasFinishTarget,
    sessionTarget: _targetValue,
    sessionValue: _currentValue,
  );

  /// What the rest-state pill names before recording — "Goal: 50 pushups"
  /// when there's a finish line, the mode's own stakes when there isn't.
  String get _restStateLabel {
    final ctx = _raceContext;
    if (ctx != null && !_hasFinishTarget) return ctx.statusLine;
    return 'Goal: $_targetLabel';
  }

  /// This session's contribution so far (starts at 0). Only this is submitted.
  int get _sessionContribution =>
      _isObjectComposition ? _objectCount : _runtime.currentValue;

  int get _startingRaceProgress => _raceTotalBefore;

  ContinuationProgress get _continuation => ContinuationProgress(
    startingRaceProgress: _startingRaceProgress,
    // No finish line means no cap on displayed progress — 0 keeps
    // [ContinuationProgress.displayedProgress] returning the true
    // cumulative count instead of clamping at a fabricated target.
    raceTarget: _hasFinishTarget
        ? (_raceTargetValue ?? (_startingRaceProgress + (_targetValue ?? 0)))
        : 0,
  );

  /// The full race target (reps / seconds / metres).
  int get _raceTarget => _continuation.raceTarget;

  /// **Race progress**, continuing from where the athlete left off — the
  /// primary number. Opens at `startingRaceProgress`, not zero.
  int get _displayedRaceProgress =>
      _continuation.displayedProgress(_sessionContribution);

  /// Kept for the internal completion check / celebration timing.
  int get _currentValue =>
      _isObjectComposition ? _objectCount : _runtime.currentValue;

  /// Latest verifier debug metrics — includes virtual distance / pace /
  /// cadence / intensity for a distance race.
  Map<String, double> _liveMetrics = const {};

  MotionMeasurementType get _measure =>
      MotionMeasurementType.values.asNameMap()[_measurementType] ??
      MotionMeasurementType.repetitions;

  bool get _isDistanceRace => _measure == MotionMeasurementType.distance;

  String get _displayUnit => _isObjectComposition
      ? 'shots'
      : motionActivityForBackendValue(_activityId)?.unit ?? _metric;

  /// "12 / 25 reps" · "0:45 / 2:00" · "0.12 / 0.25 mi".
  String _progressText(int current, int target) => _usesCustomRuntimeOutput
      ? '$current / $target'
      : formatMotionProgress(_measure, current, target, _displayUnit);

  /// "8:42 /mi" while running a distance race, else null.
  String? get _paceLabel {
    if (!_isDistanceRace) return null;
    final raw = _liveMetrics['paceSecPerMile'];
    final pace = formatPacePerMile(raw == null || raw == 0 ? null : raw);
    return pace == null ? null : '$pace /mi';
  }

  /// Whole-run average pace, for the result screen.
  String? get _avgPaceLabel {
    if (!_isDistanceRace) return null;
    final raw = _liveMetrics['avgPaceSecPerMile'];
    final pace = formatPacePerMile(raw == null || raw == 0 ? null : raw);
    return pace == null ? null : '$pace /mi';
  }

  /// "Moderate" while running a distance race, else null.
  String? get _intensityLabel {
    if (!_isDistanceRace) return null;
    return switch (_liveMetrics['intensity']?.round() ?? 0) {
      0 => null,
      1 => 'Easy',
      2 => 'Moderate',
      _ => 'Hard',
    };
  }

  /// The full race goal (not the session's remaining amount).
  String get _targetLabel {
    if (_isObjectComposition) return '$_raceTarget made shots';
    if (_usesCustomRuntimeOutput) return '$_raceTarget reps';
    final definition = motionActivityForBackendValue(_activityId);
    return definition?.targetLabel(_raceTarget) ??
        '$_raceTarget $_activityLabel';
  }

  /// The primary readout during a session — mode-aware:
  ///   first_to_goal  → race progress, continuing from the bank ("32 / 50")
  ///   most_in_window → accumulated total, no fake finish ("37")
  ///   attempt races  → the attempt itself ("14") — there is no /target
  String get _raceProgressReadout {
    final ctx = _raceContext;
    // Custom (taught) movements and shot-counting included: a window /
    // attempt race has no finish line, so it shows the running count —
    // never "N / 60 reps" or "N / 6 shots".
    if (ctx != null && !_hasFinishTarget) {
      final shown = ctx.isAttemptBased
          ? _sessionContribution
          : _raceTotalBefore + _sessionContribution;
      return _usesCustomRuntimeOutput
          ? '$shown'
          : formatMotionTarget(_measure, shown, _displayUnit);
    }
    if (_usesCustomRuntimeOutput) {
      return '$_displayedRaceProgress / $_raceTarget $_metric';
    }
    return _progressText(_displayedRaceProgress, _raceTarget);
  }

  String get _movementTitle => _isObjectComposition
      ? 'Basketball shot'
      : _usesCustomRuntimeOutput
      ? (_customMovementName ?? 'Custom movement')
      : motionActivityForBackendValue(_activityId)?.title ?? _activityLabel;

  /// True while a live preview is on screen. In that case the camera takes the
  /// whole screen instead of sitting in an inset card.
  bool get _isImmersiveCamera {
    // Stay immersive across a lens flip so the layout does not thrash.
    if (_switchingCamera) return true;
    // The camera is still opening. Stay on the immersive surface so there is
    // no boxed intermediate screen before the preview appears. A setup state
    // carrying an error means the race/session load failed — that drops to
    // the status scaffold where the retry action lives.
    if (_status == AiMotionProofStatus.setup && _message == null) return true;
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
    return _immersiveStatusScaffold();
  }

  /// Full-screen light surface for every non-camera, non-result state —
  /// session setup, permission denial, verifier errors. Same visual family as
  /// the rest of the v13 shell so no intermediate "old" page can flash.
  Widget _immersiveStatusScaffold() {
    final busy = _status == AiMotionProofStatus.processing;
    return Scaffold(
      backgroundColor: V13.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Row(
                children: [
                  _immersiveIconButton(
                    icon: Icons.arrow_back_rounded,
                    onPressed: _leaveScreen,
                  ),
                  const SizedBox(width: 10),
                  _pill('Goal: $_targetLabel', color: V13.card),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (busy)
                        const SizedBox(
                          width: 44,
                          height: 44,
                          child: CircularProgressIndicator(
                            color: V13.navy,
                            strokeWidth: 3,
                          ),
                        )
                      else
                        V13IconTile(
                          icon:
                              _status == AiMotionProofStatus.unsupportedMovement
                              ? Icons.block_rounded
                              : Icons.videocam_off_rounded,
                          color: V13.card,
                          iconColor: V13.navy,
                          size: 64,
                          radius: V13.radiusTileLg,
                        ),
                      const SizedBox(height: 16),
                      Text(
                        _movementTitle,
                        style: V13.sectionHead,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _message ?? _cameraPlaceholderText,
                        style: V13.body.copyWith(color: V13.muted),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _actions(),
              ),
            ),
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

          // Timed battle 3-2-1 — over the live preview, before the take starts.
          if (_timedTake?.countingDown == true)
            Positioned.fill(
              child: IgnorePointer(child: Center(child: _countdownOverlay())),
            ),

          if (_switchingCamera)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: CircularProgressIndicator(
                    color: V13.white,
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
                    onPressed: _leaveScreen,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          _movementTitle.isEmpty
                              ? 'AI Motion Proof'
                              : _movementTitle,
                          style: V13.bodyStrong.copyWith(color: V13.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        _pill(
                          recording ? _raceProgressReadout : _restStateLabel,
                          color: recording
                              ? (_targetReachedNow
                                    ? V13.mint
                                    : _hasFinishTarget
                                    ? V13.danger
                                    : V13.blue)
                              : V13.card,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
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

          if (kDebugMode && _usesCustomRuntimeOutput && recording)
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
    final targetReached = _targetReachedNow;

    return PoseSkeletonOverlay(
      frame: _skeletonHold.frame,
      sourceSize: Size(previewSize.height, previewSize.width),
      mirrorX: PoseSkeletonPreviewTransform.shouldMirrorX(
        lensDirection: _selectedCamera?.lensDirection,
        platform: defaultTargetPlatform,
      ),
      color: targetReached
          ? V13.mint
          : _isOnStreak
          ? V13.sun
          : V13.white,
      glow: _skeletonGlow,
    );
  }

  /// One-shot "finish line reached" moment, fired the instant the validator's
  /// count hits the target. Recording keeps running so extra reps still count.
  Widget _targetReachedOverlay() {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.center,
        child:
            Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 32,
                  ),
                  decoration: BoxDecoration(
                    color: V13.mint,
                    borderRadius: BorderRadius.circular(V13.radiusCardLg),
                    border: Border.all(
                      color: V13.navy,
                      width: V13.outlineThick,
                    ),
                    boxShadow: V13.shadow6,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _raceProgressReadout,
                          style: V13.hugeNumber.copyWith(fontSize: 56),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('FINISH LINE', style: V13.sectionHead),
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

  /// The 3-2-1 before a timed take — the attempt opens on the server clock
  /// the moment it ends, so this is the last moment to get into position.
  Widget _countdownOverlay() {
    final remaining = _timedTake?.countdownRemaining ?? 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$remaining',
          style: V13.hugeNumber.copyWith(
            fontSize: 160,
            color: V13.white,
            shadows: const [
              Shadow(
                color: Color(0xB3000000),
                blurRadius: 24,
                offset: Offset(0, 4),
              ),
            ],
          ),
        ).animate(key: ValueKey(remaining)).scale(
          begin: const Offset(0.6, 0.6),
          end: const Offset(1, 1),
          duration: 300.ms,
          curve: Curves.easeOutBack,
        ),
        const SizedBox(height: 12),
        _pill('Get in position', color: V13.card),
      ],
    );
  }

  Widget _immersiveIconButton({
    required IconData icon,
    required VoidCallback? onPressed,
    String? semanticLabel,
  }) {
    return V13IconButton(
      icon: icon,
      onTap: onPressed,
      semanticLabel: semanticLabel,
    );
  }

  // Full-screen result moment for terminal verification states.
  Widget _immersiveResultScaffold() {
    return Scaffold(
      backgroundColor: V13.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Row(
                children: [
                  _immersiveIconButton(
                    icon: Icons.arrow_back_rounded,
                    onPressed: _leaveScreen,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _movementTitle,
                      style: V13.sectionHead,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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
        color: V13.navy.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(V13.radiusTileLg),
      ),
      child: DefaultTextStyle(
        style: V13.caption.copyWith(color: V13.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('state: ${update?.state.name ?? '--'}'),
            Text(
              'count: ${update?.count ?? 0} / ${update?.target ?? _targetValue ?? '-'}',
            ),
            Text(
              'sequence: ${(update?.sequenceProgress ?? 0).toStringAsFixed(2)}',
            ),
            Text(
              'similarity: ${(update?.currentSimilarity ?? 0).toStringAsFixed(2)}',
            ),
            Text(
              'valid features: ${(update?.validFeatureRatio ?? 0).toStringAsFixed(2)}',
            ),
            if (update?.failureReason != null)
              Text(
                'reset: ${update!.failureReason}',
                style: V13.caption.copyWith(color: V13.danger),
              ),
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
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: V13.navy.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(V13.radiusPill),
                  ),
                  child: Text(
                    'Put your phone down so Nuvo sees your whole body',
                    style: V13.bodyStrong.copyWith(color: V13.white),
                    textAlign: TextAlign.center,
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
              Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: V13.mint,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: V13.navy,
                        width: V13.outlineThick,
                      ),
                      boxShadow: V13.shadow4,
                    ),
                    child: const Icon(
                      Icons.verified_rounded,
                      color: V13.navy,
                      size: 44,
                    ),
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
              FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _isObjectComposition
                          ? '+$_objectCount ${_objectCount == 1 ? 'shot' : 'shots'}'
                          : _usesCustomRuntimeOutput
                          ? '+${_customCountedLabel(customResult)}'
                          : '+${_countedLabel(result)}',
                      style: V13.hugeNumber.copyWith(fontSize: 56),
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
                    : _isDistanceRace && _avgPaceLabel != null
                    ? '${_avgPaceLabel!} average'
                    : 'Nice set. AI Motion verified it.',
                style: V13.bodyStrong,
                textAlign: TextAlign.center,
              ),
              if (_serverAnalysis?.coaching.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                Text(
                  _serverAnalysis!.coaching.first,
                  style: V13.body.copyWith(color: V13.muted),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Failed / coaching state.
    final detected = _isObjectComposition
        ? _objectCount
        : _usesCustomRuntimeOutput
        ? (customResult?.count ?? 0)
        : (result?.detectedReps ?? 0);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child:
            Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: V13.card,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: V13.navy,
                          width: V13.outlineThick,
                        ),
                        boxShadow: V13.shadow4,
                      ),
                      child: const Icon(
                        Icons.refresh_rounded,
                        color: V13.navy,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text('Try again', style: V13.title),
                    const SizedBox(height: 8),
                    Text(
                      // Race progress after this session (it continues from
                      // wherever the athlete was, and only this session's
                      // contribution was added).
                      detected > 0
                          ? (_hasFinishTarget
                                ? "You're at ${_progressText(_startingRaceProgress + detected, _raceTarget)}. Keep going."
                                : 'You logged ${formatMotionTarget(_measure, _startingRaceProgress + detected, _displayUnit)}. Keep going.')
                          : 'Nothing counted this time — line yourself up and try again.',
                      style: V13.bodyStrong,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _serverAnalysis != null &&
                              _serverAnalysis!.failureReasons.isNotEmpty
                          ? _serverAnalysis!.failureReasons.first
                          : 'Keep the camera view clear and try again.',
                      style: V13.body.copyWith(color: V13.muted),
                      textAlign: TextAlign.center,
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: _shareSession,
                        icon: const Icon(
                          Icons.ios_share_rounded,
                          size: 18,
                          color: V13.navy,
                        ),
                        label: Text(
                          'Share session',
                          style: V13.caption.copyWith(color: V13.navy),
                        ),
                      ),
                    ],
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

  /// Burst shown the moment a checkpoint lands. For reps it's "+1 / +2 / +3"
  /// (one per rep). For a distance sprint it's the checkpoint distance
  /// ("15 m") — a milestone crossed, not a claim of one measured metre.
  /// Keyed on [_repFlashSeq] so each lands with its own animation.
  Widget _repFlashOverlay() {
    final inStreak = _streakCount >= 2;
    final flashColor = inStreak ? V13.sun : V13.white;
    final burstText = _isDistanceRace
        ? '${_distancePolicy.metresAtMilestone(_distancePolicy.milestonesCrossed(_displayedRaceProgress))} m'
        : '+${_streakCount > 0 ? _streakCount : 1}';
    final shadows = [
      const Shadow(
        color: Color(0xB3000000),
        blurRadius: 18,
        offset: Offset(0, 3),
      ),
      Shadow(
        color: V13.sun.withValues(alpha: 0.4),
        blurRadius: 28,
        offset: Offset.zero,
      ),
    ];

    return IgnorePointer(
      child: Center(
        child:
            Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      // Reps: a rep landing while this is still showing grows
                      // the same badge (+1 -> +2 -> +3). Distance: the
                      // checkpoint just crossed.
                      burstText,
                      style: V13.hugeNumber.copyWith(
                        fontSize: _isDistanceRace ? 120 : 200,
                        height: 0.9,
                        color: flashColor,
                        shadows: shadows,
                      ),
                    ),
                    if (inStreak) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 10, 24, 10),
                        decoration: BoxDecoration(
                          color: V13.sun,
                          borderRadius: BorderRadius.circular(V13.radiusPill),
                          border: Border.all(
                            color: V13.navy,
                            width: V13.outline,
                          ),
                          boxShadow: V13.shadow3,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.whatshot_rounded,
                              color: V13.navy,
                              size: 32,
                            ),
                            const SizedBox(width: 8),
                            Text(_streakLabel, style: V13.sectionHead),
                          ],
                        ),
                      ),
                    ],
                  ],
                )
                .animate(key: ValueKey(_repFlashSeq))
                .fadeOut(delay: 320.ms, duration: 220.ms),
      ),
    );
  }

  Widget _recordingHud() {
    // Pace + intensity only for a mile-scale run; a metre sprint shows the
    // phase line ("HALFWAY", "ALMOST THERE") instead.
    final showsPace =
        _isDistanceRace &&
        motionProgressShowsPace(MotionMeasurementType.distance, _raceTarget);
    final phase = motionProgressPhase(
      current: _displayedRaceProgress,
      target: _raceTarget,
    );
    // A milestone/new-best beat holds the line for its flash window;
    // otherwise the phase pool's rotating line shows.
    final flashActive =
        _hudFlashUntil != null && DateTime.now().isBefore(_hudFlashUntil!);
    final phaseLine = flashActive
        ? _encouragement.flashLine
        : _encouragement.phaseLine(
            phase,
            elapsedSeconds: _elapsed.inSeconds,
            rotationTick:
                _elapsed.inSeconds ~/ SessionEncouragement.rotationSeconds,
          );
    final effort = [
      if (showsPace) ?_paceLabel,
      if (showsPace) ?_intensityLabel,
    ].join('   ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: V13.card,
        borderRadius: BorderRadius.circular(V13.radiusCard),
        border: Border.all(color: V13.navy, width: V13.outline),
        boxShadow: V13.shadow4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _raceProgressReadout,
                    style: V13.hugeNumber.copyWith(fontSize: 44),
                  ),
                ),
                Text(
                  effort.isNotEmpty ? effort : phaseLine,
                  style: V13.bodyStrong,
                ),
              ],
            ),
          ),
          Text(
            _formatElapsed(_timedRemaining ?? _elapsed),
            style: V13.numberSm.copyWith(color: V13.muted),
          ),
        ],
      ),
    );
  }

  Widget _errorMessage(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: V13.card,
        borderRadius: BorderRadius.circular(V13.radiusTileLg),
        border: Border.all(color: V13.danger, width: V13.outline),
      ),
      child: Text(message, style: V13.caption.copyWith(color: V13.danger)),
    );
  }

  List<Widget> _actions() {
    final loading =
        _status == AiMotionProofStatus.processing ||
        _status == AiMotionProofStatus.submitting;

    return switch (_status) {
      AiMotionProofStatus.setup =>
        _message != null
            ? [
                V13Button.primary(
                  label: 'Try again',
                  icon: Icons.replay_rounded,
                  fullWidth: true,
                  onPressed: _loadRace,
                ),
                const SizedBox(height: 12),
                V13Button.secondary(
                  label: 'Back',
                  fullWidth: true,
                  onPressed: _leaveScreen,
                ),
              ]
            : [const SizedBox.shrink()],
      AiMotionProofStatus.unsupportedMovement => [
        V13Button.secondary(
          label: 'Back',
          fullWidth: true,
          onPressed: _leaveScreen,
        ),
      ],
      AiMotionProofStatus.cameraReady => _timedTake?.countingDown == true
          ? [
              // The 3-2-1 is running — the only action is backing out of it.
              V13Button.secondary(
                label: 'Cancel',
                fullWidth: true,
                onPressed: _releaseTimedAttempt,
              ),
            ]
          : _attemptLimitReached
          ? [
              _errorMessage(
                'All $_attemptLimit attempts used — no attempts left in this race.',
              ),
              const SizedBox(height: 12),
              V13Button.secondary(
                label: 'Back',
                fullWidth: true,
                onPressed: _leaveScreen,
              ),
            ]
          : [
              if (_attemptUsageShown) ...[
                Center(
                  child: _pill(
                    timedAttemptsUsedLabel(_attemptLimit, _attemptsUsed),
                    color: V13.card,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              V13Button.primary(
                label: 'Start recording',
                icon: Icons.videocam_rounded,
                fullWidth: true,
                onPressed: _startRecording,
              ),
            ],
      AiMotionProofStatus.recording => [
        V13Button.primary(
          // A timed take finishes itself at zero — the button is the early out.
          label: _timedTake != null ? 'Finish early' : 'Done',
          icon: Icons.check_rounded,
          fullWidth: true,
          onPressed: _finishRecording,
        ),
        const SizedBox(height: 12),
        V13Button.secondary(
          label: 'Cancel',
          fullWidth: true,
          onPressed: _recordAgain,
        ),
      ],
      AiMotionProofStatus.aiVerified => [
        V13Button.primary(
          label: 'Add to race',
          icon: Icons.verified_rounded,
          fullWidth: true,
          onPressed: _submitVerifiedProof,
        ),
        const SizedBox(height: 12),
        V13Button.secondary(
          label: 'Record again',
          icon: Icons.replay_rounded,
          fullWidth: true,
          onPressed: _recordAgain,
        ),
      ],
      AiMotionProofStatus.submitting => [const SizedBox.shrink()],
      AiMotionProofStatus.submitted => [const SizedBox.shrink()],
      // A denied camera can't re-prompt — the only honest actions are the
      // OS settings deep link (same 'app-settings:' scheme the QR scanner
      // uses) and the way back.
      AiMotionProofStatus.permissionDenied => [
        V13Button.primary(
          label: 'Open Settings',
          icon: Icons.settings_rounded,
          fullWidth: true,
          onPressed: () => launchUrl(Uri.parse('app-settings:')),
        ),
        const SizedBox(height: 12),
        V13Button.secondary(
          label: 'Back',
          fullWidth: true,
          onPressed: _leaveScreen,
        ),
      ],
      AiMotionProofStatus.aiFailed || AiMotionProofStatus.cameraError => [
        V13Button.primary(
          label: _basketballPreflightFailed
              ? 'Retry verification'
              : 'Record again',
          icon: Icons.replay_rounded,
          fullWidth: true,
          onPressed: _basketballPreflightFailed ? _loadRace : _recordAgain,
        ),
      ],
      _ => [
        V13Button.primary(
          label: loading ? 'Checking move' : 'Begin',
          fullWidth: true,
          loading: loading,
          onPressed: null,
        ),
      ],
    };
  }

  Widget _pill(String label, {required Color color}) {
    return V13Pill(
      label: label,
      color: color,
      textColor: color.computeLuminance() > 0.5 ? V13.navy : V13.white,
    );
  }

  Widget _visibilityPill() {
    final recording = _status == AiMotionProofStatus.recording;
    final visible = _isObjectComposition
        ? _objectUpdate != null
        : _runtime.fullBodyVisible;
    final targetReached = _targetReachedNow;

    final label = recording && targetReached
        ? 'Target complete'
        : recording && visible
        ? 'Keep going'
        : recording
        ? 'Step back into frame'
        : 'Get in position';
    final color = recording && targetReached
        ? V13.mint
        : recording && visible
        ? V13.blue
        : V13.card;

    return _pill(label, color: color);
  }

  String get _cameraPlaceholderText {
    if (_status == AiMotionProofStatus.unsupportedMovement) {
      return 'This movement cannot be camera verified yet.';
    }
    if (_status == AiMotionProofStatus.processing) return 'Starting camera...';
    return 'Put your phone down so Nuvo sees your whole body.';
  }

  String _formatElapsed(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _countedLabel(AiMotionResult? result) {
    if (_isObjectComposition) {
      return '$_objectCount ${_objectCount == 1 ? 'shot' : 'shots'}';
    }
    final value = result?.detectedReps ?? _targetValue ?? 0;
    final definition = motionActivityForBackendValue(_activityId);
    if (_isDistanceRace) return formatMotionTarget(_measure, value, 'mi');
    if (definition?.isHold == true) return '$value seconds';
    final unit = definition?.unit ?? _activityLabel;
    return '$value $unit';
  }

  String _customCountedLabel(CustomPoseRuntimeResult? result) {
    final value = result?.count ?? _targetValue ?? 0;
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
      ..color = V13.white.withValues(alpha: 0.3)
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
