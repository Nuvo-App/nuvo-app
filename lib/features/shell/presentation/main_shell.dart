import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/demo/presentation_demo.dart';
import '../../../core/offline/outbox.dart';
import '../../../core/v13/v13.dart';
import '../../onboarding/data/onboarding_v2_store.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/trackside_layout_diagnostics.dart';
import '../../arena/presentation/arena_controller.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../crew/application/crew_controller.dart';
import '../../notifications/application/notification_controller.dart';
import '../../races/presentation/race_controller.dart';
import '../../social/data/crew_activity.dart';
import '../../races/presentation/motion_catalog_provider.dart';
import '../../profile/application/progression_controller.dart';
import '../../profile/presentation/widgets/level_up_dialog.dart';

/// Bottom-nav host. Also the app-wide **freshness trigger point**: on app
/// resume and on switching to a data tab it asks the canonical controllers to
/// revalidate (stale-while-revalidate — the current content stays on screen).
/// See docs/agents/18-data-freshness-contract.md.
///
/// LAYOUT CONTRACT: every tab shares one `Scaffold(bottomNavigationBar:
/// ..., extendBody: true)`. The nav is a floating dock — a compact rounded
/// container inset from the screen edges, resting on the device bottom
/// inset — and each tab's body extends to the screen's bottom edge, visible
/// in the dock's horizontal margins while scrolling. Because the dock
/// overlays content, scrollable screens must end their scroll views with
/// `V13TabBar.bottomPadding(context)` so the last row clears it.
/// Scaffold already folds the nav's rendered height into the body's
/// `MediaQuery.padding.bottom` — `bottomPadding` only adds the shared
/// section gap on top of that; never re-add the dock or the safe inset
/// inside a tab screen. One shared composition for every tab — do not
/// reintroduce a per-tab layout branch; if a screen needs different chrome,
/// that belongs in the screen, not the shell.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.child});

  /// In production this is the `StatefulNavigationShell` handed to the
  /// router's `StatefulShellRoute` builder — it renders the four branch
  /// Navigators through [NuvoTabStack] (see `navigatorContainerBuilder` in
  /// router.dart), which keeps every visited tab mounted and animates the
  /// switch directionally. In widget tests it can be any plain child.
  final Widget child;

  // Nav index → shell route path, derived from the canonical destination
  // table in bottom_nav.dart — the same order the router uses to declare
  // its StatefulShellRoute branches, so nav index == branch index always.
  static final _paths = [for (final d in activeDestinations) d.path];

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  /// Tab-switch entrance: the incoming tab fades up a few points. Driven by
  /// one controller (no key swap) so each branch keeps its state.
  late final AnimationController _tabIn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );
  int? _lastTabIndex;

  /// Reentrancy guard for the level-up moment — the server flag makes it
  /// once-per-level across devices; this makes it once-per-dialog in-flight.
  bool _levelUpShowing = false;

  /// Achievement grants already presented this session — the server emits
  /// `newlyEarned` once per grant, but state rebuilds carry the value
  /// forward, so this set is the local once-per-moment guard.
  final Set<String> _shownAchievementIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_syncPendingGraduation());
    unawaited(_flushOutbox());
    // While anything is queued, retry on a gentle tick (backoff inside).
    _outboxTick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (ref.read(outboxProvider).pendingCount > 0) _flushOutbox();
    });
    // Self-heal: a canonical controller's own provider-creation-time load can
    // miss (e.g. a load that was in flight across a sign-out — see the
    // _generation guards in RaceController/ArenaController/CrewController/
    // NotificationController). Previously only Compete patched this itself
    // (per-screen initState check), which left every other tab exposed to the exact same "stuck cold, no error, no retry"
    // state until the user happened to open Compete or force-refresh.
    // Centralized here once, for every domain, instead of duplicated per
    // screen (docs/agents/18 designates MainShell as the one freshness
    // trigger point).
    WidgetsBinding.instance.addPostFrameCallback((_) => _selfHealIfStuck());
  }

  /// True once a network round-trip is actually worth attempting. While auth
  /// is offline (stored credentials, server unreachable — see AuthStatus),
  /// every one of these domains would just fail the same way Arena's own
  /// retry will, so the shell stays quiet instead of firing four more
  /// doomed requests on every mount/resume/tab-tap.
  bool get _authIsUp =>
      ref.read(authControllerProvider).status == AuthStatus.authenticated;

  void _selfHealIfStuck() {
    if (!mounted || !_authIsUp) return;
    unawaited(refreshMotionCatalog(ref));
    final raceState = ref.read(raceControllerProvider);
    if (raceState.races.isEmpty &&
        raceState.error == null &&
        !raceState.loading) {
      ref.read(raceControllerProvider.notifier).loadRaces(force: false);
    }
    final arenaState = ref.read(arenaControllerProvider);
    if (!arenaState.hasData &&
        arenaState.error == null &&
        !arenaState.loading) {
      ref.read(arenaControllerProvider.notifier).loadSnapshot(force: false);
    }
    final crewState = ref.read(crewControllerProvider);
    if (!crewState.hasData && crewState.error == null && !crewState.loading) {
      ref.read(crewControllerProvider.notifier).load(force: false);
    }
    final notifState = ref.read(notificationControllerProvider);
    if (!notifState.hasData &&
        notifState.error == null &&
        !notifState.loading) {
      ref.read(notificationControllerProvider.notifier).load(force: false);
    }
    final progressionState = ref.read(progressionControllerProvider);
    if (progressionState.isLoading && !progressionState.hasValue) {
      ref.read(progressionControllerProvider.notifier).load(force: false);
    }
    final activityState = ref.read(crewActivityProvider);
    if (!activityState.hasData &&
        activityState.error == null &&
        !activityState.loading) {
      ref.read(crewActivityProvider.notifier).load(force: false);
    }
  }

  /// Onboarding v2 finished offline earlier: the server write is still owed.
  /// Retry it once per launch in the background; never blocks the shell.
  Future<void> _syncPendingGraduation() async {
    final store = ref.read(onboardingV2StoreProvider);
    await store.ensureLoaded();
    final user = ref.read(authControllerProvider).user;
    if (!store.graduationPending || user == null) return;
    if (user.onboardingComplete) {
      await store.setGraduationPending(false);
      return;
    }
    try {
      await ref.read(authControllerProvider.notifier).completeOnboarding();
      await store.setGraduationPending(false);
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabIn.dispose();
    _outboxTick?.cancel();
    super.dispose();
  }

  Timer? _outboxTick;

  /// Sends writes that were saved while offline (launch, resume, tick).
  Future<void> _flushOutbox({bool force = false}) async {
    final sent = await ref.read(outboxProvider).flush(force: force);
    if (sent > 0 && mounted) {
      ref.read(raceControllerProvider.notifier).revalidate();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed)
      unawaited(_flushOutbox(force: true));
    if (state == AppLifecycleState.resumed && _authIsUp) {
      // High-value user state, revalidated the moment the app comes forward.
      unawaited(refreshMotionCatalog(ref));
      ref.read(raceControllerProvider.notifier).revalidate();
      ref.read(arenaControllerProvider.notifier).revalidate();
      ref.read(crewControllerProvider.notifier).revalidate();
      ref.read(notificationControllerProvider.notifier).revalidate();
      ref.read(progressionControllerProvider.notifier).revalidate();
    }
  }

  int _indexFor(String location) {
    for (var i = 0; i < activeDestinations.length; i++) {
      if (location.startsWith(activeDestinations[i].path)) return i;
    }
    return 0;
  }

  void _onTapTab(int index) {
    // Debug-only trace of the tap → destination resolution. If a tab ever
    // shows the wrong page again, this line plus the [NuvoNav] route print
    // in router.dart pin down exactly where the mapping diverges.
    assert(() {
      final d = activeDestinations[index];
      debugPrint('[NuvoNav] tap index=$index → ${d.label} (${d.path})');
      return true;
    }());
    // Revalidate the data behind the destination tab before showing it.
    // (A deliberate, single, user-initiated tap — unlike the automatic
    // self-heal/resume triggers above, this is allowed to attempt a request
    // even while offline: tapping a tab is itself a natural "try again.")
    switch (index) {
      case 0:
        unawaited(refreshMotionCatalog(ref));
        ref.read(arenaControllerProvider.notifier).revalidate();
        break;
      case 1:
        unawaited(refreshMotionCatalog(ref));
        ref.read(raceControllerProvider.notifier).revalidate();
        break;
      case 2:
        ref.read(crewControllerProvider.notifier).revalidate();
        ref.read(notificationControllerProvider.notifier).revalidate();
        break;
      case 3:
        ref.read(progressionControllerProvider.notifier).revalidate();
        break;
    }
    // Each branch keeps its own Navigator and its last location — goBranch
    // restores the destination exactly where the user left it (scroll,
    // selection, pushed routes). `initialLocation` stays false so re-tapping
    // the current tab does not pop the user back to the branch root.
    if (widget.child case final StatefulNavigationShell shell) {
      shell.goBranch(index, initialLocation: false);
    } else {
      context.go(MainShell._paths[index]);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The level-up moment lives on the shell, not on Profile — a finish that
    // crosses a threshold rolls the number the moment the canonical
    // progression revalidates, wherever the user is standing. The server's
    // last_seen_level keeps it once-per-level across restarts and devices.
    ref.listen(progressionControllerProvider, (_, next) {
      final p = next.valueOrNull;
      if (p == null || _levelUpShowing || !mounted) return;
      final fresh = p.newlyEarned
          .where((b) => !_shownAchievementIds.contains(b.unlockId))
          .toList();
      if (!p.hasUnseenLevelUp && fresh.isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _levelUpShowing) return;
        _levelUpShowing = true;
        if (p.hasUnseenLevelUp) {
          await showLevelUpMoment(
            context,
            level: p.level,
            badge: p.levelUnlock,
          );
          if (mounted) {
            ref.read(progressionControllerProvider.notifier).markLevelSeen();
          }
        }
        for (final badge in fresh.take(3)) {
          if (!mounted) break;
          _shownAchievementIds.add(badge.unlockId);
          final ctx = context;
          if (!ctx.mounted) break;
          await showAchievementMoment(ctx, badge: badge);
        }
        _levelUpShowing = false;
      });
    });
    final currentIndex = widget.child is StatefulNavigationShell
        ? (widget.child as StatefulNavigationShell).currentIndex
        : _indexFor(GoRouterState.of(context).uri.path);

    if (_lastTabIndex != null &&
        _lastTabIndex != currentIndex &&
        !MediaQuery.disableAnimationsOf(context)) {
      _tabIn.forward(from: 0.35);
    }
    _lastTabIndex = currentIndex;

    final Widget navigation = V13TabBar(
      key: TrackSideLayoutKeys.navigation,
      items: [
        for (final d in activeDestinations)
          V13TabItem(
            label: d.label,
            icon: d.icon,
            selectedIcon: d.selectedIcon,
          ),
      ],
      currentIndex: currentIndex,
      onTap: _onTapTab,
    );

    return Scaffold(
      backgroundColor: V13.bg,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        // Content scrolls behind the floating dock; every tab pads its last
        // row by V13TabBar.bottomPadding so it can scroll fully clear.
        child: Stack(
          fit: StackFit.expand,
          children: [
            FadeTransition(
              opacity: CurvedAnimation(parent: _tabIn, curve: Curves.easeOut),
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.012), end: Offset.zero)
                    .animate(
                      CurvedAnimation(parent: _tabIn, curve: Curves.easeOut),
                    ),
                child: widget.child,
              ),
            ),
            if (showFakeDataPill(ref.watch(authControllerProvider).user?.email))
              const Positioned(top: 8, right: 12, child: _FakeDataPill()),
            // Offline indicator: shows when Nuvo is unreachable or writes are
            // waiting to send — cached screens stay up, no error pages.
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: ListenableBuilder(
                    listenable: ref.read(outboxProvider),
                    builder: (context, _) {
                      final o = ref.read(outboxProvider);
                      final offline =
                          ref.watch(authControllerProvider).status ==
                              AuthStatus.offline ||
                          o.lastReachable == false;
                      if (!offline && o.pendingCount == 0) {
                        return const SizedBox.shrink();
                      }
                      return _OfflinePill(waiting: o.pendingCount);
                    },
                  ),
                ),
              ),
            ),
            // Soft fade behind the floating dock: content dissolves into the
            // page colour instead of hard-cutting at the dock's edge.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: MediaQuery.paddingOf(context).bottom + 32,
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey('nuvo-dock-fade'),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [V13.bg.withValues(alpha: 0), V13.bg],
                      stops: const [0, 0.55],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: navigation,
    );
  }
}

