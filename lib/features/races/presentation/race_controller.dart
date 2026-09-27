// Shared race state. See docs/agents/08-codebase-navigation.md (provider graph)
// and docs/agents/10-pitfalls-and-fixes.md §A1.
//
// This is a StateNotifierProvider — it is NOT recreated on sign-out; only its
// `state` is reset (by clearRaces()). Any internal field that must not survive a
// session (the cache timestamp, the in-flight future) MUST be nulled in
// clearRaces(), or a load hung across sign-out wedges the races tab until the
// app is killed.
//
// loadRaces(): 5-minute cache + single-flight de-dup. force:false respects the
// cache; force:true always refetches. Every screen reads state via
// raceControllerProvider and calls mutations via .notifier — never a second
// source of truth, never a direct RaceApi call.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../arena/presentation/arena_controller.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../../core/demo/presentation_demo.dart';
import '../ai/custom_pose/custom_pose_sequence_runtime.dart';
import '../ai/custom_pose/custom_pose_verifier_spec.dart';
import '../data/ai_motion_models.dart';
import '../data/motion_analysis_contract.dart';
import '../data/race_api.dart';
import '../data/race_models.dart';
import '../data/race_repository.dart';
import '../domain/motion_activity.dart';

class RaceState {
  const RaceState({
    this.races = const [],
    this.loading = false,
    this.refreshing = false,
    this.error,
  });

  final List<Race> races;

  /// First load, nothing cached yet — a screen may show a full skeleton.
  final bool loading;

  /// A background revalidation while cached data is already on screen — a
  /// screen should keep its content and, at most, show a subtle indicator.
  final bool refreshing;

  final String? error;

  bool get hasData => races.isNotEmpty;

  RaceState copyWith({
    List<Race>? races,
    bool? loading,
    bool? refreshing,
    String? error,
  }) => RaceState(
    races: races ?? this.races,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    error: error,
  );
}

class RaceController extends StateNotifier<RaceState> {
  RaceController(
    this._repo, {
    this.onMutated,
    this.isPresentationDemo = _neverPresentationDemo,
    this.presentationUserId = _emptyPresentationUserId,
  }) : super(const RaceState());

  final RaceRepository _repo;

  /// Called after a race write or a successful list refresh so sibling caches
  /// (Arena) can revalidate. See docs/agents/18-data-freshness-contract.md.
  final void Function()? onMutated;
  final bool Function() isPresentationDemo;
  final String Function() presentationUserId;

  static bool _neverPresentationDemo() => false;
  static String _emptyPresentationUserId() => '';

  /// How old cached data may be before [revalidate] refetches it in the
  /// background. Short — this fires on screen focus and app resume.
  static const _staleWindow = Duration(seconds: 45);

  Future<MotionAnalysisResult> analyzeMotion(MotionAnalysisRequest request) =>
      _repo.analyzeMotion(request);

  Future<MotionModelArtifactFetch> getMotionModelArtifact(
    String modelVersion, {
    String? etag,
  }) => _repo.getMotionModelArtifact(modelVersion, etag: etag);

  Future<VerificationSessionHandshake> createVerificationSession(
    String raceId, {
    required String appVersion,
    required String appBuild,
    required Set<String> runtimeCapabilities,
  }) => _repo.createVerificationSession(
    raceId,
    appVersion: appVersion,
    appBuild: appBuild,
    runtimeCapabilities: runtimeCapabilities,
  );

  Future<VerificationSession> startVerificationSession(String sessionId) =>
      _repo.startVerificationSession(sessionId);

  Future<VerificationSession> completeVerificationSession(
    String sessionId, {
    required String releaseId,
    required String releaseChecksum,
    required String status,
    required int resultValue,
    required double confidence,
    String? failureReason,
    String? motionSessionId,
  }) => _repo.completeVerificationSession(
    sessionId,
    releaseId: releaseId,
    releaseChecksum: releaseChecksum,
    status: status,
    resultValue: resultValue,
    confidence: confidence,
    failureReason: failureReason,
    motionSessionId: motionSessionId,
  );

