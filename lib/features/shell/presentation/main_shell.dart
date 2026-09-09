import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/trackside_layout_diagnostics.dart';
import '../../arena/presentation/arena_controller.dart';
import '../../crew/application/crew_controller.dart';
import '../../notifications/application/notification_controller.dart';
import '../../races/presentation/race_controller.dart';

/// Bottom-nav host. Also the app-wide **freshness trigger point**: on app
/// resume and on switching to a data tab it asks the canonical controllers to
/// revalidate (stale-while-revalidate — the current content stays on screen).
/// See docs/agents/18-data-freshness-contract.md.
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
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
    final isArena = currentIndex == 0;

    final navigation = NuvoBottomNav(
      key: TrackSideLayoutKeys.navigation,
      rowKey: TrackSideLayoutKeys.navigationRow,
      currentIndex: currentIndex,
      onTap: _onTapTab,
      isDark: false,
    );

    final shellBody = Scaffold(
      backgroundColor: NuvoColors.page,
      extendBody: !isArena,
      body: isArena
          ? LayoutBuilder(
              builder: (context, constraints) {
                if (trackSideLayoutDiagnosticsEnabled) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    TrackSideLayoutDiagnostics.report({
                      ...TrackSideLayoutDiagnostics.viewData(context),
                      'mainShellRootConstraints': constraints.toString(),
                      'arenaStackConstraints': constraints.toString(),
                      'mainShellRoot': TrackSideLayoutDiagnostics.box(
                        TrackSideLayoutKeys.shell,
                      ),
                      'arenaStack': TrackSideLayoutDiagnostics.box(
                        TrackSideLayoutKeys.arenaStack,
                      ),
                      'navigationBackground': TrackSideLayoutDiagnostics.box(
                        TrackSideLayoutKeys.navigation,
                      ),
                      'navigationIconRow': TrackSideLayoutDiagnostics.box(
                        TrackSideLayoutKeys.navigationRow,
                      ),
                    });
                  });
                }
                return KeyedSubtree(
                  key: TrackSideLayoutKeys.shell,
                  child: Stack(
                    key: TrackSideLayoutKeys.arenaStack,
                    fit: StackFit.expand,
                    children: [
                      widget.child,
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: navigation,
                      ),
                      const TrackSideLayoutDiagnosticsOverlay(),
                    ],
                  ),
                );
              },
            )
          : SafeArea(bottom: false, child: widget.child),
      bottomNavigationBar: isArena ? null : navigation,
    );

    return shellBody;
  }
}
