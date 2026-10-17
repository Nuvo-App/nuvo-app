import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nuvo/core/theme/app_colors.dart';
import 'package:nuvo/core/theme/app_theme.dart';
import 'package:nuvo/core/widgets/bottom_nav.dart';
import 'package:nuvo/core/widgets/nuvo_back_header.dart';
import 'package:nuvo/core/widgets/nuvo_button.dart';
import 'package:nuvo/core/widgets/nuvo_empty_state.dart';
import 'package:nuvo/core/widgets/nuvo_error_state.dart';

double _lum(Color c) {
  double f(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}

double _contrast(Color a, Color b) {
  final hi = math.max(_lum(a), _lum(b));
  final lo = math.min(_lum(a), _lum(b));
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  const d = NuvoThemeColors.dark;

  group('dark palette contrast', () {
    test('ink / muted / subtle meet AA on page and surface', () {
      for (final bg in [d.page, d.surface]) {
        expect(_contrast(d.ink, bg), greaterThanOrEqualTo(4.5));
        expect(_contrast(d.inkMuted, bg), greaterThanOrEqualTo(4.5));
        expect(_contrast(d.inkSubtle, bg), greaterThanOrEqualTo(4.5));
      }
    });

    test('inkDim stays legible for decoration (>= 3:1)', () {
      expect(_contrast(d.inkDim, d.page), greaterThanOrEqualTo(3.0));
      expect(_contrast(d.inkDim, d.surface), greaterThanOrEqualTo(3.0));
    });

    test('ink is a cold off-white, not pure white', () {
      expect(d.ink, isNot(const Color(0xFFFFFFFF)));
    });

    test('accent and semantic text tokens meet AA on page and surface', () {
      for (final bg in [d.page, d.surface]) {
        expect(_contrast(d.accent, bg), greaterThanOrEqualTo(4.5));
        expect(_contrast(d.successText, bg), greaterThanOrEqualTo(4.5));
        expect(_contrast(d.dangerText, bg), greaterThanOrEqualTo(4.5));
        expect(_contrast(d.warningText, bg), greaterThanOrEqualTo(4.5));
        expect(_contrast(d.goldText, bg), greaterThanOrEqualTo(4.5));
      }
    });

    test('light theme keeps brand blue as accent', () {
      expect(NuvoThemeColors.light.accent, NuvoColors.blue);
    });
  });

  group('dark elevation ladder', () {
    test('page < surface < panelLight < panel (strictly increasing)', () {
      expect(_lum(d.page), lessThan(_lum(d.surface)));
      expect(_lum(d.surface), lessThan(_lum(d.panelLight)));
      expect(_lum(d.panelLight), lessThan(_lum(d.panel)));
    });

    test('border is visible but softer than ink; plate is deeper than page', () {
      expect(_contrast(d.border, d.surface), greaterThan(1.4));
      expect(_contrast(d.border, d.surface), lessThan(3.0));
      expect(_lum(d.inkShadow), lessThan(_lum(d.page)));
      expect(_lum(d.inkShadow), lessThan(_lum(d.border)));
    });
  });

  group('core widgets render in both themes', () {
    Future<void> pump(WidgetTester t, ThemeData theme) async {
      await t.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  NuvoBackHeader(title: 'Header', onBack: () {}),
                  NuvoPrimaryButton(label: 'Primary go', onPressed: () {}),
                  NuvoOutlineButton(label: 'Outline go', onPressed: () {}),
                  const NuvoEmptyState(
                    icon: Icons.flag_rounded,
                    title: 'Empty title',
                    body: 'Empty body',
                  ),
                  NuvoErrorState(message: 'Broke', onRetry: () {}),
                  NuvoBottomNav(currentIndex: 0, onTap: (_) {}),
                ],
              ),
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 400));
    }

    for (final entry in {
      'dark': AppTheme.dark,
      'light': AppTheme.light,
    }.entries) {
      testWidgets('${entry.key}: no exceptions, primary pair has contrast', (
        t,
      ) async {
        await pump(t, entry.value());
        expect(t.takeException(), isNull);

        final label = t.widget<Text>(find.text('Primary go'));
        final fg = label.style?.color;
        expect(fg, isNotNull);
        expect(_contrast(fg!, NuvoColors.blue), greaterThanOrEqualTo(4.5));
      });
    }

    testWidgets('dark theme exposes dark chrome extension', (t) async {
      await pump(t, AppTheme.dark());
      final ctx = t.element(find.text('Empty title'));
      expect(ctx.themeColors.page, NuvoColors.darkPage);
      expect(ctx.themeColors.accent, d.accent);
      expect(
        _contrast(
          t.widget<Text>(find.text('Empty title')).style?.color ?? d.ink,
          ctx.themeColors.page,
        ),
        greaterThanOrEqualTo(4.5),
      );
    });
  });
}