  Future<void> submitMotionTrainingExample({
    required MotionAnalysisRequest request,
    required String consentVersion,
    String? label,
  }) => _repo.submitMotionTrainingExample(
    request: request,
    consentVersion: consentVersion,
    label: label,
  );
  static const _cacheLifetime = Duration(minutes: 5);
  Future<void>? _loadInFlight;
  DateTime? _racesLoadedAt;
  final Map<String, Timer> _presentationDeletionTimers = {};

  @override
  void dispose() {
    for (final timer in _presentationDeletionTimers.values) {
      timer.cancel();
    }
    _presentationDeletionTimers.clear();
    super.dispose();
  }

  /// Bumped by [clearRaces] (sign-out). A fetch started before a sign-out can
  /// still be in flight when the response arrives after clearRaces() has
  /// already reset state for the *next* session — without this guard that
  /// stale response would silently overwrite the new session's (possibly
  /// empty, correctly-clearing) state with the previous account's races.
  /// `_fetchRaces` captures the generation at start and only applies its
  /// result if nothing has cleared the cache in the meantime.
  int _generation = 0;

  Future<void> loadRaces({bool force = true}) {
    final loadedAt = _racesLoadedAt;
    if (!force &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < _cacheLifetime) {
      return Future.value();
    }
    final inFlight = _loadInFlight;
    if (inFlight != null) return inFlight;

    final request = _fetchRaces();
    _loadInFlight = request;
    request.then<void>(
      (_) => _clearInFlight(request),
      onError: (Object _, StackTrace _) => _clearInFlight(request),
    );
    return request;
  }

  /// Stale-while-revalidate entry point: call on screen focus and app resume.
  /// Renders nothing itself — if the cache is fresh it's a no-op, otherwise it
  /// kicks a background refresh while the current races stay on screen.
  void revalidate() {
    final at = _racesLoadedAt;
    if (state.hasData &&
        at != null &&
        DateTime.now().difference(at) < _staleWindow) {
      return;
    }
    loadRaces(force: true);
  }

  void _clearInFlight(Future<void> request) {
    if (identical(_loadInFlight, request)) _loadInFlight = null;
  }

  Future<void> _fetchRaces() async {
    final generation = _generation;
    if (mounted) {
      final haveData = state.hasData;
      state = RaceState(
        races: state.races,
        loading: !haveData,
        refreshing: haveData,
      );
    }
    try {
      final races = isPresentationDemo()
          ? PresentationDemoData.races(presentationUserId())
          : await _repo.getRaces();
      if (generation != _generation) return; // superseded by a sign-out
      _racesLoadedAt = DateTime.now();
      if (mounted) {
        state = RaceState(races: races);
        // Arena is a derived view of the same races. A successful read can
        // discover a race created elsewhere, so it must invalidate the
        // sibling snapshot just like a local write does.
        onMutated?.call();
      }
    } on ApiException catch (e) {
      if (generation != _generation) return;
      // A demo session must never surface a network error — if the session
      // resolved as presentation mode mid-flight, fixtures win.
      if (isPresentationDemo()) {
        if (mounted) _applyFixtures();
        return;
      }
      // Keep cached races visible on a failed background refresh.
      if (mounted) {
        state = state.copyWith(
          loading: false,
          refreshing: false,
          error: state.hasData ? null : e.message,
        );
      }
    } catch (_) {
      if (generation != _generation) return;
      if (isPresentationDemo()) {
        if (mounted) _applyFixtures();
        return;
      }
      if (mounted) {
        state = state.copyWith(
          loading: false,
          refreshing: false,
          error: state.hasData ? null : 'Failed to load races.',
        );
      }
    }
  }

  void _applyFixtures() {
    _racesLoadedAt = DateTime.now();
    state = RaceState(races: PresentationDemoData.races(presentationUserId()));
    onMutated?.call();
  }

