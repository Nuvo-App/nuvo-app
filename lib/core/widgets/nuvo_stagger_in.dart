import 'package:flutter/material.dart';

/// A small, purposeful entrance for the Nth row/item in a freshly-rendered
/// list — a light fade + rise, staggered by [index]. Respects reduced
/// motion. Each reveal should fit what it reveals: use this for feed-like
/// content that just appeared, not for static chrome.
class NuvoStaggerIn extends StatelessWidget {
  const NuvoStaggerIn({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + (index.clamp(0, 6) * 40)),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 8),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
