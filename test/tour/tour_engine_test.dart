import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/tour/tour_controller.dart';
import 'package:nuvo/features/tour/tour_engine.dart';
import 'package:nuvo/features/tour/tour_overlay.dart';
import 'package:nuvo/features/tour/tour_script.dart';
import 'package:nuvo/features/tour/tour_store.dart';

import 'tour_harness.dart';

/// Advances fake time in frame-sized steps so animations and tickers run
/// (one big pump is a single frame).
Future<void> adv(WidgetTester t, Duration d) async {
  const step = Duration(milliseconds: 50);
  var left = d;
  while (left > Duration.zero) {
    final s = left < step ? left : step;
    await t.pump(s);
    left -= s;
  }
}

Future<ProviderContainer> _pump(
  WidgetTester t, {
  required TourStore store,
  required VoidCallback onTarget,
  required VoidCallback onOther,
  bool withTarget = true,
  String location = '/arena',
}) async {
  final container = ProviderContainer(overrides: tourOverrides(store));
  addTearDown(container.dispose);
  await startTour(container, location: location);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: TourStageHarness(
        onTarget: onTarget,
        onOther: onOther,
        withTarget: withTarget,
      ),
    ),
  );
  return container;
}

void main() {
  testWidgets('renders nothing when the tour is not active', (t) async {
    final store = TourStore.memory();
    final container = ProviderContainer(overrides: tourOverrides(store));
    addTearDown(container.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TourStageHarness(onTarget: () {}, onOther: () {}),
      ),
    );
    await adv(t, const Duration(seconds: 3));
    expect(find.byKey(const ValueKey('tour-scrim')), findsNothing);
    expect(find.byKey(const ValueKey('tour-copy')), findsNothing);
  });

  testWidgets('cutout geometry follows the target (+8, radius+8)', (t) async {
    final store = TourStore.memory();
    await _pump(t, store: store, onTarget: () {}, onOther: () {});
    await adv(t, const Duration(milliseconds: 600));
    final scrim = t.allRenderObjects.whereType<RenderTourScrim>().first;
    final hole = scrim.hole!;
    expect(hole.outerRect, const Rect.fromLTWH(32, 192, 216, 106));
    // 'arenaRace' targetRadius is 24 -> 32.
    expect(hole.tlRadiusX, 32);
  });

  testWidgets('only the target takes touches; the scrim absorbs the rest', (
    t,
  ) async {
    var target = 0;
    var other = 0;
    await _pump(
      t,
      store: TourStore.memory(),
      onTarget: () => target++,
      onOther: () => other++,
    );
    await adv(t, const Duration(milliseconds: 600));

    await t.tapAt(const Offset(140, 245)); // centre of the target
    expect(target, 1);

    await t.tapAt(const Offset(140, 550)); // bystander button under scrim
    expect(other, 0);
    await t.tapAt(const Offset(300, 100)); // empty scrim
    expect(other, 0);
    expect(target, 1);
  });

  testWidgets('bubble: at most 3 lines, never covers the target', (t) async {
    await _pump(t, store: TourStore.memory(), onTarget: () {}, onOther: () {});
    await adv(t, const Duration(milliseconds: 700));
    final copy = t.widget<Text>(find.byKey(const ValueKey('tour-copy')));
    expect(copy.maxLines, 3);
    final bubble = t.getRect(
      find.byKey(const ValueKey('tour-bubble-arenaRace:target')),
    );
    final targetRect = t.getRect(find.text('target')).inflate(8);
    expect(bubble.overlaps(targetRect), isFalse);
  });

  testWidgets('Skip tour appears after 2s, not before; skipping persists', (
    t,
  ) async {
    final store = TourStore.memory();
    final container = await _pump(
      t,
      store: store,
      onTarget: () {},
      onOther: () {},
    );
    await adv(t, const Duration(milliseconds: 1900));
    expect(find.byKey(const ValueKey('tour-skip')), findsNothing);
    await adv(t, const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('tour-skip')), findsOneWidget);
    await adv(t, const Duration(milliseconds: 700)); // entrance settles

    await t.tap(find.byKey(const ValueKey('tour-skip')));
    await t.pump();
    expect(store.skipped, isTrue);
    expect(container.read(tourControllerProvider).active, isFalse);
    await adv(t, const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('tour-scrim')), findsNothing);
  });

  testWidgets('close works immediately and resumes next run (not skipped)', (
    t,
  ) async {
    final store = TourStore.memory();
    final container = await _pump(
      t,
      store: store,
      onTarget: () {},
      onOther: () {},
    );
    await adv(t, const Duration(milliseconds: 600));
    await t.tap(find.byKey(const ValueKey('tour-close')));
    await t.pump();
    expect(container.read(tourControllerProvider).active, isFalse);
    expect(store.skipped, isFalse);
  });

  testWidgets(
    'missing anchor: stop is skipped after 1.5s, logged, never blocks',
    (t) async {
      final container = await _pump(
        t,
        store: TourStore.memory(),
        onTarget: () {},
        onOther: () {},
        withTarget: false,
      );
      await adv(t, const Duration(milliseconds: 1400));
      expect(container.read(tourControllerProvider).beat, 'arenaRace');
      await adv(t, const Duration(milliseconds: 300));
      final s = container.read(tourControllerProvider);
      expect(s.skipLog, isNotEmpty);
      expect(s.skippedBeats, contains('arenaRace'));
      expect(s.beat, isNot('arenaRace'));
      // The skipped stop is still owed on a later launch.
      expect(
        container
            .read(tourControllerProvider.notifier)
            .store
            .isCompleted('arenaRace'),
        isFalse,
      );
    },
  );

  testWidgets('hand pointer taps once, idles 6s, taps once more, then stops', (
    t,
  ) async {
    await _pump(t, store: TourStore.memory(), onTarget: () {}, onOther: () {});
    final hand = find.byKey(const ValueKey('tour-hand'));
    await adv(t, const Duration(milliseconds: 100));
    expect(hand, findsNothing);
    await adv(t, const Duration(milliseconds: 500)); // enter done -> tap 1
    expect(hand, findsOneWidget);
    await adv(t, const Duration(milliseconds: 800)); // tap 1 over
    await adv(t, const Duration(seconds: 6)); // idle -> tap 2
    expect(hand, findsOneWidget);
    await adv(t, const Duration(milliseconds: 800));
    expect(hand, findsNothing);
    await adv(t, const Duration(seconds: 20));
    expect(hand, findsNothing); // no looping
  });

  testWidgets('reduce motion: no hand pointer animation', (t) async {
    final container = ProviderContainer(
      overrides: tourOverrides(TourStore.memory()),
    );
    addTearDown(container.dispose);
    await startTour(container);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TourStageHarness(
          onTarget: () {},
          onOther: () {},
          reduceMotion: true,
        ),
      ),
    );
    await adv(t, const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('tour-hand')), findsNothing);
    expect(find.byKey(const ValueKey('tour-copy')), findsOneWidget);
  });

  group('resume and XP', () {
    test('resumes at the earliest owed stop after a kill', () async {
      final store = TourStore.fromSnapshot({
        'accountEmail': 'a@b.c',
        'completed': ['arenaRace', 'arenaProof'],
        'xpAwarded': {'arenaProof': 10},
      });
      final c = ProviderContainer(overrides: tourOverrides(store));
      addTearDown(c.dispose);
      await c
          .read(tourControllerProvider.notifier)
          .sync(email: 'a@b.c', graduated: true);
      expect(c.read(tourControllerProvider).active, isTrue);
      expect(c.read(tourControllerProvider).beat, kTourNotifyId);
      expect(c.read(tourControllerProvider).practiceDone, isTrue);
    });

    test('snapshot round trip survives a relaunch', () async {
      final a = TourStore.memory();
      await a.attachAccount('a@b.c');
      await a.complete('arenaRace');
      await a.complete('arenaProof', xp: 30);
      final b = TourStore.fromSnapshot(a.toJson());
      expect(b.completed, {'arenaRace', 'arenaProof'});
      expect(b.totalXp, 30);
    });

    test('XP is never awarded twice, even across a replay', () async {
      final store = TourStore.memory();
      final c = ProviderContainer(overrides: tourOverrides(store));
      addTearDown(c.dispose);
      final ctl = c.read(tourControllerProvider.notifier);
      await ctl.sync(email: 'a@b.c', graduated: true);
      expect(await ctl.completeBeat('compete'), 10);
      expect(await ctl.completeBeat('compete'), 0);
      await ctl.replay();
      expect(await ctl.completeBeat('compete'), 0);
      expect(store.totalXp, 10);
    });

    test('camera fallback pays the Practice amount (10, not 30)', () async {
      final store = TourStore.memory();
      final c = ProviderContainer(overrides: tourOverrides(store));
      addTearDown(c.dispose);
      final ctl = c.read(tourControllerProvider.notifier);
      await ctl.sync(email: 'a@b.c', graduated: true);
      expect(await ctl.practiceProofDone(fallback: true), 10);
      expect(store.cameraFallback, isTrue);
    });

    test(
      'does not start unless graduated, and never after finish/skip',
      () async {
        final cases = <(TourStore, bool)>[
          (TourStore.memory(), false),
          (
            TourStore.fromSnapshot({'accountEmail': 'a@b.c', 'finished': true}),
            true,
          ),
          (
            TourStore.fromSnapshot({'accountEmail': 'a@b.c', 'skipped': true}),
            true,
          ),
        ];
        for (final (store, graduated) in cases) {
          final c = ProviderContainer(overrides: tourOverrides(store));
          addTearDown(c.dispose);
          await c
              .read(tourControllerProvider.notifier)
              .sync(email: 'a@b.c', graduated: graduated);
          expect(c.read(tourControllerProvider).active, isFalse);
        }
      },
    );

    test('a different account wipes the previous account progress', () async {
      final store = TourStore.fromSnapshot({
        'accountEmail': 'old@b.c',
        'completed': ['arenaRace'],
        'xpAwarded': {'compete': 10},
      });
      final c = ProviderContainer(overrides: tourOverrides(store));
      addTearDown(c.dispose);
      await c
          .read(tourControllerProvider.notifier)
          .sync(email: 'new@b.c', graduated: true);
      expect(store.completed, isEmpty);
      expect(c.read(tourControllerProvider).beat, 'arenaRace');
    });
  });

  group('view resolution follows the location', () {
    test('a stop on another tab spotlights the dock first', () {
      final dock = resolveTourView('compete', '/arena');
      expect(dock.phase, TourPhase.dock);
      expect(dock.dockIndex, 1);
      expect(dock.copy, 'Compete is where races find you.');
      final target = resolveTourView('compete', '/compete');
      expect(target.phase, TourPhase.target);
      expect(target.counter, 1);
    });

    test('hidden on pushed screens, sheet and done beats resolve', () {
      expect(resolveTourView('compete', '/race/abc').phase, TourPhase.hidden);
      expect(resolveTourView(kTourNotifyId, '/arena').phase, TourPhase.sheet);
      expect(resolveTourView(kTourDoneBeat, '/arena').phase, TourPhase.done);
      expect(resolveTourView(null, '/arena').phase, TourPhase.hidden);
    });
  });
}
