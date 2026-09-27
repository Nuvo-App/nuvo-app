import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nuvo/core/widgets/nuvo_motion.dart';
import 'package:nuvo/core/widgets/nuvo_number_flow.dart';

Widget _wrap(Widget child, {bool disableAnimations = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

Widget _row(String label, {double height = 40, Key? key}) => Container(
      key: key ?? ValueKey(label),
      height: height,
      width: 200,
      color: Colors.white,
      child: Text(label),
    );

void main() {
  group('NuvoPop', () {
    testWidgets('does not animate on first build', (tester) async {
      await tester.pumpWidget(
        _wrap(const NuvoPop(trigger: false, child: Text('🔥'))),
      );
      // First frame is the rest state — nothing runs.
      final scale = tester.widget<Transform>(
        find.ancestor(
          of: find.text('🔥'),
          matching: find.byType(Transform),
        ).first,
      );
      expect(scale.transform.getMaxScaleOnAxis(), 1);
    });

    testWidgets('pops (scale > 1) mid-animation when trigger flips',
        (tester) async {
      var trigger = false;
      late StateSetter setOuter;
      await tester.pumpWidget(
        _wrap(StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return NuvoPop(trigger: trigger, child: const Text('🔥'));
          },
        )),
      );
      setOuter(() => trigger = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final scale = tester.widget<Transform>(
        find
            .ancestor(
              of: find.text('🔥'),
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(scale.transform.getMaxScaleOnAxis(), greaterThan(1));
      await tester.pump(const Duration(milliseconds: 400));
      final settled = tester.widget<Transform>(
        find
            .ancestor(
              of: find.text('🔥'),
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(settled.transform.getMaxScaleOnAxis(), closeTo(1, 0.001));
    });

    testWidgets('skips animation entirely under reduced motion',
        (tester) async {
      var trigger = false;
      late StateSetter setOuter;
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return NuvoPop(trigger: trigger, child: const Text('🔥'));
            },
          ),
          disableAnimations: true,
        ),
      );
      setOuter(() => trigger = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final scale = tester.widget<Transform>(
        find
            .ancestor(
              of: find.text('🔥'),
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(scale.transform.getMaxScaleOnAxis(), 1);
    });
  });

  group('NuvoReorderColumn', () {
    testWidgets('one-place overtake: rows trade places, no error',
        (tester) async {
      var order = ['A', 'B', 'C'];
      late StateSetter setOuter;
      await tester.pumpWidget(
        _wrap(StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return NuvoReorderColumn(
              children: [for (final k in order) _row(k)],
            );
          },
        )),
      );
      await tester.pumpAndSettle();
      final aBefore = tester.getTopLeft(find.text('A')).dy;
      final bBefore = tester.getTopLeft(find.text('B')).dy;
      setOuter(() => order = ['B', 'A', 'C']);
      await tester.pump();
      // FLIP capture happens in a post-frame callback — give it one frame.
      await tester.pump();
      // Mid-flight: positions are transitioning, nothing has jumped yet.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('B')).dy, aBefore);
      expect(tester.getTopLeft(find.text('A')).dy, bBefore);
    });

    testWidgets('multi-place movement settles to canonical order',
        (tester) async {
      var order = ['A', 'B', 'C', 'D'];
      late StateSetter setOuter;
      await tester.pumpWidget(
        _wrap(StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return NuvoReorderColumn(
              children: [for (final k in order) _row(k)],
            );
          },
        )),
      );
      await tester.pumpAndSettle();
      setOuter(() => order = ['D', 'A', 'B', 'C']);
      await tester.pumpAndSettle();
      final ys = [
        for (final k in ['D', 'A', 'B', 'C'])
          tester.getTopLeft(find.text(k)).dy,
      ];
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThan(ys[i - 1]));
      }
    });

    testWidgets('newly inserted row enters without crashing',
        (tester) async {
      var order = ['A', 'B'];
      late StateSetter setOuter;
      await tester.pumpWidget(
        _wrap(StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return NuvoReorderColumn(
              children: [for (final k in order) _row(k)],
            );
          },
        )),
      );
      await tester.pumpAndSettle();
      setOuter(() => order = ['A', 'B', 'C']);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('C'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('reduced motion: swaps instantly, still correct order',
        (tester) async {
      var order = ['A', 'B', 'C'];
      late StateSetter setOuter;
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return NuvoReorderColumn(
                children: [for (final k in order) _row(k)],
              );
            },
          ),
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();
      setOuter(() => order = ['C', 'A', 'B']);
      await tester.pump();
      await tester.pump();
      expect(tester.getTopLeft(find.text('C')).dy,
          lessThan(tester.getTopLeft(find.text('A')).dy));
    });
  });

  group('NuvoReorderColumn edge cases', () {
    testWidgets('row removal: survivors settle, no crash', (tester) async {
      var order = ['A', 'B', 'C'];
      late StateSetter setOuter;
      await tester.pumpWidget(
        _wrap(StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return NuvoReorderColumn(
              children: [for (final k in order) _row(k)],
            );
          },
        )),
      );
      await tester.pumpAndSettle();
      setOuter(() => order = ['A', 'C']);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.text('B'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'score change without order change: no deltas, positions stable',
        (tester) async {
      var scores = [10, 5];
      late StateSetter setOuter;
      await tester.pumpWidget(
        _wrap(StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return NuvoReorderColumn(
              children: [
                for (var i = 0; i < scores.length; i++)
                  _row('p$i:${scores[i]}', key: ValueKey('p$i')),
              ],
            );
          },
        )),
      );
      await tester.pumpAndSettle();
      final before = tester.getTopLeft(find.text('p0:10')).dy;
      // Content changes (score) but keys and order stay — nothing travels.
      setOuter(() => scores = [99, 5]);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('p0:99')).dy, before);
    });

    testWidgets('remove then re-add: item re-enters without leak',
        (tester) async {
      var order = ['A', 'B'];
      late StateSetter setOuter;
      await tester.pumpWidget(
        _wrap(StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return NuvoReorderColumn(
              children: [for (final k in order) _row(k)],
            );
          },
        )),
      );
      await tester.pumpAndSettle();
      setOuter(() => order = ['A']);
      await tester.pumpAndSettle();
      setOuter(() => order = ['A', 'B']);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text('B'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('NuvoShake', () {
    testWidgets('shakes horizontally when trigger changes', (tester) async {
      var nudges = 0;
      late StateSetter setOuter;
      await tester.pumpWidget(
        _wrap(StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return NuvoShake(trigger: nudges, child: const Text('field'));
          },
        )),
      );
      setOuter(() => nudges = 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      final t = tester.widget<Transform>(
        find
            .ancestor(of: find.text('field'), matching: find.byType(Transform))
            .first,
      );
      expect(t.transform.getTranslation().x.abs(), greaterThan(0));
      await tester.pump(const Duration(milliseconds: 400));
      final settled = tester.widget<Transform>(
        find
            .ancestor(of: find.text('field'), matching: find.byType(Transform))
            .first,
      );
      expect(settled.transform.getTranslation().x, closeTo(0, 0.001));
    });

    testWidgets('same trigger does not replay', (tester) async {
      await tester.pumpWidget(
        _wrap(const NuvoShake(trigger: 1, child: Text('field'))),
      );
      await tester.pump(const Duration(milliseconds: 90));
      final t = tester.widget<Transform>(
        find
            .ancestor(of: find.text('field'), matching: find.byType(Transform))
            .first,
      );
      expect(t.transform.getTranslation().x, 0);
    });

    testWidgets('reduced motion: no shake', (tester) async {
      var nudges = 0;
      late StateSetter setOuter;
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return NuvoShake(trigger: nudges, child: const Text('field'));
            },
          ),
          disableAnimations: true,
        ),
      );
      setOuter(() => nudges = 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      final t = tester.widget<Transform>(
        find
            .ancestor(of: find.text('field'), matching: find.byType(Transform))
            .first,
      );
      expect(t.transform.getTranslation().x, 0);
    });
  });

  group('NuvoStateMorph', () {
    testWidgets('crossfades between state children', (tester) async {
      var state = 'none';
      late StateSetter setOuter;
      await tester.pumpWidget(
        _wrap(StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return NuvoStateMorph(
              stateKey: state,
              child: state == 'none'
                  ? const SizedBox(height: 48, child: Text('Add'))
                  : const SizedBox(height: 28, child: Text('Sent')),
            );
          },
        )),
      );
      setOuter(() => state = 'sent');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Mid-morph: both children are in the tree (crossfade).
      expect(find.text('Add'), findsOneWidget);
      expect(find.text('Sent'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Add'), findsNothing);
      expect(find.text('Sent'), findsOneWidget);
    });
  });

  group('NuvoNumberFlow in competitive values', () {
    testWidgets('rolls when the value increases', (tester) async {
      var value = 3;
      late StateSetter setOuter;
      await tester.pumpWidget(
        _wrap(StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return NuvoNumberFlow(value: value);
          },
        )),
      );
      expect(find.text('3'), findsOneWidget);
      setOuter(() => value = 4);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // During the roll both digits may be in the tree (outgoing + incoming).
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.text('4'), findsOneWidget);
    });
  });
}
