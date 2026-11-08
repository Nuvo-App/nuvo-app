import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/config/v13.dart';
import 'package:nuvo/core/v13/v13.dart';
import 'package:nuvo/core/widgets/bottom_nav.dart';

void main() {
  test('v13 flag defaults on', () {
    expect(kNuvoV13, isTrue);
    expect(identical(activeDestinations, v13Destinations), isTrue);
  });

  test('v13 tabs: Arena, Compete, Crew, Profile on the canonical paths', () {
    expect(v13Destinations.map((d) => d.label), [
      'Arena',
      'Compete',
      'Crew',
      'Profile',
    ]);
    // Same paths and order as the pre-v13 table, so branch index, deep links
    // and auth_gate's protected-route list keep working.
    expect(
      v13Destinations.map((d) => d.path),
      nuvoDestinations.map((d) => d.path),
    );
  });

  testWidgets('v13 tab bar renders every destination and reports taps', (
    tester,
  ) async {
    var tapped = -1;
    await tester.pumpWidget(
      MaterialApp(
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
            currentIndex: 0,
            onTap: (i) => tapped = i,
          ),
        ),
      ),
    );
    for (final d in activeDestinations) {
      expect(find.text(d.label), findsOneWidget);
    }
    await tester.tap(find.text('Crew'));
    await tester.pumpAndSettle();
    expect(tapped, 2);
  });
}
