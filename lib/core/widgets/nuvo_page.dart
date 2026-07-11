import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';

// ── NuvoPage ──────────────────────────────────────────────────────────────────

/// Full-page scaffold wrapper for standalone pages (those outside the ShellRoute).
/// Shell pages use SafeArea directly inside the shell scaffold.
class NuvoPage extends StatelessWidget {
  const NuvoPage({
    super.key,
    required this.child,
    this.topBar,
    this.bottomBar,
    this.backgroundColor,
    this.resizeToAvoidBottomInset = true,
  });

  final Widget child;
  final Widget? topBar;
  final Widget? bottomBar;
  final Color? backgroundColor;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor ?? NuvoColors.page,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      body: DecoratedBox(
        decoration: BoxDecoration(color: backgroundColor ?? NuvoColors.page),
        child: Column(
          children: [
            ?topBar,
            Expanded(child: child),
            ?bottomBar,
          ],
        ),
      ),
    );
  }
}

// ── NuvoTopBar ────────────────────────────────────────────────────────────────

/// Standard app top bar — logo on left, optional trailing widget on right.
/// Does not use AppBar so it works both inside and outside ShellRoute.
class NuvoTopBar extends StatelessWidget {
  const NuvoTopBar({
    super.key,
    this.title,
    this.leading,
    this.trailing,
    this.centerTitle = false,
    this.showLogo = false,
    this.backgroundColor,
  });

  final String? title;
  final Widget? leading;
  final Widget? trailing;
  final bool centerTitle;
  final bool showLogo;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      color: backgroundColor ?? Colors.transparent,
      padding: EdgeInsets.only(top: top + 8, left: 16, right: 16, bottom: 10),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: NuvoColors.inkNavy, width: 2),
          boxShadow: AppShadows.hardShadow3,
        ),
        child: Row(
          children: [
            if (leading case final l?)
              l
            else if (showLogo)
              const _NuvoLogoMark(),
            if (centerTitle && title != null) ...[
              const Spacer(),
              Flexible(
                child: Text(
                  title!,
                  style: AppTextStyles.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
            ] else if (title != null) ...[
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
            ?trailing,
          ],
        ),
      ),
    );
  }
}

// ── _NuvoLogoMark ─────────────────────────────────────────────────────────────

class _NuvoLogoMark extends StatelessWidget {
  const _NuvoLogoMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 7, 12, 7),
      decoration: BoxDecoration(
        color: NuvoColors.navy,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: NuvoColors.navy.withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Text(
        'nuvo',
        style: AppTextStyles.brandLabel.copyWith(color: NuvoColors.white),
      ),
    );
  }
}

// ── NuvoSectionHeader ─────────────────────────────────────────────────────────

/// Section header with optional "See all" link.
class NuvoSectionHeader extends StatelessWidget {
  const NuvoSectionHeader({super.key, required this.title, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 20,
          decoration: BoxDecoration(
            color: NuvoColors.blue,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 9),
        Text(title, style: AppTextStyles.titleMedium),
        const Spacer(),
        if (onSeeAll != null)
          GestureDetector(
            onTap: onSeeAll,
            child: Text(
              'See all',
              style: AppTextStyles.labelMedium.copyWith(color: NuvoColors.blue),
            ),
          ),
      ],
    );
  }
}
