import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../tokens.dart';

/// Loading placeholder box — shimmer sweep over a divider-colored block.
/// Compose a few of these where real content will land.
class V13Skeleton extends StatelessWidget {
  const V13Skeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 8,
    this.shape = BoxShape.rectangle,
  }) : _isScreen = false;

  /// Text-line style box.
  const V13Skeleton.line({super.key, this.width, this.height = 14})
    : radius = 7,
      shape = BoxShape.rectangle,
      _isScreen = false;

  /// Card-style block.
  const V13Skeleton.box({
    super.key,
    required this.width,
    required this.height,
    this.radius = V13.radiusCard,
  }) : shape = BoxShape.rectangle,
       _isScreen = false;

  /// Circle placeholder (faces, medal slots).
  const V13Skeleton.circle({super.key, required double size})
    : width = size,
      height = size,
      radius = 0,
      shape = BoxShape.circle,
      _isScreen = false;

  /// A generic loading block for [V13AsyncView]: title line + two content
  /// blocks that roughly match a card + rows layout.
  const V13Skeleton.screen({super.key})
    : width = null,
      height = 0,
      radius = 0,
      shape = BoxShape.rectangle,
      _isScreen = true;

  final double? width;
  final double height;
  final double radius;
  final BoxShape shape;
  final bool _isScreen;

  @override
  Widget build(BuildContext context) {
    if (_isScreen) return const _ScreenSkeleton();
    return Shimmer.fromColors(
      baseColor: V13.divider,
      highlightColor: V13.card,
      enabled: !MediaQuery.disableAnimationsOf(context),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: V13.divider,
          borderRadius: shape == BoxShape.circle
              ? null
              : BorderRadius.circular(radius),
          shape: shape,
        ),
      ),
    );
  }
}

class _ScreenSkeleton extends StatelessWidget {
  const _ScreenSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(V13.pagePad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          V13Skeleton.line(width: 160, height: 26),
          SizedBox(height: V13.gapXl),
          V13Skeleton.box(width: double.infinity, height: 160),
          SizedBox(height: V13.gapXl),
          V13Skeleton.line(width: 120),
          SizedBox(height: V13.gapMd),
          V13Skeleton.line(width: double.infinity),
          SizedBox(height: V13.gapMd),
          V13Skeleton.line(width: double.infinity),
          SizedBox(height: V13.gapMd),
          V13Skeleton.line(width: 220),
        ],
      ),
    );
  }
}
