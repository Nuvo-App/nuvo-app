import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/trackside_layout_diagnostics.dart';

class MainShell extends StatelessWidget {
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

  int _indexFor(String location) {
    if (location.startsWith('/compete')) return 1;
    if (location.startsWith('/move')) return 2;
    if (location.startsWith('/pass')) return 3;
    if (location.startsWith('/profile')) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _indexFor(GoRouterState.of(context).uri.path);

    final isArena = currentIndex == 0;

    final navigation = NuvoBottomNav(
      key: TrackSideLayoutKeys.navigation,
      rowKey: TrackSideLayoutKeys.navigationRow,
      currentIndex: currentIndex,
      onTap: (index) => context.go(_paths[index]),
      isDark: isArena,
    );

    return Scaffold(
      backgroundColor: isArena ? NuvoColors.navy : NuvoColors.page,
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
                      child,
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
          : SafeArea(bottom: false, child: child),
      bottomNavigationBar: isArena ? null : navigation,
    );
  }
}
