/// Nuvo progression — server-owned persistent meta-game projected from
/// canonical race events. The client never computes XP, level, or
/// achievement progress itself; it renders what the Worker returns.
library;

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
        unlockId: json['unlockId'] as String,
        level: json['level'] as int? ?? 0,
        type: json['type'] as String? ?? 'badge',
        key: json['key'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
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
        unlockId: json['unlockId'] as String,
        type: json['type'] as String? ?? 'badge',
        key: json['key'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        requiredLevel: json['requiredLevel'] as int? ?? 0,
        metadata: json['metadata'] is Map<String, dynamic>
            ? json['metadata'] as Map<String, dynamic>
            : null,
        unlocked: json['unlocked'] as bool? ?? false,
        unlockedAt: json['unlockedAt'] as String?,
        featured: json['featured'] as bool? ?? false,
        position: json['position'] as int?,
        category: json['category'] as String?,
        iconKey: json['iconKey'] as String?,
        statKey: json['statKey'] as String?,
        threshold: json['threshold'] as int?,
        progressValue: json['progressValue'] as int? ?? 0,
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

  /// The server has a level the client has not yet acknowledged — the
  /// level-up moment should present exactly once.
  bool get hasUnseenLevelUp => level > lastSeenLevel;

  factory NuvoProgression.fromJson(Map<String, dynamic> json) =>
      NuvoProgression(
        level: json['level'] as int? ?? 1,
        totalXp: json['totalXp'] as int? ?? 0,
        currentLevelXp: json['currentLevelXp'] as int? ?? 0,
        nextLevelXp: json['nextLevelXp'] as int? ?? 0,
        progress: (json['progress'] as num?)?.toDouble() ?? 0,
        xpToNext: json['xpToNext'] as int? ?? 0,
        lastSeenLevel: json['lastSeenLevel'] as int? ?? 1,
        featuredSlots: json['featuredSlots'] as int? ?? 1,
        achievementsEarned: json['achievementsEarned'] as int? ?? 0,
        achievementsTotal: json['achievementsTotal'] as int? ?? 0,
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
                  label: l['label'] as String? ?? '',
                  xp: l['xp'] as int? ?? 0,
                ))
            .toList(),
        totalXp: json['totalXp'] as int? ?? 0,
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
        level: json['level'] as int? ?? 1,
        achievementsEarned: json['achievementsEarned'] as int? ?? 0,
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
        unlockId: json['unlockId'] as String,
        key: json['key'] as String? ?? '',
        name: json['name'] as String? ?? '',
        iconKey: json['iconKey'] as String?,
      );
}
