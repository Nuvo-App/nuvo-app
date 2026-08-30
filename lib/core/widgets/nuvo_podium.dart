import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_geometry.dart';
import '../theme/app_text_styles.dart';
import '../theme/nuvo_responsive.dart';
import 'nuvo_avatar.dart';

/// One entry on the podium / leaderboard.
class NuvoPodiumEntry {
  const NuvoPodiumEntry({
    required this.rank,
    required this.name,
    required this.statLabel,
    this.initials,
    this.photoUrl,
    this.avatarSeedId,
    this.isCurrentUser = false,
  });

  final int rank;
  final String name;

  /// The number shown under the name — "7 / 10", "40 reps", "10 days", …
  final String statLabel;
  final String? initials;
  final String? photoUrl;
  final String? avatarSeedId;
  final bool isCurrentUser;
}

/// Top-3 standings, flat. Three avatars with a small placement badge, name and
/// score — first place centred, a little larger, and raised. No pedestals, no
/// blocks, no shadows: the podium is content, not a tappable surface, so it
/// stays flat per the Nuvo depth rules. Ranks 4+ are rendered by [rest].
class NuvoPodium extends StatelessWidget {
  const NuvoPodium({super.key, required this.top, this.rest});

  /// Up to three entries. Placement is read from `.rank`, not list order.
  final List<NuvoPodiumEntry> top;
  final Widget? rest;

  NuvoPodiumEntry? _byRank(int r) {
    for (final e in top) {
      if (e.rank == r) return e;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final first = _byRank(1) ?? (top.isNotEmpty ? top.first : null);
    final second = _byRank(2);
    final third = _byRank(3);
    final s = context.nuvoScale;

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 26 * s),
                child: _Place(entry: second, place: 2),
              ),
            ),
            Expanded(child: _Place(entry: first, place: 1, raised: true)),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 26 * s),
                child: _Place(entry: third, place: 3),
              ),
            ),
          ],
        ),
        if (rest != null) ...[SizedBox(height: 22 * s), rest!],
      ],
    );
  }
}

class _Place extends StatelessWidget {
  const _Place({required this.entry, required this.place, this.raised = false});

  final NuvoPodiumEntry? entry;
  final int place;
  final bool raised;

  Color get _placeColor => switch (place) {
    1 => NuvoColors.gold,
    2 => NuvoColors.silver,
    _ => NuvoColors.bronze,
  };

  @override
  Widget build(BuildContext context) {
    final e = entry;
    if (e == null) return const SizedBox.shrink();
    final s = context.nuvoScale;
    final avatarSize = (raised ? 76.0 : 60.0) * s;
    final me = e.isCurrentUser;

    return Column(
      children: [
        SizedBox(
          width: avatarSize,
          height: avatarSize,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              NuvoAvatar(
                initials: e.initials ?? _initials(e.name),
                photoUrl: e.photoUrl,
                size: avatarSize,
                bgColor: nuvoAvatarColorFor(e.avatarSeedId ?? e.name),
                textColor: NuvoColors.white,
                borderColor: me
                    ? NuvoColors.blue
                    : (place <= 3 ? _placeColor : NuvoColors.navy),
                borderWidth: me || place == 1 ? 3 : 2,
              ),
              Positioned(
                top: -8 * s,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 22 * s,
                    height: 22 * s,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _placeColor,
                      borderRadius: BorderRadius.circular(NuvoRadii.badge),
                      border: Border.all(color: NuvoColors.navy, width: 1.5),
                    ),
                    child: Text(
                      '$place',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: NuvoColors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 11 * s,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 10 * s),
        Text(
          e.isCurrentUser ? 'You' : e.name.split(' ').first,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTextStyles.titleMedium.copyWith(
            color: NuvoColors.navy,
            fontSize: (raised ? 16 : 14) * s,
          ),
        ),
        SizedBox(height: 2 * s),
        Text(
          e.statLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTextStyles.raceRowMeta.copyWith(
            color: me
                ? NuvoColors.blue
                : (place <= 3 ? _placeColor : NuvoColors.muted),
            fontWeight: FontWeight.w800,
            fontSize: 12 * s,
          ),
        ),
      ],
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}
