import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import 'pressable_scale.dart';

// Indices map to shell paths in main_shell.dart:
// 0 → /arena, 1 → /compete (Races), 2 → /move, 3 → /pass (Crew), 4 → /profile

class NuvoBottomNav extends StatelessWidget {
  const NuvoBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _items = [
    _NavItem(icon: Icons.bolt_rounded,    label: 'Arena'),
    _NavItem(icon: Icons.flag_rounded,    label: 'Races'),
    _NavItem(icon: Icons.add_rounded,     label: 'Move',   isCta: true),
    _NavItem(icon: Icons.group_rounded,   label: 'Crew'),
    _NavItem(icon: Icons.person_rounded,  label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        color: NuvoColors.navy,
        border: Border(
          top: BorderSide(color: Color(0x14FFFFFF), width: 0.5),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom, top: 6),
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: _NavButton(
                    item: _items[i],
                    selected: i == currentIndex,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onTap(i);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.label,
    this.isCta = false,
  });

  final IconData icon;
  final String label;
  final bool isCta;
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (item.isCta) return _CtaButton(selected: selected, onTap: onTap);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon
          AnimatedScale(
            scale: selected ? 1.08 : 1.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: Icon(
              item.icon,
              size: 22,
              color: selected
                  ? NuvoColors.white
                  : NuvoColors.white.withValues(alpha: 0.38),
            ),
          ),

          const SizedBox(height: 5),

          // Animated indicator pill
          AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            width: selected ? 18.0 : 0.0,
            height: 3,
            decoration: BoxDecoration(
              color: NuvoColors.blue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _CtaButton extends StatelessWidget {
  const _CtaButton({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      scale: 0.90,
      child: Center(
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2B7FFF), NuvoColors.blue],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: NuvoColors.blue.withValues(alpha: 0.40),
                blurRadius: 18,
                spreadRadius: 0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.add_rounded,
            color: NuvoColors.white,
            size: 26,
          ),
        ),
      ),
    );
  }
}
