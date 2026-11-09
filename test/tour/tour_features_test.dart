import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/v13/widgets/v13_tab_bar.dart';
import 'package:nuvo/features/onboarding/flow/xp_table.dart';
import 'package:nuvo/features/races/domain/race_display.dart';
import 'package:nuvo/features/onboarding/tour/notify_opt_in_step.dart';
import 'package:nuvo/features/tour/tour_anchors.dart';
import 'package:nuvo/features/tour/tour_controller.dart';
import 'package:nuvo/features/tour/tour_fixtures.dart';
import 'package:nuvo/features/tour/tour_flags.dart';
import 'package:nuvo/features/tour/tour_getting_started.dart';
import 'package:nuvo/features/tour/tour_script.dart';
import 'package:nuvo/features/tour/tour_store.dart';

import 'tour_engine_test.dart' show adv;
import 'tour_harness.dart';

void main() {
  test('ships OFF', () {
    expect(kTourEnabled, isFalse);
  });

  group('fixtures', () {
    test('absent unless the tour is active', () async {
      final c = ProviderContainer(overrides: tourOverrides(TourStore.memory()));
      addTearDown(c.dispose);
      expect(c.read(tourFixturesProvider), isNull);
      await startTour(c);
      expect(c.read(tourFixturesProvider), isNotNull);
      await c.read(tourControllerProvider.notifier).skip();
      expect(c.read(tourFixturesProvider), isNull);
    });

    test('flag off: no fixtures even if the controller were active', () async {
      final c = ProviderContainer(
        overrides: [tourStoreProvider.overrideWithValue(TourStore.memory())],
      );
      addTearDown(c.dispose);
      await startTour(c);
      expect(c.read(tourFixturesProvider), isNull);
    });

    test('practice race: Nuvo Crew bots 6 and 4, user 0, labeled Practice', () {
      final fx = buildTourFixtures(userId: 'u1', q1: null, practiceDone: false);
      final r = fx.practiceRace;
      expect(r.title, 'Squat Race · First to 10');
      final scores = {
        for (final p in r.participants) p.userId: p.progressValue,
      };
      expect(scores['u1'], 0);
      expect(
        r.participants
            .where((p) => p.userId != 'u1')
            .map((p) => p.progressValue),
        unorderedEquals([6, 4]),
      );
      expect(
        r.participants
            .where((p) => p.userId != 'u1')
            .every((p) => p.displayName == 'Nuvo Crew'),
        isTrue,
      );
      expect(r.viewerContext!.rank, 3);
      expect(isTourRace(r) && isTourRace(fx.joinableRace), isTrue);
      expect(raceIsActive(r), isTrue);
      final after = buildTourFixtures(userId: 'u1', practiceDone: true);
      expect(after.practiceRace.viewerContext!.rank, 2);
    });

    test('every fixture id is a client-only tour id', () {
      final fx = buildTourFixtures(userId: 'u1', practiceDone: false);
      final ids = [
        fx.practiceRace.id,
        fx.joinableRace.id,
        fx.badge.unlockId,
        ...fx.friends.map((f) => f.id),
        for (final p in fx.practiceRace.participants)
          if (p.userId != 'u1') p.userId,
      ];
      expect(ids.every(isTourId), isTrue, reason: '$ids');
    });
  });

  group('XP', () {
    test('tour awards match the onboarding table and reach Level 2', () {
      expect(tourStopById('arenaProof')!.xp, OnboardingXp.firstProof);
      expect(
        tourStopById('arenaProof')!.fallbackXp,
        OnboardingXp.firstProofCameraFallback,
      );
      expect(tourStopById('compete')!.xp, OnboardingXp.tourCompete);
      expect(tourStopById('crew')!.xp, OnboardingXp.tourCrew);
      expect(tourStopById('profile')!.xp, OnboardingXp.tourProfile);
      expect(kTourNotifyXp, OnboardingXp.notifyAccepted);
      // Server curve (server/worker/src/domain/progression.ts): Level 2 at
      // 60 XP, Level 3 at 180. The full table must land inside Level 2.
      expect(OnboardingXp.sum(), 100);
      expect(OnboardingXp.sum() >= 60 && OnboardingXp.sum() < 180, isTrue);
    });
  });

  group('dock anchors', () {
    testWidgets('slot keys give the tour a rect for every tab', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: V13TabBar(
              items: const [
                V13TabItem(label: 'Arena', icon: Icons.stadium),
                V13TabItem(label: 'Compete', icon: Icons.emoji_events),
                V13TabItem(label: 'Crew', icon: Icons.group),
                V13TabItem(label: 'Profile', icon: Icons.person),
              ],
              currentIndex: 0,
              onTap: (_) {},
              slotKeys: [for (var i = 0; i < 4; i++) TourAnchors.dockSlot(i)],
            ),
          ),
        ),
      );
      for (final a in [
        TourAnchor.dockArena,
        TourAnchor.dockCompete,
        TourAnchor.dockCrew,
        TourAnchor.dockProfile,
      ]) {
        expect(TourAnchors.rectOf(a), isNotNull, reason: a.name);
      }
    });
  });

  group('Getting started row', () {
    Future<void> pumpRow(WidgetTester t, TourStore store) async {
      await t.pumpWidget(
        ProviderScope(
          overrides: tourOverrides(store),
          child: const MaterialApp(
            home: Scaffold(body: TourGettingStartedRow()),
          ),
        ),
      );
      await t.pump();
    }

    testWidgets('shown for a skipper with 5 dots; hidden otherwise', (t) async {
      await pumpRow(
        t,
        TourStore.fromSnapshot({
          'accountEmail': 'a@b.c',
          'skipped': true,
          'completed': ['arenaProof'],
        }),
      );
      expect(find.text('Getting started'), findsOneWidget);
      expect(find.byKey(const ValueKey('tour-dot-compete')), findsOneWidget);
      expect(find.byType(Container), findsWidgets);
      await pumpRow(t, TourStore.memory());
      expect(find.text('Getting started'), findsNothing);
    });

    testWidgets('tapping resumes the tour at the earliest owed stop', (
      t,
    ) async {
      final store = TourStore.fromSnapshot({
        'accountEmail': 'a@b.c',
        'skipped': true,
        'completed': ['arenaRace', 'arenaProof'],
      });
      late ProviderContainer c;
      await t.pumpWidget(
        ProviderScope(
          overrides: tourOverrides(store),
          child: Consumer(
            builder: (context, ref, _) {
              c = ProviderScope.containerOf(context);
              return const MaterialApp(
                home: Scaffold(body: TourGettingStartedRow()),
              );
            },
          ),
        ),
      );
      await t.pump();
      await t.tap(find.text('Getting started'));
      await adv(t, const Duration(milliseconds: 300));
      expect(c.read(tourControllerProvider).active, isTrue);
      expect(c.read(tourControllerProvider).beat, kTourNotifyId);
      expect(store.skipped, isFalse);
    });
  });

  group('S11 notification sheet', () {
    testWidgets('accepting pays +5; later pays nothing; both complete', (
      t,
    ) async {
      for (final accept in [true, false]) {
        final store = TourStore.memory();
        final c = ProviderContainer(
          overrides: [
            ...tourOverrides(store),
            notifyPermissionRequestProvider.overrideWith(
              (ref) =>
                  () async => accept,
            ),
          ],
        );
        addTearDown(c.dispose);
        await startTour(c);
        c.read(tourControllerProvider.notifier).debugSetBeat(kTourNotifyId);
        await t.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: TourStageHarness(onTarget: () {}, onOther: () {}),
          ),
        );
        await adv(t, const Duration(seconds: 1));
        expect(find.text(kTourNotifyTitle), findsOneWidget);
        expect(find.text('Turn on notifications'), findsOneWidget);
        expect(find.text('Maybe later'), findsOneWidget);
        await t.tap(
          find.byKey(
            ValueKey(accept ? 'tour-notify-accept' : 'tour-notify-later'),
          ),
        );
        await adv(t, const Duration(seconds: 2));
        expect(store.isCompleted(kTourNotifyId), isTrue);
        expect(store.xpAwarded[kTourNotifyId], accept ? 5 : isNull);
        expect(store.notifyOutcome, accept ? 'accepted' : 'declined');
        await t.pumpWidget(const SizedBox());
      }
    });
  });
}
