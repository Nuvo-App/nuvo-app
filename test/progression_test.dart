import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nuvo/features/profile/data/progression_models.dart';
import 'package:nuvo/features/profile/presentation/widgets/nuvo_badges.dart';

// ── Model parsing ───────────────────────────────────────────────────────────

Map<String, dynamic> _payload({
  int level = 8,
  int totalXp = 1240,
  int currentLevelXp = 40,
  int nextLevelXp = 180,
  int lastSeenLevel = 8,
}) => {
  'level': level,
  'totalXp': totalXp,
  'currentLevelXp': currentLevelXp,
  'nextLevelXp': nextLevelXp,
  'progress': currentLevelXp / nextLevelXp,
  'xpToNext': nextLevelXp - currentLevelXp,
  'lastSeenLevel': lastSeenLevel,
  'nextUnlock': {
    'unlockId': 'bdg-double-digits',
    'level': 10,
    'type': 'badge',
    'key': 'double_digits',
    'name': 'Double Digits',
    'description': 'Two digits of real competition.',
    'metadata': {'icon': 'medal', 'rarity': 'milestone'},
  },
  'levelUnlock': {
    'unlockId': 'bdg-locked-in',
    'type': 'badge',
    'key': 'locked_in',
    'name': 'Locked In',
    'description': null,
    'requiredLevel': 7,
    'metadata': {'icon': 'target', 'rarity': 'standard'},
    'unlocked': true,
    'unlockedAt': '2026-09-20T00:00:00Z',
    'featured': false,
    'position': null,
  },
  'featuredBadges': [
    {
      'unlockId': 'bdg-five-deep',
      'type': 'badge',
      'key': 'five_deep',
      'name': 'Five Deep',
      'description': null,
      'requiredLevel': 5,
      'metadata': {'icon': 'flame', 'rarity': 'milestone'},
      'unlocked': true,
      'unlockedAt': '2026-09-18T00:00:00Z',
      'featured': true,
      'position': 0,
    },
  ],
};

void main() {
  group('NuvoProgression.fromJson', () {
    test('parses the full server payload', () {
      final p = NuvoProgression.fromJson(_payload());
      expect(p.level, 8);
      expect(p.totalXp, 1240);
      expect(p.currentLevelXp, 40);
      expect(p.nextLevelXp, 180);
      expect(p.xpToNext, 140);
      expect(p.lastSeenLevel, 8);
      expect(p.nextUnlock?.unlockId, 'bdg-double-digits');
      expect(p.nextUnlock?.level, 10);
      expect(p.levelUnlock?.name, 'Locked In');
      expect(p.featuredBadges.single.name, 'Five Deep');
      expect(p.featuredBadges.single.isMilestone, isTrue);
    });

    test('tolerates missing fields with safe defaults', () {
      final p = NuvoProgression.fromJson(const {});
      expect(p.level, 1);
      expect(p.totalXp, 0);
      expect(p.nextUnlock, isNull);
      expect(p.levelUnlock, isNull);
      expect(p.featuredBadges, isEmpty);
    });

    test('hasUnseenLevelUp only when server level is ahead', () {
      expect(
        NuvoProgression.fromJson(
          _payload(level: 8, lastSeenLevel: 7),
        ).hasUnseenLevelUp,
        isTrue,
      );
      expect(
        NuvoProgression.fromJson(
          _payload(level: 8, lastSeenLevel: 8),
        ).hasUnseenLevelUp,
        isFalse,
      );
    });
  });

  // ── Badge disc ────────────────────────────────────────────────────────────

  NuvoBadge badge({bool unlocked = true, bool milestone = false}) => NuvoBadge(
    unlockId: 'b1',
    type: 'badge',
    key: 'k',
    name: 'Test Badge',
    requiredLevel: 0,
    metadata: {'rarity': milestone ? 'milestone' : 'standard'},
    unlocked: unlocked,
    featured: false,
    iconKey: 'flag',
  );

  group('NuvoBadgeDisc', () {
    testWidgets('locked badge shows a lock glyph', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NuvoBadgeDisc(badge: badge(unlocked: false))),
        ),
      );
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    });

    testWidgets('unlocked badge shows its icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NuvoBadgeDisc(badge: badge())),
        ),
      );
      expect(find.byIcon(Icons.flag_rounded), findsOneWidget);
    });
  });

  // ── Badges screen ─────────────────────────────────────────────────────────

  group('BadgesScreen', () {});
}

// ── Fakes ───────────────────────────────────────────────────────────────────
