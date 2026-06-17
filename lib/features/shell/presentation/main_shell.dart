import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Root shell — provides the bottom nav bar around the four main tabs.
/// Tabs: Home · Crew · Create · Profile
/// Proof (verification) is a standalone screen accessible from race cards.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.child});
  final Widget child;

  static const _tabs = [
    _TabItem(icon: Icons.home_rounded, label: 'Home', path: '/arena'),
    _TabItem(icon: Icons.people_rounded, label: 'Crew', path: '/crew'),
    _TabItem(icon: Icons.add_circle_rounded, label: 'Create', path: '/create'),
    _TabItem(icon: Icons.person_rounded, label: 'Profile', path: '/profile'),
  ];

  int _indexFor(String location) {
    if (location.startsWith('/crew')) return 1;
    if (location.startsWith('/create')) return 2;
    if (location.startsWith('/profile')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final currentIndex = _indexFor(location);

    return Scaffold(
      backgroundColor: NuvoColors.page,
      // SafeArea(bottom: false) — shell owns the top inset so each tab screen
      // doesn't need to manually calculate statusBar height. bottom: false so
      // Scaffold.bottomNavigationBar handles the bottom inset itself.
      body: SafeArea(
        bottom: false,
        child: child,
      ),
      bottomNavigationBar: _NuvoNavBar(
        currentIndex: currentIndex,
        onTap: (i) => context.go(_tabs[i].path),
      ),
    );
  }
}

class _TabItem {
  const _TabItem({
    required this.icon,
    required this.label,
    required this.path,
  });
  final IconData icon;
  final String label;
  final String path;
}

class _NuvoNavBar extends StatelessWidget {
  const _NuvoNavBar({required this.currentIndex, required this.onTap});
  final int currentIndex;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        color: NuvoColors.white,
        border: Border(
          top: BorderSide(color: NuvoColors.border, width: 1),
        ),
      ),
      padding: EdgeInsets.only(bottom: bottomPadding, top: 10),
      child: Row(
        children: [
          for (var i = 0; i < MainShell._tabs.length; i++)
            Expanded(
              child: _NavTile(
                item: MainShell._tabs[i],
                selected: i == currentIndex,
                onTap: () => onTap(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });
  final _TabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? NuvoColors.blue : AppColors.textMuted;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item.icon, size: 24, color: color),
          const SizedBox(height: 4),
          Text(
            item.label,
            style: AppTextStyles.labelSmall.copyWith(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
