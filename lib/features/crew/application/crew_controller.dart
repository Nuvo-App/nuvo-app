// The canonical crew domain — follows docs/agents/18-data-freshness-contract.md.
// Screens read `crewControllerProvider` and never call CrewApi directly.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart' show PublicUser;
import '../../races/presentation/race_controller.dart';
import '../data/crew_api.dart';
import '../data/crew_repository.dart';

class CrewState {
  const CrewState({
    this.members = const [],
    this.requests = const [],
    this.loading = false,
    this.refreshing = false,
    this.error,
  });

  final List<PublicUser> members;
  final List<PublicUser> requests;
  final bool loading;
  final bool refreshing;
  final String? error;

  bool get hasData => members.isNotEmpty || requests.isNotEmpty;
  int get requestCount => requests.length;

  CrewState copyWith({
    List<PublicUser>? members,
    List<PublicUser>? requests,
    bool? loading,
    bool? refreshing,
    String? error,
  }) =>
      CrewState(
        members: members ?? this.members,
        requests: requests ?? this.requests,
        loading: loading ?? this.loading,
        refreshing: refreshing ?? this.refreshing,
        error: error,
      );
}

class CrewController extends StateNotifier<CrewState> {
  CrewController(this._repo, {this.onMutated, this.onSessionExpired})
      : super(const CrewState());

  final CrewRepository _repo;

  /// A crew change can reveal a co-racer's identity — nudge the race cache.
  final VoidCallback? onMutated;
  final VoidCallback? onSessionExpired;

  static const _cacheLifetime = Duration(minutes: 5);
  static const _staleWindow = Duration(seconds: 45);
  Future<void>? _loadInFlight;
  DateTime? _loadedAt;

  void revalidate() {
    final at = _loadedAt;
    if (state.hasData && at != null && DateTime.now().difference(at) < _staleWindow) {
      return;
    }
    load(force: true);
  }

  void markStale() {
    _loadedAt = null;
    if (mounted) load(force: true);
  }

  Future<void> load({bool force = true}) {
    final at = _loadedAt;
    if (!force && at != null && DateTime.now().difference(at) < _cacheLifetime) {
      return Future.value();
    }
    final inFlight = _loadInFlight;
    if (inFlight != null) return inFlight;
    final request = _fetch();
    _loadInFlight = request;
    request.whenComplete(() {
      if (identical(_loadInFlight, request)) _loadInFlight = null;
    });
    return request;
  }

  Future<void> _fetch() async {
    if (mounted) {
      state = state.copyWith(loading: !state.hasData, refreshing: state.hasData, error: null);
    }
    try {
      final results = await Future.wait([_repo.getCrew(), _repo.getRequests()]);
      _loadedAt = DateTime.now();
      if (mounted) {
        state = CrewState(
          members: results[0],
          requests: results[1],
        );
      }
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        if (mounted) state = state.copyWith(loading: false, refreshing: false);
        onSessionExpired?.call();
        return;
      }
      if (mounted) {
        state = state.copyWith(
          loading: false,
          refreshing: false,
          error: state.hasData ? null : "Couldn't load your crew.",
        );
      }
    } catch (e, st) {
      debugPrint('[CrewController] $e\n$st');
      if (mounted) {
        state = state.copyWith(
          loading: false,
          refreshing: false,
          error: state.hasData ? null : "Couldn't load your crew.",
        );
      }
    }
  }

  /// Returns the outcome so the caller can tell the user "request sent".
  Future<ConnectOutcome> add(PublicUser user) async {
    final outcome = await _repo.add(user.id);
    if (outcome == ConnectOutcome.active && mounted) {
      state = state.copyWith(members: [user, ...state.members.where((m) => m.id != user.id)]);
      _loadedAt = DateTime.now();
      onMutated?.call();
    }
    return outcome;
  }

  Future<void> acceptRequest(PublicUser user) async {
    await _repo.acceptRequest(user.id);
    if (mounted) {
      state = state.copyWith(
        members: [user, ...state.members.where((m) => m.id != user.id)],
        requests: state.requests.where((r) => r.id != user.id).toList(),
      );
      _loadedAt = DateTime.now();
      onMutated?.call();
    }
  }

  Future<void> declineRequest(PublicUser user) async {
    await _repo.declineRequest(user.id);
    if (mounted) {
      state = state.copyWith(
        requests: state.requests.where((r) => r.id != user.id).toList(),
      );
    }
  }

  Future<void> remove(String userId) async {
    await _repo.remove(userId);
    if (mounted) {
      state = state.copyWith(
        members: state.members.where((m) => m.id != userId).toList(),
      );
      _loadedAt = DateTime.now();
      onMutated?.call();
    }
  }

  void clear() {
    _loadedAt = null;
    _loadInFlight = null;
    if (mounted) state = const CrewState();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final _crewApiProvider = Provider<CrewApi>((_) => CrewApi());

final crewRepositoryProvider = Provider<CrewRepository>((ref) {
  return CrewRepository(
    ref.watch(_crewApiProvider),
    ref.watch(secureTokenStoreProvider),
    ref.watch(authApiProvider),
  );
});

final crewControllerProvider =
    StateNotifierProvider<CrewController, CrewState>((ref) {
  final controller = CrewController(
    ref.watch(crewRepositoryProvider),
    onMutated: () {
      // A new connection can change what identities the viewer sees in a
      // shared race — pull fresh participants.
      ref.read(raceControllerProvider.notifier).loadRaces(force: true);
    },
    onSessionExpired: () =>
        ref.read(authControllerProvider.notifier).sessionExpired(),
  );
  if (ref.read(authControllerProvider).status == AuthStatus.authenticated) {
    controller.load(force: false);
  }
  ref.listen<AuthState>(authControllerProvider, (prev, next) {
    if (next.status == AuthStatus.unauthenticated) {
      controller.clear();
    } else if (next.status == AuthStatus.authenticated &&
        prev?.status != AuthStatus.authenticated) {
      controller.load(force: false);
    }
  });
  return controller;
});
