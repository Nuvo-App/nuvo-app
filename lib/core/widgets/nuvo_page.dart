import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

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
      body: Column(
        children: [
          ?topBar,
          Expanded(child: child),
          ?bottomBar,
        ],
      ),
    );
  }
}

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
      color: backgroundColor ?? NuvoColors.white,
      padding: EdgeInsets.only(top: top, left: 20, right: 20, bottom: 12),
      child: Row(
        children: [
          if (leading case final l?)
            l
          else if (showLogo)
            Text(
              'nuvo',
              style: AppTextStyles.titleLarge.copyWith(
                color: NuvoColors.blue,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          if (centerTitle && title != null) ...[
            const Spacer(),
            Text(title!, style: AppTextStyles.titleLarge),
            const Spacer(),
          ] else if (title != null) ...[
            const SizedBox(width: 12),
            Text(title!, style: AppTextStyles.titleLarge),
            const Spacer(),
          ] else
            const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// Section header with optional "See all" link.
class NuvoSectionHeader extends StatelessWidget {
  const NuvoSectionHeader({super.key, required this.title, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
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
