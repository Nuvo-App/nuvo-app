import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/v13/v13.dart';
import 'package:nuvo/core/widgets/bottom_nav.dart';

void main() {
  testWidgets('bottom bar keeps every destination visible', (tester) async {
    var selected = 0;
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
            currentIndex: selected,
            onTap: (index) => selected = index,
          ),
        ),
      ),
    );

    // The v13 bar labels every slot — there are no icon-only slots.
    for (final d in activeDestinations) {
      expect(find.text(d.label), findsOneWidget);
    }
    expect(find.text('Verify'), findsNothing);
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(ValueKey('v13-tab-slot-$i')), findsOneWidget);
    }

    await tester.tap(find.byKey(const ValueKey('v13-tab-slot-2')));
    expect(selected, 2);
  });
}
