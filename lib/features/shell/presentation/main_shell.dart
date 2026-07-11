import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../arena/presentation/arena_screen.dart';
import '../../compete/presentation/compete_screen.dart';
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
  late final PageController _pageCtrl;
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
  void initState() {
    super.initState();
    _pageCtrl = PageController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final location = GoRouterState.of(context).uri.path;
    final newIndex = _indexFor(location);
    if (newIndex != _currentIndex) {
      _currentIndex = newIndex;
      if (_pageCtrl.hasClients) {
        _pageCtrl.animateToPage(
          newIndex,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
    context.go(_paths[index]);
  }

  void _onNavTap(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
    _pageCtrl.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
    context.go(_paths[index]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NuvoColors.page,
      extendBody: true,
      body: PageView(
        controller: _pageCtrl,
        onPageChanged: _onPageChanged,
        physics: const BouncingScrollPhysics(),
        children: _pages,
      ),
      bottomNavigationBar: NuvoBottomNav(
        currentIndex: _currentIndex,
        onTap: _onNavTap,
      ),
    );
  }
}
