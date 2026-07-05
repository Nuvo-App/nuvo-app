import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/widgets/nuvo_icons.dart';

void main() {
  group('parseSvgPath', () {
    test('splits decimal-shorthand numbers like "5.2.2" into two tokens', () {
      // Regression check for the fire icon's "a2.6 2.6 0 0 0 5.2.2" arc,
      // where "5.2.2" must be read as x=5.2, y=.2, not a malformed number.
      final path = parseSvgPath('M0 0L5.2.2');
      final metrics = path.computeMetrics().single;
      final end = metrics.getTangentForOffset(metrics.length)!.position;
      expect(end.dx, closeTo(5.2, 0.001));
      expect(end.dy, closeTo(0.2, 0.001));
    });

    test('handles implicit command repeats (M pairs become L)', () {
      final path = parseSvgPath('M13 2 4 14h6');
      final bounds = path.getBounds();
      expect(bounds.left, closeTo(4, 0.001));
      expect(bounds.right, closeTo(13, 0.001));
    });

    test('parses relative arcs without throwing', () {
      // Exercises every icon that uses "a"/"A" (fire, hand, users, user,
      // lock, bell) to catch arcToPoint parameter mistakes.
      for (final type in NuvoIconType.values) {
        expect(() => NuvoIcon(type, size: 24), returnsNormally, reason: 'building $type');
      }
    });
  });

  testWidgets('every Nuvo icon paints without throwing', (tester) async {
    for (final type in NuvoIconType.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: NuvoIcon(type, size: 32, color: Colors.black)),
        ),
      );
      await tester.pump();
      expect(find.byType(NuvoIcon), findsOneWidget, reason: 'icon $type failed to render');
    }
  });
}
