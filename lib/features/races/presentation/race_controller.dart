import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/ai_motion_models.dart';
import '../data/race_api.dart';
import '../data/race_models.dart';
import '../data/race_repository.dart';

class RaceState {
  const RaceState({this.races = const [], this.loading = false, this.error});

  final List<Race> races;
  final bool loading;
  final String? error;

  RaceState copyWith({List<Race>? races, bool? loading, String? error}) =>
      RaceState(
        races: races ?? this.races,
        loading: loading ?? this.loading,
        error: error,
      );
}

class RaceController extends StateNotifier<RaceState> {
  RaceController(this._repo) : super(const RaceState()) {
    loadRaces();
  }

  final RaceRepository _repo;

  Future<void> loadRaces() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final races = await _repo.getRaces();
      if (mounted) state = state.copyWith(races: races, loading: false);
    } on ApiException catch (e) {
      if (mounted) state = state.copyWith(loading: false, error: e.message);
    } catch (_) {
      if (mounted) {
        state = state.copyWith(loading: false, error: 'Failed to load races.');
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
      targetUnit: targetUnit,
      proofMode: proofMode,
    );
    if (mounted) {
      state = state.copyWith(races: [race, ...state.races]);
    }
    return race;
  }

  Future<Race> getRaceDetail(String id) => _repo.getRaceDetail(id);

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
    }
    return race;
  }

  Future<Race> submitAiMotionProof(
    String raceId, {
    required AiMotionResult result,
  }) async {
    final race = await _repo.submitAiMotionProof(raceId, result: result);
    if (mounted) {
      state = state.copyWith(
        races: state.races.map((r) => r.id == raceId ? race : r).toList(),
      );
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
    }
  }

  Future<void> leaveRace(String id) async {
    await _repo.leaveRace(id);
    if (mounted) {
      state = state.copyWith(
        races: state.races.where((race) => race.id != id).toList(),
      );
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

  void _upsertRace(Race race) {
    if (!mounted) return;
    final exists = state.races.any((item) => item.id == race.id);
    state = state.copyWith(
      races: exists
          ? state.races.map((item) => item.id == race.id ? race : item).toList()
          : [race, ...state.races],
    );
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
    final controller = RaceController(ref.watch(raceRepositoryProvider));
    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (next.status == AuthStatus.unauthenticated) {
        controller.clearRaces();
      } else if (next.status == AuthStatus.authenticated &&
          prev?.status != AuthStatus.authenticated) {
        controller.loadRaces();
      }
    });
    return controller;
  },
);
