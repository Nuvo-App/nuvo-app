import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/bottom_nav.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

  static const _paths = ['/arena', '/pass', '/compete', '/profile'];

  int _indexFor(String location) {
    if (location.startsWith('/pass')) return 1;
    if (location.startsWith('/compete')) return 2;
    if (location.startsWith('/profile')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final currentIndex = _indexFor(location);

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(bottom: false, child: child),
      bottomNavigationBar: NuvoBottomNav(
        currentIndex: currentIndex,
        onTap: (index) => context.go(_paths[index]),
      ),
    );
  }
}
