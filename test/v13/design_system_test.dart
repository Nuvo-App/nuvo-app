import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/v13/v13.dart';

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  group('tokens', () {
    test('raceColor is stable for the same id and inside the palette', () {
      for (final id in ['race-1', 'abc', 'pushup-monday', '42']) {
        expect(V13.raceColor(id), V13.raceColor(id));
        expect(V13.racePalette, contains(V13.raceColor(id)));
      }
    });

    test('crewColor prefers the server color_key, falls back to hash', () {
      expect(V13.crewColor('coral', 'x'), V13.coral);
      expect(V13.crewColor('mint', 'x'), V13.mint);
      expect(V13.crewColor(null, 'crew-9'), V13.raceColor('crew-9'));
      expect(V13.crewColor('unknown', 'crew-9'), V13.raceColor('crew-9'));
    });
  });

  group('V13Pressable', () {
    testWidgets('fires onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(
          V13Pressable(
            onTap: () => taps++,
            child: const SizedBox.square(dimension: 40),
          ),
        ),
      );
      await tester.tap(find.byType(V13Pressable));
      expect(taps, 1);
    });

    testWidgets('does not fire when disabled', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(
          V13Pressable(
            onTap: () => taps++,
            enabled: false,
            child: const SizedBox.square(dimension: 40),
          ),
        ),
      );
      await tester.tap(find.byType(V13Pressable));
      expect(taps, 0);
    });
  });

  group('V13Button', () {
    testWidgets('primary fires onPressed', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(
          V13Button.primary(label: 'Submit proof', onPressed: () => taps++),
        ),
      );
      await tester.tap(find.text('Submit proof'));
      expect(taps, 1);
    });

    testWidgets('loading shows a spinner and blocks the tap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(
          V13Button.primary(
            label: 'Submit proof',
            loading: true,
            onPressed: () => taps++,
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(V13Button));
      expect(taps, 0);
    });

    testWidgets('disabled button does not fire', (tester) async {
      await tester.pumpWidget(
        _wrap(const V13Button.primary(label: 'Nope', onPressed: null)),
      );
      await tester.tap(find.text('Nope'));
      expect(find.byType(V13Button), findsOneWidget);
    });

    testWidgets('all variants render', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              V13Button.primary(label: 'A', onPressed: () {}),
              V13Button.secondary(label: 'B', onPressed: () {}),
              V13Button.ghost(label: 'C', onPressed: () {}),
              V13Button.danger(label: 'D', onPressed: () {}),
            ],
          ),
        ),
      );
      for (final label in ['A', 'B', 'C', 'D']) {
        expect(find.text(label), findsOneWidget);
      }
    });
  });

  group('V13Card', () {
    testWidgets('renders child and handles tap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(V13Card(onTap: () => taps++, child: const Text('inside'))),
      );
      expect(find.text('inside'), findsOneWidget);
      await tester.tap(find.text('inside'));
      expect(taps, 1);
    });

    testWidgets('dashed variant renders', (tester) async {
      await tester.pumpWidget(
        _wrap(const V13Card.dashed(child: Text('add slot'))),
      );
      expect(find.text('add slot'), findsOneWidget);
    });
  });

  testWidgets('V13IconButton shows badge and fires', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        V13IconButton(
          icon: Icons.notifications_none,
          badgeCount: 3,
          onTap: () => taps++,
          semanticLabel: 'Activity',
        ),
      ),
    );
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.byType(V13IconButton));
    expect(taps, 1);
  });

  group('V13Face', () {
    testWidgets('shows the neutral silhouette when url is null', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const V13Face()));
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
      // Never initials.
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('fires onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(V13Face(name: 'Maya', onTap: () => taps++)),
      );
      await tester.tap(find.byType(V13Face));
      expect(taps, 1);
    });
  });

  testWidgets('V13FaceStack caps at max and shows the +N chip', (tester) async {
    final faces = List.generate(5, (i) => V13FaceInfo(id: 'u$i', name: 'P$i'));
    await tester.pumpWidget(_wrap(V13FaceStack(faces: faces, max: 3)));
    expect(find.byType(V13Face), findsNWidgets(3));
    expect(find.text('+2'), findsOneWidget);
  });

  group('V13Chip', () {
    testWidgets('fires onTap and renders the auto tag', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(V13Chip(label: 'Squats', auto: true, onTap: () => taps++)),
      );
      expect(find.text('auto'), findsOneWidget);
      await tester.tap(find.text('Squats'));
      expect(taps, 1);
    });
  });

  testWidgets('V13Pill renders its label', (tester) async {
    await tester.pumpWidget(_wrap(const V13Pill(label: 'Live now')));
    expect(find.text('Live now'), findsOneWidget);
  });

  testWidgets('V13Segmented reports the tapped segment', (tester) async {
    var picked = -1;
    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) => V13Segmented(
            segments: const [
              V13Segment(label: 'Camera'),
              V13Segment(label: 'Manual'),
            ],
            selectedIndex: picked == -1 ? 0 : picked,
            onChanged: (i) => setState(() => picked = i),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Manual'));
    expect(picked, 1);
  });

  testWidgets('V13Toggle flips on tap', (tester) async {
    var value = false;
    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) => V13Toggle(
            value: value,
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(V13Toggle));
    expect(value, isTrue);
  });

  group('V13Stepper', () {
    testWidgets('increments and respects bounds', (tester) async {
      var value = 1;
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) => V13Stepper(
              value: value,
              min: 0,
              max: 2,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(value, 2);
      // At max — tapping again changes nothing.
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(value, 2);
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
      expect(value, 1);
    });
  });

  testWidgets('V13ProgressBar renders', (tester) async {
    await tester.pumpWidget(
      _wrap(const SizedBox(width: 200, child: V13ProgressBar(value: 0.4))),
    );
    expect(find.byType(V13ProgressBar), findsOneWidget);
  });

  testWidgets('V13ListRow shows divider and fires onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        V13ListRow(
          title: 'Maya Chen',
          subtitle: 'Raced you 9 times',
          trailing: const Icon(Icons.chevron_right),
          onTap: () => taps++,
        ),
      ),
    );
    expect(find.text('Maya Chen'), findsOneWidget);
    expect(find.byType(V13Divider), findsOneWidget);
    await tester.tap(find.text('Maya Chen'));
    expect(taps, 1);
  });

  testWidgets('V13SectionHeader uppercases title, trailing fires', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        V13SectionHeader(
          title: 'Your races · 3',
          trailingLabel: 'Swipe for more',
          onTrailingTap: () => taps++,
        ),
      ),
    );
    expect(find.text('YOUR RACES · 3'), findsOneWidget);
    await tester.tap(find.text('Swipe for more'));
    expect(taps, 1);
  });

  testWidgets('V13IconTile renders its icon', (tester) async {
    await tester.pumpWidget(
      _wrap(const V13IconTile(icon: Icons.fitness_center, color: V13.mint)),
    );
    expect(find.byIcon(Icons.fitness_center), findsOneWidget);
  });

  testWidgets('V13MedalCircle shows the place', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            V13MedalCircle(place: 1),
            V13MedalCircle(place: 2),
            V13MedalCircle(place: 3),
          ],
        ),
      ),
    );
    for (final p in ['1', '2', '3']) {
      expect(find.text(p), findsOneWidget);
    }
  });

  testWidgets('V13StatTriple renders values and uppercased labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const V13StatTriple(
          stats: [
            V13Stat(label: 'Racing', value: '4'),
            V13Stat(label: 'Wins', value: '9'),
            V13Stat(label: 'Win rate', value: '64%'),
          ],
        ),
      ),
    );
    for (final s in ['4', '9', '64%', 'RACING', 'WINS', 'WIN RATE']) {
      expect(find.text(s), findsOneWidget);
    }
  });

  testWidgets('V13HeatMap renders grid plus Less→More legend', (tester) async {
    final today = DateTime.now();
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 340,
          child: V13HeatMap(
            counts: {DateTime(today.year, today.month, today.day): 3},
          ),
        ),
      ),
    );
    expect(find.byType(V13HeatMap), findsOneWidget);
    expect(find.text('Less'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
  });

  testWidgets('V13XpRing renders a face inside the ring', (tester) async {
    await tester.pumpWidget(_wrap(const V13XpRing(progress: 0.6, size: 48)));
    expect(find.byType(V13Face), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('V13NumberPop updates its value', (tester) async {
    await tester.pumpWidget(_wrap(const V13NumberPop(value: 3)));
    expect(find.text('3'), findsOneWidget);

    // Same widget position, new value — the pop replays and text swaps.
    await tester.pumpWidget(_wrap(const V13NumberPop(value: 5)));
    await tester.pump();
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('V13FloatingPlus renders "+N"', (tester) async {
    await tester.pumpWidget(_wrap(const V13FloatingPlus(value: 12)));
    expect(find.text('+12'), findsOneWidget);
  });

  group('feedback overlays', () {
    testWidgets('toast appears near the bottom and disappears', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: V13Button.primary(
                    label: 'Go',
                    onPressed: () => showV13Toast(context, 'Proof logged'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Go'));
      await tester.pump();
      expect(find.text('Proof logged'), findsOneWidget);

      // Auto-dismiss after the toast duration + exit animation.
      await tester.pump(const Duration(milliseconds: 2600));
      await tester.pumpAndSettle();
      expect(find.text('Proof logged'), findsNothing);
    });

    testWidgets('confetti overlay fires and removes itself', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: V13Button.primary(
                    label: 'Join',
                    onPressed: () => showV13Confetti(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Join'));
      await tester.pump();
      expect(find.byType(V13Confetti), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byType(V13Confetti), findsNothing);
    });
  });

  group('sheets', () {
    Future<void> pumpSheetHarness(
      WidgetTester tester,
      void Function(BuildContext) onTap,
    ) {
      return tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: V13Button.primary(
                    label: 'Open',
                    onPressed: () => onTap(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('showV13Sheet renders rounded sheet content', (tester) async {
      await pumpSheetHarness(tester, (context) {
        showV13Sheet<void>(
          context,
          builder: (_) => const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Sheet body'),
          ),
        );
      });
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Sheet body'), findsOneWidget);
    });

    testWidgets('confirm sheet resolves true / false', (tester) async {
      bool? result;
      await pumpSheetHarness(tester, (context) async {
        result = await showV13ConfirmSheet(
          context,
          title: 'Leave this race?',
          body: 'Your progress stays.',
          confirmLabel: 'Leave',
          destructive: true,
        );
      });
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Leave this race?'), findsOneWidget);
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('action sheet resolves the action value', (tester) async {
      String? picked;
      await pumpSheetHarness(tester, (context) async {
        picked = await showV13ActionSheet<String>(
          context,
          title: 'Race options',
          actions: const [
            V13SheetAction(
              label: 'Share race',
              value: 'share',
              icon: Icons.share,
            ),
            V13SheetAction(
              label: 'Leave race',
              value: 'leave',
              icon: Icons.exit_to_app,
              destructive: true,
            ),
          ],
        );
      });
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave race'));
      await tester.pumpAndSettle();
      expect(picked, 'leave');
    });
  });

  group('V13AsyncView', () {
    testWidgets('loading state shows the skeleton', (tester) async {
      await tester.pumpWidget(
        _wrap(
          V13AsyncView<int>(
            value: const AsyncValue.loading(),
            builder: (d) => Text('data $d'),
          ),
        ),
      );
      expect(find.byType(V13Skeleton), findsWidgets);
    });

    testWidgets('error state shows Retry and calls onRetry', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        _wrap(
          V13AsyncView<int>(
            value: AsyncValue.error(StateError('x'), StackTrace.empty),
            onRetry: () => retries++,
            builder: (d) => Text('data $d'),
          ),
        ),
      );
      expect(find.text('Something went wrong'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });

    testWidgets('data state builds child; empty flag shows empty state', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          V13AsyncView<List<int>>(
            value: const AsyncValue.data([1, 2]),
            isEmpty: (d) => d.isEmpty,
            emptyTitle: 'No races yet',
            builder: (d) => Text('count ${d.length}'),
          ),
        ),
      );
      expect(find.text('count 2'), findsOneWidget);

      await tester.pumpWidget(
        _wrap(
          V13AsyncView<List<int>>(
            value: const AsyncValue.data(<int>[]),
            isEmpty: (d) => d.isEmpty,
            emptyTitle: 'No races yet',
            builder: (d) => Text('count ${d.length}'),
          ),
        ),
      );
      expect(find.text('No races yet'), findsOneWidget);
    });

    testWidgets('explicit .state drive renders error', (tester) async {
      await tester.pumpWidget(
        _wrap(
          V13AsyncView<int>.state(
            status: V13AsyncStatus.error,
            onRetry: () {},
            builder: (d) => Text('data $d'),
          ),
        ),
      );
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('bars', () {
    testWidgets('V13TabBar shows 4 slots and reports taps', (tester) async {
      var picked = -1;
      const items = [
        V13TabItem(label: 'Arena', icon: Icons.stadium_outlined),
        V13TabItem(label: 'Compete', icon: Icons.emoji_events_outlined),
        V13TabItem(label: 'Crew', icon: Icons.group_outlined),
        V13TabItem(label: 'Profile', icon: Icons.person_outline),
      ];
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              bottomNavigationBar: V13TabBar(
                items: items,
                currentIndex: 0,
                onTap: (i) => picked = i,
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        expect(find.byKey(ValueKey('v13-tab-slot-$i')), findsOneWidget);
      }
      expect(find.text('Arena'), findsOneWidget);
      expect(find.text('Crew'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('v13-tab-slot-2')));
      expect(picked, 2);
    });

    testWidgets('V13TopBar renders title and trailing', (tester) async {
      await tester.pumpWidget(
        _wrap(const V13TopBar(title: 'Compete', trailing: [Icon(Icons.add)])),
      );
      expect(find.text('Compete'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('V13BackBar back button invokes onBack', (tester) async {
      var backs = 0;
      await tester.pumpWidget(
        _wrap(V13BackBar(title: 'Squat Race', onBack: () => backs++)),
      );
      expect(find.text('Squat Race'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back));
      expect(backs, 1);
    });
  });
}
