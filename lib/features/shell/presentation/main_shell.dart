import 'dart:async';

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
import '../../races/presentation/motion_catalog_provider.dart';

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
/// `NuvoBottomNav.bottomPadding(context)` so the last row clears it.
/// Scaffold already folds the nav's rendered height into the body's
/// `MediaQuery.padding.bottom` — `bottomPadding` only adds the shared
/// section gap on top of that; never re-add the dock or the safe inset
/// inside a tab screen. One shared composition for every tab — do not
/// reintroduce a per-tab layout branch; if a screen needs different chrome,
/// that belongs in the screen, not the shell.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.child});

  /// In production this is the `StatefulNavigationShell` handed to the
  /// router's `StatefulShellRoute` builder — it renders the five branch
  /// Navigators through [NuvoTabStack] (see `navigatorContainerBuilder` in
  /// router.dart), which keeps every visited tab mounted and animates the
  /// switch directionally. In widget tests it can be any plain child.
  final Widget child;

  // Nav index → shell route path, derived from the canonical destination
  // table in bottom_nav.dart — the same order the router uses to declare
  // its StatefulShellRoute branches, so nav index == branch index always.
  static final _paths = [
    for (final d in nuvoDestinations) d.path,
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
      unawaited(refreshMotionCatalog(ref));
      ref.read(raceControllerProvider.notifier).revalidate();
      ref.read(arenaControllerProvider.notifier).revalidate();
      ref.read(crewControllerProvider.notifier).revalidate();
      ref.read(notificationControllerProvider.notifier).revalidate();
    }
  }

  int _indexFor(String location) {
    for (var i = 0; i < nuvoDestinations.length; i++) {
      if (location.startsWith(nuvoDestinations[i].path)) return i;
    }
    return 0;
  }

  void _onTapTab(int index) {
    // Debug-only trace of the tap → destination resolution. If a tab ever
    // shows the wrong page again, this line plus the [NuvoNav] route print
    // in router.dart pin down exactly where the mapping diverges.
    assert(() {
      final d = nuvoDestinations[index];
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
      case 2:
        unawaited(refreshMotionCatalog(ref));
        ref.read(raceControllerProvider.notifier).revalidate();
        break;
      case 3:
        ref.read(crewControllerProvider.notifier).revalidate();
        ref.read(notificationControllerProvider.notifier).revalidate();
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
    final currentIndex = widget.child is StatefulNavigationShell
        ? (widget.child as StatefulNavigationShell).currentIndex
        : _indexFor(GoRouterState.of(context).uri.path);

    final navigation = NuvoBottomNav(
      key: TrackSideLayoutKeys.navigation,
      rowKey: TrackSideLayoutKeys.navigationRow,
      currentIndex: currentIndex,
      onTap: _onTapTab,
      isDark: false,
    );

    return Scaffold(
      backgroundColor: context.themeColors.page,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _DockOcclusion(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: navigation,
    );
  }
}

/// Foreground occlusion for the floating dock — one shared contract for
/// every tab. The nav widget only paints the rounded dock itself; its
/// margins are transparent, so without this band scrolled body content
/// showed through (and under) the dock. The band is page-colored and
/// spans the nav's rendered extent plus Verify's raised-circle strip —
/// content scrolls behind it and re-emerges above the dock's top edge,
/// which is what the shared `bottomPadding` scroll clearance reserves.
/// IgnorePointer so taps still reach the nav painted on top.
class _DockOcclusion extends StatelessWidget {
  const _DockOcclusion();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        key: const ValueKey('nuvo-dock-occlusion'),
        height: MediaQuery.paddingOf(context).bottom +
            NuvoBottomNav.navVerifyRaise,
        color: context.themeColors.page,
      ),
    );
  }
}
