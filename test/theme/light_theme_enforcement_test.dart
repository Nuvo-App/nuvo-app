import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nuvo/app/app.dart';
import 'package:nuvo/core/theme/app_colors.dart';
import 'package:nuvo/core/theme/app_theme.dart';
import 'package:nuvo/core/widgets/bottom_nav.dart';

import '../support/nuvo_test_harness.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Light Theme Enforcement
//
// Nuvo has ONE light application theme. Every primary tab — Arena included —
// must render light regardless of the device's system appearance setting.
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    final label = brightness == Brightness.dark
        ? 'platform dark'
        : 'platform light';

    group('All five tabs stay light — $label', () {
      for (final tab in kNuvoTabs) {
        testWidgets('${tab.name} shell background is NuvoColors.page',
            (tester) async {
          await pumpNuvoTab(tester, tab.route, platformBrightness: brightness);

          final shell = tester
              .widgetList<Scaffold>(find.byType(Scaffold))
              .first;
          expect(
            shell.backgroundColor,
            equals(NuvoColors.page),
            reason: '${tab.name} shell must be NuvoColors.page '
                '(#F7F9FC); got ${shell.backgroundColor}',
          );
        });

        testWidgets('${tab.name} navigation surface is white', (tester) async {
          await pumpNuvoTab(tester, tab.route, platformBrightness: brightness);
          expectLightNavSurface(tester, tab.name);
        });
      }
    });
  }

  group('No dark surface leaks into any tab', () {
    for (final tab in kNuvoTabs) {
      testWidgets('${tab.name} paints no full-page dark background',
          (tester) async {
        await pumpNuvoTab(tester, tab.route);

        // A page-sized navy/near-black box would mean a screen is still
        // rendering a dark hero or a dark canvas.
        final size = tester.view.physicalSize / tester.view.devicePixelRatio;
        for (final c in tester.widgetList<Container>(find.byType(Container))) {
          final deco = c.decoration;
          if (deco is! BoxDecoration) continue;
          final color = deco.color;
          if (color == null || color.a < 0.9) continue;
          if (color.computeLuminance() > 0.2) continue;

          final ctxFinder = find.byWidget(c);
          if (ctxFinder.evaluate().isEmpty) continue;
          final box = tester.getSize(ctxFinder.first);
          final coversPage =
              box.width > size.width * 0.85 && box.height > size.height * 0.4;
          expect(
            coversPage,
            isFalse,
            reason: '${tab.name} has a page-sized dark surface '
                '($color at $box) — that reads as dark mode',
          );
        }
      });
    }
  });

  group('Theme configuration', () {
    testWidgets('NuvoApp pins ThemeMode.light and a light darkTheme',
        (tester) async {
      await tester.pumpWidget(const ProviderScope(child: NuvoApp()));
      await tester.pump();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.light,
          reason: 'themeMode must be explicitly light');
      expect(app.darkTheme, isNotNull,
          reason: 'darkTheme must be set so system dark cannot take over');
      expect(app.darkTheme!.brightness, Brightness.light,
          reason: 'darkTheme must itself be a light theme');
    });

    test('AppTheme.light() is light and uses the page colour', () {
      final theme = AppTheme.light();
      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, NuvoColors.page);
    });

    test('palette matches the approved light specification', () {
      expect(NuvoColors.page, const Color(0xFFF7F9FC));
      expect(NuvoColors.surface, const Color(0xFFFFFFFF));
      expect(NuvoColors.secondarySurface, const Color(0xFFEEF4FF));
      expect(NuvoColors.navy, const Color(0xFF152238));
      expect(NuvoColors.textMuted, const Color(0xFF7F8795));
      expect(NuvoColors.blue, const Color(0xFF2F7CFF));
      expect(NuvoColors.border, const Color(0xFFDDE4EE));
      expect(NuvoColors.disabledSurface, const Color(0xFFE8ECF2));
    });

    test('page is bright and navy is dark enough to read on it', () {
      expect(NuvoColors.page.computeLuminance(), greaterThan(0.85));
      expect(NuvoColors.navy.computeLuminance(), lessThan(0.1));
    });
  });

  group('Navigation is shared and consistent across all five tabs', () {
    testWidgets('every tab renders exactly one NuvoBottomNav', (tester) async {
      for (final tab in kNuvoTabs) {
        await pumpNuvoTab(tester, tab.route);
        expect(find.byType(NuvoBottomNav), findsOneWidget,
            reason: '${tab.name} must show exactly one shared nav');
      }
    });

    testWidgets('the active tab is the only one marked selected',
        (tester) async {
      for (var i = 0; i < kNuvoTabs.length; i++) {
        await pumpNuvoTab(tester, kNuvoTabs[i].route);

        // The selected nav button paints a translucent blue chip; the others
        // are transparent. Count how many chips are tinted.
        final tinted = tester
            .widgetList<AnimatedContainer>(
              find.descendant(
                of: find.byType(NuvoBottomNav),
                matching: find.byType(AnimatedContainer),
              ),
            )
            .where((c) {
              final deco = c.decoration;
              if (deco is! BoxDecoration) return false;
              final color = deco.color;
              return color != null && color.a > 0.01;
            }).length;

        expect(tinted, 1,
            reason: 'On ${kNuvoTabs[i].name} exactly one nav button should '
                'be marked selected, but $tinted were tinted');
      }
    });
  });
}
