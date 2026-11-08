// v13 Crew-tab widgets — crew cards, the racing-right-now strip, request
// cards, feed rows, friends' crews and the shared input sheet.
import 'package:flutter/material.dart';

import 'package:nuvo/core/utils/json_safe.dart';
import 'package:nuvo/core/v13/v13.dart';
import 'package:nuvo/features/crew/data/crew_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/domain/race_display.dart';
import 'package:nuvo/features/social/data/crew_activity_models.dart';
import 'package:nuvo/features/squads/data/squad_api.dart';
import 'package:nuvo/features/notifications/domain/notification_display.dart';

/// One "Your crews" card — crew-color icon tile, name, member line, my week
/// rank, member faces and the next recurring race. Tap opens the crew page.
class CrewGroupCard extends StatelessWidget {
  const CrewGroupCard({super.key, required this.crew, this.onTap});

  final CrewGroup crew;
  final VoidCallback? onTap;

  String get _membersLine {
    final count =
        '${crew.memberCount} member${crew.memberCount == 1 ? '' : 's'}';
    final owner = crew.ownerName ?? (crew.isOwner ? 'you' : null);
    return owner == null ? count : '$count · Run by $owner';
  }

  @override
  Widget build(BuildContext context) {
    final recurring = crew.nextRecurring;
    return V13Card(
      onTap: onTap,
      semanticLabel: crew.name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              V13IconTile(
                icon: Icons.groups,
                color: V13.crewColor(crew.colorKey, crew.id),
                size: 48,
              ),
              const SizedBox(width: V13.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      crew.name,
                      style: V13.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _membersLine,
                      style: V13.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (crew.myRankWeek != null) ...[
                const SizedBox(width: V13.gapSm),
                V13Pill(label: '#${crew.myRankWeek} this week', color: V13.sun),
              ],
            ],
          ),
          if (crew.memberPreviews.isNotEmpty) ...[
            const SizedBox(height: V13.gapMd),
            V13FaceStack(
              faces: [
                for (final m in crew.memberPreviews.take(4))
                  V13FaceInfo(
                    id: m.userId,
                    photoUrl: m.profilePhotoUrl,
                    name: m.displayName,
                  ),
              ],
              total: crew.memberCount,
              size: 26,
            ),
          ],
          if (recurring != null) ...[
            const SizedBox(height: V13.gapMd),
            Row(
              children: [
                const Icon(Icons.repeat, size: 15, color: V13.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    [recurring.title, ?recurring.tagLabel].join(' · '),
                    style: V13.caption.copyWith(color: V13.navy),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One face in the "Racing right now" strip — photo, movement badge, name and
/// the race they're in. Tap opens their profile.
class RacingFriendCell extends StatelessWidget {
  const RacingFriendCell({
    super.key,
    required this.name,
    required this.photoUrl,
    required this.race,
    this.onTap,
  });

  final String name;
  final String? photoUrl;
  final Race race;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final icon = raceActivityDefinition(race)?.icon ?? Icons.bolt;
    return V13Pressable(
      onTap: onTap,
      semanticLabel: name,
      child: SizedBox(
        width: 80,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                V13Face(photoUrl: photoUrl, size: 56, name: name),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: V13.raceColor(race.id),
                      shape: BoxShape.circle,
                      border: Border.all(color: V13.navy, width: V13.outline),
                    ),
                    child: Icon(icon, size: 11, color: V13.navy),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              name.split(' ').first,
              style: V13.caption.copyWith(
                color: V13.navy,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'Racing · ${race.displayTitle}',
              style: V13.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// The lilac friend-request card — "[Name] wants to race", the mutual line
/// when the server sends it, Accept + Decline.
class FriendRequestCard extends StatelessWidget {
  const FriendRequestCard({
    super.key,
    this.onPersonTap,
    required this.user,
    this.mutuals,
    this.busy = false,
    required this.onAccept,
    required this.onDecline,
  });

  /// Tapping the face opens that person's profile.
  final VoidCallback? onPersonTap;

  final PublicUser user;
  final CrewRequestMutuals? mutuals;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  /// "Friends with Priya and Alex" → names first, the count as fallback.
  String? get _mutualLine {
    final m = mutuals;
    if (m == null) return null;
    final names = [
      for (final n in m.names)
        if (n.trim().isNotEmpty) n.trim(),
    ];
    if (names.length >= 2) return 'Friends with ${names[0]} and ${names[1]}';
    if (names.length == 1) return 'Friends with ${names[0]}';
    if (m.count > 0) {
      return '${m.count} mutual friend${m.count == 1 ? '' : 's'}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final mutualLine = _mutualLine;
    return V13Card(
      color: V13.lilac,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              V13Face(
                photoUrl: user.profilePhotoUrl,
                size: 48,
                name: user.displayName,
                onTap: onPersonTap,
              ),
              const SizedBox(width: V13.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${user.displayName.split(' ').first} wants to race',
                      style: V13.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (mutualLine != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        mutualLine,
                        style: V13.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: V13.gapMd),
          Row(
            children: [
              Expanded(
                child: V13Button.secondary(
                  label: 'Decline',
                  size: V13ButtonSize.small,
                  onPressed: busy ? null : onDecline,
                ),
              ),
              const SizedBox(width: V13.gapMd),
              Expanded(
                flex: 2,
                child: V13Button.primary(
                  label: 'Accept',
                  size: V13ButtonSize.small,
                  loading: busy,
                  onPressed: busy ? null : onAccept,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A request I already sent — "Waiting on Sam" with a quiet Cancel.
class OutgoingRequestRow extends StatelessWidget {
  const OutgoingRequestRow({
    super.key,
    this.onPersonTap,
    required this.user,
    this.busy = false,
    required this.onCancel,
  });

  /// Tapping the face opens that person's profile.
  final VoidCallback? onPersonTap;

  final PublicUser user;
  final bool busy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return V13ListRow(
      leading: V13Face(
        photoUrl: user.profilePhotoUrl,
        size: 40,
        name: user.displayName,
        onTap: onPersonTap,
      ),
      title: 'Waiting on ${user.displayName.split(' ').first}',
      subtitle: 'Request sent',
      trailing: V13Button.ghost(
        label: 'Cancel',
        size: V13ButtonSize.small,
        loading: busy,
        onPressed: busy ? null : onCancel,
      ),
      showDivider: false,
    );
  }
}

/// The feed kind badge's look — the small circle pinned on the actor's photo.
class FeedKindBadge {
  const FeedKindBadge(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;
}

/// Maps a feed item to its kind badge — logged / earned a badge / passed you
/// / won / live. Returns null for types that carry no badge.
FeedKindBadge? feedKindBadge(CrewActivityItem item, String myId) {
  switch (item.type) {
    case 'race_live':
      return const FeedKindBadge('Live', V13.coral, Icons.play_arrow);
    case 'badge_earned':
      return const FeedKindBadge(
        'Earned a badge',
        V13.gold,
        Icons.emoji_events,
      );
    case 'winner_determined':
      return const FeedKindBadge('Won', V13.gold, Icons.emoji_events);
    case 'personal_best':
      return const FeedKindBadge('New best', V13.sun, Icons.star);
    case 'rank_changed':
    case 'lead_changed':
      final payload = item.payload;
      final displaced = payload['displacedUserId'] == myId;
      final overtaken = payload['overtakenUserIds'];
      final passedMe =
          displaced || (overtaken is List && overtaken.contains(myId));
      if (passedMe) {
        return const FeedKindBadge('Passed you', V13.coral, Icons.trending_up);
      }
      return const FeedKindBadge('Moved up', V13.mint, Icons.trending_up);
    case 'progress_accepted':
    case 'attempt_completed':
    case 'proof_submitted':
    case 'move_logged':
      return const FeedKindBadge('Logged', V13.sky, Icons.check);
    default:
      return null;
  }
}

/// The logged value behind a "big number chip" — the payload's score/value/
/// delta when the server sends one. Null means the chip hides.
int? feedLogValue(CrewActivityItem item) =>
    jInt(item.payload['score']) ??
    jInt(item.payload['value']) ??
    jInt(item.payload['delta']) ??
    jInt(item.payload['amount']);

/// One feed row — photo + kind badge, headline, race-color dot + time, big
/// number chip for logs and the flame cheer toggle.
class FeedItemRow extends StatelessWidget {
  const FeedItemRow({
    super.key,
    this.onPersonTap,
    required this.item,
    this.myId = '',
    this.reactBusy = false,
    this.onTap,
    this.onCheer,
  });

  /// Tapping the face opens that person's profile.
  final VoidCallback? onPersonTap;

  final CrewActivityItem item;
  final String myId;
  final bool reactBusy;
  final VoidCallback? onTap;
  final VoidCallback? onCheer;

  @override
  Widget build(BuildContext context) {
    final badge = feedKindBadge(item, myId);
    final live = item.live;
    final value = live == null ? feedLogValue(item) : null;
    final cheerCount = item.reactions['fire'] ?? 0;
    final cheered = item.myReaction == 'fire';
    final headline = live?.title ?? item.headline;
    final raceColor = item.raceId != null
        ? V13.raceColor(item.raceId!)
        : V13.divider;

    return V13Pressable(
      onTap: onTap,
      semanticLabel: headline,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: V13.gapMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    V13Face(
                      photoUrl: item.actor?.profilePhotoUrl,
                      size: 44,
                      name: item.actor?.displayName,
                      onTap: onPersonTap,
                    ),
                    if (badge != null)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: badge.color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: V13.navy,
                              width: V13.outline,
                            ),
                          ),
                          child: Icon(badge.icon, size: 10, color: V13.navy),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: V13.gapMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headline,
                        style: V13.bodyStrong,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: raceColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: V13.navy, width: 1),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              [
                                ?item.raceTitle,
                                notificationRelativeTime(item.occurredAt),
                              ].join(' · '),
                              style: V13.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: V13.gapSm),
                  V13Pill(label: '+$value', color: V13.sun),
                ],
              ],
            ),
            if (item.isReactionable && onCheer != null) ...[
              const SizedBox(height: V13.gapSm),
              Padding(
                padding: const EdgeInsets.only(left: 56),
                child: _CheerChip(
                  cheered: cheered,
                  count: cheerCount,
                  busy: reactBusy,
                  onTap: onCheer,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The flame cheer toggle — bare text when idle, a mint chip when it's mine.
class _CheerChip extends StatelessWidget {
  const _CheerChip({
    required this.cheered,
    required this.count,
    required this.busy,
    this.onTap,
  });

  final bool cheered;
  final int count;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return V13Pressable(
      onTap: busy ? null : onTap,
      enabled: !busy && onTap != null,
      semanticLabel: cheered ? 'Cheered' : 'Cheer',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutBack,
        padding: EdgeInsets.symmetric(
          horizontal: cheered ? 10 : 6,
          vertical: cheered ? 4 : 3,
        ),
        decoration: cheered
            ? BoxDecoration(
                color: V13.mint,
                borderRadius: BorderRadius.circular(V13.radiusPill),
                border: Border.all(color: V13.navy, width: V13.outline),
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_fire_department_rounded,
              size: 16,
              color: cheered ? V13.coral : V13.muted,
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: V13.caption.copyWith(
                  color: V13.navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            if (cheered) ...[
              const SizedBox(width: 4),
              Text(
                'Cheered',
                style: V13.caption.copyWith(
                  color: V13.navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One "your friends' crews" row — icon tile, name, faces, "X's crew · N
/// members" and the Ask to join / Requested action.
class DiscoverCrewRow extends StatelessWidget {
  const DiscoverCrewRow({
    super.key,
    required this.crew,
    this.requested = false,
    this.busy = false,
    this.onTap,
    this.onAskToJoin,
  });

  final CrewDiscoverItem crew;
  final bool requested;
  final bool busy;
  final VoidCallback? onTap;
  final VoidCallback? onAskToJoin;

  @override
  Widget build(BuildContext context) {
    final owner = crew.ownerName;
    final subtitle = [
      if (owner != null && owner.isNotEmpty) "$owner's crew",
      '${crew.memberCount} member${crew.memberCount == 1 ? '' : 's'}',
    ].join(' · ');
    return V13Pressable(
      onTap: onTap,
      semanticLabel: crew.name,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: V13.gapMd),
        child: Row(
          children: [
            V13IconTile(
              icon: Icons.groups,
              color: V13.crewColor(crew.colorKey, crew.id),
              size: 44,
            ),
            const SizedBox(width: V13.gapMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    crew.name,
                    style: V13.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (crew.memberPreviews.isNotEmpty) ...[
                        V13FaceStack(
                          faces: [
                            for (final m in crew.memberPreviews.take(3))
                              V13FaceInfo(
                                id: m.userId,
                                photoUrl: m.profilePhotoUrl,
                                name: m.displayName,
                              ),
                          ],
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          subtitle,
                          style: V13.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: V13.gapSm),
            if (requested)
              const V13Pill(label: 'Requested', color: V13.lilac)
            else
              V13Button.secondary(
                label: 'Ask to join',
                size: V13ButtonSize.small,
                loading: busy,
                onPressed: busy ? null : onAskToJoin,
              ),
          ],
        ),
      ),
    );
  }
}

/// A small inline error row for a single section — message + Retry.
class CrewSectionError extends StatelessWidget {
  const CrewSectionError({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: V13.gapSm),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 20, color: V13.muted),
          const SizedBox(width: V13.gapSm),
          Expanded(child: Text(message, style: V13.caption)),
          if (onRetry != null)
            V13Button.ghost(
              label: 'Retry',
              size: V13ButtonSize.small,
              onPressed: onRetry,
            ),
        ],
      ),
    );
  }
}

/// The shared "name a thing" input sheet — crew name or join code. The sheet
/// keeps its own busy/error state; [onSubmit] returns an error string to
/// show, or null to close (the screen then does the navigation/reward).
class CrewInputSheet extends StatefulWidget {
  const CrewInputSheet({
    super.key,
    required this.title,
    required this.hint,
    required this.buttonLabel,
    required this.onSubmit,
    this.upperCase = false,
    this.keyboardType,
  });

  final String title;
  final String hint;
  final String buttonLabel;

  /// Runs the mutation; returns null on success or the error text to show.
  final Future<String?> Function(String value) onSubmit;

  /// Join codes are all caps.
  final bool upperCase;
  final TextInputType? keyboardType;

  @override
  State<CrewInputSheet> createState() => _CrewInputSheetState();
}

class _CrewInputSheetState extends State<CrewInputSheet> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _controller.text.trim();
    if (value.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSubmit(
      widget.upperCase ? value.toUpperCase() : value,
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V13.pagePad,
        V13.gapMd,
        V13.pagePad,
        V13.gapXl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: V13.sectionHead),
          const SizedBox(height: V13.gapLg),
          Container(
            decoration: BoxDecoration(
              color: V13.card,
              borderRadius: BorderRadius.circular(V13.radiusButton),
              border: Border.all(color: V13.navy, width: V13.outline),
            ),
            padding: const EdgeInsets.symmetric(horizontal: V13.gapLg),
            child: TextField(
              controller: _controller,
              enabled: !_busy,
              autofocus: true,
              keyboardType: widget.keyboardType,
              textCapitalization: widget.upperCase
                  ? TextCapitalization.characters
                  : TextCapitalization.words,
              style: V13.bodyStrong,
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: V13.body.copyWith(color: V13.muted),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: V13.gapSm),
            Text(_error!, style: V13.caption.copyWith(color: V13.danger)),
          ],
          const SizedBox(height: V13.gapLg),
          V13Button.primary(
            label: widget.buttonLabel,
            fullWidth: true,
            loading: _busy,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
