import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/widgets/race_ring.dart';

void main() {
  group('ringPointForProgress', () {
    const center = Offset(80, 80);
    const radius = 58.0;

    test('0% sits at the top (12 o\'clock)', () {
      final p = ringPointForProgress(progress: 0, center: center, radius: radius);
      expect(p.dx, closeTo(80, 1e-9));
      expect(p.dy, closeTo(80 - radius, 1e-9));
    });

    test('25% sits at 3 o\'clock (quarter turn clockwise)', () {
      final p = ringPointForProgress(progress: 0.25, center: center, radius: radius);
      expect(p.dx, closeTo(80 + radius, 1e-9));
      expect(p.dy, closeTo(80, 1e-9));
    });

    test('50% sits at the bottom (6 o\'clock)', () {
      final p = ringPointForProgress(progress: 0.5, center: center, radius: radius);
      expect(p.dx, closeTo(80, 1e-9));
      expect(p.dy, closeTo(80 + radius, 1e-9));
    });

    test('75% sits at 9 o\'clock', () {
      final p = ringPointForProgress(progress: 0.75, center: center, radius: radius);
      expect(p.dx, closeTo(80 - radius, 1e-9));
      expect(p.dy, closeTo(80, 1e-9));
    });

    test('100% returns to the top, same as 0%', () {
      final start = ringPointForProgress(progress: 0, center: center, radius: radius);
      final end = ringPointForProgress(progress: 1.0, center: center, radius: radius);
      expect(end.dx, closeTo(start.dx, 1e-9));
      expect(end.dy, closeTo(start.dy, 1e-9));
    });

    test('progresses strictly clockwise between quarter turns', () {
      // At 10% (still in the top-right quadrant heading toward 3 o'clock),
      // x should have grown from center and y should still be above center.
      final p = ringPointForProgress(progress: 0.10, center: center, radius: radius);
      expect(p.dx, greaterThan(center.dx));
      expect(p.dy, lessThan(center.dy));
    });

    test('clamps out-of-range progress instead of extrapolating past a full turn', () {
      final over = ringPointForProgress(progress: 1.4, center: center, radius: radius);
      final atOne = ringPointForProgress(progress: 1.0, center: center, radius: radius);
      expect(over.dx, closeTo(atOne.dx, 1e-9));
      expect(over.dy, closeTo(atOne.dy, 1e-9));

      final under = ringPointForProgress(progress: -0.5, center: center, radius: radius);
      final atZero = ringPointForProgress(progress: 0.0, center: center, radius: radius);
      expect(under.dx, closeTo(atZero.dx, 1e-9));
      expect(under.dy, closeTo(atZero.dy, 1e-9));
    });

    test('every point stays exactly radius away from center regardless of progress', () {
      for (var i = 0; i <= 20; i++) {
        final progress = i / 20;
        final p = ringPointForProgress(progress: progress, center: center, radius: radius);
        final distance = (p - center).distance;
        expect(distance, closeTo(radius, 1e-9), reason: 'progress=$progress');
      }
    });

    test('matches the prototype formula literally: angle = -90 + progressPercent/100*360', () {
      for (final progressPercent in [0, 17, 34, 50, 76, 99]) {
        final angle = -90 + (progressPercent / 100) * 360;
        final radians = angle * (math.pi / 180);
        final expected = Offset(
          center.dx + radius * math.cos(radians),
          center.dy + radius * math.sin(radians),
        );
        final actual = ringPointForProgress(
          progress: progressPercent / 100,
          center: center,
          radius: radius,
        );
        expect(actual.dx, closeTo(expected.dx, 1e-9));
        expect(actual.dy, closeTo(expected.dy, 1e-9));
      }
    });
  });

  testWidgets('RaceRing renders with racer markers without throwing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: RaceRing(
              progress: 0.34,
              centerValue: '17',
              centerLabel: 'reps',
              racers: [
                RingRacer(id: 'a', initials: 'LP', progress: 0.76),
                RingRacer(id: 'b', initials: 'MK', progress: 0.44),
                RingRacer(id: 'you', initials: 'You', progress: 0.34, isCurrentUser: true),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(RaceRing), findsOneWidget);
    expect(find.text('17'), findsOneWidget);
  });
}
