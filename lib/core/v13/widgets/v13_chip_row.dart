import 'package:flutter/material.dart';

/// One horizontally scrolling row of chips/pills. Never wraps; keeps room
/// for the 2px outline and the 3px hard shadow inside the scroll clip, and
/// fades the left/right edges softly instead of hard-cutting chips that run
/// off screen. iOS bounce physics like every other scroller.
class V13ChipRow extends StatelessWidget {
  const V13ChipRow({
    super.key,
    required this.children,
    this.spacing = 8,
    this.fade = 16,
  });

  final List<Widget> children;
  final double spacing;
  final double fade;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final f = (fade / rect.width).clamp(0.0, 0.5);
        return LinearGradient(
          colors: const [
            Color(0x00000000),
            Color(0xFF000000),
            Color(0xFF000000),
            Color(0x00000000),
          ],
          stops: [0, f, 1 - f, 1],
        ).createShader(rect);
      },
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        // Inner padding keeps outline + hard shadow inside the clip, and lets
        // the first/last chip start clear of the fade.
        padding: EdgeInsets.fromLTRB(fade / 2, 3, fade, 7),
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: spacing),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}
