// Canonical relationships shared by Crew, search, profiles and invite entry.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/demo/presentation_demo.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../notifications/application/notification_controller.dart';
import '../../races/data/race_models.dart' show PublicUser;
import '../../races/presentation/race_controller.dart';
import '../data/crew_api.dart';
import '../data/crew_repository.dart';

class CrewState {
  const CrewState({
    this.members = const [],
    this.requests = const [],
    this.outgoing = const [],
    this.relationships = const {},
    this.pendingUserIds = const {},
    this.loading = false,
    this.refreshing = false,
    this.error,
  });

  final List<PublicUser> members;
  final List<PublicUser> requests;

  /// Pending requests I sent — the "waiting on them" side of requests.
  final List<PublicUser> outgoing;
  final Map<String, CrewConnectionStatus> relationships;
  final Set<String> pendingUserIds;
  final bool loading;
  final bool refreshing;
  final String? error;

  bool get hasData =>
      members.isNotEmpty || requests.isNotEmpty || outgoing.isNotEmpty;
  int get requestCount => requests.length;

  CrewConnectionStatus relationshipFor(
    String userId, {
    CrewConnectionStatus fallback = CrewConnectionStatus.none,
  }) {
    if (members.any((user) => user.id == userId)) {
      return CrewConnectionStatus.connected;
    }
    if (requests.any((user) => user.id == userId)) {
      return CrewConnectionStatus.pendingIncoming;
    }
    if (outgoing.any((user) => user.id == userId)) {
      return CrewConnectionStatus.pendingOutgoing;
    }
    return relationships[userId] ?? fallback;
  }

  CrewState copyWith({
    List<PublicUser>? members,
    List<PublicUser>? requests,
    List<PublicUser>? outgoing,
    Map<String, CrewConnectionStatus>? relationships,
    Set<String>? pendingUserIds,
    bool? loading,
    bool? refreshing,
    String? error,
  }) => CrewState(
    members: members ?? this.members,
    requests: requests ?? this.requests,
    outgoing: outgoing ?? this.outgoing,
    relationships: relationships ?? this.relationships,
    pendingUserIds: pendingUserIds ?? this.pendingUserIds,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    error: error,
  );
}

class CrewController extends StateNotifier<CrewState> {
  CrewController(
    this._repo, {
    this.onMutated,
    this.onRequestResolved,
    this.onSessionExpired,
    this.isPresentationDemo = _neverPresentationDemo,
  }) : super(const CrewState());

  final CrewRepository _repo;
  final VoidCallback? onMutated;
  final ValueChanged<String>? onRequestResolved;
  final VoidCallback? onSessionExpired;
  final bool Function() isPresentationDemo;
  static bool _neverPresentationDemo() => false;

  static const _cacheLifetime = Duration(minutes: 5);
  static const _staleWindow = Duration(seconds: 45);
  Future<void>? _loadInFlight;
  DateTime? _loadedAt;
  int _generation = 0;
  int _revision = 0;
  final Map<String, ({String action, Future<dynamic> future})> _mutations = {};

  void revalidate() {
    final at = _loadedAt;
    if (at != null && DateTime.now().difference(at) < _staleWindow) return;
    load(force: true);
  }

  void markStale() {
    _loadedAt = null;
    _invalidateFetch();
    if (mounted) load(force: true);
  }

  Future<void> load({bool force = true}) {
    final at = _loadedAt;
    if (!force && at != null && DateTime.now().difference(at) < _cacheLifetime) {
      return Future.value();
    }
    if (_loadInFlight case final request?) return request;
    final request = _fetch();
    _loadInFlight = request;
    request.whenComplete(() {
      if (identical(_loadInFlight, request)) _loadInFlight = null;
    });
    return request;
  }

