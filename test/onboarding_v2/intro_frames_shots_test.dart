// Frame strips for each intro moment (anticipation, climax, settle). Run
// with SHOTS_DIR to write PNGs; otherwise this only checks every frame builds.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/v13/tokens.dart';
import 'package:nuvo/features/onboarding/intro/intro_demos.dart';

import '../helpers/screenshot.dart';

const _fields = [V13.sky, V13.mint, V13.lilac, V13.sun, V13.sky];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadShotFonts);
  final on = (Platform.environment['SHOTS_DIR'] ?? '').isNotEmpty;
  for (var kind = 0; kind < 5; kind++) {
    for (final size in const {
      'l': Size(342, 420),
      'xs': Size(272, 250),
    }.entries) {
      testWidgets('frames page ${kind + 1} ${size.key}', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = size.value;
        addTearDown(t.view.reset);
        final c = introClimax[kind];
        final frames = [0.30, c - 0.14, c + 0.02, c + 0.07, c + 0.18, 1.0];
        for (var i = 0; i < frames.length; i++) {
          await t.pumpWidget(
            MaterialApp(
              home: ColoredBox(
                color: _fields[kind],
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: IntroDemo(kind: kind, t: frames[i]),
                ),
              ),
            ),
          );
          await t.pump();
          if (on) await shot(t, 'frames_${size.key}_${kind}_$i');
        }
      });
    }
  }
}
