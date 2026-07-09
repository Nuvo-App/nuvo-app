import 'package:flutter/material.dart';

import '../theme/app_text_styles.dart';

/// Animates an integer value from 0 to [value] over [duration].
/// Keeps layout stable by measuring the maximum width of the target string
/// and using a fixed min width.
class CountUpText extends StatefulWidget {
  const CountUpText({
    super.key,
    required this.value,
    this.prefix = '',
    this.suffix = '',
    this.style,
    this.duration = const Duration(milliseconds: 600),
    this.curve = Curves.easeOutCubic,
  });

  final int value;
  final String prefix;
  final String suffix;
  final TextStyle? style;
  final Duration duration;
  final Curve curve;

  @override
  State<CountUpText> createState() => _CountUpTextState();
}

class _CountUpTextState extends State<CountUpText>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<int> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _anim = IntTween(begin: 0, end: widget.value)
        .chain(CurveTween(curve: widget.curve))
        .animate(_ctrl);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(covariant CountUpText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _anim = IntTween(
        begin: _anim.value.clamp(0, widget.value),
        end: widget.value,
      ).chain(CurveTween(curve: widget.curve)).animate(_ctrl);
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? AppTextStyles.labelSmall;

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        return Text(
          '${widget.prefix}${_anim.value}${widget.suffix}',
          style: style,
        );
      },
    );
  }
}
