// Regression coverage for the MainShell layout contract: every tab renders
// through one Scaffold(bottomNavigationBar: ..., extendBody: false), so the
// body's usable viewport must physically end at (or above) the nav's top
// edge — never behind it. This used to be two different code paths (a
// Scaffold slot for most tabs, a Stack that floated the nav over Arena's
// body with extendBody: true) and the Stack path was the actual cause of
// Arena content painting underneath the dock.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
    testWidgets('${entry.key}: body never renders content under the nav', (
      tester,
    ) async {
      await _pumpShell(tester, entry.value);
      expect(tester.takeException(), isNull);

      final navTopY = _navRenderBox(tester).localToGlobal(Offset.zero).dy;

      // Scaffold sizes the body to end above bottomNavigationBar when
      // extendBody is false — assert that contract directly on the
      // screen's own render box rather than trusting a scroll offset.
      final bodyBox = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('fill-screen-arena')),
      );
      final bodyTopY = bodyBox.localToGlobal(Offset.zero).dy;
      final bodyBottomY = bodyTopY + bodyBox.size.height;

      expect(
        bodyBottomY,
        lessThanOrEqualTo(navTopY + 0.5), // allow sub-pixel float slop
        reason:
            "${entry.key}: the screen's own layout box must end at or "
            "above the nav's top edge — content laid out inside it "
            'structurally cannot render underneath the dock.',
      );

      // And the body must not be starved down to near-nothing either —
      // that would trivially satisfy the bound above without actually
      // proving the shell reserves a sane amount of usable viewport.
      expect(
        bodyBox.size.height,
        greaterThan(entry.value.height * 0.6),
        reason: '${entry.key}: body should retain the large majority of '
            'the screen, not just a sliver above the nav.',
      );
    });
  }

  testWidgets('nav bounds are identical across tabs — one shell composition', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(390, 844));
    final arenaNavTop = _navRenderBox(tester).localToGlobal(Offset.zero).dy;
    final arenaBodyBox = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('fill-screen-arena')),
    );
    final arenaBodyHeight = arenaBodyBox.size.height;

    final context = tester.element(find.byKey(const ValueKey('fill-screen-arena')));
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
