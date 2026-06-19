import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'pressable_scale.dart';

// ── NuvoIconBadge ─────────────────────────────────────────────────────────────

/// Rounded-square icon container used as the left visual anchor in rows.
class NuvoIconBadge extends StatelessWidget {
  const NuvoIconBadge({
    super.key,
    required this.icon,
    this.size = 40,
    this.iconSize = 20,
    this.color = NuvoColors.navy,
    this.iconColor = NuvoColors.white,
    this.radius = 13,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final Color color;
  final Color iconColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: iconColor, size: iconSize),
    );
  }
}

// ── NuvoPill ──────────────────────────────────────────────────────────────────

/// Inline status / label pill.
class NuvoPill extends StatelessWidget {
  const NuvoPill({
    super.key,
    required this.label,
    this.color = NuvoColors.blue,
    this.onDark = false,
  });

  final String label;
  final Color color;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final bg = onDark
        ? color.withValues(alpha: 0.22)
        : color.withValues(alpha: 0.12);
    final text = onDark ? NuvoColors.white : color;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: onDark ? 0.35 : 0.28),
        ),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: text,
          fontWeight: FontWeight.w800,
          fontSize: 10,
        ),
      ),
    );
  }
}

// ── NuvoBackplateCard ─────────────────────────────────────────────────────────

/// Hero / premium surface with offset navy backplate shadow.
class NuvoBackplateCard extends StatelessWidget {
  const NuvoBackplateCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color = NuvoColors.navy,
    this.radius = 24.0,
    this.onTap,
    this.shadowOpacity = 0.70,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final double radius;
  final VoidCallback? onTap;
  final double shadowOpacity;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(7, 21, 43, shadowOpacity),
            blurRadius: 0,
            offset: const Offset(5, 6),
          ),
        ],
      ),
      child: child,
    );

    if (onTap != null) {
      return PressableScale(onTap: onTap, child: card);
    }
    return card;
  }
}

// ── NuvoCompactCard ───────────────────────────────────────────────────────────

/// Light card with subtle border and small offset shadow — for secondary rows.
class NuvoCompactCard extends StatelessWidget {
  const NuvoCompactCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    this.onTap,
    this.color = NuvoColors.white,
    this.radius = 18.0,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color color;
  final double radius;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? NuvoColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1007152B),
            blurRadius: 0,
            offset: Offset(2, 3),
          ),
        ],
      ),
      child: child,
    );

    if (onTap != null) {
      return PressableScale(onTap: onTap, child: card);
    }
    return card;
  }
}

// ── NuvoSectionHeader ─────────────────────────────────────────────────────────

/// Section title with consistent spacing and optional action.
class NuvoSectionHeader extends StatelessWidget {
  const NuvoSectionHeader({
    super.key,
    required this.title,
    this.action,
    this.topPadding = 0,
    this.bottomPadding = 10,
  });

  final String title;
  final Widget? action;
  final double topPadding;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
      child: Row(
        children: [
          Expanded(child: Text(title, style: AppTextStyles.titleLarge)),
          ?action,
        ],
      ),
    );
  }
}

// ── NuvoActionTile ────────────────────────────────────────────────────────────

/// Compact action row: icon badge · title · optional subtitle · optional arrow.
/// Used for settings, invite rows, proof rows, quick actions.
class NuvoActionTile extends StatelessWidget {
  const NuvoActionTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.showArrow = true,
    this.iconColor = NuvoColors.navy,
    this.iconBg = NuvoColors.icyBlue,
    this.iconBadgeSize = 38,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool showArrow;
  final Color iconColor;
  final Color iconBg;
  final double iconBadgeSize;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return NuvoCompactCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: iconBadgeSize,
            height: iconBadgeSize,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NuvoColors.border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1207152B),
                  blurRadius: 0,
                  offset: Offset(2, 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.bodyMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing case final t?) ...[
            const SizedBox(width: 8),
            t,
          ] else if (showArrow && onTap != null)
            const Icon(
              Icons.chevron_right_rounded,
              color: NuvoColors.muted,
              size: 18,
            ),
        ],
      ),
    );
  }
}

// ── NuvoDenseRaceRow ──────────────────────────────────────────────────────────

/// Compact premium race row for active race lists.
class NuvoDenseRaceRow extends StatelessWidget {
  const NuvoDenseRaceRow({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.progressPercent,
    this.isComplete = false,
    this.isAiMotion = false,
    this.icon = Icons.flag_rounded,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final int? progressPercent;
  final bool isComplete;
  final bool isAiMotion;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: NuvoColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1207152B),
              blurRadius: 0,
              offset: Offset(2, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon badge
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isComplete ? NuvoColors.success : NuvoColors.navy,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(
                isAiMotion ? Icons.directions_run_rounded : icon,
                color: NuvoColors.white,
                size: 19,
              ),
            ),
            const SizedBox(width: 12),
            // Title + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.titleMedium,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: NuvoColors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Pills + arrow
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isComplete)
                  const NuvoPill(label: '100%', color: NuvoColors.success)
                else if (progressPercent != null && progressPercent! > 0)
                  NuvoPill(label: '$progressPercent%', color: NuvoColors.blue),
                if (isAiMotion && !isComplete) ...[
                  const SizedBox(width: 4),
                  const NuvoPill(label: 'AI', color: NuvoColors.blue),
                ],
                const SizedBox(width: 6),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: NuvoColors.muted,
                  size: 13,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── NuvoStatTile ──────────────────────────────────────────────────────────────

/// Compact stat cell for a 2×2 stats grid on Profile.
class NuvoStatTile extends StatelessWidget {
  const NuvoStatTile({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NuvoColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1007152B),
            blurRadius: 0,
            offset: Offset(2, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: AppTextStyles.headlineMedium.copyWith(
              color: NuvoColors.blue,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
          ),
        ],
      ),
    );
  }
}
