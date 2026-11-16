// Quality gate for the full-screen intro scenes (docs/redesign/
// onboarding-v2-motion-brief.md): nothing is clipped by a container, and every
// frame of every scene builds at the small and the tall phone.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/onboarding/intro/intro_demos.dart';

void main() {
  test('no scene or page layer clips its contents (no boxed demos)', () {
    for (final f in [
      'lib/features/onboarding/intro/intro_demos.dart',
      'lib/features/onboarding/intro/intro_pages_step.dart',
    ]) {
      final src = File(f).readAsStringSync();
      for (final banned in [
        'ClipRect(',
        'ClipRRect(',
        'ClipPath(',
        '.clipRect(',
        '.clipRRect(',
        'clipBehavior: Clip.hardEdge',
        'clipBehavior: Clip.antiAlias',
      ]) {
        expect(src.contains(banned), isFalse, reason: '$f uses $banned');
      }
    }
  });

  for (final size in const [Size(320, 568), Size(390, 844)]) {
    testWidgets('every scene frame builds at ${size.width}x${size.height}', (
      t,
    ) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = size;
      addTearDown(t.view.reset);
      final stage = Rect.fromLTRB(
        0,
        76,
        size.width,
        size.height < 640 ? 340 : 532,
      );
      for (var kind = 0; kind < 5; kind++) {
        for (var i = 0; i <= 40; i++) {
          await t.pumpWidget(
            MaterialApp(
              home: SizedBox.expand(
                child: IntroDemo(kind: kind, t: i / 40, stage: stage),
              ),
            ),
          );
          expect(t.takeException(), isNull, reason: 'scene $kind t=${i / 40}');
        }
      }
    });
  }
}
