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

/// Deterministic flat avatar color per person, picked from the muted
/// avatar palette — never a gradient, never generic.
Color nuvoAvatarColorFor(String id) {
  if (id.isEmpty) return NuvoColors.avatarPalette.first;
  final hash = id.codeUnits.fold<int>(0, (acc, c) => acc + c);
  return NuvoColors.avatarPalette[hash % NuvoColors.avatarPalette.length];
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

enum NuvoCompetitorAvatarRole { standard, currentUser, leader }

/// Competition-specific avatar treatment built on top of [NuvoAvatar].
///
/// Keeps the existing image loading and fallback behavior intact while adding
/// the restrained outlines used in race tracks and leaderboards.
class NuvoCompetitorAvatar extends StatelessWidget {
  const NuvoCompetitorAvatar({
    super.key,
    required this.initials,
    required this.id,
    this.photoUrl,
    this.size = NuvoAvatarSizes.sm,
    this.role = NuvoCompetitorAvatarRole.standard,
    this.showStatus = false,
  });

  final String initials;
  final String id;
  final String? photoUrl;
  final double size;
  final NuvoCompetitorAvatarRole role;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final borderColor = switch (role) {
      NuvoCompetitorAvatarRole.currentUser => NuvoColors.blue,
      NuvoCompetitorAvatarRole.leader => NuvoColors.gold.withValues(
        alpha: 0.86,
      ),
      NuvoCompetitorAvatarRole.standard => NuvoColors.white,
    };
    final borderWidth = role == NuvoCompetitorAvatarRole.currentUser
        ? 3.0
        : 2.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        NuvoAvatar(
          initials: initials,
          size: size,
          photoUrl: photoUrl,
          bgColor: nuvoAvatarColorFor(id),
          textColor: NuvoColors.white,
          borderColor: borderColor,
          borderWidth: borderWidth,
        ),
        if (showStatus)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: (size * 0.22).clamp(7.0, 10.0),
              height: (size * 0.22).clamp(7.0, 10.0),
              decoration: BoxDecoration(
                color: NuvoColors.blue,
                shape: BoxShape.circle,
                border: Border.all(color: NuvoColors.white, width: 1.5),
              ),
            ),
          ),
      ],
    );
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
