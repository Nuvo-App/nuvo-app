import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../tokens.dart';
import 'v13_button.dart';

/// Screen header — title on the left at 26/800, trailing actions on the
/// right (icon buttons, avatars, the one blue action).
class V13TopBar extends StatelessWidget {
  const V13TopBar({
    super.key,
    required this.title,
    this.trailing = const [],
    this.padding,
  });

  final String title;

  /// Trailing widgets rendered left-to-right with 12 px gaps.
  final List<Widget> trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          padding ??
          const EdgeInsets.fromLTRB(
            V13.pagePad,
            V13.gapMd,
            V13.pagePad,
            V13.gapSm,
          ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: V13.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          for (final w in trailing) ...[const SizedBox(width: V13.gapMd), w],
        ],
      ),
    );
  }
}

/// Pushed-screen header — outlined back button, section-head title,
/// optional trailing actions (the 3-dot menu lives here).
class V13BackBar extends StatelessWidget {
  const V13BackBar({
    super.key,
    required this.title,
    this.trailing = const [],
    this.onBack,
    this.fallback = '/arena',
    this.padding,
  });

  final String title;
  final List<Widget> trailing;

  /// Defaults to pop, falling back to [fallback] when nothing can pop.
  final VoidCallback? onBack;

  /// Where back lands if this screen is somehow the route root.
  final String fallback;
  final EdgeInsetsGeometry? padding;

  void _back(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      GoRouter.maybeOf(context)?.go(fallback);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          padding ??
          const EdgeInsets.fromLTRB(
            V13.gapMd,
            V13.gapSm,
            V13.pagePad,
            V13.gapSm,
          ),
      child: Row(
        children: [
          V13IconButton(
            icon: Icons.arrow_back,
            shape: V13IconButtonShape.square,
            onTap: onBack ?? () => _back(context),
            semanticLabel: 'Back',
          ),
          const SizedBox(width: V13.gapMd),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: V13.sectionHead,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          for (final w in trailing) ...[const SizedBox(width: V13.gapMd), w],
        ],
      ),
    );
  }
}
