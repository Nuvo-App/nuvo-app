import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/bottom_nav.dart';

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

    return Scaffold(
      backgroundColor: NuvoColors.page,
      extendBody: true,
      body: SafeArea(bottom: false, child: child),
      bottomNavigationBar: NuvoBottomNav(
        currentIndex: currentIndex,
        onTap: (index) => context.go(_paths[index]),
        isDark: currentIndex == 0,
      ),
    );
  }
}
