import 'package:flutter/material.dart';

import '../tokens.dart';
import 'v13_face.dart';
import 'v13_pressable.dart';

/// Avatar inside a blue XP progress ring — the Arena header's level meter.
/// There is no separate level bar: the ring IS the progress readout.
class V13XpRing extends StatelessWidget {
  const V13XpRing({
    super.key,
    required this.progress,
    this.photoUrl,
    this.size = 44,
    this.strokeWidth = 4,
    this.onTap,
    this.name,
    this.semanticLabel,
    this.emptyFill,
    this.trackColor = V13.divider,
  });

  /// XP to next level, 0.0–1.0 (clamped).
  final double progress;
  final String? photoUrl;
  final double size;
  final double strokeWidth;
  final VoidCallback? onTap;
  final String? name;
  final String? semanticLabel;

  /// Fill for the no-photo silhouette (see [V13Face.emptyFill]).
  final Color? emptyFill;

  /// The unfilled part of the ring.
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    final faceSize = size - strokeWidth * 2 - 4;
    Widget ring = SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CircularProgressIndicator(
              value: clamped,
              strokeWidth: strokeWidth,
              strokeCap: StrokeCap.round,
              backgroundColor: trackColor,
              valueColor: const AlwaysStoppedAnimation<Color>(V13.blue),
            ),
          ),
          V13Face(
            photoUrl: photoUrl,
            size: faceSize,
            name: name,
            emptyFill: emptyFill,
          ),
        ],
      ),
    );

    ring = Semantics(
      label:
          semanticLabel ?? 'Level progress ${(clamped * 100).round()} percent',
      button: onTap != null,
      child: ring,
    );

    if (onTap != null) {
      return V13Pressable(
        onTap: onTap,
        pressDepth: 2,
        semanticLabel: semanticLabel ?? name,
        child: ring,
      );
    }
    return ring;
  }
}
