import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/features/arena/presentation/arena_screen.dart';
import 'package:nuvo/features/shell/presentation/main_shell.dart';

void main() {
  Future<void> pumpArena(
    WidgetTester tester, {
    Size physicalSize = const Size(390, 844),
    double bottomInset = 0,
  }) async {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(bottom: bottomInset);
    tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
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
              builder: (context, state) => const ArenaScreen(preview: true),
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

  testWidgets('focus board fits the phone viewport above navigation', (
    tester,
  ) async {
    await pumpArena(tester);

    final titleRect = tester.getRect(find.text('First to 100 Pushups'));
    final actionRect = tester.getRect(find.text('Submit proof').first);

    expect(titleRect.left, greaterThanOrEqualTo(0));
    expect(titleRect.right, lessThanOrEqualTo(390));
    expect(actionRect.top, greaterThan(titleRect.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('focus board supports reduced motion', (tester) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(
          disableAnimations: true,
          reduceMotion: true,
        );
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

    await pumpArena(tester);

    expect(find.text('YOUR NEXT MOVE'), findsOneWidget);
    expect(find.text('You lead Alex by 17 reps.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('focus board handles the iPhone home indicator inset', (
    tester,
  ) async {
    await pumpArena(tester, bottomInset: 34);

    expect(find.text('LEADERBOARD'), findsOneWidget);
    expect(find.text('Submit proof'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
