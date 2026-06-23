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

// ── NuvoPageHeader ────────────────────────────────────────────────────────────

/// Tab-screen page header: large bold title, optional subtitle, optional trailing.
/// Matches Arena spacing and typography for use on Compete, Pass, Profile tabs.
class NuvoPageHeader extends StatelessWidget {
  const NuvoPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.headlineLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: NuvoColors.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

// ── NuvoBackNavRow ────────────────────────────────────────────────────────────

/// Deep-screen back navigation row: chevron button, optional title, optional trailing.
/// Replaces Material AppBar on push routes — sits directly on the page background.
class NuvoBackNavRow extends StatelessWidget {
  const NuvoBackNavRow({
    super.key,
    required this.onBack,
    this.title,
    this.trailing,
  });

  final VoidCallback onBack;
  final String? title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        PressableScale(
          onTap: onBack,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: NuvoColors.icyBlue,
              shape: BoxShape.circle,
              border: Border.all(color: NuvoColors.border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1207152B),
                  blurRadius: 0,
                  offset: Offset(2, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: NuvoColors.navy,
              size: 20,
            ),
          ),
        ),
        if (title != null) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title!,
              style: AppTextStyles.titleLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ] else
          const Spacer(),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

// ── NuvoTextInput ─────────────────────────────────────────────────────────────

/// Standard form input: label above, white fill, #DCE5F2 border, radius 14,
/// focused blue border, muted helper/error text.
class NuvoTextInput extends StatelessWidget {
  const NuvoTextInput({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
    this.minLines,
    this.maxLines = 1,
    this.autofocus = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? helperText;
  final String? errorText;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  final int? minLines;
  final int maxLines;
  final bool autofocus;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.labelMedium.copyWith(color: NuvoColors.navy),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          onChanged: onChanged,
          minLines: minLines,
          maxLines: maxLines,
          autofocus: autofocus,
          enabled: enabled,
          style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.navy),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTextStyles.bodyMedium.copyWith(
              color: NuvoColors.muted,
            ),
            filled: true,
            fillColor: NuvoColors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: NuvoColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: NuvoColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: NuvoColors.blue, width: 1.6),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE5484D)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: Color(0xFFE5484D),
                width: 1.6,
              ),
            ),
            errorText: errorText,
            helperText: helperText,
            helperStyle: AppTextStyles.bodySmall.copyWith(
              color: NuvoColors.muted,
            ),
            errorStyle: AppTextStyles.bodySmall.copyWith(
              color: const Color(0xFFE5484D),
            ),
          ),
        ),
      ],
    );
  }
}

// ── NuvoCurrentUserRow ────────────────────────────────────────────────────────

/// Current-user highlight row for leaderboards.
/// Pale blue fill, blue 1.5px border, blue rank pill, bold navy name,
/// blue right-aligned value. No shadow.
class NuvoCurrentUserRow extends StatelessWidget {
  const NuvoCurrentUserRow({
    super.key,
    required this.rank,
    required this.name,
    required this.value,
    this.initials,
  });

  final int rank;
  final String name;
  final String value;

  /// Pre-computed initials; if null, derived from [name].
  final String? initials;

  String _abbreviate(String n) {
    final parts = n.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final abbr = initials ?? _abbreviate(name);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: NuvoColors.icyBlue,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NuvoColors.blue, width: 1.5),
      ),
      child: Row(
        children: [
          // Blue rank circle pill
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: NuvoColors.blue,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$rank',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: NuvoColors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Initials circle
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
              color: NuvoColors.icyBlue,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              abbr,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: NuvoColors.blue,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Name
          Expanded(
            child: Text(
              name,
              style: AppTextStyles.bodyMedium.copyWith(
                color: NuvoColors.navy,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Value right-aligned
          Text(
            value,
            style: AppTextStyles.bodyMedium.copyWith(
              color: NuvoColors.blue,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── NuvoRaceLane ──────────────────────────────────────────────────────────────

/// Horizontal progress track — thin line with a blue dot at the current
/// position. The core visual element of the Nuvo redesign, echoing the logo's
/// smooth line + blue dot motif.
class NuvoRaceLane extends StatelessWidget {
  const NuvoRaceLane({
    super.key,
    required this.progressPercent,
    this.onDark = false,
    this.trackHeight = 3.0,
    this.dotDiameter = 12.0,
  });

  final int progressPercent;
  final bool onDark;
  final double trackHeight;
  final double dotDiameter;

  @override
  Widget build(BuildContext context) {
    final progress = (progressPercent / 100).clamp(0.0, 1.0);
    final trackColor = onDark
        ? Colors.white.withValues(alpha: 0.18)
        : NuvoColors.trackBg;
    final fillColor =
        progress >= 1 ? NuvoColors.success : NuvoColors.blue;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final fillWidth = (totalWidth * progress).clamp(0.0, totalWidth);

        return SizedBox(
          height: dotDiameter,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: trackHeight,
                decoration: BoxDecoration(
                  color: trackColor,
                  borderRadius: BorderRadius.circular(trackHeight / 2),
                ),
              ),
              if (progress > 0)
                Container(
                  width: fillWidth,
                  height: trackHeight,
                  decoration: BoxDecoration(
                    color: fillColor,
                    borderRadius: BorderRadius.circular(trackHeight / 2),
                  ),
                ),
              if (progress > 0 && progress < 1)
                Positioned(
                  left: (fillWidth - dotDiameter / 2)
                      .clamp(0.0, totalWidth - dotDiameter),
                  child: Container(
                    width: dotDiameter,
                    height: dotDiameter,
                    decoration: const BoxDecoration(
                      color: NuvoColors.blue,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              if (progress >= 1)
                Positioned(
                  right: 0,
                  child: Container(
                    width: dotDiameter,
                    height: dotDiameter,
                    decoration: const BoxDecoration(
                      color: NuvoColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ── NuvoLeaderboardRow ────────────────────────────────────────────────────────

/// Full-width leaderboard row with inline race lane and rank number.
class NuvoLeaderboardRow extends StatelessWidget {
  const NuvoLeaderboardRow({
    super.key,
    required this.rank,
    required this.name,
    required this.progressPercent,
    this.value,
    this.initials,
    this.isCurrentUser = false,
  });

  final int rank;
  final String name;
  final int progressPercent;
  final String? value;
  final String? initials;
  final bool isCurrentUser;

  String _abbrev(String n) {
    final parts = n.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final abbr = initials ?? _abbrev(name);
    final isComplete = progressPercent >= 100;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: isCurrentUser
          ? BoxDecoration(
              color: NuvoColors.icyBlue,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NuvoColors.blue, width: 1.5),
            )
          : null,
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '$rank',
              style: AppTextStyles.labelMedium.copyWith(
                color: isCurrentUser ? NuvoColors.blue : NuvoColors.muted,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isCurrentUser ? NuvoColors.blue : NuvoColors.border,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              abbr,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isCurrentUser ? NuvoColors.white : NuvoColors.navy,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight:
                        isCurrentUser ? FontWeight.w700 : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                NuvoRaceLane(
                  progressPercent: progressPercent,
                  trackHeight: 2.5,
                  dotDiameter: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value ?? (isComplete ? '100%' : '$progressPercent%'),
            style: AppTextStyles.labelMedium.copyWith(
              color: isCurrentUser ? NuvoColors.blue : NuvoColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}