/// R4 gate: the fake-data pill exists for testing@getnuvo.net and nobody else.
@visibleForTesting
bool showFakeDataPill(String? email) => isNuvoStoreDemoEmail(email ?? '');

/// R4 — testing@getnuvo.net only: flips fake (presentation) data on/off from
/// any tab and reloads, so the store-review account starts clean but can
/// show a full app on demand.
class _FakeDataPill extends ConsumerStatefulWidget {
  const _FakeDataPill();

  @override
  ConsumerState<_FakeDataPill> createState() => _FakeDataPillState();
}

class _FakeDataPillState extends ConsumerState<_FakeDataPill> {
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final on = !presentationModeToggleEnabled;
      await setPresentationModeEnabled(on);
      final races = ref.read(raceControllerProvider.notifier)..clearRaces();
      final arena = ref.read(arenaControllerProvider.notifier)..clearSnapshot();
      await Future.wait([
        races.loadRaces(force: true),
        arena.loadSnapshot(force: true),
      ]);
      if (mounted)
        showV13Toast(context, on ? 'Fake data on.' : 'Fake data off.');
    } catch (_) {
      if (mounted)
        showV13Toast(context, 'Couldn\u2019t switch data. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = presentationModeToggleEnabled;
    return V13Pressable(
      onTap: _toggle,
      shadow: V13.shadow3,
      borderRadius: BorderRadius.circular(V13.radiusPill),
      semanticLabel: on ? 'Turn fake data off' : 'Load fake data',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: on ? V13.sun : V13.card,
          borderRadius: BorderRadius.circular(V13.radiusPill),
          border: Border.all(color: V13.navy, width: V13.outline),
        ),
        child: Text(
          _busy ? '\u2026' : (on ? 'Fake data: on' : 'Fake data'),
          style: V13.caption.copyWith(
            color: V13.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _OfflinePill extends StatelessWidget {
  const _OfflinePill({required this.waiting});
  final int waiting;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: V13.navy,
        borderRadius: BorderRadius.circular(V13.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 14, color: V13.card),
          const SizedBox(width: 6),
          Text(
            waiting > 0 ? 'Offline \u00b7 $waiting waiting to send' : 'Offline',
            style: V13.caption.copyWith(
              color: V13.card,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
