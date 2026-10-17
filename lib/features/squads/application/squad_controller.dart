// Crews (API: squads) state. One StateNotifier owns the list and a per-id
// detail map; screens only read it and never call SquadApi. See
// docs/agents/18-data-freshness-contract.md and
// docs/agents/22-screen-roles-and-data-plan.md (5.1-5.5).
//
// - 5-minute cache, 45 s revalidate() window, single-flight per resource.
// - Disk snapshot (domains 'squads' and 'squad_<id>', 7 days) is hydrated
//   asynchronously before the first request, never blocking the first frame.
// - Conditional GET: the stored ETag is sent; a 304 keeps state.
// - Mutations patch/refetch, null the etag and rewrite/delete snapshots.
// - A generation guard drops results that finish after clear().
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cache_store.dart';
import '../../auth/data/auth_api.dart' show ApiException;
import '../../auth/presentation/auth_controller.dart';
import '../data/squad_api.dart';

class SquadState {
  const SquadState({
    this.groups,
    this.details = const {},
    this.loading = false,
    this.refreshing = false,
    this.error,
    this.detailLoading = const {},
    this.detailRefreshing = const {},
    this.detailErrors = const {},
  });

  /// My crews. Null until the first load or disk hydration resolves, so a
  /// screen can tell "not loaded" from "loaded, empty".
  final List<CrewGroup>? groups;
  final Map<String, CrewGroupDetail> details;

  final bool loading;
  final bool refreshing;
  final String? error;

  final Set<String> detailLoading;
  final Set<String> detailRefreshing;
  final Map<String, String> detailErrors;

  bool get hasData => groups != null;

  SquadState copyWith({
    List<CrewGroup>? groups,
    Map<String, CrewGroupDetail>? details,
    bool? loading,
    bool? refreshing,
    String? error,
    bool clearError = false,
    Set<String>? detailLoading,
    Set<String>? detailRefreshing,
    Map<String, String>? detailErrors,
  }) => SquadState(
    groups: groups ?? this.groups,
    details: details ?? this.details,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    error: clearError ? null : (error ?? this.error),
    detailLoading: detailLoading ?? this.detailLoading,
    detailRefreshing: detailRefreshing ?? this.detailRefreshing,
    detailErrors: detailErrors ?? this.detailErrors,
  );
}

const _listDomain = 'squads';
String _detailDomain(String id) => 'squad_$id';

String _messageFor(Object e) =>
    e is ApiException ? e.message : 'Something went wrong. Try again.';

class SquadController extends StateNotifier<SquadState> {
  SquadController(
    this._repo,
    this._store, {
    required this.accountId,
  }) : super(const SquadState());

  final SquadRepository _repo;
  final CacheStore _store;

  /// Current account id, or null when signed out.
  final String? Function() accountId;

  static const _cacheLifetime = Duration(minutes: 5);
  static const _staleWindow = Duration(seconds: 45);
  static const _snapshotMaxAge = Duration(days: 7);

  int _generation = 0;
  // Bumped by mutations so a read that started before the write is dropped.
  int _listRev = 0;
  final Map<String, int> _detailRev = {};
  String? _bound;

  Future<void>? _listInFlight;
  DateTime? _listLoadedAt;
  String? _listEtag;
  bool _listHydrated = false;

  final Map<String, Future<void>> _detailInFlight = {};
  final Map<String, DateTime> _detailLoadedAt = {};
  final Map<String, String?> _detailEtag = {};
  final Set<String> _detailHydrated = {};

  // ── account binding ──────────────────────────────────────────────────────

  /// Resets in-memory state if the account changed under us.
  String? _account() {
    final id = accountId();
    if (_bound != null && id != _bound) {
      _resetMemory();
    }
    _bound = id;
    return id != null && isValidCacheId(id) ? id : null;
  }

  void _resetMemory() {
    _generation++;
    _listInFlight = null;
    _listLoadedAt = null;
    _listEtag = null;
    _listHydrated = false;
    _detailInFlight.clear();
    _detailLoadedAt.clear();
    _detailEtag.clear();
    _detailHydrated.clear();
    _detailRev.clear();
    if (mounted) state = const SquadState();
  }

  /// Sign-out / account switch: drop memory and wipe the disk snapshots.
  Future<void> clear({String? accountIdHint}) async {
    final id = _bound ?? accountIdHint;
    _resetMemory();
    _bound = null;
    if (id != null && isValidCacheId(id)) {
      await _store.clearAccount(id);
    }
  }

  // ── reads ────────────────────────────────────────────────────────────────

  /// Loads the crew list. force:false respects the 5-minute cache.
  Future<void> load({bool force = false}) {
    final at = _listLoadedAt;
    if (!force &&
        state.hasData &&
        at != null &&
        DateTime.now().difference(at) < _cacheLifetime) {
      return Future.value();
    }
    final running = _listInFlight;
    if (running != null) return running;
    final request = _fetchList();
    _listInFlight = request;
    request.whenComplete(() {
      if (identical(_listInFlight, request)) _listInFlight = null;
    });
    return request;
  }

