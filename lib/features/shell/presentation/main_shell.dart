import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../arena/presentation/arena_screen_fixed.dart';
import '../../compete/presentation/compete_screen_fixed.dart';
import '../../move/presentation/move_screen.dart';
import '../../pass/presentation/pass_screen.dart';
import '../../profile/presentation/profile_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  // Maps nav index → shell route path.
  static const _paths = [
    '/arena', // 0 Arena
    '/compete', // 1 Races
    '/move', // 2 Verify
    '/pass', // 3 Crew
    '/profile', // 4 Profile
  ];

  static const _pages = [
    ArenaScreen(),
    CompeteScreen(),
    MoveScreen(),
    PassScreen(),
    ProfileScreen(),
  ];

  int _indexFor(String location) {
    if (location.startsWith('/compete')) return 1;
    if (location.startsWith('/move')) return 2;
    if (location.startsWith('/pass')) return 3;
    if (location.startsWith('/profile')) return 4;
    return 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final location = GoRouterState.of(context).uri.path;
    final newIndex = _indexFor(location);
    if (newIndex != _currentIndex) {
      _currentIndex = newIndex;
    }
  }

  void _onNavTap(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
    context.go(_paths[index]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NuvoColors.page,
      extendBody: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          for (var index = 0; index < _pages.length; index++)
            IgnorePointer(
              ignoring: index != _currentIndex,
              child: ExcludeSemantics(
                excluding: index != _currentIndex,
                child: TickerMode(
                  enabled: index == _currentIndex,
                  child: AnimatedSlide(
                    offset: index == _currentIndex
                        ? Offset.zero
                        : Offset(index < _currentIndex ? -0.025 : 0.025, 0),
                    duration: const Duration(milliseconds: 360),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: index == _currentIndex ? 1 : 0,
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      child: RepaintBoundary(child: _pages[index]),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: NuvoBottomNav(
        currentIndex: _currentIndex,
        onTap: _onNavTap,
      ),
    );
  }
}
