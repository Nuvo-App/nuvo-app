// v13 Crew-page widgets — header hero, leaderboard rows, recurring races,
// the crew battle card and the members grid.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:nuvo/core/v13/v13.dart';
import 'package:nuvo/features/squads/data/squad_api.dart';

/// The crew header — one colored hero: big crew-color icon tile, name,
/// "[N] members · since Mon YYYY" (when the server sends createdAt), bio.
class CrewPageHeader extends StatelessWidget {
  const CrewPageHeader({super.key, required this.crew});

  final CrewGroup crew;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String get _metaLine {
    final count =
        '${crew.memberCount} member${crew.memberCount == 1 ? '' : 's'}';
    final at = crew.createdAt;
    if (at == null) return count;
    return '$count · since ${_months[at.month - 1]} ${at.year}';
  }

  @override
  Widget build(BuildContext context) {
    final bio = crew.bio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        V13IconTile(
          icon: Icons.groups,
          color: V13.crewColor(crew.colorKey, crew.id),
          size: 76,
          radius: V13.radiusTileLg,
        ),
        const SizedBox(height: V13.gapMd),
        Text(crew.name, style: V13.title),
        const SizedBox(height: 4),
        Text(_metaLine, style: V13.caption),
        if (bio != null && bio.trim().isNotEmpty) ...[
          const SizedBox(height: V13.gapSm),
          Text(bio.trim(), style: V13.body),
        ],
      ],
    );
  }
}

/// One leaderboard row — medal circle, face, name + role tag, points. The
/// signed-in user's row is tinted blue.
class StandingRow extends StatelessWidget {
  const StandingRow({super.key, required this.standing, this.role, this.onTap});

  final CrewGroupStanding standing;

