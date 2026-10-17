// The signed-in user's member pass (member id, slug, share link), loaded once
// per account instead of on every Crew open (docs/agents/22 C6): cached data
// is returned immediately, one background refresh runs per session, and the
// pass is re-fetched only on an explicit refresh or an account change.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cache_store.dart';
import '../../../core/demo/presentation_demo.dart';
import '../../auth/data/auth_models.dart';
import '../../auth/presentation/auth_controller.dart';

class MemberPassState {
  const MemberPassState({this.info, this.loading = true, this.failed = false});

  final PassInfo? info;

  /// True until the first result (cached or fetched) is available.
  final bool loading;

  /// The fetch failed and there is no cached pass to show.
  final bool failed;
}

class MemberPassController extends StateNotifier<MemberPassState> {
  MemberPassController({
    required this.fetch,
    this.cache,
    this.accountId,
    this.isDemo = _never,
  }) : super(const MemberPassState());

  final Future<PassInfo> Function() fetch;
  final CacheStore? cache;
  final String? accountId;
  final bool Function() isDemo;
  static bool _never() => false;

  static const _domain = 'member_pass';
  static const _maxAge = Duration(days: 30);

  bool _started = false;
  bool _fetched = false;
  Future<void>? _inFlight;

  String? get _account {
    final id = accountId;
    return cache != null && id != null && isValidCacheId(id) ? id : null;
  }

  /// Loads the pass once per account (cache first, then a background
  /// refresh). Later calls are no-ops unless the last attempt failed with
  /// nothing to show.
  Future<void> ensureLoaded() {
    if (isDemo()) {
      _showDemo();
      return Future.value();
    }
    if (_inFlight case final request?) return request;
    if (_started && !(state.failed && state.info == null)) {
      return Future.value();
    }
    _started = true;
    return _run(hydrate: true);
  }

  /// Explicit refresh (pull-to-refresh / retry).
  Future<void> refresh() {
    if (isDemo()) {
      _showDemo();
      return Future.value();
    }
    _started = true;
    return _inFlight ?? _run(hydrate: state.info == null);
  }

  void _showDemo() {
    if (mounted) {
      state = MemberPassState(info: presentationDemoPassInfo(), loading: false);
    }
  }

  Future<void> _run({required bool hydrate}) {
    final request = _load(hydrate: hydrate);
    _inFlight = request;
    request.whenComplete(() {
      if (identical(_inFlight, request)) _inFlight = null;
    });
    return request;
  }

  Future<void> _load({required bool hydrate}) async {
    if (!mounted) return;
    state = MemberPassState(info: state.info, loading: state.info == null);
    final account = _account;
    // Hydration runs alongside the fetch, never in front of it: a slow disk
    // must not delay the network, and a late snapshot never beats fresh data.
    if (hydrate && account != null) {
      () async {
        try {
          final entry = await cache!.read(account, _domain, maxAge: _maxAge);
          final data = entry?.data;
          if (mounted &&
              !_fetched &&
              state.info == null &&
              data is Map<String, dynamic>) {
            state = MemberPassState(
              info: PassInfo.fromJson(data),
              loading: false,
            );
          }
        } catch (_) {
          // A bad snapshot is just a cache miss.
        }
      }();
    }
    try {
      final pass = await fetch();
      _fetched = true;
      if (!mounted) return;
      state = MemberPassState(info: pass, loading: false);
      if (account != null) {
        cache!
            .write(account, _domain, {
              'memberId': pass.memberId,
              'passSlug': pass.passSlug,
              'shareUrl': pass.shareUrl,
            })
            .catchError((_) {});
      }
    } catch (_) {
      if (!mounted) return;
      // A demo session must never surface a network error.
      if (isDemo()) {
        _showDemo();
        return;
      }
      state = MemberPassState(
        info: state.info,
        loading: false,
        failed: state.info == null,
      );
    }
  }
}

/// Keyed to the signed-in user: a new account (or presentation-mode change)
/// builds a fresh controller, so account B never sees account A's pass.
final memberPassProvider =
    StateNotifierProvider<MemberPassController, MemberPassState>((ref) {
      final userId = ref.watch(authControllerProvider.select((s) => s.user?.id));
      ref.watch(presentationModeEnabledProvider);
      final auth = ref.read(authControllerProvider.notifier);
      return MemberPassController(
        fetch: auth.getMemberPass,
        cache: ref.watch(cacheStoreProvider),
        accountId: userId,
        isDemo: () => isPresentationDemoUser(ref.read(authControllerProvider).user),
      );
    });
