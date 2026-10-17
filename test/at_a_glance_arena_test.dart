import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/widgets/bottom_nav.dart';
import 'package:nuvo/features/arena/data/arena_models.dart';
import 'package:nuvo/features/arena/presentation/arena_screen.dart';
import 'package:nuvo/features/shell/presentation/main_shell.dart';

void main() {
  Future<void> pumpArena(
    WidgetTester tester,
    Size size, {
    double bottomInset = 34,
    double textScale = 1.0,
    ArenaSnapshot? snapshot,
    bool dark = false,
    bool reduceMotion = false,
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(top: 47, bottom: bottomInset);
    tester.view.viewPadding = FakeViewPadding(top: 47, bottom: bottomInset);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    final router = GoRouter(
      initialLocation: '/arena',
      routes: [
        ShellRoute(
          builder: (c, s, child) => MainShell(child: child),
          routes: [
            GoRoute(
              path: '/arena',
              builder: (c, s) =>
                  ArenaScreen(preview: true, debugSnapshot: snapshot),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          theme: dark ? ThemeData.dark() : null,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: reduceMotion,
            ),
            child: child!,
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  ArenaSnapshot snap(List<(String, String, bool)> rows) => ArenaSnapshot(
    mode: 'real',
    headerPulse: '',
    focusBoard: ArenaBoard(
      id: 'r1',
      source: 'real',
      title: 'First to 100 Pushups',
      progressLabel: '22 / 100 reps',
      boardContext: '',
      primaryActionLabel: 'Submit proof',
      primaryActionType: 'submit_proof',
      progressPercent: 22,
      racerCount: rows.length,
      isResult: false,
      myRank: rows.indexWhere((r) => r.$3) + 1,
      chaseCopy: 'You trail Alex by 17 reps.',
      miniLeaderboard: [
        for (final r in rows)
          ArenaMiniLeaderboardRow(
            label: r.$1,
            value: '${r.$2} / 100',
            isCurrentUser: r.$3,
          ),
      ],
    ),
    activity: const [],
  );

  final full = snap([
    ('Alex R.', '39', false),
    ('Maya L.', '31', false),
    ('You', '22', true),
  ]);
  const sizes = <Size>[
    Size(320, 568),
    Size(375, 667),
    Size(390, 844),
    Size(393, 852),
    Size(430, 932),
  ];
  for (final size in sizes) {
    for (final inset in [0.0, 34.0]) {
      for (final dark in [false, true]) {
        for (final scale in [1.0, 1.3]) {
          testWidgets(
            'arena at-a-glance ${size.width.toInt()}x${size.height.toInt()} '
            'inset $inset ${dark ? 'dark' : 'light'} x$scale',
            (tester) async {
              await pumpArena(
                tester,
                size,
                bottomInset: inset,
                dark: dark,
                textScale: scale,
                snapshot: full,
              );
              expect(tester.takeException(), isNull);
              final navTop = tester.getTopLeft(find.byType(NuvoBottomNav)).dy;
              final fade = find
                  .byKey(const ValueKey('nuvo-bottom-fade'))
                  .evaluate()
                  .isNotEmpty;
              final screen = Offset.zero & size;
              for (final e in find.byType(Text).evaluate()) {
                final f = find.byWidget(e.widget);
                final r = tester.getRect(f);
                if (!r.overlaps(screen) || r.top >= size.height) continue;
                // Skip text inside the nav itself.
                if (find
                    .descendant(of: find.byType(NuvoBottomNav), matching: f)
                    .evaluate()
                    .isNotEmpty) {
                  continue;
                }
                final label = (e.widget as Text).data ?? '';
                if (!fade) {
                  expect(
                    r.top < navTop - 0.5 && r.bottom > navTop + 0.5,
                    isFalse,
                    reason: 'Text "$label" $r straddles nav top $navTop',
                  );
                }
                expect(
                  r.bottom,
                  lessThanOrEqualTo(size.height + 0.5),
                  reason: 'Text "$label" crosses viewport bottom',
                );
              }
              if (scale == 1.0) {
                for (final t in ['Alex', 'Maya', 'You', 'Submit proof']) {
                  for (final el in find.text(t).evaluate()) {
                    final ro = el.renderObject;
                    if (ro is RenderParagraph) {
                      expect(
                        ro.didExceedMaxLines,
                        isFalse,
                        reason: '"$t" ellipsized',
                      );
                    }
                  }
                }
              }
            },
          );
        }
      }
    }
  }
}
