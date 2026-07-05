import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

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
    this.radius = 12,
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
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.20),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
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
        : color.withValues(alpha: 0.10);
    final text = onDark ? NuvoColors.white : color;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: onDark ? 0.32 : 0.22),
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: text,
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      ),
    );
  }
}

// ── NuvoBackplateCard ─────────────────────────────────────────────────────────

/// Hero / premium surface with a soft gradient and refined shadow.
class NuvoBackplateCard extends StatelessWidget {
  const NuvoBackplateCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color = NuvoColors.white,
    this.radius = 20.0,
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: color == NuvoColors.white
              ? const [
                  NuvoColors.white,
                  NuvoColors.inkWash,
                  NuvoColors.icyBlue,
                ]
              : [color, color],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: NuvoColors.border,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: NuvoColors.blue.withValues(
              alpha: 0.12 * shadowOpacity,
            ),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: NuvoColors.navy.withValues(
              alpha: 0.06 * shadowOpacity,
            ),
            blurRadius: 14,
            offset: const Offset(0, 5),
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

/// White card with a very soft shadow — secondary rows and tiles.
class NuvoCompactCard extends StatelessWidget {
  const NuvoCompactCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    this.onTap,
    this.color = NuvoColors.white,
    this.radius = 16.0,
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
        border: Border.all(
          color: borderColor ?? NuvoColors.border,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: NuvoColors.blue.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
          const BoxShadow(
            color: Color(0x080A1A33),
            blurRadius: 8,
            offset: Offset(0, 3),
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
          Container(
            width: 5,
            height: 20,
            decoration: BoxDecoration(
              color: NuvoColors.blue,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(title, style: AppTextStyles.titleMedium),
          ),
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
              border: Border.all(
                color: NuvoColors.border,
                width: 1,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: iconColor, size: 17),
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
              color: NuvoColors.paleSlate,
              size: 17,
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
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: NuvoColors.border, width: 1),
          boxShadow: [
            BoxShadow(
              color: NuvoColors.blue.withValues(alpha: 0.07),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
            const BoxShadow(
              color: Color(0x080A1A33),
              blurRadius: 8,
              offset: Offset(0, 3),
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
                color: isComplete ? NuvoColors.success : NuvoColors.blue,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(
                isAiMotion ? Icons.directions_run_rounded : icon,
                color: NuvoColors.white,
                size: 18,
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
                  color: NuvoColors.paleSlate,
                  size: 12,
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
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NuvoColors.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: NuvoColors.blue.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
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
/// A single blue accent line at the top instead of multi-colored dots.
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
              Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: NuvoColors.blue,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 10),
              Text(title, style: AppTextStyles.displaySmall),
              if (subtitle != null) ...[
                const SizedBox(height: 5),
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
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: NuvoColors.white,
              shape: BoxShape.circle,
              border: Border.all(color: NuvoColors.border, width: 1),
              boxShadow: [
                BoxShadow(
                  color: NuvoColors.blue.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: NuvoColors.navy,
              size: 19,
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

/// Standard form input: label above, white fill, clean 14px radius border,
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
              color: NuvoColors.textMuted,
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
              borderSide: const BorderSide(
                color: NuvoColors.blue,
                width: 1.6,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: NuvoColors.danger),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: NuvoColors.danger,
                width: 1.6,
              ),
            ),
            errorText: errorText,
            helperText: helperText,
            helperStyle: AppTextStyles.bodySmall.copyWith(
              color: NuvoColors.muted,
            ),
            errorStyle: AppTextStyles.bodySmall.copyWith(
              color: NuvoColors.danger,
            ),
          ),
        ),
      ],
    );
  }
}

// ── NuvoCurrentUserRow ────────────────────────────────────────────────────────

/// Current-user highlight row for leaderboards.
/// Icy blue fill, blue border, blue rank pill, bold navy name, blue value.
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
        border: Border.all(
          color: NuvoColors.blue.withValues(alpha: 0.50),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          // Blue rank circle
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
                fontWeight: FontWeight.w700,
                color: NuvoColors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Initials circle
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: NuvoColors.blue.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              abbr,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
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
class NuvoRaceLane extends StatefulWidget {
  const NuvoRaceLane({
    super.key,
    required this.progressPercent,
    this.onDark = false,
    this.trackHeight = 3.0,
    this.dotDiameter = 12.0,
    this.delay = Duration.zero,
  });

  final int progressPercent;
  final bool onDark;
  final double trackHeight;
  final double dotDiameter;

  /// Delay before the fill starts animating from 0, so a stack of race
  /// cards can stagger their bars the same way the design stipulates.
  final Duration delay;

  @override
  State<NuvoRaceLane> createState() => _NuvoRaceLaneState();
}

class _NuvoRaceLaneState extends State<NuvoRaceLane> {
  double _target = 0;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _target = (widget.progressPercent / 100).clamp(0.0, 1.0);
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) {
          setState(() => _target = (widget.progressPercent / 100).clamp(0.0, 1.0));
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant NuvoRaceLane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progressPercent != widget.progressPercent) {
      _target = (widget.progressPercent / 100).clamp(0.0, 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trackHeight = widget.trackHeight;
    final dotDiameter = widget.dotDiameter;
    final trackColor = widget.onDark
        ? Colors.white.withValues(alpha: 0.18)
        : NuvoColors.trackBg;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: _target),
          duration: const Duration(milliseconds: 1100),
          curve: Curves.easeOut,
          builder: (context, progress, _) {
            final fillWidth = (totalWidth * progress).clamp(0.0, totalWidth);
            final fillBar = Container(
              width: fillWidth,
              height: trackHeight,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: progress >= 1
                      ? const [NuvoColors.success, NuvoColors.aqua]
                      : const [NuvoColors.blueInk, NuvoColors.blue2],
                ),
                borderRadius: BorderRadius.circular(trackHeight / 2),
              ),
            );

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
                    Shimmer.fromColors(
                      baseColor: NuvoColors.blue,
                      highlightColor: Colors.white.withValues(alpha: 0.55),
                      period: const Duration(milliseconds: 2600),
                      loop: 3,
                      child: fillBar,
                    ),
                  if (progress > 0 && progress < 1)
                    Positioned(
                      left: (fillWidth - dotDiameter / 2).clamp(
                        0.0,
                        totalWidth - dotDiameter,
                      ),
                      child: Container(
                        width: dotDiameter,
                        height: dotDiameter,
                        decoration: BoxDecoration(
                          color: NuvoColors.blue,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: NuvoColors.blue.withValues(alpha: 0.25),
                              blurRadius: 10,
                            ),
                          ],
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
              border: Border.all(
                color: NuvoColors.blue.withValues(alpha: 0.50),
                width: 1.5,
              ),
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
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: isCurrentUser
                  ? NuvoColors.blue
                  : NuvoColors.border,
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
