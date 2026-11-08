import 'package:flutter/material.dart';

import '../tokens.dart';

/// Medal circle for podium places — gold / silver / bronze fill with the
/// place number. Places beyond 3 get a neutral white circle.
class V13MedalCircle extends StatelessWidget {
  const V13MedalCircle({
    super.key,
    required this.place,
    this.size = 36,
    this.semanticLabel,
  });

  final int place;
  final double size;
  final String? semanticLabel;

  static const Map<int, Color> _fills = {
    1: V13.gold,
    2: V13.silver,
    3: V13.bronze,
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel ?? 'Place $place',
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _fills[place] ?? V13.card,
          border: Border.all(color: V13.navy, width: V13.outline),
        ),
        child: Text(
          '$place',
          style: V13.numberSm.copyWith(fontSize: size * 0.42),
        ),
      ),
    );
  }
}
