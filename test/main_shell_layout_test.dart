// Regression coverage for the MainShell layout contract: every tab renders
// through one Scaffold(bottomNavigationBar: ..., extendBody: true). The nav
// is a connected bar — full width, flush against the bottom edge — and the
// body extends to the screen's bottom edge underneath it. Scrollable screens
// clear the bar with NuvoBottomNav.bottomPadding.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/widgets/bottom_nav.dart';
import 'package:nuvo/features/shell/presentation/main_shell.dart';

/// A screen that fills all available space — tall enough that, if the shell
/// ever let the body extend behind the nav again, this would occupy that
/// space rather than trivially satisfying the bound check.
class _FillScreen extends StatelessWidget {
  const _FillScreen({this.tag = 'fill'});
  final String tag;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: ValueKey('fill-screen-$tag'),
      color: Colors.white,
      child: const SizedBox.expand(),
    );
  }
}

Future<void> _pumpShell(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);

  final router = GoRouter(
    initialLocation: '/arena',
    routes: [
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/arena',
            builder: (context, state) => const _FillScreen(tag: 'arena'),
          ),
          GoRoute(
            path: '/compete',
            builder: (context, state) => const _FillScreen(tag: 'compete'),
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(child: MaterialApp.router(routerConfig: router)),
  );
  await tester.pumpAndSettle();
}

RenderBox _navRenderBox(WidgetTester tester) => tester.renderObject<RenderBox>(
  find.byWidgetPredicate((w) => w.runtimeType.toString() == 'NuvoBottomNav'),
);

void main() {
  const sizes = <String, Size>{
    'iPhone SE (375x812)': Size(375, 812),
    'standard iPhone (390x844)': Size(390, 844),
    'Pro Max iPhone (430x932)': Size(430, 932),
  };

  for (final entry in sizes.entries) {
    testWidgets('${entry.key}: nav is edge-connected and body slides under', (
      tester,
    ) async {
      await _pumpShell(tester, entry.value);
      expect(tester.takeException(), isNull);

      final navBox = _navRenderBox(tester);
      final navTopLeft = navBox.localToGlobal(Offset.zero);

      // Floating dock: horizontally inset, and its bottom edge sits at the
      // very bottom of the screen (the inset margin is part of the widget).
      expect(
        navTopLeft.dx,
        0,
        reason:
            '${entry.key}: nav widget starts at the left edge (the dock is '
            'inset inside it)',
      );
      expect(
        navBox.size.width,
        entry.value.width,
        reason: '${entry.key}: nav must span the full screen width',
      );
      expect(
        navTopLeft.dy + navBox.size.height,
        entry.value.height,
        reason: '${entry.key}: nav must sit flush against the bottom edge',
      );

      // extendBody: true — the body reaches the bottom edge underneath the
      // bar rather than ending above it.
      final bodyBox = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('fill-screen-arena')),
      );
      final bodyTopY = bodyBox.localToGlobal(Offset.zero).dy;
      final bodyBottomY = bodyTopY + bodyBox.size.height;

      expect(
        bodyBottomY,
        greaterThan(navTopLeft.dy + 0.5),
        reason:
            '${entry.key}: the body must extend underneath the connected '
            'nav bar — content slides under it, so the body cannot stop at '
            "the bar's top edge.",
      );
      expect(
        bodyBox.size.height,
        greaterThan(entry.value.height * 0.6),
        reason:
            '${entry.key}: body should retain the large majority of '
            'the screen.',
      );
    });
  }

  testWidgets('nav footprint is compact — content zone + safe inset only', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(390, 844));

    final navBox = _navRenderBox(tester);

    // The rendered nav is exactly navDockHeight + the device bottom inset
    // (34 in this harness). No padding is allowed to sneak back in — this is
    // the regression guard for the compact dock contract.
    expect(
      navBox.size.height,
      NuvoBottomNav.navDockHeight + 34,
      reason: 'nav renders dock height + safe inset, nothing else',
    );
    expect(
      navBox.size.height,
      lessThan(100),
      reason:
          'compact dock: total footprint stays under ~100px on modern '
          'iPhones (dock 58 + inset 34)',
    );

    // The shared scroll contract reserves the dock, Verify's rise above its
    // top edge, plus a small section gap — never a second dock's worth of
    // dead space.
    final context = tester.element(
      find.byKey(const ValueKey('fill-screen-arena')),
    );
    final clearance = NuvoBottomNav.bottomPadding(context);
    expect(
      clearance,
      NuvoBottomNav.navDockHeight +
          34 +
          NuvoBottomNav.navVerifyRaise +
          NuvoBottomNav.navScrollClearance,
    );
    expect(
      clearance,
      lessThan(115),
      reason:
          'screens reserve the full obstruction + a small gap, not a '
          'shelf',
    );
  });

  testWidgets(
    'scrollable tab content clears the dock through a nested Scaffold',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);

      // Mirror the real screens: every tab builds its own inner Scaffold and
      // applies NuvoBottomNav.bottomPadding inside the scroll view. The
      // contract must survive that nesting — if the inner Scaffold reset
      // MediaQuery.padding.bottom, the last row would land under the dock.
      final router = GoRouter(
        initialLocation: '/arena',
        routes: [
          ShellRoute(
            builder: (context, state, child) => MainShell(child: child),
            routes: [
              GoRoute(
                path: '/arena',
                builder: (context, state) => Scaffold(
                  body: SafeArea(
                    bottom: false,
                    child: ListView(
                      padding: EdgeInsets.only(
                        bottom: NuvoBottomNav.bottomPadding(context),
                      ),
                      children: const [
                        SizedBox(key: ValueKey('last-row'), height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byKey(const ValueKey('last-row')));
      final clearance = NuvoBottomNav.bottomPadding(context);

      // The inner Scaffold must not have eaten the dock's height: clearance
      // still covers the whole rendered nav plus the shared section gap.
      final probeNavBox = _navRenderBox(tester);
      expect(
        clearance,
        greaterThanOrEqualTo(
          probeNavBox.size.height + NuvoBottomNav.navScrollClearance,
        ),
        reason:
            'bottomPadding must cover the dock through nested Scaffolds, '
            'not collapse to the section gap alone',
      );

      // And the last row, scrolled to the end, must end fully above the
      // dock's top edge.
      final rowBox = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('last-row')),
      );
      final rowBottom =
          rowBox.localToGlobal(Offset.zero).dy + rowBox.size.height;
      expect(
        rowBottom,
        lessThanOrEqualTo(probeNavBox.localToGlobal(Offset.zero).dy),
        reason: 'final row must scroll fully above the floating dock',
      );
    },
  );

  testWidgets('nav bounds are identical across tabs — one shell composition', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(390, 844));
    final arenaNavTop = _navRenderBox(tester).localToGlobal(Offset.zero).dy;
    final arenaBodyBox = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('fill-screen-arena')),
    );
    final arenaBodyHeight = arenaBodyBox.size.height;

    final context = tester.element(
      find.byKey(const ValueKey('fill-screen-arena')),
    );
    GoRouter.of(context).go('/compete');
    await tester.pumpAndSettle();

    final competeNavTop = _navRenderBox(tester).localToGlobal(Offset.zero).dy;
    final competeBodyBox = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('fill-screen-compete')),
    );

    expect(
      competeNavTop,
      arenaNavTop,
      reason:
          'Every tab must share the exact same Scaffold/nav composition — '
          'there is no longer a special per-tab layout branch.',
    );
    expect(competeBodyBox.size.height, arenaBodyHeight);
  });
}
