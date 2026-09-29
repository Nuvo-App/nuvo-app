import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nuvo/features/notifications/application/push_service.dart';
import 'package:nuvo/features/onboarding/data/first_use_store.dart';
import 'package:nuvo/features/onboarding/presentation/notification_permission_screen.dart';

/// A PushService double that never touches Firebase — the screen's only
/// contract is "ask the OS state, request after the CTA, continue".
class _FakePushService extends PushService {
  _FakePushService(super.ref, {this.status});

  AuthorizationStatus? status;
  int requestCount = 0;

  @override
  Future<AuthorizationStatus?> notificationAuthorizationStatus() async =>
      status;

  @override
  Future<bool> requestPermissionInContext() async {
    requestCount++;
    return status == AuthorizationStatus.authorized;
  }
}

({GoRouter router, ProviderContainer container}) _build({
  AuthorizationStatus? status,
  FirstUseStore? store,
}) {
  final container = ProviderContainer(
    overrides: [
      pushServiceProvider
          .overrideWith((ref) => _FakePushService(ref, status: status)),
      firstUseStoreProvider
          .overrideWithValue(store ?? FirstUseStore.memory()),
    ],
  );
  final router = GoRouter(
    initialLocation: '/onboarding/notifications',
    routes: [
      GoRoute(
        path: '/onboarding/notifications',
        builder: (_, _) => const NotificationPermissionScreen(),
      ),
      GoRoute(
        path: '/arena',
        builder: (_, _) => const Scaffold(body: Text('arena-home')),
      ),
    ],
  );
  return (router: router, container: container);
}

_FakePushService _push(ProviderContainer container) =>
    container.read(pushServiceProvider) as _FakePushService;

Future<({GoRouter router, ProviderContainer container})> _pump(
  WidgetTester tester, {
  AuthorizationStatus? status = AuthorizationStatus.notDetermined,
  FirstUseStore? store,
  Size size = const Size(390, 844),
  double textScale = 1.0,
  bool dark = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final built = _build(status: status, store: store);
  addTearDown(built.container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: built.container,
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: MaterialApp.router(
          theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          routerConfig: built.router,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return built;
}

String _path(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('notification permission moment', () {
    testWidgets('NOT_DETERMINED shows education, no system prompt on load',
        (tester) async {
      final built = await _pump(tester);
      expect(find.text('Don’t miss the move.'), findsOneWidget);
      expect(find.text('Turn on notifications'), findsOneWidget);
      expect(find.text('Maybe later'), findsOneWidget);
      // The OS prompt is strictly CTA-gated.
      expect(_push(built.container).requestCount, 0);
    });

    testWidgets('CTA requests then continues to Arena', (tester) async {
      final store = FirstUseStore.memory();
      await store.markNotificationPromptOwed();
      final built = await _pump(tester, store: store);
      await tester.tap(find.text('Turn on notifications'));
      await tester.pumpAndSettle();
      expect(_push(built.container).requestCount, 1);
      expect(_path(built.router), '/arena');
      // Resolved — the step never replays for this install.
      expect(store.isNotificationPromptOwed, isFalse);
    });

    testWidgets('MAYBE_LATER skips the request and continues', (tester) async {
      final built = await _pump(tester);
      await tester.tap(find.text('Maybe later'));
      await tester.pumpAndSettle();
      expect(_push(built.container).requestCount, 0);
      expect(_path(built.router), '/arena');
    });

    for (final status in [
      AuthorizationStatus.authorized,
      AuthorizationStatus.provisional,
      AuthorizationStatus.denied,
      null, // push transport unavailable
    ]) {
      testWidgets('AUTHORIZED SKIP — $status resolves silently',
          (tester) async {
        final built = await _pump(tester, status: status);
        expect(_path(built.router), '/arena');
        expect(_push(built.container).requestCount, 0);
      });
    }

    group('layout matrix', () {
      for (final size in const [
        Size(320, 568),
        Size(375, 667),
        Size(390, 844),
        Size(430, 932),
      ]) {
        testWidgets('${size.width.toInt()} — no overflow', (tester) async {
          await _pump(tester, size: size);
          expect(find.text('Turn on notifications'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }

      for (final scale in const [1.2, 1.4]) {
        testWidgets('text scale $scale — no overflow', (tester) async {
          await _pump(tester, textScale: scale);
          expect(find.text('Turn on notifications'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('dark mode — no overflow', (tester) async {
        await _pump(tester, dark: true);
        expect(find.text('Turn on notifications'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('first-use permission flags', () {
    test('notification owed flag sets and clears', () async {
      final store = FirstUseStore.memory();
      expect(store.isNotificationPromptOwed, isFalse);
      await store.markNotificationPromptOwed();
      expect(store.isNotificationPromptOwed, isTrue);
      await store.clearNotificationPromptOwed();
      expect(store.isNotificationPromptOwed, isFalse);
    });

    test('camera primer flag defaults unseen and persists in-memory',
        () async {
      final store = FirstUseStore.memory();
      expect(store.isCameraPrimerSeen, isFalse);
      await store.markCameraPrimerSeen();
      expect(store.isCameraPrimerSeen, isTrue);
    });
  });
}
