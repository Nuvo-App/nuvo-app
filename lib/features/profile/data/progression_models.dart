/// Nuvo progression — server-owned persistent meta-game projected from
/// canonical race events. The client never computes XP, level, or
/// achievement progress itself; it renders what the Worker returns.
library;

import 'package:nuvo/core/utils/json_safe.dart';

class NuvoUnlockRef {
  const NuvoUnlockRef({
    required this.unlockId,
    required this.level,
    required this.type,
    required this.key,
    required this.name,
    this.description,
    this.metadata,
  });

  final String unlockId;
  final int level;
  final String type;
  final String key;
  final String name;
  final String? description;
  final Map<String, dynamic>? metadata;

  factory NuvoUnlockRef.fromJson(Map<String, dynamic> json) => NuvoUnlockRef(
        unlockId: (jStr(json['unlockId']) ?? ''),
        level: jInt(json['level']) ?? 0,
        type: jStr(json['type']) ?? 'badge',
        key: jStr(json['key']) ?? '',
        name: jStr(json['name']) ?? '',
        description: jStr(json['description']),
        metadata: json['metadata'] is Map<String, dynamic>
            ? json['metadata'] as Map<String, dynamic>
            : null,
      );
}

class NuvoBadge {
  const NuvoBadge({
    required this.unlockId,
    required this.type,
    required this.key,
    required this.name,
    this.description,
    required this.requiredLevel,
    this.metadata,
    required this.unlocked,
    this.unlockedAt,
    required this.featured,
    this.position,
    this.category,
    this.iconKey,
    this.statKey,
    this.threshold,
    this.progressValue = 0,
  });

  final String unlockId;
  final String type;
  final String key;
  final String name;
  final String? description;
  final int requiredLevel;
  final Map<String, dynamic>? metadata;
  final bool unlocked;
  final String? unlockedAt;
  final bool featured;
  final int? position;

  /// Collection section (racing / winning / creation / performance /
  /// social / variety / motion / proof / category / level).
  final String? category;

  /// Server-declared glyph key — mapped to Nuvo icons by the presentation
  /// layer, never stored as client art on the server.
  final String? iconKey;

  /// Canonical stat the threshold reads (stat achievements only).
  final String? statKey;

  /// Goal for stat achievements; level requirement for level milestones.
  final int? threshold;

  /// Live canonical progress toward a locked stat achievement.
  final int progressValue;

  bool get isAchievement => type == 'achievement';
  bool get isMilestone =>
      metadata?['rarity'] == 'milestone' || metadata?['rarity'] == 'legendary';

  /// Fill fraction for a locked achievement's progress track (0 when the
  /// goal isn't countable, e.g. level milestones).
  double get goalProgress {
    final t = threshold;
    if (t == null || t <= 0) return 0;
    return (progressValue / t).clamp(0, 1);
  }

  factory NuvoBadge.fromJson(Map<String, dynamic> json) => NuvoBadge(
        unlockId: (jStr(json['unlockId']) ?? ''),
        type: jStr(json['type']) ?? 'badge',
        key: jStr(json['key']) ?? '',
        name: jStr(json['name']) ?? '',
        description: jStr(json['description']),
        requiredLevel: jInt(json['requiredLevel']) ?? 0,
        metadata: json['metadata'] is Map<String, dynamic>
            ? json['metadata'] as Map<String, dynamic>
            : null,
        unlocked: jBool(json['unlocked']) ?? false,
        unlockedAt: jStr(json['unlockedAt']),
        featured: jBool(json['featured']) ?? false,
        position: jInt(json['position']),
        category: jStr(json['category']),
        iconKey: jStr(json['iconKey']),
        statKey: jStr(json['statKey']),
        threshold: jInt(json['threshold']),
        progressValue: jInt(json['progressValue']) ?? 0,
      );
}

/// Server-computed race record shown on Profile. Sibling of `progression`
/// in the GET /progression body; absent on older servers.
class ProfileRecord {
  const ProfileRecord({
    required this.active,
    required this.finished,
    required this.wins,
    this.winRatePercent,
  });

  final int active;
  final int finished;
  final int wins;

  /// Integer percent; null when [finished] is 0.
  final int? winRatePercent;

  factory ProfileRecord.fromJson(Map<String, dynamic> json) => ProfileRecord(
        active: jInt(json['active']) ?? 0,
        finished: jInt(json['finished']) ?? 0,
        wins: jInt(json['wins']) ?? 0,
        winRatePercent: (jDouble(json['winRatePercent']))?.round(),
      );
}

class NuvoProgression {
  const NuvoProgression({
    required this.level,
    required this.totalXp,
    required this.currentLevelXp,
    required this.nextLevelXp,
    required this.progress,
    required this.xpToNext,
    required this.lastSeenLevel,
    this.featuredSlots = 1,
    this.achievementsEarned = 0,
    this.achievementsTotal = 0,
    this.nextUnlock,
    this.levelUnlock,
    this.nextAchievement,
    this.featuredBadges = const [],
    this.newlyEarned = const [],
    this.record,
  });

  final int level;
  final int totalXp;
  final int currentLevelXp;
  final int nextLevelXp;
  final double progress;
  final int xpToNext;
  final int lastSeenLevel;

  /// Featured slots granted by the level ladder — never a client constant.
  final int featuredSlots;
  final int achievementsEarned;
  final int achievementsTotal;
  final NuvoUnlockRef? nextUnlock;

  /// The reward earned at the current level — presented by the level-up
  /// moment. Null when the level carries no reward.
  final NuvoBadge? levelUnlock;

