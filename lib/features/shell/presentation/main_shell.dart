import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/bottom_nav.dart';

/// The single shell for all five primary tabs.
///
/// Nuvo has one light application theme, so every tab — Arena included —
/// shares the same warm off-white canvas and the same floating light
/// navigation. There is no per-tab dark treatment.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

  static const _paths = [
    '/arena', // 0 Arena
    '/compete', // 1 Compete
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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      backgroundColor: NuvoColors.page,
      // The nav floats over the page, so the body extends behind it. Every
      // screen adds NuvoBottomNav.bottomPadding() to its scroll view so the
      // final item still clears the pill.
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: reduceMotion
          ? child
          : PageTransitionSwitcher(
              transitionBuilder: (child, primaryAnimation, secondaryAnimation) =>
                  FadeThroughTransition(
                animation: primaryAnimation,
                secondaryAnimation: secondaryAnimation,
                child: child,
              ),
              child: child,
            ),
      bottomNavigationBar: NuvoBottomNav(
        currentIndex: currentIndex,
        onTap: (index) {
          if (index == currentIndex) return;
          context.go(_paths[index]);
        },
      ),
    );
  }
}