  Future<Race> createRace({
    required String title,
    String? description,
    String? category,
    String goalType = 'manual',
    int? targetValue,
    String? unit,
    String? startLineAt,
    String? finishLineAt,
    String? rules,
    String? proofRequirement,
    String? proofReviewMode,
    String? visibility,
    String? aiActivityType,
    String? activityId,
    String? metric,
    String? format,
    String? recurrence,
    String? targetUnit,
    String? proofMode,
    String? scoreDirection,
  }) async {
    if (isPresentationDemo()) {
      final id =
          '$presentationDemoCreatedRacePrefix${DateTime.now().microsecondsSinceEpoch}';
      final race = PresentationDemoData.createdRace(
        id: id,
        userId: presentationUserId(),
        title: title,
        targetValue: targetValue ?? 10,
        activityId: activityId ?? aiActivityType,
        unit: unit ?? targetUnit,
      );
      _addPresentationRace(race);
      return race;
    }
    final race = await _repo.createRace(
      title: title,
      description: description,
      category: category,
      goalType: goalType,
      targetValue: targetValue,
      unit: unit,
      startLineAt: startLineAt,
      finishLineAt: finishLineAt,
      rules: rules,
      proofRequirement: proofRequirement,
      proofReviewMode: proofReviewMode,
      visibility: visibility,
      aiActivityType: aiActivityType,
      activityId: activityId,
      metric: metric,
      format: format,
      recurrence: recurrence,
      targetUnit: targetUnit,
      proofMode: proofMode,
      scoreDirection: scoreDirection,
    );
    if (mounted) {
      state = state.copyWith(races: [race, ...state.races]);
      _racesLoadedAt = DateTime.now();
      onMutated?.call();
    }
    return race;
  }

  Future<Race> createCustomRace({
    required String title,
    required int targetValue,
    required String customActivityName,
    required CustomPoseVerifierSpec verifierSpec,
  }) async {
    if (isPresentationDemo()) {
      final id =
          '$presentationDemoCreatedRacePrefix${DateTime.now().microsecondsSinceEpoch}';
      final race = PresentationDemoData.createdRace(
        id: id,
        userId: presentationUserId(),
        title: customActivityName,
        targetValue: targetValue,
        customActivityName: customActivityName,
      );
      _addPresentationRace(race);
      return race;
    }
    final race = await _repo.createCustomRace(
      title: title,
      targetValue: targetValue,
      customActivityName: customActivityName,
      verifierSpec: verifierSpec,
    );
    if (mounted) {
      state = state.copyWith(races: [race, ...state.races]);
      _racesLoadedAt = DateTime.now();
      onMutated?.call();
    }
    return race;
  }

  Future<Race> getRaceDetail(String id, {bool syncArena = false}) async {
    if (_isPresentationLocalRace(id)) {
      final cached = state.races.where((race) => race.id == id).firstOrNull;
      if (cached != null) return cached;
      final fixture = PresentationDemoData.races(
        presentationUserId(),
      ).where((race) => race.id == id).firstOrNull;
      if (fixture != null) return fixture;
      throw const ApiException(404, 'This race could not be found.');
    }
    final race = await _repo.getRaceDetail(id);
    // The detail response is the freshest view of this race (participants,
    // progress, standings) — fold it into the canonical list so Compete /
    // Arena / Move see it without their own refetch.
    _upsertRace(race, silent: !syncArena);
    return race;
  }

  Future<Race> updateRace(
    String id, {
    String? title,
    String? description,
    String? category,
    String? goalType,
    int? targetValue,
    String? unit,
    String? status,
    String? startLineAt,
    String? finishLineAt,
    String? rules,
    String? proofRequirement,
    String? proofReviewMode,
    String? visibility,
    String? aiActivityType,
    String? targetUnit,
    String? proofMode,
  }) async {
    final race = await _repo.updateRace(
      id,
      title: title,
      description: description,
      category: category,
      goalType: goalType,
      targetValue: targetValue,
      unit: unit,
      status: status,
      startLineAt: startLineAt,
      finishLineAt: finishLineAt,
      rules: rules,
      proofRequirement: proofRequirement,
      proofReviewMode: proofReviewMode,
      visibility: visibility,
      aiActivityType: aiActivityType,
      targetUnit: targetUnit,
      proofMode: proofMode,
    );
    _upsertRace(race);
    return race;
  }

  void clearRaces() {
    _racesLoadedAt = null;
    // Drop any in-flight load so the next sign-in starts a fresh request
    // instead of awaiting a future tied to the previous session (which could
    // be hung on a stalled socket and wedge the races tab until an app kill).
    _loadInFlight = null;
    for (final timer in _presentationDeletionTimers.values) {
      timer.cancel();
    }
    _presentationDeletionTimers.clear();
    // Invalidate any fetch already in flight — see [_generation] — so its
    // response cannot land after this reset and resurrect the previous
    // account's races into the new session.
    _generation++;
    if (mounted) state = const RaceState();
  }

