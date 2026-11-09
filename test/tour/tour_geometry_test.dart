import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/motion/motion.dart';
import 'package:nuvo/features/tour/tour_geometry.dart';

void main() {
  test('cutout = target + 8 on every side, radius + 8', () {
    const target = Rect.fromLTWH(40, 200, 200, 90);
    final c = tourCutout(target, targetRadius: 16);
    expect(NuvoMotion.tourCutoutPad, 8);
    expect(c.outerRect, const Rect.fromLTWH(32, 192, 216, 106));
    expect(c.tlRadiusX, 24);
    expect(NuvoMotion.tourCutoutOutline, 2.5);
    expect(NuvoMotion.tourCutoutShadow, 4);
    expect(NuvoMotion.tourScrimOpacity, 0.72);
  });

  for (final screen in const [Size(390, 844), Size(320, 568)]) {
    group(
      'bubble placement on ${screen.width.toInt()}x${screen.height.toInt()}',
      () {
        const bubble = Size(288, 150);
        const safe = EdgeInsets.only(top: 24, bottom: 16);

        for (final y in [90.0, 250.0, screen.height - 160]) {
          test('target at y=$y: inside the screen, never over the cutout', () {
            final cutout = tourCutout(Rect.fromLTWH(30, y, 200, 70)).outerRect;
            final p = placeTourBubble(
              cutout: cutout,
              screen: screen,
              bubble: Size(
                screen.width - 32 < 288 ? screen.width - 32 : 288,
                150,
              ),
              safe: safe,
            );
            expect(
              p.rect.overlaps(cutout),
              isFalse,
              reason: '${p.rect} vs $cutout',
            );
            expect(p.rect.left >= 16, isTrue);
            expect(p.rect.right <= screen.width - 16, isTrue);
            expect(p.rect.top >= safe.top, isTrue);
            expect(p.rect.bottom <= screen.height, isTrue);
          });
        }

        test('flips above when there is no room below', () {
          final cutout = tourCutout(
            Rect.fromLTWH(30, screen.height - 150, 200, 60),
          ).outerRect;
          final p = placeTourBubble(
            cutout: cutout,
            screen: screen,
            bubble: bubble.width > screen.width - 32
                ? Size(screen.width - 32, 150)
                : bubble,
            safe: safe,
          );
          expect(p.side, TourBubbleSide.above);
          final high = placeTourBubble(
            cutout: tourCutout(const Rect.fromLTWH(30, 80, 200, 60)).outerRect,
            screen: screen,
            bubble: Size(screen.width - 32, 150),
            safe: safe,
          );
          expect(high.side, TourBubbleSide.below);
        });
      },
    );
  }

  test('offscreen test respects status bar and dock', () {
    const screen = Size(390, 844);
    expect(
      tourTargetOffscreen(
        const Rect.fromLTWH(0, 300, 100, 50),
        screen: screen,
        top: 44,
        bottom: 100,
      ),
      isFalse,
    );
    expect(
      tourTargetOffscreen(
        const Rect.fromLTWH(0, 780, 100, 50),
        screen: screen,
        top: 44,
        bottom: 100,
      ),
      isTrue,
    );
  });
}
