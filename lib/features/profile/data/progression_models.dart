/// Nuvo Levels — server-owned persistent progression projected from
/// canonical race events. The client never computes XP or level itself;
/// it renders what the Worker returns.
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

  /// Metadata identifier for the badge glyph — mapped to Nuvo icons by the
  /// presentation layer, never stored as client art on the server.
  String? get icon => metadata?['icon'] as String?;
  bool get isMilestone => metadata?['rarity'] == 'milestone';

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
    this.nextUnlock,
    this.levelUnlock,
    this.featuredBadges = const [],
  });

  final int level;
  final int totalXp;
  final int currentLevelXp;
  final int nextLevelXp;
  final double progress;
  final int xpToNext;
  final int lastSeenLevel;
  final NuvoUnlockRef? nextUnlock;

  /// The reward earned at the current level — presented by the level-up
  /// moment. Null when the level carries no reward.
  final NuvoBadge? levelUnlock;
  final List<NuvoBadge> featuredBadges;

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
        nextUnlock: json['nextUnlock'] is Map<String, dynamic>
            ? NuvoUnlockRef.fromJson(json['nextUnlock'] as Map<String, dynamic>)
            : null,
        levelUnlock: json['levelUnlock'] is Map<String, dynamic>
            ? NuvoBadge.fromJson(json['levelUnlock'] as Map<String, dynamic>)
            : null,
        featuredBadges: (json['featuredBadges'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(NuvoBadge.fromJson)
            .toList(),
      );
}
