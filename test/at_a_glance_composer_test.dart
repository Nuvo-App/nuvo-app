// At-a-glance contract for the race composer: on first load of every step,
// nothing is cut off by the viewport bottom or the pinned CTA, nothing
// overflows, and scrolling steps carry a bottom fade.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nuvo/core/theme/app_theme.dart';
import 'package:nuvo/core/widgets/nuvo_button.dart';
import 'package:nuvo/core/widgets/nuvo_fade_scroll.dart';
import 'package:nuvo/features/races/presentation/race_composer_screen.dart';

const _sizes = [
  Size(320, 568),
  Size(375, 667),
  Size(390, 844),
  Size(393, 852),
  Size(430, 932),
];
const _stepNames = ['name', 'activity', 'goal', 'racers', 'review'];

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  for (final size in _sizes) {
    for (final inset in [0.0, 34.0]) {
      for (final dark in [false, true]) {
        for (final scale in [1.0, 1.3]) {
          final label =
              '${size.width.toInt()}x${size.height.toInt()} inset$inset '
              '${dark ? 'dark' : 'light'} x$scale';
          testWidgets('composer at a glance: $label', (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            tester.view.padding = FakeViewPadding(top: 47, bottom: inset);
            tester.view.viewPadding = FakeViewPadding(top: 47, bottom: inset);
            addTearDown(tester.view.reset);

            await tester.pumpWidget(
              ProviderScope(
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: dark ? AppTheme.dark() : AppTheme.light(),
                  home: MediaQuery.withClampedTextScaling(
                    minScaleFactor: scale,
                    maxScaleFactor: scale,
                    child: const RaceComposerScreen(),
                  ),
                ),
              ),
            );

            for (var i = 0; i < _stepNames.length; i++) {
              await tester.pumpAndSettle(const Duration(milliseconds: 100));
              _check(tester, size, '$label step ${_stepNames[i]}');
              if (i == _stepNames.length - 1) break;
              if (i == 0) {
                await tester.enterText(
                  find.byType(TextField).first,
                  'Sunday showdown',
                );
                await tester.pump();
              }
              final cta = find.byType(NuvoPrimaryButton).hitTestable();
              expect(cta, findsWidgets, reason: 'CTA on ${_stepNames[i]}');
              await tester.tap(cta.last);
              await tester.pumpAndSettle(const Duration(milliseconds: 100));
            }
          });
        }
      }
    }
  }
}

void _check(WidgetTester tester, Size size, String where) {
  expect(tester.takeException(), isNull, reason: where);
  final buttons = find.byType(NuvoPrimaryButton).hitTestable();
  expect(buttons, findsWidgets, reason: '$where: CTA missing');
  final ctaTop = tester.getTopLeft(buttons.last).dy - 8;

  // Scroll metrics of the page on screen.
  var scrolls = false;
  var contentBottom = 0.0;
  final softCut = <String>[];
  var scrollBottom = double.infinity;
  for (final s in tester.stateList<ScrollableState>(
    find.byType(Scrollable).hitTestable(),
  )) {
    if (s.position.axis != Axis.vertical) continue;
    final pos = s.position;
    final box = s.context.findRenderObject()! as RenderBox;
    if (box.size.width < size.width * 0.9) continue;
    scrollBottom = box.localToGlobal(Offset(0, box.size.height)).dy;
    if (pos.maxScrollExtent > 1) scrolls = true;
  }
  final hasFade = find.byType(NuvoFadeScroll).evaluate().isNotEmpty;
  if (scrolls) {
    expect(hasFade, isTrue, reason: '$where: scrolling step lacks fade');
  }

  for (final e in find.byType(RichText).evaluate()) {
    final ro = e.renderObject;
    if (ro is! RenderParagraph) continue;
    if (ro.text.toPlainText().trim().isEmpty) continue;
    final tl = ro.localToGlobal(Offset.zero);
    final r = tl & ro.size;
    if (r.right < 0 || r.left >= size.width) continue; // other page
    if (r.top < 80 && r.bottom < 80) continue; // top bar area
    // Skip text scrolled above/inside obscured overlays: only hit CTA zone.
    double? vb;
    for (RenderObject? p = ro.parent; p != null; p = p.parent) {
      if (p is RenderViewportBase) {
        final b = p as RenderBox;
        if (b.size.width > size.width * 0.9) {
          vb = b.localToGlobal(Offset(0, b.size.height)).dy;
        }
        break;
      }
    }
    if (vb != null) {
      // Inside a scroller: whole, or hidden below the fade edge.
      if (r.top >= vb - 0.5) continue;
      if (r.bottom > vb + 0.5) {
        final ok = find.byType(NuvoFadeScroll).evaluate().isNotEmpty;
        if (!ok) fail('$where: "${ro.text.toPlainText()}" cut at scroll edge');
        softCut.add(ro.text.toPlainText());
      }
      continue;
    }
    if (r.bottom > size.height + 0.5 && r.top < size.height) {
      fail('$where: "${ro.text.toPlainText()}" straddles viewport bottom $r');
    }
    if (!scrolls && r.top >= 0 && r.top < ctaTop - 0.5 && r.bottom > ctaTop + 0.5) {
      fail('$where: "${ro.text.toPlainText()}" straddles CTA top ($r vs $ctaTop)');
    }
    if (!scrolls && r.top < ctaTop && r.bottom > ctaTop + 0.5) {
      fail('$where: "${ro.text.toPlainText()}" overlaps CTA');
    }
    contentBottom = contentBottom < r.bottom ? r.bottom : contentBottom;
  }
  if (softCut.isNotEmpty) debugPrint('SOFT $where: $softCut');
  if (scrollBottom.isFinite) {
    expect(scrollBottom, lessThanOrEqualTo(ctaTop + 0.5),
        reason: '$where: scroll area runs under CTA');
  }
}
