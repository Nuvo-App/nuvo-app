import 'package:flutter/material.dart';

/// A thin translucent strip pinned to the left screen edge that turns a
/// rightward drag into [onBack] — the in-flow equivalent of the iOS
/// interactive pop gesture for routes whose [PopScope] deliberately vetoes
/// the pop. `canPop: false` disables the native route gesture entirely, so
/// without this the edge swipe would be dead on deeper flow steps.
///
/// Hit-testing is translucent: taps fall through to whatever sits beneath
/// the strip, and horizontal recognizers inside real content still win
/// their own drags.
class NuvoEdgeBackSwipe extends StatefulWidget {
  const NuvoEdgeBackSwipe({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<NuvoEdgeBackSwipe> createState() => _NuvoEdgeBackSwipeState();
}

class _NuvoEdgeBackSwipeState extends State<NuvoEdgeBackSwipe> {
  double _distance = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _distance = 0,
      onHorizontalDragUpdate: (d) => _distance += d.delta.dx,
      onHorizontalDragEnd: (d) {
        // A committed swipe reads as either real rightward travel or a
        // rightward flick; leftward and taps never reach here as a back.
        if (_distance > 48 || (d.primaryVelocity ?? 0) > 300) {
          widget.onBack();
        }
        _distance = 0;
      },
      onHorizontalDragCancel: () => _distance = 0,
    );
  }
}
