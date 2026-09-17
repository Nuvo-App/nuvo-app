import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/trackside_layout_diagnostics.dart';
import '../../arena/presentation/arena_controller.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../crew/application/crew_controller.dart';
import '../../notifications/application/notification_controller.dart';
import '../../races/presentation/race_controller.dart';

/// Bottom-nav host. Also the app-wide **freshness trigger point**: on app
/// resume and on switching to a data tab it asks the canonical controllers to
/// revalidate (stale-while-revalidate — the current content stays on screen).
/// See docs/agents/18-data-freshness-contract.md.
///
/// LAYOUT CONTRACT: every tab shares one `Scaffold(bottomNavigationBar:
/// ..., extendBody: false)`. Scaffold reserves exactly the nav's rendered
/// height for the body — the body's usable viewport physically ends above
/// the dock, so no screen can paint content underneath it. There used to be
/// a second code path here (a `Stack` that floated the nav over Arena's
/// body with `extendBody: true`) which was the actual cause of Arena
/// content rendering behind the dock — not insufficient bottom padding on
/// Arena's own scroll view. Do not reintroduce a per-tab layout branch here;
/// if a screen needs different chrome, that belongs in the screen, not the
/// shell.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

  // Maps nav index → shell route path.
  static const _paths = [
    '/arena', // 0 Arena
    '/compete', // 1 Races
    '/move', // 2 Verify
    '/pass', // 3 Crew
    '/profile', // 4 Profile
  ];

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Self-heal: a canonical controller's own provider-creation-time load can
    // miss (e.g. a load that was in flight across a sign-out — see the
    // _generation guards in RaceController/ArenaController/CrewController/
    // NotificationController). Previously only Compete patched this itself
    // (per-screen initState check), which left every other tab — Verify
    // included — exposed to the exact same "stuck cold, no error, no retry"
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _authIsUp) {
      // High-value user state, revalidated the moment the app comes forward.
      ref.read(raceControllerProvider.notifier).revalidate();
      ref.read(arenaControllerProvider.notifier).revalidate();
      ref.read(crewControllerProvider.notifier).revalidate();
      ref.read(notificationControllerProvider.notifier).revalidate();
    }
  }

  int _indexFor(String location) {
    if (location.startsWith('/compete')) return 1;
    if (location.startsWith('/move')) return 2;
    if (location.startsWith('/pass')) return 3;
    if (location.startsWith('/profile')) return 4;
    return 0;
  }

  void _onTapTab(int index) {
    // Revalidate the data behind the destination tab before showing it.
    // (A deliberate, single, user-initiated tap — unlike the automatic
    // self-heal/resume triggers above, this is allowed to attempt a request
    // even while offline: tapping a tab is itself a natural "try again.")
    switch (index) {
      case 0:
        ref.read(arenaControllerProvider.notifier).revalidate();
      case 1:
      case 2:
        ref.read(raceControllerProvider.notifier).revalidate();
      case 3:
        ref.read(crewControllerProvider.notifier).revalidate();
        ref.read(notificationControllerProvider.notifier).revalidate();
    }
    context.go(MainShell._paths[index]);
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _indexFor(GoRouterState.of(context).uri.path);

    final navigation = NuvoBottomNav(
      key: TrackSideLayoutKeys.navigation,
      rowKey: TrackSideLayoutKeys.navigationRow,
      currentIndex: currentIndex,
      onTap: _onTapTab,
      isDark: false,
    );

    return Scaffold(
      backgroundColor: NuvoColors.page,
      extendBody: false,
      body: SafeArea(bottom: false, child: widget.child),
      bottomNavigationBar: navigation,
    );
  }
}