  Future<Race> submitProof(
    String raceId, {
    String proofType = 'manual',
    String? note,
    required int value,
    String? mediaObjectKey,
  }) async {
    if (_isPresentationLocalRace(raceId)) {
      final race = _applyPresentationProof(
        raceId,
        proofType: proofType,
        note: note,
        value: value,
      );
      _upsertRace(race);
      return race;
    }
    final existing = state.races
        .where((race) => race.id == raceId)
        .firstOrNull;
    if (existing != null && raceFormatUsesAttempts(existing.format)) {
      // Attempt races reject proofs with no open attempt ("Start an attempt
      // first"). Declare one; an already-open attempt binds this submission,
      // so a 409 is success, not failure.
      try {
        await _repo.startAttempt(raceId);
      } on ApiException catch (e) {
        if (e.statusCode != 409) rethrow;
      }
    }
    final race = await _repo.submitProof(
      raceId,
      proofType: proofType,
      note: note,
      value: value,
      mediaObjectKey: mediaObjectKey,
    );
    if (mounted) {
      state = state.copyWith(
        races: state.races.map((r) => r.id == raceId ? race : r).toList(),
      );
      _racesLoadedAt = DateTime.now();
      onMutated?.call();
    }
    return race;
  }

  Future<Race> submitAiMotionProof(
    String raceId, {
    required AiMotionResult result,
    required String clientSubmissionId,
    required String metric,
  }) async {
    if (_isPresentationLocalRace(raceId)) {
      final race = _applyPresentationProof(
        raceId,
        proofType: 'ai_motion',
        value: result.detectedReps,
        aiActivityType: result.activity.backendValue,
        detectedValue: result.detectedReps,
        targetValue: result.targetReps,
        confidence: result.confidence,
        validatorVersion: result.validatorVersion,
        framesAnalyzed: result.framesAnalyzed,
        validPoseFrames: result.validPoseFrames,
        durationMs: result.durationMs,
        verificationStatus: result.verificationStatus,
        verificationSummary: result.verificationSummary,
      );
      _upsertRace(race);
      return race;
    }
    final race = await _repo.submitAiMotionProof(
      raceId,
      result: result,
      clientSubmissionId: clientSubmissionId,
      metric: metric,
    );
    if (mounted) {
      state = state.copyWith(
        races: state.races.map((r) => r.id == raceId ? race : r).toList(),
      );
      _racesLoadedAt = DateTime.now();
      onMutated?.call();
    }
    return race;
  }

  Future<Race> submitObjectCompositionProof(
    String raceId, {
    required String activityId,
    required String clientSubmissionId,
    required String metric,
    required int value,
    required int targetValue,
    required double confidence,
    required String verificationSummary,
    required String validatorVersion,
    required int framesAnalyzed,
    required int durationMs,
  }) async {
    if (_isPresentationLocalRace(raceId)) {
      final race = _applyPresentationProof(
        raceId,
        proofType: 'ai_motion',
        value: value,
        detectedValue: value,
        targetValue: targetValue,
        confidence: confidence,
        validatorVersion: validatorVersion,
        framesAnalyzed: framesAnalyzed,
        durationMs: durationMs,
        verificationStatus: 'ai_verified',
        verificationSummary: verificationSummary,
      );
      _upsertRace(race);
      return race;
    }
    final race = await _repo.submitObjectCompositionProof(
      raceId,
      activityId: activityId,
      clientSubmissionId: clientSubmissionId,
      metric: metric,
      value: value,
      targetValue: targetValue,
      confidence: confidence,
      verificationSummary: verificationSummary,
      validatorVersion: validatorVersion,
      framesAnalyzed: framesAnalyzed,
      durationMs: durationMs,
    );
    if (mounted) {
      state = state.copyWith(
        races: state.races.map((r) => r.id == raceId ? race : r).toList(),
      );
      _racesLoadedAt = DateTime.now();
      onMutated?.call();
    }
    return race;
  }

