// Crew social-activity models — the typed item shape GET /crew/feed serves
// (docs/agents/21-race-system-v2-design.md §18).
//
// Item `type` carries the canonical domain event name (race_events
// `event_type`: race_created / lead_changed / participant_finished / ...) or
// a crew notification category while crew events lack their own log.
// Nuvo-language headlines are composed here, in the app — the server stays
// copy-free for event rows (§14: copy lives client-side).
import '../domain/nuvo_destination.dart';
import 'package:nuvo/core/utils/json_safe.dart';

/// The shipped reaction set. Wire codes, not emoji — the UI owns the glyphs.
const kReactionEmojis = ['fire', 'clap', 'muscle'];
const kReactionGlyphs = {'fire': '🔥', 'clap': '👏', 'muscle': '💪'};

class CrewActivityActor {
  const CrewActivityActor({
    required this.id,
    required this.displayName,
    this.profilePhotoUrl,
  });

  final String id;
  final String displayName;
  final String? profilePhotoUrl;
}

/// Canonical live-race presentation contract (Race V2 §18 `race_live` items).
/// Crew renders this; it never computes live truth itself — the payload is
/// produced by the race system.
class CrewLiveRace {
  const CrewLiveRace({
    required this.title,
    required this.participants,
    this.endsAt,
  });

  final String title;
  final List<CrewLiveParticipant> participants;
  final DateTime? endsAt;

  factory CrewLiveRace.fromJson(Map<String, dynamic> j) => CrewLiveRace(
        title: jStr(j['title']) ?? 'Live race',
        endsAt: DateTime.tryParse(jStr(j['endsAt']) ?? ''),
        participants: jMapList(j['participants']).map(CrewLiveParticipant.fromJson)
            .toList(),
      );
}

class CrewLiveParticipant {
  const CrewLiveParticipant({
    required this.name,
    required this.score,
    this.rank,
    this.isMe = false,
    this.isCrew = false,
  });

  final String name;
  final int score;
  final int? rank;
  final bool isMe;
  final bool isCrew;

  factory CrewLiveParticipant.fromJson(Map<String, dynamic> j) =>
      CrewLiveParticipant(
        name: jStr(j['name']) ?? 'Racer',
        score: jInt(j['score']) ?? 0,
        rank: jInt(j['rank']),
        isMe: jBool(j['isMe']) ?? false,
        isCrew: jBool(j['isCrew']) ?? false,
      );
}

class CrewActivityItem {
  const CrewActivityItem({
    required this.id,
    required this.type,
    required this.occurredAt,
    this.actor,
    this.raceId,
    this.raceTitle,
    this.title,
    this.summary,
    this.payload = const {},
    this.entityType,
    this.entityId,
    this.destination,
    this.read = true,
    this.reactions = const {},
    this.myReaction,
  });

  final String id;

  /// Canonical domain event name (race_events `event_type`) or a crew
  /// notification category while crew events lack their own log.
  final String type;
  final DateTime occurredAt;
  final CrewActivityActor? actor;
  final String? raceId;
  final String? raceTitle;
  final String? title;
  final String? summary;

  /// Structured event payload — scores, ranks, gaps — straight from
  /// race_events.payload_json. Copy is composed from it, never parsed out
  /// of strings.
  final Map<String, dynamic> payload;
  final String? entityType;
  final String? entityId;
  final NuvoDestination? destination;
  final bool read;

  /// Aggregate counts keyed by wire emoji code ('fire'|'clap'|'muscle').
  final Map<String, int> reactions;
  final String? myReaction;

  bool get isReactionable => entityType != null && entityId != null;

  /// 'For you' — the event's subject or effect lands on [myId]: my own
  /// actions, someone passing me, taking my lead, or a result naming me.
  /// Derived from the canonical payload — `subject_user_id` is a feed column
  /// the item shape doesn't expose, but the payload keys carry the same
  /// truth for every event type that can involve the viewer.
  bool involvesUser(String myId) {
    if (myId.isEmpty) return false;
    if (actor?.id == myId) return true;
    if (payload['userId'] == myId ||
        payload['winnerUserId'] == myId ||
        payload['displacedUserId'] == myId) {
      return true;
    }
    final overtaken = payload['overtakenUserIds'];
    return overtaken is List && overtaken.contains(myId);
  }

