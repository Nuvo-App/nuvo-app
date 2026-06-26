import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/bottom_nav.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

  // Maps nav index → shell route path.
  // Index 2 = Move tab (/move) is a new shell route added in router.dart.
  static const _paths = [
    '/arena', // 0 Arena
    '/compete', // 1 Races (label updated in bottom_nav)
    '/move', // 2 Move
    '/pass', // 3 Crew (label updated in bottom_nav)
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
    final location = GoRouterState.of(context).uri.path;
    final currentIndex = _indexFor(location);

    return Scaffold(
      backgroundColor: NuvoColors.navy,
      body: child,
      bottomNavigationBar: NuvoBottomNav(
        currentIndex: currentIndex,
        onTap: (index) => context.go(_paths[index]),
      ),
    );
  }
}