  Future<Race> submitCustomPoseProof(
    String raceId, {
    required CustomPoseRuntimeResult result,
    required String clientSubmissionId,
  }) async {
    if (_isPresentationLocalRace(raceId)) {
      final race = _applyPresentationProof(
        raceId,
        proofType: 'ai_motion',
        value: result.count,
        detectedValue: result.count,
        targetValue: result.target,
        confidence: result.confidence,
        validatorVersion: 'custom_pose_v${result.verifierVersion}',
        framesAnalyzed: result.framesAnalyzed,
        validPoseFrames: result.validFrames,
        durationMs: result.durationMs,
        verificationStatus: result.verificationStatus,
        verificationSummary:
            result.finalFailureReason ?? 'Demo proof recorded locally.',
      );
      _upsertRace(race);
      return race;
    }
    final race = await _repo.submitCustomPoseProof(
      raceId,
      result: result,
      clientSubmissionId: clientSubmissionId,
    );
    if (mounted) {
      state = state.copyWith(
        races: state.races.map((r) => r.id == raceId ? race : r).toList(),
      );
      _racesLoadedAt = DateTime.now();
      onMutated?.call();
    }
    return race;
  }

  Future<Race> archiveRace(String id) async {
    final race = await _repo.archiveRace(id);
    _upsertRace(race);
    return race;
  }

  Future<Race> cancelRace(String id) async {
    final race = await _repo.cancelRace(id);
    _upsertRace(race);
    return race;
  }

  Future<void> deleteRace(String id) async {
    if (isPresentationDemo() && isPresentationDemoCreatedRace(id)) {
      _removePresentationRace(id);
      return;
    }
    await _repo.deleteRace(id);
    if (mounted) {
      state = state.copyWith(
        races: state.races.where((race) => race.id != id).toList(),
      );
      _racesLoadedAt = DateTime.now();
      onMutated?.call();
    }
  }

  Future<void> leaveRace(String id) async {
    await _repo.leaveRace(id);
    if (mounted) {
      state = state.copyWith(
        races: state.races.where((race) => race.id != id).toList(),
      );
      _racesLoadedAt = DateTime.now();
      onMutated?.call();
    }
  }

  Future<Race> joinRace(String id) async {
    final race = await _repo.joinRace(id);
    _upsertRace(race);
    return race;
  }

  Future<List<PublicUser>> searchUsers(String query) =>
      _repo.searchUsers(query);

  Future<List<PublicUser>> getCrew() => _repo.getCrew();

  Future<PublicUser?> addCrewUser(String userId) => _repo.addCrewUser(userId);

  Future<void> removeCrewUser(String userId) => _repo.removeCrewUser(userId);

  Future<Race> addRaceParticipant(String raceId, String userId) async {
    final race = await _repo.addRaceParticipant(raceId, userId);
    _upsertRace(race);
    return race;
  }

  Future<String> createInviteCode(String id) => _repo.createInviteCode(id);

  Future<Race> joinRaceByCode(String code) async {
    final race = await _repo.joinRaceByCode(code);
    _upsertRace(race);
    return race;
  }

  /// Fold a race into the canonical cache after joining it through an invite
  /// link / QR (the invite endpoint lives outside this repository). Fires the
  /// sibling nudge so Arena / Compete update immediately, per the freshness
  /// contract (docs/agents/18).
  Future<Race> refreshJoinedRace(String raceId) async {
    final race = await _repo.getRaceDetail(raceId);
    _upsertRace(race); // non-silent: bump loadedAt + nudge Arena
    return race;
  }

  /// Open a server-timestamped attempt (best-attempt / timed races). The
  /// returned `serverTime`/`deadlineAt` are authoritative for the attempt
  /// window — the next verified proof binds to this attempt automatically.
  Future<RaceAttemptResult> startAttempt(
    String raceId, {
    String? clientAttemptId,
  }) => _repo.startAttempt(raceId, clientAttemptId: clientAttemptId);

  /// Clone a finished race's settings + roster into a fresh race — the
  /// one-tap "race again" loop.
  Future<Race> rematchRace(String raceId) async {
    final race = await _repo.rematchRace(raceId);
    _upsertRace(race);
    return race;
  }