  /// The canonical live presentation hook: a `race_live` item carries its
  /// full spectator payload and renders as a LIVE card instead of a row.
  CrewLiveRace? get live {
    if (type != 'race_live') return null;
    final raw = payload['live'] ?? payload;
    return raw is Map<String, dynamic> ? CrewLiveRace.fromJson(raw) : null;
  }

  /// Headline-ready copy, composed client-side from the canonical event
  /// type + structured payload. Notification-sourced items already carry
  /// server copy in [title].
  String get headline {
    if (title != null && title!.isNotEmpty) return title!;
    final who = actor?.displayName.split(' ').first ?? 'Someone';
    final race = raceTitle ?? 'a race';
    switch (type) {
      case 'race_created':
        return '$who started $race';
      case 'race_joined':
        return '$who joined $race';
      case 'race_started':
        return '$race is on';
      case 'progress_accepted':
        return '$who submitted proof in $race';
      case 'rank_changed':
        final rank = jInt(payload['newRank']);
        return rank != null
            ? '$who moved to #$rank in $race'
            : '$who moved up in $race';
      case 'lead_changed':
        return '$who took the lead in $race';
      case 'attempt_started':
        return '$who started an attempt in $race';
      case 'attempt_completed':
        final score = jInt(payload['score']);
        return score != null
            ? '$who locked in $score in $race'
            : '$who finished an attempt in $race';
      case 'participant_finished':
        return '$who finished $race';
      case 'race_finished':
        return '$race is finished';
      case 'winner_determined':
        return '$who won $race';
      case 'personal_best':
        return '$who set a new best in $race';
      case 'rematch_requested':
        return '$who called a rematch in $race';
      default:
        return summary ?? '$who in $race';
    }
  }

  CrewActivityItem copyWith({
    bool? read,
    Map<String, int>? reactions,
    String? Function()? myReaction,
  }) =>
      CrewActivityItem(
        id: id,
        type: type,
        occurredAt: occurredAt,
        actor: actor,
        raceId: raceId,
        raceTitle: raceTitle,
        title: title,
        summary: summary,
        payload: payload,
        entityType: entityType,
        entityId: entityId,
        destination: destination,
        read: read ?? this.read,
        reactions: reactions ?? this.reactions,
        myReaction: myReaction != null ? myReaction() : this.myReaction,
      );

  factory CrewActivityItem.fromJson(Map<String, dynamic> j) {
    final actor = j['actor'] as Map<String, dynamic>?;
    final reactions = <String, int>{};
    if (j['reactions'] is Map) {
      for (final e in (j['reactions'] as Map).entries) {
        final n = (e.value as num?)?.toInt() ?? 0;
        if (n > 0) reactions[e.key.toString()] = n;
      }
    }
    return CrewActivityItem(
      id: jStr(j['id']) ?? '',
      type: jStr(j['type']) ?? 'unknown',
      occurredAt:
          DateTime.tryParse(jStr(j['occurredAt']) ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
      actor: actor == null
          ? null
          : CrewActivityActor(
              id: jStr(actor['id']) ?? '',
              displayName: jStr(actor['displayName']) ?? 'Nuvo member',
              profilePhotoUrl: jStr(actor['profilePhotoUrl']),
            ),
      raceId: jStr(j['raceId']),
      raceTitle: jStr(j['raceTitle']),
      title: jStr(j['title']),
      summary: jStr(j['summary']),
      payload: j['payload'] is Map
          ? Map<String, dynamic>.from(j['payload'] as Map)
          : const {},
      entityType: jStr(j['entityType']),
      entityId: jStr(j['entityId']),
      destination: NuvoDestination.fromDescriptor(
        j['destination'] as Map<String, dynamic>?,
      ),
      read: jBool(j['read']) ?? true,
      reactions: reactions,
      myReaction: jStr(j['myReaction']),
    );
  }
}

/// Reaction summary returned by POST/DELETE /reactions.
class ReactionSummary {
  const ReactionSummary({required this.counts, this.myReaction});
  final Map<String, int> counts;
  final String? myReaction;
}