  /// Locked achievement closest to done — the profile's "Next up" goal.
  final NuvoBadge? nextAchievement;
  final List<NuvoBadge> featuredBadges;

  /// Achievements granted by this read's reconcile — non-empty exactly
  /// once per grant, so the earned moment can never replay.
  final List<NuvoBadge> newlyEarned;

  /// Server-computed race record; null on older servers.
  final ProfileRecord? record;

  /// Parses a full GET /progression body (`progression` + sibling `record`).
  factory NuvoProgression.fromBody(Map<String, dynamic> body) {
    final p = NuvoProgression.fromJson(
      (body['progression'] as Map<String, dynamic>?) ?? const {},
    );
    final r = body['record'];
    if (r is! Map<String, dynamic>) return p;
    return p.withRecord(ProfileRecord.fromJson(r));
  }

  NuvoProgression withRecord(ProfileRecord? record) => NuvoProgression(
        level: level,
        totalXp: totalXp,
        currentLevelXp: currentLevelXp,
        nextLevelXp: nextLevelXp,
        progress: progress,
        xpToNext: xpToNext,
        lastSeenLevel: lastSeenLevel,
        featuredSlots: featuredSlots,
        achievementsEarned: achievementsEarned,
        achievementsTotal: achievementsTotal,
        nextUnlock: nextUnlock,
        levelUnlock: levelUnlock,
        nextAchievement: nextAchievement,
        featuredBadges: featuredBadges,
        newlyEarned: newlyEarned,
        record: record,
      );

  /// The server has a level the client has not yet acknowledged — the
  /// level-up moment should present exactly once.
  bool get hasUnseenLevelUp => level > lastSeenLevel;

  factory NuvoProgression.fromJson(Map<String, dynamic> json) =>
      NuvoProgression(
        level: jInt(json['level']) ?? 1,
        totalXp: jInt(json['totalXp']) ?? 0,
        currentLevelXp: jInt(json['currentLevelXp']) ?? 0,
        nextLevelXp: jInt(json['nextLevelXp']) ?? 0,
        progress: jDouble(json['progress']) ?? 0,
        xpToNext: jInt(json['xpToNext']) ?? 0,
        lastSeenLevel: jInt(json['lastSeenLevel']) ?? 1,
        featuredSlots: jInt(json['featuredSlots']) ?? 1,
        achievementsEarned: jInt(json['achievementsEarned']) ?? 0,
        achievementsTotal: jInt(json['achievementsTotal']) ?? 0,
        nextUnlock: json['nextUnlock'] is Map<String, dynamic>
            ? NuvoUnlockRef.fromJson(json['nextUnlock'] as Map<String, dynamic>)
            : null,
        levelUnlock: json['levelUnlock'] is Map<String, dynamic>
            ? NuvoBadge.fromJson(json['levelUnlock'] as Map<String, dynamic>)
            : null,
        nextAchievement: json['nextAchievement'] is Map<String, dynamic>
            ? NuvoBadge.fromJson(json['nextAchievement'] as Map<String, dynamic>)
            : null,
        featuredBadges: (json['featuredBadges'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(NuvoBadge.fromJson)
            .toList(),
        newlyEarned: (json['newlyEarned'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(NuvoBadge.fromJson)
            .toList(),
      );
}

/// What one race paid out — rendered by the finish screen's reward block.
class NuvoRaceXp {
  const NuvoRaceXp({
    required this.lines,
    required this.totalXp,
    this.earned = const [],
  });

  final List<NuvoXpLine> lines;
  final int totalXp;

  /// Achievements the reconcile granted — the finish screen's earned moment.
  final List<NuvoBadge> earned;

  factory NuvoRaceXp.fromJson(Map<String, dynamic> json) => NuvoRaceXp(
        lines: (json['lines'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map((l) => NuvoXpLine(
                  label: jStr(l['label']) ?? '',
                  xp: jInt(l['xp']) ?? 0,
                ))
            .toList(),
        totalXp: jInt(json['totalXp']) ?? 0,
        earned: (json['earned'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(NuvoBadge.fromJson)
            .toList(),
      );
}

class NuvoXpLine {
  const NuvoXpLine({required this.label, required this.xp});
  final String label;
  final int xp;
}

/// Compact identity for another member's surfaces — Crew/person sheet.
class NuvoPublicIdentity {
  const NuvoPublicIdentity({
    required this.level,
    required this.achievementsEarned,
    required this.featured,
  });

  final int level;
  final int achievementsEarned;
  final List<NuvoPublicBadge> featured;

  factory NuvoPublicIdentity.fromJson(Map<String, dynamic> json) =>
      NuvoPublicIdentity(
        level: jInt(json['level']) ?? 1,
        achievementsEarned: jInt(json['achievementsEarned']) ?? 0,
        featured: (json['featured'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(NuvoPublicBadge.fromJson)
            .toList(),
      );
}

class NuvoPublicBadge {
  const NuvoPublicBadge({
    required this.unlockId,
    required this.key,
    required this.name,
    this.iconKey,
  });

  final String unlockId;
  final String key;
  final String name;
  final String? iconKey;

  factory NuvoPublicBadge.fromJson(Map<String, dynamic> json) =>
      NuvoPublicBadge(
        unlockId: (jStr(json['unlockId']) ?? ''),
        key: jStr(json['key']) ?? '',
        name: jStr(json['name']) ?? '',
        iconKey: jStr(json['iconKey']),
      );
}