  /// Compact live-state poll — no proof history, cheap when `version` is
  /// unchanged.
  Future<RaceLiveState> getRaceLiveState(String raceId, {int? version}) =>
      _repo.getRaceLiveState(raceId, version: version);

  Future<Race> reviewProof(
    String raceId,
    String proofId, {
    required String status,
    String? summary,
  }) async {
    final race = await _repo.reviewProof(
      raceId,
      proofId,
      status: status,
      summary: summary,
    );
    _upsertRace(race);
    return race;
  }

  /// [silent] skips the [onMutated] sibling-cache nudge — used when the update
  /// is a read (getRaceDetail), not a user write.
  void _upsertRace(Race race, {bool silent = false}) {
    if (!mounted) return;
    final exists = state.races.any((item) => item.id == race.id);
    state = state.copyWith(
      races: exists
          ? state.races.map((item) => item.id == race.id ? race : item).toList()
          : [race, ...state.races],
    );
    if (!silent) {
      _racesLoadedAt = DateTime.now();
      onMutated?.call();
    }
  }

  bool _isPresentationLocalRace(String id) =>
      isPresentationDemo() &&
      (isPresentationDemoRace(id) || isPresentationDemoCreatedRace(id));

  Race _applyPresentationProof(
    String raceId, {
    required String proofType,
    required int value,
    String? note,
    String? aiActivityType,
    int? detectedValue,
    int? targetValue,
    double? confidence,
    String? validatorVersion,
    int? framesAnalyzed,
    int? validPoseFrames,
    int? durationMs,
    String verificationStatus = 'accepted',
    String? verificationSummary,
  }) {
    final existing = state.races.where((race) => race.id == raceId).firstOrNull;
    if (existing == null) {
      throw const ApiException(404, 'This race could not be found.');
    }

    final userId = presentationUserId();
    final current = existing.participantFor(userId);
    if (current == null) {
      throw const ApiException(403, 'You are not on this race.');
    }

    final safeValue = math.max(0, value);
    final previousScore = current.progressValue;
    final newScore = previousScore + safeValue;
    final target = targetValue ?? existing.targetValue;
    final newPercent = target == null || target <= 0
        ? current.progressPercent
        : math.min(100, ((newScore / target) * 100).round());
    final now = DateTime.now().toUtc().toIso8601String();

    final updatedParticipants = [
      for (final participant in existing.participants)
        participant.userId == userId
            ? RaceParticipant(
                id: participant.id,
                userId: participant.userId,
                displayName: participant.displayName,
                progressValue: newScore,
                progressPercent: newPercent,
                rank: participant.rank,
                joinedAt: participant.joinedAt,
                profilePhotoUrl: participant.profilePhotoUrl,
              )
            : participant,
    ];
    final rankedParticipants = [...updatedParticipants]
      ..sort((a, b) => b.progressValue.compareTo(a.progressValue));
    final newRank =
        rankedParticipants.indexWhere(
          (participant) => participant.userId == userId,
        ) +
        1;
    final participantsWithRanks = [
      for (final participant in updatedParticipants)
        RaceParticipant(
          id: participant.id,
          userId: participant.userId,
          displayName: participant.displayName,
          progressValue: participant.progressValue,
          progressPercent: participant.progressPercent,
          rank:
              rankedParticipants.indexWhere(
                (ranked) => ranked.userId == participant.userId,
              ) +
              1,
          joinedAt: participant.joinedAt,
          profilePhotoUrl: participant.profilePhotoUrl,
        ),
    ];
    final proof = RaceProof(
      id: 'presentation-demo-proof-${DateTime.now().microsecondsSinceEpoch}',
      userId: userId,
      displayName: current.displayName,
      proofType: proofType,
      aiActivityType: aiActivityType ?? existing.effectiveAiActivityType,
      note: note,
      value: safeValue,
      detectedValue: detectedValue ?? safeValue,
      targetValue: target,
      confidence: confidence,
      validatorVersion: validatorVersion,
      framesAnalyzed: framesAnalyzed,
      validPoseFrames: validPoseFrames,
      durationMs: durationMs,
      verificationStatus: verificationStatus,
      verificationSummary:
          verificationSummary ?? 'Demo proof recorded locally.',
      createdAt: now,
      profilePhotoUrl: current.profilePhotoUrl,
      rankBefore: current.rank,
      rankAfter: newRank,
      peoplePassed: math.max(0, (current.rank ?? newRank) - newRank),
    );
    final completed = target != null && newScore >= target;
    return Race(
      id: existing.id,
      creatorId: existing.creatorId,
      title: existing.title,
      description: existing.description,
      category: existing.category,
      goalType: existing.goalType,
      targetValue: existing.targetValue,
      unit: existing.unit,
      aiActivityType: existing.aiActivityType,
      targetUnit: existing.targetUnit,
      proofMode: existing.proofMode,
      activityId: existing.activityId,
      metric: existing.metric,
      format: existing.format,
      scoringRule: existing.scoringRule,
      attemptDurationSeconds: existing.attemptDurationSeconds,
      attemptLimit: existing.attemptLimit,
      verificationMethod: existing.verificationMethod,
      verifierType: existing.verifierType,
      verifierVersion: existing.verifierVersion,
      customVerifierSpec: existing.customVerifierSpec,
      customActivityName: existing.customActivityName,
      verifierInvalidReason: existing.verifierInvalidReason,
      timezone: existing.timezone,
      recurrence: existing.recurrence,
      status: existing.status,
      storedStatus: existing.storedStatus,
      winnerUserId: completed ? userId : existing.winnerUserId,
      completedAt: completed ? now : existing.completedAt,
      startLineAt: existing.startLineAt,
      finishLineAt: existing.finishLineAt,
      rules: existing.rules,
      proofRequirement: existing.proofRequirement,
      proofReviewMode: existing.proofReviewMode,
      visibility: existing.visibility,
      inviteCode: existing.inviteCode,
      createdAt: existing.createdAt,
      updatedAt: now,
      participants: participantsWithRanks,
      recentProofs: [proof, ...existing.recentProofs].take(8).toList(),
      finalStandings: existing.finalStandings,
      submissionResult: RaceSubmissionResult(
        verifiedValue: safeValue,
        previousScore: previousScore,
        newScore: newScore,
        previousRank: current.rank,
        newRank: newRank,
        peoplePassed: math.max(0, (current.rank ?? newRank) - newRank),
        raceCompleted: completed,
        winnerUserId: completed ? userId : existing.winnerUserId,
      ),
    );
  }

