import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'nuvo_icons.dart';
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
    _NavItem(icon: NuvoIconType.bolt, label: 'Arena'),
    _NavItem(icon: NuvoIconType.flag, label: 'Races'),
    _NavItem(icon: NuvoIconType.plus, label: 'Move', isCta: true),
    _NavItem(icon: NuvoIconType.users, label: 'Crew'),
    _NavItem(icon: NuvoIconType.user, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottom + 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: NuvoColors.navy.withValues(alpha: 0.18),
              blurRadius: 34,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: NuvoColors.surface,
            child: Row(
              children: [
                for (var i = 0; i < _items.length; i++)
                  if (_items[i].isCta)
                    _CtaButton(onTap: () => onTap(i))
                  else
                    _NavButton(
                      item: _items[i],
                      selected: i == currentIndex,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        onTap(i);
                      },
                    ),
              ],
            ),
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

  final NuvoIconType icon;
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
    return Expanded(
      child: PressableScale(
        onTap: onTap,
        scale: 0.95,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(horizontal: selected ? 10 : 11, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? NuvoColors.navy : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: selected ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: NuvoIcon(
                  item.icon,
                  size: 17,
                  color: selected ? NuvoColors.white : NuvoColors.textDim,
                ),
              ),
              Flexible(
                child: AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: const Cubic(0.22, 1, 0.36, 1),
                child: selected
                    ? Padding(
                        padding: const EdgeInsets.only(left: 5),
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: AppTextStyles.labelSmall.copyWith(
                            color: NuvoColors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : const SizedBox(width: 0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CtaButton extends StatefulWidget {
  const _CtaButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_CtaButton> createState() => _CtaButtonState();
}

class _CtaButtonState extends State<_CtaButton> with SingleTickerProviderStateMixin {
  late final AnimationController _ringCtrl;

  @override
  void initState() {
    super.initState();
    // A handful of breaths to draw the eye to the FAB, then it settles —
    // the bottom nav is on screen the entire time the app is open, so an
    // indefinite repeat here means a ticker runs forever in the background.
    _ringCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat(count: 4);
  }

  @override
  void dispose() {
    _ringCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        width: 52,
        height: 52,
        child: PressableScale(
          onTap: widget.onTap,
          scale: 0.88,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              AnimatedBuilder(
                animation: _ringCtrl,
                builder: (context, _) {
                  final t = _ringCtrl.value;
                  final scale = 0.85 + t * 0.65;
                  final opacity = (0.9 * (1 - t)).clamp(0.0, 1.0);
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: NuvoColors.blue.withValues(alpha: opacity * 0.35),
                      ),
                    ),
                  );
                },
              ),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: NuvoColors.blue,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: NuvoColors.blue.withValues(alpha: 0.45),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Center(
                  child: NuvoIcon(NuvoIconType.plus, color: NuvoColors.white, size: 19),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
