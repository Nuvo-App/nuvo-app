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
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../arena/presentation/arena_controller.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../ai/custom_pose/custom_pose_sequence_runtime.dart';
import '../ai/custom_pose/custom_pose_verifier_spec.dart';
import '../data/ai_motion_models.dart';
import '../data/motion_analysis_contract.dart';
import '../data/race_api.dart';
import '../data/race_models.dart';
import '../data/race_repository.dart';

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
  RaceController(this._repo, {this.onMutated}) : super(const RaceState());

  final RaceRepository _repo;

  /// Called after any local write so sibling caches (Arena) can revalidate.
  /// See docs/agents/18-data-freshness-contract.md.
  final void Function()? onMutated;

  /// How old cached data may be before [revalidate] refetches it in the
  /// background. Short — this fires on screen focus and app resume.
  static const _staleWindow = Duration(seconds: 45);

  Future<MotionAnalysisResult> analyzeMotion(MotionAnalysisRequest request) =>
      _repo.analyzeMotion(request);

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
    if (mounted) {
      final haveData = state.hasData;
      state = RaceState(
        races: state.races,
        loading: !haveData,
        refreshing: haveData,
      );
    }
    try {
      final races = await _repo.getRaces();
      _racesLoadedAt = DateTime.now();
      if (mounted) state = RaceState(races: races);
    } on ApiException catch (e) {
      // Keep cached races visible on a failed background refresh.
      if (mounted) {
        state = state.copyWith(
          loading: false,
          refreshing: false,
          error: state.hasData ? null : e.message,
        );
      }
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          loading: false,
          refreshing: false,
          error: state.hasData ? null : 'Failed to load races.',
        );
      }
    }
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
  }) async {
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

  Future<Race> getRaceDetail(String id) async {
    final race = await _repo.getRaceDetail(id);
    // The detail response is the freshest view of this race (participants,
    // progress, standings) — fold it into the canonical list so Compete /
    // Arena / Move see it without their own refetch.
    _upsertRace(race, silent: true);
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
    if (mounted) state = const RaceState();
  }

  Future<Race> submitProof(
    String raceId, {
    String proofType = 'manual',
    String? note,
    required int value,
  }) async {
    final race = await _repo.submitProof(
      raceId,
      proofType: proofType,
      note: note,
      value: value,
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

  Future<Race> submitCustomPoseProof(
    String raceId, {
    required CustomPoseRuntimeResult result,
    required String clientSubmissionId,
  }) async {
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
