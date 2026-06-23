import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

abstract final class NuvoAvatarSizes {
  static const double xs = 24;
  static const double sm = 32;
  static const double md = 44;
  static const double lg = 56;
  static const double xl = 72;
  static const double profile = 96;
}

/// Circular avatar that shows a network photo when available, with a clean
/// initials fallback. Never shows a broken-image icon.
///
/// Priority: [localBytes] > [photoUrl] > initials fallback.
class NuvoAvatar extends StatelessWidget {
  const NuvoAvatar({
    super.key,
    required this.initials,
    required this.size,
    this.localBytes,
    this.photoUrl,
    this.onTap,
    this.bgColor,
    this.textColor,
    this.borderColor,
    this.borderWidth = 1.5,
  });

  final String initials;
  final double size;

  /// Raw bytes of a locally-picked/cropped image. Takes priority over [photoUrl].
  final Uint8List? localBytes;
  final String? photoUrl;
  final VoidCallback? onTap;
  final Color? bgColor;
  final Color? textColor;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (localBytes != null) {
      child = _circle(
        child: Image.memory(
          localBytes!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          alignment: Alignment.center,
        ),
      );
    } else {
      final url = photoUrl;
      if (url != null && url.isNotEmpty) {
        child = CachedNetworkImage(
          imageUrl: url,
          imageBuilder: (_, provider) => _circle(
            child: Image(
              image: provider,
              width: size,
              height: size,
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
          placeholder: (_, _) => _fallback(),
          errorWidget: (_, _, _) => _fallback(),
        );
      } else {
        child = _fallback();
      }
    }

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: child);
    }
    return child;
  }

  Widget _fallback() => _circle(
    child: Center(
      child: Text(
        _clamp(initials),
        style: TextStyle(
          fontSize: (size * 0.36).clamp(7.0, 20.0),
          fontWeight: FontWeight.w700,
          color: textColor ?? NuvoColors.navy,
          height: 1.0,
        ),
      ),
    ),
  );

  Widget _circle({required Widget child}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor ?? NuvoColors.navy.withValues(alpha: 0.09),
        border: borderColor != null
            ? Border.all(color: borderColor!, width: borderWidth)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: ClipOval(
        child: SizedBox.square(dimension: size, child: child),
      ),
    );
  }

  static String _clamp(String s) {
    final t = s.trim();
    return t.isEmpty ? '?' : t.substring(0, t.length.clamp(1, 2)).toUpperCase();
  }
}

/// Overlapping avatar stack — shows up to [max] avatars then a +N bubble.
class NuvoAvatarStack extends StatelessWidget {
  const NuvoAvatarStack({
    super.key,
    required this.avatars,
    required this.total,
    this.size = 36,
    this.max = 4,
    this.borderColor = NuvoColors.white,
  });

  final List<({String initials, String? photoUrl})> avatars;
  final int total;
  final double size;
  final int max;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final show = avatars.length.clamp(0, max);
    final overflow = total > max;
    // When showing overflow bubble, reserve the last slot for it
    final visibleCount = overflow ? (show - 1).clamp(0, max - 1) : show;
    final totalSlots = overflow ? visibleCount + 1 : visibleCount;

    if (totalSlots == 0) return const SizedBox.shrink();

    final overlap = (size * 0.28).clamp(8.0, 12.0);
    final stepWidth = size - overlap;
    final stackWidth = size + stepWidth * (totalSlots - 1);

    return SizedBox(
      width: stackWidth,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < visibleCount; i++)
            Positioned(
              left: i * stepWidth,
              child: NuvoAvatar(
                initials: avatars[i].initials,
                photoUrl: avatars[i].photoUrl,
                size: size,
                bgColor: NuvoColors.navy.withValues(
                  alpha: (0.75 - i * 0.12).clamp(0.2, 0.75),
                ),
                textColor: NuvoColors.white,
                borderColor: borderColor,
                borderWidth: 2,
              ),
            ),
          if (overflow)
            Positioned(
              left: visibleCount * stepWidth,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NuvoColors.trackBg,
                  border: Border.all(color: borderColor, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+${total - visibleCount}',
                  style: TextStyle(
                    fontSize: (size * 0.3).clamp(6.0, 10.0),
                    fontWeight: FontWeight.w700,
                    color: NuvoColors.navy,
                    height: 1.0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
