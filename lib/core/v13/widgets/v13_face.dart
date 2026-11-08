import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../tokens.dart';
import 'v13_pressable.dart';

/// A person in the v13 system: a real profile photo in a navy-outlined
/// circle — never initials. With no photo a neutral silhouette shows.
/// [isMe] swaps the navy ring for a blue one ("you").
class V13Face extends StatelessWidget {
  const V13Face({
    super.key,
    this.photoUrl,
    this.size = 44,
    this.isMe = false,
    this.onTap,
    this.name,
    this.semanticLabel,
  });

  final String? photoUrl;
  final double size;

  /// Blue ring — the signed-in user's own face.
  final bool isMe;
  final VoidCallback? onTap;

  /// Person's name — used for the semantics label.
  final String? name;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final ringColor = isMe ? V13.blue : V13.navy;
    final ringWidth = isMe ? V13.outlineThick : V13.outline;

    final url = photoUrl;
    Widget inner;
    if (url != null && url.isNotEmpty) {
      inner = CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        width: size,
        height: size,
        placeholder: (_, _) => const _FaceSilhouette(),
        errorWidget: (_, _, _) => const _FaceSilhouette(),
      );
    } else {
      inner = const _FaceSilhouette();
    }

    Widget face = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: V13.bg,
        border: Border.all(color: ringColor, width: ringWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: ClipOval(
        child: SizedBox.square(dimension: size, child: inner),
      ),
    );

    face = Semantics(
      image: onTap == null,
      button: onTap != null,
      label: semanticLabel ?? (name ?? 'Person'),
      child: face,
    );

    if (onTap != null) {
      return V13Pressable(
        onTap: onTap,
        pressDepth: 2,
        semanticLabel: semanticLabel ?? name,
        child: face,
      );
    }
    return face;
  }
}

/// Neutral grey person — the no-photo state. No initials, ever.
class _FaceSilhouette extends StatelessWidget {
  const _FaceSilhouette();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final s = constraints.biggest.shortestSide;
        return Center(
          child: Icon(
            Icons.person_rounded,
            size: s.isFinite ? s * 0.62 : 28,
            color: V13.muted,
          ),
        );
      },
    );
  }
}

/// Lightweight face descriptor for stacks — enough for a ring + fallback.
class V13FaceInfo {
  const V13FaceInfo({this.id, this.photoUrl, this.name, this.isMe = false});

  final String? id;
  final String? photoUrl;
  final String? name;
  final bool isMe;
}

/// Overlapping face row. Shows up to [max] faces; the remainder collapses
/// into a "+N" chip in the same outlined-circle treatment.
class V13FaceStack extends StatelessWidget {
  const V13FaceStack({
    super.key,
    required this.faces,
    this.total,
    this.max = 3,
    this.size = 32,
    this.onFaceTap,
    this.semanticLabel,
  });

  final List<V13FaceInfo> faces;

  /// Total people count — defaults to `faces.length`. Pass the real total
  /// when [faces] is only a preview slice.
  final int? total;
  final int max;
  final double size;

  /// Optional tap handler for individual faces.
  final void Function(V13FaceInfo face)? onFaceTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final count = total ?? faces.length;
    final visible = faces.length < max ? faces.length : max;
    final overflow = count - visible;
    if (visible <= 0) return const SizedBox.shrink();

    final step = size * 0.68;
    final slots = overflow > 0 ? visible + 1 : visible;
    final width = size + step * (slots - 1);

    return Semantics(
      label: semanticLabel ?? '$count people',
      child: SizedBox(
        width: width,
        height: size,
        child: Stack(
          children: [
            for (var i = 0; i < visible; i++)
              Positioned(
                left: i * step,
                child: V13Face(
                  photoUrl: faces[i].photoUrl,
                  size: size,
                  isMe: faces[i].isMe,
                  name: faces[i].name,
                  onTap: onFaceTap == null ? null : () => onFaceTap!(faces[i]),
                ),
              ),
            if (overflow > 0)
              Positioned(
                left: visible * step,
                child: Container(
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: V13.card,
                    border: Border.all(color: V13.navy, width: V13.outline),
                  ),
                  child: Text(
                    '+$overflow',
                    style: V13.label.copyWith(
                      color: V13.navy,
                      letterSpacing: 0,
                      fontSize: (size * 0.3).clamp(8.0, 12.0).toDouble(),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