  /// 'owner' | 'admin' | 'member' — owner/admin get a tag pill.
  final String? role;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tag = switch (role) {
      'owner' => 'Owner',
      'admin' => 'Admin',
      _ => null,
    };
    final tagColor = role == 'owner' ? V13.gold : V13.sky;
    return V13Pressable(
      onTap: onTap,
      semanticLabel: standing.displayName,
      child: Container(
        decoration: standing.isYou
            ? BoxDecoration(
                color: V13.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(V13.radiusTile),
              )
            : null,
        padding: const EdgeInsets.symmetric(
          horizontal: V13.gapSm,
          vertical: V13.gapSm,
        ),
        child: Row(
          children: [
            V13MedalCircle(place: standing.rank, size: 30),
            const SizedBox(width: V13.gapMd),
            V13Face(
              photoUrl: standing.profilePhotoUrl,
              size: 38,
              name: standing.displayName,
              isMe: standing.isYou,
            ),
            const SizedBox(width: V13.gapMd),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      standing.isYou ? 'You' : standing.displayName,
                      style: V13.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (tag != null) ...[
                    const SizedBox(width: V13.gapSm),
                    V13Pill(label: tag, color: tagColor),
                  ],
                ],
              ),
            ),
            const SizedBox(width: V13.gapSm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${standing.points}', style: V13.numberSm),
                Text('pts', style: V13.caption),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One recurring-race card — icon tile, name, "Every Monday · First to 100",
/// the Live now / In N days tag, auto-join faces and the toggle.
class RecurringRaceCard extends StatelessWidget {
  const RecurringRaceCard({
    super.key,
    required this.recurring,
    required this.crewColor,
    required this.autoJoin,
    this.busy = false,
    this.onToggle,
  });

  final CrewRecurringRace recurring;
  final Color crewColor;
  final bool autoJoin;
  final bool busy;
  final ValueChanged<bool>? onToggle;

  IconData get _icon => switch (recurring.iconKey) {
    'pushups' || 'push_ups' => Icons.fitness_center,
    'steps' || 'walking' => Icons.directions_walk,
    'running' || 'run' => Icons.directions_run,
    'plank' => Icons.self_improvement,
    _ => Icons.repeat,
  };

  @override
  Widget build(BuildContext context) {
    final tag = recurring.tagLabel;
    final subtitle = [
      ?recurring.scheduleLabel,
      ?recurring.ruleLabel,
    ].join(' · ');
    return V13Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              V13IconTile(icon: _icon, color: crewColor, size: 44),
              const SizedBox(width: V13.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recurring.title,
                      style: V13.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: V13.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (tag != null) ...[
                const SizedBox(width: V13.gapSm),
                V13Pill(
                  label: tag,
                  color: recurring.isLive ? V13.blue : V13.card,
                  textColor: recurring.isLive ? V13.card : V13.navy,
                ),
              ],
            ],
          ),
          const SizedBox(height: V13.gapMd),
          Row(
            children: [
              if (recurring.autoJoinFaces.isNotEmpty) ...[
                V13FaceStack(
                  faces: [
                    for (final m in recurring.autoJoinFaces.take(3))
                      V13FaceInfo(
                        id: m.userId,
                        photoUrl: m.profilePhotoUrl,
                        name: m.displayName,
                      ),
                  ],
                  size: 22,
                ),
                const SizedBox(width: V13.gapSm),
              ],
              Expanded(child: Text('Auto-join', style: V13.caption)),
              V13Toggle(
                value: autoJoin,
                semanticLabel: 'Auto-join ${recurring.title}',
                onChanged: busy ? (_) {} : (v) => onToggle?.call(v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The crew-vs-crew battle card — renders only when the payload carries an
/// active battle; there is no empty placeholder.
class CrewBattleCard extends StatelessWidget {
  const CrewBattleCard({
    super.key,
    required this.battle,
    required this.crewName,
    required this.crewColor,
  });

  final CrewBattle battle;
  final String crewName;
  final Color crewColor;

  @override
  Widget build(BuildContext context) {
    final rival = battle.rivalName ?? 'the other crew';
    final mine = battle.myPoints;
    final theirs = battle.rivalPoints;
    final total = (mine ?? 0) + (theirs ?? 0);
    final fraction = total > 0 ? (mine ?? 0) / total : 0.5;
    final endsAt = battle.endsAt;
    return V13Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$crewName vs $rival',
            style: V13.bodyStrong,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: V13.gapMd),
          ClipRRect(
            borderRadius: BorderRadius.circular(V13.radiusPill),
            child: Container(
              height: 18,
              decoration: BoxDecoration(
                color: V13.coral,
                border: Border.all(color: V13.navy, width: V13.outline),
                borderRadius: BorderRadius.circular(V13.radiusPill),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fraction,
                child: const ColoredBox(color: V13.blue),
              ),
            ),
          ),
          const SizedBox(height: V13.gapSm),
          Row(
            children: [
              if (mine != null)
                Text('$mine', style: V13.numberSm)
              else
                const SizedBox.shrink(),
              const Spacer(),
              if (theirs != null) Text('$theirs', style: V13.numberSm),
            ],
          ),
          if (endsAt != null) ...[
            const SizedBox(height: 2),
            Text(
              'Ends ${DateFormat.EEEE().format(endsAt.toLocal())}',
              style: V13.caption,
            ),
          ],
        ],
      ),
    );
  }
}

/// One member cell in the grid — face, name, Owner/Admin tag. Tap opens the
/// profile; owners/admins long-press for member actions.
class MemberCell extends StatelessWidget {
  const MemberCell({
    super.key,
    required this.member,
    this.isMe = false,
    this.onTap,
    this.onLongPress,
  });

  final CrewMember member;
  final bool isMe;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final tag = switch (member.role) {
      'owner' => 'Owner',
      'admin' => 'Admin',
      _ => null,
    };
    final tagColor = member.isOwner ? V13.gold : V13.sky;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
      child: V13Pressable(
        onTap: onTap,
        semanticLabel: member.displayName,
        child: SizedBox(
          width: 78,
          child: Column(
            children: [
              V13Face(
                photoUrl: member.profilePhotoUrl,
                size: 56,
                name: member.displayName,
                isMe: isMe,
              ),
              const SizedBox(height: 6),
              Text(
                isMe ? 'You' : member.displayName.split(' ').first,
                style: V13.caption.copyWith(
                  color: V13.navy,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (tag != null) V13Pill(label: tag, color: tagColor),
            ],
          ),
        ),
      ),
    );
  }
}
