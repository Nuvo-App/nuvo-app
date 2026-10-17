import 'package:flutter/material.dart';
import 'package:nuvo/core/theme/app_colors.dart';

/// ~28pt page-colored gradient laid over the bottom edge of a scrolling body
/// so a row that continues below the fold eases out instead of being sliced.
/// Place inside a [Stack] as the last child.
class NuvoBottomFade extends StatelessWidget {
  const NuvoBottomFade({super.key, this.bottom = 0});

  final double bottom;

  @override
  Widget build(BuildContext context) {
    final page = context.themeColors.page;
    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom,
      height: 28,
      child: IgnorePointer(
        child: DecoratedBox(
          key: const ValueKey('nuvo-bottom-fade'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [page.withValues(alpha: 0), page],
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps a scrollable and lays [NuvoBottomFade] over its bottom edge only
/// while more content sits below the fold, so a row that continues past the
/// bottom eases out; a page that fits shows no fade at all.
class NuvoScrollBottomFade extends StatefulWidget {
  const NuvoScrollBottomFade({super.key, required this.child, this.bottom = 0});

  final Widget child;
  final double bottom;

  @override
  State<NuvoScrollBottomFade> createState() => _NuvoScrollBottomFadeState();
}

class _NuvoScrollBottomFadeState extends State<NuvoScrollBottomFade> {
  bool _more = false;

  bool _onMetrics(ScrollMetrics m) {
    if (m.axis != Axis.vertical) return false;
    final more = m.extentAfter > 1;
    if (more != _more && mounted) setState(() => _more = more);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (n) => _onMetrics(n.metrics),
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) => _onMetrics(n.metrics),
            child: widget.child,
          ),
        ),
        if (_more) NuvoBottomFade(bottom: widget.bottom),
      ],
    );
  }
}
