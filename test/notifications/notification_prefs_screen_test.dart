// Notification Settings: stable back-header, one App/Push column header per
// section, compact rows, working toggles, and full semantic labels on each
// switch (the column headers themselves are visual-only).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/widgets/nuvo_back_header.dart';
import 'package:nuvo/core/widgets/nuvo_button.dart';
import 'package:nuvo/core/widgets/nuvo_toggle.dart';
import 'package:nuvo/features/notifications/data/notification_prefs.dart';
import 'package:nuvo/features/notifications/presentation/notification_prefs_screen.dart';

class _Update {
  const _Update(this.category, this.inApp, this.push);
  final String category;
  final bool? inApp;
  final bool? push;
}

class _FakePrefsApi implements NotificationPrefsApi {
  _FakePrefsApi(this.prefs);

  final List<NotificationPref> prefs;
  final updates = <_Update>[];

  @override
  Future<List<NotificationPref>> list() async => prefs;

  @override
  Future<void> update(String category, {bool? inApp, bool? push}) async {
    updates.add(_Update(category, inApp, push));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<NotificationPref> _prefs() => const [
  NotificationPref(category: 'race_starting', inApp: true, push: true),
  NotificationPref(category: 'race_completed', inApp: true, push: true),
  NotificationPref(
    category: 'passed_on_leaderboard',
    inApp: true,
    push: false,
  ),
  NotificationPref(category: 'proof_accepted', inApp: true, push: true),
  NotificationPref(category: 'proof_rejected', inApp: true, push: false),
  NotificationPref(category: 'crew_request', inApp: true, push: true),
  NotificationPref(category: 'crew_request_accepted', inApp: true, push: false),
];

Future<_FakePrefsApi> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);

  final api = _FakePrefsApi(_prefs());
  final router = GoRouter(
    initialLocation: '/settings/notifications',
    routes: [
      GoRoute(
        path: '/settings/notifications',
        builder: (c, s) => const NotificationPrefsScreen(),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [notificationPrefsApiProvider.overrideWithValue(api)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('header is one stable back row — no floating shadow button', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.byType(NuvoBackHeader), findsOneWidget);
    expect(find.byType(NuvoBackButton), findsNothing);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.bySemanticsLabel('Back'), findsOneWidget);

    // Title sits beside the back control, not under it.
    final backBottom = tester.getBottomLeft(find.byIcon(Icons.arrow_back_rounded)).dy;
    final titleTop = tester.getTopLeft(find.text('Notifications')).dy;
    final titleBottom = tester.getBottomLeft(find.text('Notifications')).dy;
    expect(titleTop, lessThan(backBottom));
    expect(titleBottom, greaterThan(backBottom - 44));
  });

  testWidgets('App/Push declared once per section, not per row', (
    tester,
  ) async {
    await _pump(tester);

    // 7 rows across 3 groups — exactly 3 "App" and 3 "Push" headers.
    expect(find.text('App'), findsNWidgets(3));
    expect(find.text('Push'), findsNWidgets(3));
    expect(find.text('RACES'), findsOneWidget);
    expect(find.text('PROOF'), findsOneWidget);
    expect(find.text('CREW'), findsOneWidget);

    // Concise labels.
    expect(find.text('Race starting'), findsOneWidget);
    expect(find.text('Race finished'), findsOneWidget);
    expect(find.text('Passed on leaderboard'), findsOneWidget);
    expect(find.text('Proof needs another try'), findsOneWidget);
    expect(find.text('Request accepted'), findsOneWidget);
  });

  testWidgets('each switch carries a full semantic phrase', (tester) async {
    await _pump(tester);

    expect(
      find.bySemanticsLabel('Race starting, app notifications'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Race starting, push notifications'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Crew requests, push notifications'),
      findsOneWidget,
    );
  });

  testWidgets('toggling a push switch updates that category only', (
    tester,
  ) async {
    final api = await _pump(tester);

    // Row order: race_starting, race_completed, passed, proof_accepted,
    // proof_rejected — each row is App cell then Push cell.
    final pushSwitch = find.byType(NuvoToggle).at(4 * 2 + 1);
    await tester.tap(pushSwitch);
    await tester.pumpAndSettle();

    expect(api.updates, hasLength(1));
    expect(api.updates.single.category, 'proof_rejected');
    // Fixture starts push: false — the tap turns it on, and only that
    // channel is sent (inApp untouched).
    expect(api.updates.single.push, isTrue);
    expect(api.updates.single.inApp, isNull);
  });

  for (final size in [
    const Size(375, 667),
    const Size(390, 844),
    const Size(430, 932),
  ]) {
    testWidgets('${size.width}x${size.height}: no overflow, header stable', (
      tester,
    ) async {
      await _pump(tester, size: size);

      expect(tester.takeException(), isNull);
      expect(find.byType(NuvoBackHeader), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
    });
  }
}