  /// Pull-to-refresh: the only forced path.
  Future<void> refresh() => load(force: true);

  /// Focus / resume: no-op while fresh, otherwise a background refresh.
  void revalidate() {
    final at = _listLoadedAt;
    if (state.hasData &&
        at != null &&
        DateTime.now().difference(at) < _staleWindow) {
      return;
    }
    unawaited(load(force: true));
  }

  Future<void> loadDetail(String id, {bool force = false}) {
    final at = _detailLoadedAt[id];
    if (!force &&
        state.details.containsKey(id) &&
        at != null &&
        DateTime.now().difference(at) < _cacheLifetime) {
      return Future.value();
    }
    final running = _detailInFlight[id];
    if (running != null) return running;
    final request = _fetchDetail(id);
    _detailInFlight[id] = request;
    request.whenComplete(() {
      if (identical(_detailInFlight[id], request)) _detailInFlight.remove(id);
    });
    return request;
  }

  Future<void> refreshDetail(String id) => loadDetail(id, force: true);

  void revalidateDetail(String id) {
    final at = _detailLoadedAt[id];
    if (state.details.containsKey(id) &&
        at != null &&
        DateTime.now().difference(at) < _staleWindow) {
      return;
    }
    unawaited(loadDetail(id, force: true));
  }

  Future<void> _hydrateList(String account, int generation) async {
    if (_listHydrated) return;
    _listHydrated = true;
    try {
      final entry = await _store.read(
        account,
        _listDomain,
        maxAge: _snapshotMaxAge,
      );
      if (entry == null || entry.data == null) return;
      if (!mounted || generation != _generation || state.hasData) return;
      state = state.copyWith(groups: parseCrewGroupList(entry.data));
      _listEtag = entry.etag;
    } catch (_) {
      // A bad snapshot is just "no cache".
    }
  }

  Future<void> _hydrateDetail(String account, String id, int generation) async {
    if (_detailHydrated.contains(id) || !isValidCacheId(id)) return;
    _detailHydrated.add(id);
    try {
      final entry = await _store.read(
        account,
        _detailDomain(id),
        maxAge: _snapshotMaxAge,
      );
      final raw = entry?.data;
      if (entry == null || raw is! Map<String, dynamic>) return;
      if (!mounted ||
          generation != _generation ||
          state.details.containsKey(id)) {
        return;
      }
      state = state.copyWith(
        details: {...state.details, id: CrewGroupDetail.fromJson(raw)},
      );
      _detailEtag[id] = entry.etag;
    } catch (_) {}
  }

  Future<void> _fetchList() async {
    final account = _account();
    final generation = _generation;
    final rev = _listRev;
    if (!mounted) return;
    if (account != null) await _hydrateList(account, generation);
    if (!mounted || generation != _generation) return;
    state = state.copyWith(
      loading: !state.hasData,
      refreshing: state.hasData,
      clearError: true,
    );
    try {
      final res = await _repo.list(etag: _listEtag);
      if (!mounted || generation != _generation || rev != _listRev) return;
      if (res.notModified) {
        _listLoadedAt = DateTime.now();
        state = state.copyWith(
          groups: state.groups ?? const <CrewGroup>[],
          loading: false,
          refreshing: false,
        );
        return;
      }
      _listEtag = res.etag;
      _listLoadedAt = DateTime.now();
      state = state.copyWith(
        groups: res.data,
        loading: false,
        refreshing: false,
        clearError: true,
      );
      if (account != null) {
        unawaited(_store.write(account, _listDomain, res.raw, etag: res.etag));
      }
    } catch (e) {
      if (!mounted || generation != _generation || rev != _listRev) return;
      // A failed background refresh keeps data; errors only show with none.
      state = state.copyWith(
        loading: false,
        refreshing: false,
        error: state.hasData ? null : _messageFor(e),
        clearError: state.hasData,
      );
    }
  }

