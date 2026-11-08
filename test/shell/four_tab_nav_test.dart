// The nav is four equal destinations — Arena, Compete, Crew, Profile — and
// the retired Verify tab's old /move links redirect. The rendered bar is
// V13TabBar; the destination table lives in core/widgets/bottom_nav.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/app/router.dart';
import 'package:nuvo/core/v13/v13.dart';
import 'package:nuvo/core/widgets/bottom_nav.dart';

Future<List<int>> _pumpBar(
  WidgetTester tester, {
  int current = 0,
  double scale = 1.0,
  Size size = const Size(320, 568),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  final taps = <int>[];
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          padding: const EdgeInsets.only(bottom: 34),
        ),
        child: child!,
      ),
      home: Scaffold(
        bottomNavigationBar: V13TabBar(
          items: [
            for (final d in activeDestinations)
              V13TabItem(
                label: d.label,
                icon: d.icon,
                selectedIcon: d.selectedIcon,
              ),
          ],
          currentIndex: current,
          onTap: taps.add,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return taps;
}

void main() {
  test('canonical table is Arena, Compete, Friends, Profile', () {
    expect(nuvoDestinations.map((d) => d.label), [
      'Arena',
      'Compete',
      'Friends',
      'Profile',
    ]);
    expect(nuvoDestinations.map((d) => d.path), [
      '/arena',
      '/compete',
      '/pass',
      '/profile',
    ]);
  });

  for (final scale in [1.0, 1.4]) {
    testWidgets('bar: 4 slots, 44pt+ targets, no overflow (scale=$scale)', (
      tester,
    ) async {
      final taps = await _pumpBar(tester, scale: scale);
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 4; i++) {
        final r = tester.getRect(find.byKey(ValueKey('v13-tab-slot-$i')));
        expect(r.width, greaterThanOrEqualTo(44));
        expect(r.height, greaterThanOrEqualTo(44));
      }
      await tester.tap(find.byKey(const ValueKey('v13-tab-slot-2')));
      await tester.tap(find.byKey(const ValueKey('v13-tab-slot-3')));
      expect(taps, [2, 3]);
    });
  }

  testWidgets('every destination keeps its label, regardless of selection', (
    tester,
  ) async {
    for (var i = 0; i < 4; i++) {
      await _pumpBar(tester, current: i);
      for (final d in activeDestinations) {
        expect(find.text(d.label), findsOneWidget);
      }
    }
  });

  group('/move redirect', () {
    test('plain /move goes to Arena', () {
      expect(moveRedirect(Uri.parse('/move')), '/arena');
      expect(moveRedirect(Uri.parse('/move?race=')), '/arena');
    });
    test('/move?race=<id> goes to that race proof entry', () {
      expect(moveRedirect(Uri.parse('/move?race=abc')), '/race/abc/proof');
    });
    testWidgets('router applies it', (tester) async {
      final router = GoRouter(
        initialLocation: '/move?race=r1',
        routes: [
          GoRoute(path: '/move', redirect: (_, s) => moveRedirect(s.uri)),
          GoRoute(path: '/arena', builder: (_, _) => const Text('arena')),
          GoRoute(
            path: '/race/:id/proof',
            builder: (_, s) => Text('proof-${s.pathParameters['id']}'),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('proof-r1'), findsOneWidget);
    });
  });
}
