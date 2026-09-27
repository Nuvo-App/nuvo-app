import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/profile/application/progression_controller.dart';
import 'package:nuvo/features/profile/data/progression_api.dart';
import 'package:nuvo/features/profile/data/progression_models.dart';
import 'package:nuvo/features/profile/presentation/badges_screen.dart';
import 'package:nuvo/features/profile/presentation/widgets/nuvo_badges.dart';

// ── Model parsing ───────────────────────────────────────────────────────────

Map<String, dynamic> _payload({
  int level = 8,
  int totalXp = 1240,
  int currentLevelXp = 40,
  int nextLevelXp = 180,
  int lastSeenLevel = 8,
}) =>
    {
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
      expect(NuvoProgression.fromJson(_payload(level: 8, lastSeenLevel: 7))
          .hasUnseenLevelUp, isTrue);
      expect(NuvoProgression.fromJson(_payload(level: 8, lastSeenLevel: 8))
          .hasUnseenLevelUp, isFalse);
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
          home: Scaffold(
            body: NuvoBadgeDisc(badge: badge(unlocked: false)),
          ),
        ),
      );
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    });

    testWidgets('unlocked badge shows its icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NuvoBadgeDisc(badge: badge()),
          ),
        ),
      );
      expect(find.byIcon(Icons.flag_rounded), findsOneWidget);
    });
  });

  // ── Badges screen ─────────────────────────────────────────────────────────

  group('BadgesScreen', () {
    testWidgets(
        'locked badges show progress; earned badges feature via the detail '
        'sheet', (tester) async {
      final api = _FakeProgressionApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            progressionControllerProvider.overrideWith(
              (ref) => ProgressionController(api, _FakeStore()),
            ),
          ],
          child: const MaterialApp(home: BadgesScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Earned/locked counts sit in the header.
      expect(find.text('1 / 2 earned · 0 / 1 featured'), findsOneWidget);

      // A locked badge's detail sheet shows live progress and no
      // feature affordance.
      await tester.tap(find.text('Double Digits'));
      await tester.pumpAndSettle();
      expect(find.text('8 / 10'), findsOneWidget);
      expect(find.text('Feature on Profile'), findsNothing);
      expect(api.featuredCalls, isEmpty);
      Navigator.of(tester.element(find.text('Double Digits').last))
          .maybePop();
      await tester.pumpAndSettle();

      // An earned badge's detail sheet offers the feature action.
      await tester.tap(find.text('Off the Line'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Feature on Profile'));
      await tester.pumpAndSettle();
      expect(api.featuredCalls, [
        ['bdg-off-the-line'],
      ]);
    });
  });
}

// ── Fakes ───────────────────────────────────────────────────────────────────

class _FakeStore extends SecureTokenStore {
  @override
  Future<String?> getAccessToken() async => 'test-token';
}

class _FakeProgressionApi extends ProgressionApi {
  _FakeProgressionApi() : super(client: null);

  final featuredCalls = <List<String>>[];

  final badges = <NuvoBadge>[
    const NuvoBadge(
      unlockId: 'bdg-off-the-line',
      type: 'achievement',
      key: 'off_the_line',
      name: 'Off the Line',
      requiredLevel: 0,
      metadata: {'rarity': 'standard'},
      unlocked: true,
      featured: false,
      category: 'racing',
      iconKey: 'flag',
      statKey: 'races_finished',
      threshold: 1,
      progressValue: 1,
    ),
    const NuvoBadge(
      unlockId: 'bdg-double-digits',
      type: 'achievement',
      key: 'double_digits',
      name: 'Double Digits',
      requiredLevel: 0,
      metadata: {'rarity': 'milestone'},
      unlocked: false,
      featured: false,
      category: 'racing',
      iconKey: 'num_10',
      statKey: 'races_finished',
      threshold: 10,
      progressValue: 8,
    ),
  ];

  @override
  Future<List<NuvoBadge>> getBadges(String token) async => badges;

  @override
  Future<List<NuvoBadge>> setFeatured(
    String token,
    List<String> unlockIds,
  ) async {
    featuredCalls.add(unlockIds);
    return badges
        .map(
          (b) => NuvoBadge(
            unlockId: b.unlockId,
            type: b.type,
            key: b.key,
            name: b.name,
            requiredLevel: b.requiredLevel,
            metadata: b.metadata,
            unlocked: b.unlocked,
            featured: unlockIds.contains(b.unlockId),
          ),
        )
        .toList();
  }

  @override
  Future<NuvoProgression> getProgression(String token) async =>
      NuvoProgression.fromJson(const {'level': 2, 'lastSeenLevel': 2});

  @override
  Future<NuvoProgression> markLevelSeen(String token) async =>
      NuvoProgression.fromJson(const {'level': 2, 'lastSeenLevel': 2});
}