  Future<void> _fetch() async {
    final generation = _generation;
    final revision = _revision;
    if (!mounted) return;
    state = state.copyWith(loading: !state.hasData, refreshing: state.hasData);
    try {
      final demo = isPresentationDemo();
      final results = demo
          ? <Object>[
              PresentationDemoData.crewMembers(),
              PresentationDemoData.crewRequestPage(),
            ]
          : await Future.wait<Object>([_repo.getCrew(), _repo.getRequestPage()]);
      if (!mounted || generation != _generation || revision != _revision) return;
      final members = results[0] as List<PublicUser>;
      final page = results[1] as CrewRequestPage;
      final ids = members.map((user) => user.id).toSet();
      final requests = page.incoming.where((user) => !ids.contains(user.id)).toList();
      final outgoing = page.outgoing.where((user) => !ids.contains(user.id)).toList();
      _loadedAt = DateTime.now();
      state = CrewState(
        members: members,
        requests: requests,
        outgoing: outgoing,
        pendingUserIds: state.pendingUserIds,
        relationships: {
          for (final id in state.relationships.keys) id: CrewConnectionStatus.none,
          for (final user in outgoing) user.id: CrewConnectionStatus.pendingOutgoing,
          for (final user in requests) user.id: CrewConnectionStatus.pendingIncoming,
          for (final user in members) user.id: CrewConnectionStatus.connected,
        },
      );
    } catch (error) {
      if (!mounted || generation != _generation || revision != _revision) return;
      // A demo session must never surface a network error — if the session
      // resolved as presentation mode mid-flight, fixtures win over the
      // failure.
      if (isPresentationDemo()) {
        final members = PresentationDemoData.crewMembers();
        final page = PresentationDemoData.crewRequestPage();
        final ids = members.map((user) => user.id).toSet();
        _loadedAt = DateTime.now();
        state = CrewState(
          members: members,
          requests: page.incoming
              .where((user) => !ids.contains(user.id))
              .toList(),
          outgoing: page.outgoing
              .where((user) => !ids.contains(user.id))
              .toList(),
          pendingUserIds: state.pendingUserIds,
          relationships: {
            for (final id in state.relationships.keys)
              id: CrewConnectionStatus.none,
            for (final user in page.outgoing)
              user.id: CrewConnectionStatus.pendingOutgoing,
            for (final user in page.incoming)
              user.id: CrewConnectionStatus.pendingIncoming,
            for (final user in members) user.id: CrewConnectionStatus.connected,
          },
        );
        return;
      }
      state = state.copyWith(
        loading: false,
        refreshing: false,
        error: "Couldn't refresh your crew. Try again.",
      );
      if (error is ApiException && error.statusCode == 401) onSessionExpired?.call();
    }
  }

  Future<List<CrewSearchResult>> search(String query) async {
    final generation = _generation;
    final revision = _revision;
    final trimmed = query.trim().replaceFirst(RegExp(r'^@'), '');
    if (trimmed.isEmpty) return const [];
    final results = isPresentationDemo()
        ? PresentationDemoData.crewMembers()
            .where((user) => '${user.displayName} ${user.username ?? ''}'
                .toLowerCase().contains(trimmed.toLowerCase()))
            .map((user) => CrewSearchResult(
              user: user,
              connectionStatus: state.relationshipFor(user.id),
            )).toList()
        : await _repo.search(trimmed);
    if (!mounted || generation != _generation) return const [];
    if (revision == _revision) {
      state = state.copyWith(relationships: {
        ...state.relationships,
        for (final result in results)
          if (!state.pendingUserIds.contains(result.user.id))
            result.user.id: result.connectionStatus,
      });
    }
    return results;
  }

  Future<T> _mutate<T>(String id, String action, Future<T> Function() write,
      void Function(T result) apply) {
    final existing = _mutations[id];
    if (existing != null) {
      if (existing.action == action) return existing.future.then((value) => value as T);
      return Future.error(const ApiException(409, 'A crew update is still in progress.'));
    }
    final generation = _generation;
    state = state.copyWith(pendingUserIds: {...state.pendingUserIds, id});
    final future = Future<T>(() async {
      try {
        final result = await write();
        if (mounted && generation == _generation) {
          _invalidateFetch();
          apply(result);
          _loadedAt = null;
          onMutated?.call();
        }
        return result;
      } on ApiException catch (error) {
        if (mounted && generation == _generation && error.statusCode == 401) {
          onSessionExpired?.call();
        }
        rethrow;
      } finally {
        if (mounted && generation == _generation) {
          _mutations.remove(id);
          state = state.copyWith(pendingUserIds: {...state.pendingUserIds}..remove(id));
        }
      }
    });
    _mutations[id] = (action: action, future: future);
    return future;
  }

