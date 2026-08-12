import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/widgets/nuvo_button.dart';
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

  testWidgets('Arena shows the Nuvo next-move board', (tester) async {
    await pumpArena(tester);

    expect(find.byType(ArenaScreen), findsOneWidget);
    expect(find.text('Arena'), findsWidgets);
    expect(find.text('YOUR NEXT MOVE'), findsOneWidget);
    expect(find.text('First to 100 Pushups'), findsOneWidget);
    expect(find.text('LEADERBOARD'), findsOneWidget);
    expect(find.text('Submit proof'), findsWidgets);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Join'), findsOneWidget);
    expect(find.byType(NuvoPrimaryButton), findsOneWidget);
    expect(find.byType(NuvoOutlineButton), findsNWidgets(2));
    expect(find.text('More races'), findsNothing);
  });

  testWidgets('Arena remains usable on a taller inset viewport', (
    tester,
  ) async {
    await pumpArena(
      tester,
      physicalSize: const Size(390, 932),
      bottomInset: 34,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('First to 100 Pushups'), findsOneWidget);
    expect(find.text('65'), findsOneWidget);
  });

  testWidgets('recent activity remains available below the dashboard', (
    tester,
  ) async {
    await pumpArena(tester);

    expect(find.text('submitted 20 pushups'), findsNothing);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(find.text('RECENT ACTIVITY'), findsOneWidget);
    expect(find.text('submitted 20 pushups'), findsOneWidget);
  });
}
