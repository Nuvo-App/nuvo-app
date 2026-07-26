import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/arena/presentation/track_view/track_view_fixture.dart';
import 'package:nuvo/features/arena/presentation/track_view/track_view_screen.dart';

void main() {
  const scrollableKey = ValueKey('track-view-scrollable');

  Future<void> pumpTrackView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SizedBox.expand(child: ArenaScreen())),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  ScrollPosition trackPosition(WidgetTester tester) {
    final scrollableFinder = find.descendant(
      of: find.byKey(scrollableKey),
      matching: find.byType(Scrollable),
    );
    return tester.state<ScrollableState>(scrollableFinder).position;
  }

  test('TrackView source does not use Flame', () {
    const bannedTerms = [
      'flame',
      'GameWidget',
      'FlameGame',
      'CameraComponent',
      'PanDetector',
      'InteractiveViewer',
    ];
    final files = Directory('lib/features/arena/presentation/track_view')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in files) {
      final source = file.readAsStringSync();
      for (final term in bannedTerms) {
        expect(
          source.contains(term),
          isFalse,
          reason: '${file.path} contains $term',
        );
      }
    }
  });

  test('three fixture races preserve the required data and ordering', () {
    expect(trackViewFixtures, hasLength(3));
    expect(trackViewFixtures[0].title, 'First to 100 Pushups');
    expect(trackViewFixtures[0].goal, 100);
    expect(trackViewFixtures[0].participants.map((p) => p.displayName), [
      'Maya',
      'You',
      'Riley',
    ]);

    expect(trackViewFixtures[1].title, 'First to 60 Squats');
    expect(trackViewFixtures[1].goal, 60);
    expect(trackViewFixtures[1].participants.map((p) => p.displayName), [
      'Jordan',
      'You',
      'Riley',
    ]);

    expect(trackViewFixtures[2].title, 'First to 40 Lunges');
    expect(trackViewFixtures[2].goal, 40);
    expect(trackViewFixtures[2].participants.map((p) => p.displayName), [
      'You',
      'Maya',
      'Jordan',
    ]);
  });

  testWidgets('uses one native horizontal scrollable oval bar', (tester) async {
    await pumpTrackView(tester);

    final scrollables = tester.widgetList<Scrollable>(find.byType(Scrollable));
    expect(scrollables, hasLength(1));
    expect(scrollables.single.axisDirection, AxisDirection.right);
    expect(find.byKey(scrollableKey), findsOneWidget);
  });

  testWidgets('dragging the oval bar changes offset and focused racer', (
    tester,
  ) async {
    await pumpTrackView(tester);
    final before = trackPosition(tester).pixels;
    expect(find.textContaining('You · #2'), findsOneWidget);

    await tester.drag(find.byKey(scrollableKey), const Offset(-90, 0));
    await tester.pumpAndSettle();
    expect(trackPosition(tester).pixels, greaterThan(before));
    expect(find.textContaining('Riley · #1'), findsOneWidget);

    await tester.drag(find.byKey(scrollableKey), const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('Maya · #3'), findsOneWidget);
  });

  testWidgets(
    'selecting races updates title, goal, participants, and current progress',
    (tester) async {
      await pumpTrackView(tester);

      expect(find.text('First to 100 Pushups'), findsOneWidget);
      expect(find.text('68'), findsOneWidget);
      expect(find.textContaining('Riley'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('next-race')));
      await tester.pumpAndSettle();
      expect(find.text('First to 60 Squats'), findsOneWidget);
      expect(find.text('28'), findsOneWidget);
      expect(find.textContaining('You · #2 · 28 / 60 reps'), findsOneWidget);
      expect(find.textContaining('/ 60 reps'), findsWidgets);
      await tester.drag(find.byKey(scrollableKey), const Offset(90, 0));
      await tester.pumpAndSettle();
      expect(find.textContaining('Jordan · #3'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('next-race')));
      await tester.pumpAndSettle();
      expect(find.text('First to 40 Lunges'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.textContaining('You · #3 · 0 / 40 reps'), findsOneWidget);
      expect(find.textContaining('/ 40 reps'), findsWidgets);
      await tester.drag(find.byKey(scrollableKey), const Offset(-90, 0));
      await tester.pumpAndSettle();
      expect(find.textContaining('Maya · #2'), findsOneWidget);
    },
  );

  testWidgets('Submit proof gives the local prototype response', (
    tester,
  ) async {
    await pumpTrackView(tester);

    await tester.tap(find.byKey(const ValueKey('track-view-make-move')));
    await tester.pump();

    expect(
      find.text('Verification will be connected in the next gate.'),
      findsOneWidget,
    );
  });

  testWidgets('Arena mounts without external HTTP or network fonts', (
    tester,
  ) async {
    await pumpTrackView(tester);

    expect(find.text('ARENA'), findsOneWidget);
    expect(find.text('Submit proof'), findsOneWidget);
    expect(find.byKey(scrollableKey), findsOneWidget);
  });
}