  Future<ConnectOutcome> add(PublicUser user) => _mutate(
    user.id, 'add',
    () async => isPresentationDemo() ? ConnectOutcome.active : await _repo.add(user.id),
    (outcome) {
      final connected = outcome == ConnectOutcome.active;
      state = state.copyWith(
        members: connected ? [user, ...state.members.where((m) => m.id != user.id)] : null,
        requests: connected ? state.requests.where((r) => r.id != user.id).toList() : null,
        outgoing: connected
            ? state.outgoing.where((o) => o.id != user.id).toList()
            : [user, ...state.outgoing.where((o) => o.id != user.id)],
        relationships: {...state.relationships, user.id: connected
            ? CrewConnectionStatus.connected : CrewConnectionStatus.pendingOutgoing},
        loading: false, refreshing: false,
      );
      if (connected) onRequestResolved?.call(user.id);
    },
  );

  Future<void> acceptRequest(PublicUser user) => _mutate<void>(
    user.id, 'accept',
    () async { if (!isPresentationDemo()) await _repo.acceptRequest(user.id); },
    (_) {
      state = state.copyWith(
        members: [user, ...state.members.where((m) => m.id != user.id)],
        requests: state.requests.where((r) => r.id != user.id).toList(),
        outgoing: state.outgoing.where((o) => o.id != user.id).toList(),
        relationships: {...state.relationships, user.id: CrewConnectionStatus.connected},
        loading: false, refreshing: false,
      );
      onRequestResolved?.call(user.id);
    },
  );

  Future<void> declineRequest(PublicUser user) => _mutate<void>(
    user.id, 'decline',
    () async { if (!isPresentationDemo()) await _repo.declineRequest(user.id); },
    (_) => _forget(user.id),
  );

  Future<void> remove(String userId) => _mutate<void>(
    userId, 'remove',
    () async { if (!isPresentationDemo()) await _repo.remove(userId); },
    (_) => _forget(userId),
  );

  void _forget(String userId) {
    state = state.copyWith(
      members: state.members.where((m) => m.id != userId).toList(),
      requests: state.requests.where((r) => r.id != userId).toList(),
      outgoing: state.outgoing.where((o) => o.id != userId).toList(),
      relationships: {...state.relationships, userId: CrewConnectionStatus.none},
      loading: false, refreshing: false,
    );
    onRequestResolved?.call(userId);
  }

  void _invalidateFetch() {
    _revision++;
    _loadInFlight = null;
  }

  void clear() {
    _generation++;
    _invalidateFetch();
    _loadedAt = null;
    _mutations.clear();
    if (mounted) state = const CrewState();
  }
}

final _crewApiProvider = Provider<CrewApi>((_) => CrewApi());
final crewRepositoryProvider = Provider<CrewRepository>((ref) => CrewRepository(
  ref.watch(_crewApiProvider), ref.watch(secureTokenStoreProvider), ref.watch(authApiProvider),
));

final crewControllerProvider = StateNotifierProvider<CrewController, CrewState>((ref) {
  final controller = CrewController(
    ref.watch(crewRepositoryProvider),
    isPresentationDemo: () => isPresentationDemoUser(ref.read(authControllerProvider).user),
    onMutated: () => ref.read(raceControllerProvider.notifier).loadRaces(force: true),
    onRequestResolved: (id) => ref.read(notificationControllerProvider.notifier).resolveCrewRequest(id),
    onSessionExpired: () => ref.read(authControllerProvider.notifier).sessionExpired(),
  );
  var demo = isPresentationDemoUser(ref.read(authControllerProvider).user);
  // Deferred: a synchronous mutation during the kickoff would modify other
  // providers while this one is still initializing (Riverpod asserts).
  if (ref.read(authControllerProvider).status == AuthStatus.authenticated) {
    Future(() => controller.load(force: false));
  }
  ref.listen<AuthState>(authControllerProvider, (prev, next) {
    if (prev?.user?.id != next.user?.id || prev?.status != next.status) {
      controller.clear();
      demo = isPresentationDemoUser(next.user);
      if (next.status == AuthStatus.authenticated) controller.load(force: false);
    }
  });
  ref.listen<bool>(presentationModeEnabledProvider, (_, _) {
    final current = isPresentationDemoUser(ref.read(authControllerProvider).user);
    if (demo == current) return;
    demo = current;
    controller.clear();
    if (ref.read(authControllerProvider).status == AuthStatus.authenticated) controller.load(force: true);
  });
  return controller;
});