  void _addPresentationRace(Race race) {
    if (!mounted) return;
    state = state.copyWith(races: [race, ...state.races]);
    _racesLoadedAt = DateTime.now();
    onMutated?.call();
    _presentationDeletionTimers[race.id] = Timer(
      const Duration(minutes: 10),
      () => _removePresentationRace(race.id),
    );
  }

  void _removePresentationRace(String id) {
    _presentationDeletionTimers.remove(id)?.cancel();
    if (!mounted) return;
    state = state.copyWith(
      races: state.races.where((race) => race.id != id).toList(),
    );
    _racesLoadedAt = DateTime.now();
    onMutated?.call();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final _raceApiProvider = Provider<RaceApi>((_) => RaceApi());

final raceRepositoryProvider = Provider<RaceRepository>(
  (ref) => RaceRepository(
    ref.watch(_raceApiProvider),
    ref.watch(secureTokenStoreProvider),
    ref.watch(authApiProvider),
  ),
);

final raceControllerProvider = StateNotifierProvider<RaceController, RaceState>(
  (ref) {
    final controller = RaceController(
      ref.watch(raceRepositoryProvider),
      isPresentationDemo: () =>
          isPresentationDemoUser(ref.read(authControllerProvider).user),
      presentationUserId: () => ref.read(authControllerProvider).user?.id ?? '',
      // Any race write immediately revalidates the Arena snapshot (it is
      // derived from races) so a race created in the composer shows up in the
      // Arena without the user navigating there and back.
      onMutated: () => ref.read(arenaControllerProvider.notifier).markStale(),
    );
    if (ref.read(authControllerProvider).status == AuthStatus.authenticated) {
      controller.loadRaces(force: false);
    }
    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (next.status == AuthStatus.unauthenticated) {
        controller.clearRaces();
      } else if (next.status == AuthStatus.authenticated &&
          prev?.status != AuthStatus.authenticated) {
        controller.loadRaces(force: false);
      }
    });
    return controller;
  },
);