  Future<void> _fetchDetail(String id) async {
    final account = _account();
    final generation = _generation;
    final rev = _detailRev[id] ?? 0;
    if (!mounted) return;
    if (account != null) await _hydrateDetail(account, id, generation);
    if (!mounted || generation != _generation) return;
    final has = state.details.containsKey(id);
    state = state.copyWith(
      detailLoading: has ? null : {...state.detailLoading, id},
      detailRefreshing: has ? {...state.detailRefreshing, id} : null,
      detailErrors: {...state.detailErrors}..remove(id),
    );
    SquadState settle() => state.copyWith(
      detailLoading: {...state.detailLoading}..remove(id),
      detailRefreshing: {...state.detailRefreshing}..remove(id),
    );
    try {
      final res = await _repo.detail(id, etag: _detailEtag[id]);
      if (!mounted || generation != _generation || rev != (_detailRev[id] ?? 0)) {
        return;
      }
      _detailLoadedAt[id] = DateTime.now();
      if (res.notModified) {
        state = settle();
        return;
      }
      _detailEtag[id] = res.etag;
      state = settle().copyWith(details: {...state.details, id: res.data!});
      if (account != null && isValidCacheId(id)) {
        unawaited(
          _store.write(account, _detailDomain(id), res.raw, etag: res.etag),
        );
      }
    } catch (e) {
      if (!mounted || generation != _generation || rev != (_detailRev[id] ?? 0)) {
        return;
      }
      final kept = state.details.containsKey(id);
      state = settle().copyWith(
        detailErrors: kept
            ? null
            : {...state.detailErrors, id: _messageFor(e)},
      );
    }
  }

  // ── mutations ────────────────────────────────────────────────────────────

  /// Creates a crew; it is prepended to the list immediately.
  Future<CrewGroup> create(String name) async {
    final group = await _repo.create(name);
    final account = _account();
    _invalidateList();
    final current = state.groups;
    if (current != null) {
      final next = [group, ...current];
      if (mounted) state = state.copyWith(groups: next);
      if (account != null) {
        unawaited(_store.write(account, _listDomain, _listJson(next)));
      }
    }
    unawaited(load(force: true));
    return group;
  }

  /// Joins a crew by code, then refetches the list. Joining pulls me into the
  /// crew's running races, so my races are reloaded too.
  Future<void> join(String code) async {
    await _repo.join(code);
    _invalidateList();
    for (final id in state.details.keys) {
      _invalidateDetail(id);
    }
    await load(force: true);
  }

  /// Links one of my races to the crew, then refreshes that crew and the list.
  Future<int> addRace(String id, String raceId) async {
    final added = await _repo.addRace(id, raceId);
    _invalidateDetail(id);
    _invalidateList();
    await loadDetail(id, force: true);
    unawaited(load(force: true));
    return added;
  }

  /// Owner only: make a member an admin, or take it back.
  Future<void> setRole(String id, String userId, String role) async {
    await _repo.setRole(id, userId, role);
    _invalidateDetail(id);
    await loadDetail(id, force: true);
  }

  /// Owner / admin: remove someone from the crew.
  Future<void> removeMember(String id, String userId) async {
    await _repo.removeMember(id, userId);
    _invalidateDetail(id);
    _invalidateList();
    await loadDetail(id, force: true);
    unawaited(load(force: true));
  }

  /// Owner / admin: stop a race counting for the crew.
  Future<void> removeRace(String id, String raceId) async {
    await _repo.removeRace(id, raceId);
    _invalidateDetail(id);
    _invalidateList();
    await loadDetail(id, force: true);
    unawaited(load(force: true));
  }

  Future<void> leave(String id) async {
    await _repo.leave(id);
    final account = _account();
    _invalidateList();
    _invalidateDetail(id);
    _detailLoadedAt.remove(id);
    final current = state.groups;
    final next = current == null
        ? null
        : [
            for (final g in current)
              if (g.id != id) g,
          ];
    if (mounted) {
      state = state.copyWith(
        groups: next,
        details: {...state.details}..remove(id),
      );
    }
    if (account != null) {
      if (next != null) {
        unawaited(_store.write(account, _listDomain, _listJson(next)));
      }
      if (isValidCacheId(id)) {
        unawaited(_store.write(account, _detailDomain(id), null));
      }
    }
  }

  void _invalidateList() {
    _listRev++;
    _listEtag = null;
    _listInFlight = null;
  }

  void _invalidateDetail(String id) {
    _detailRev[id] = (_detailRev[id] ?? 0) + 1;
    _detailEtag[id] = null;
    _detailInFlight.remove(id);
  }

  Map<String, dynamic> _listJson(List<CrewGroup> groups) => {
    'squads': [
      for (final g in groups)
        {
          'id': g.id,
          'name': g.name,
          'joinCode': g.joinCode,
          'isOwner': g.isOwner,
          'memberCount': g.memberCount,
          'raceCount': g.raceCount,
        },
    ],
  };
}

final squadControllerProvider =
    StateNotifierProvider<SquadController, SquadState>((ref) {
      final controller = SquadController(
        ref.watch(squadRepositoryProvider),
        ref.watch(cacheStoreProvider),
        accountId: () => ref.read(authControllerProvider).user?.id,
      );
      ref.listen<AuthState>(authControllerProvider, (prev, next) {
        final was = prev?.user?.id;
        final now = next.user?.id;
        if (next.status == AuthStatus.unauthenticated ||
            (was != null && was != now)) {
          controller.clear(accountIdHint: was);
        }
      });
      return controller;
    });
