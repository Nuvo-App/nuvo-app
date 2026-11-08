// The v13 floating dock: a white outlined pill inset from the edges, four
// labelled slots, and a blue capsule that slides to the active slot.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/v13/v13.dart';
import 'package:nuvo/core/widgets/bottom_nav.dart';

const _sizes = [
  Size(320, 568),
  Size(375, 667),
  Size(390, 844),
  Size(393, 852),
  Size(430, 932),
];

List<V13TabItem> get _items => [
  for (final d in activeDestinations)
    V13TabItem(label: d.label, icon: d.icon, selectedIcon: d.selectedIcon),
];

Widget _app(
  int current,
  double scale,
  double inset, {
  bool reduce = false,
  ValueChanged<int>? onTap,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        padding: EdgeInsets.only(bottom: inset),
        disableAnimations: reduce,
      ),
      child: child!,
    ),
    home: Scaffold(
      bottomNavigationBar: V13TabBar(
        items: _items,
        currentIndex: current,
        onTap: onTap ?? (_) {},
      ),
    ),
  );
}

void main() {
  for (final size in _sizes) {
    for (final inset in [0.0, 34.0]) {
      for (final scale in [1.0, 1.4]) {
        testWidgets('v13 bar ${size.width.toInt()}x${size.height.toInt()} '
            'inset=$inset scale=$scale', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          await tester.pumpWidget(_app(1, scale, inset));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // Floating dock: inset from both edges, centred, sized to its
          // slots, sitting just above the home indicator.
          final dock = tester.getRect(find.byKey(const ValueKey('v13-dock')));
          expect(dock.left, greaterThanOrEqualTo(V13TabBar.sideInset - 0.01));
          expect(
            dock.right,
            lessThanOrEqualTo(size.width - V13TabBar.sideInset + 0.01),
          );
          expect((dock.left + dock.right) / 2, closeTo(size.width / 2, 0.5));
          expect(
            dock.height,
            closeTo(V13TabBar.barHeight + V13.outline * 2, 0.01),
          );
          final gap = inset > 0 ? inset - 8 : 12.0;
          expect(size.height - dock.bottom, closeTo(gap, 0.01));

          for (var i = 0; i < 4; i++) {
            expect(find.byKey(ValueKey('v13-tab-slot-$i')), findsOneWidget);
          }
          // Every slot labels itself; the selected indicator is singular.
          for (final d in activeDestinations) {
            expect(find.text(d.label), findsOneWidget);
          }
          expect(find.byType(AnimatedPositioned), findsOneWidget);
        });
      }
    }
  }

  testWidgets('tapping another slot slides the indicator across', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    var current = 0;
    late StateSetter set;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          set = setState;
          return _app(current, 1.0, 34, onTap: (i) => current = i);
        },
      ),
    );
    await tester.pumpAndSettle();

    final slotW = V13TabBar.slotWidthFor(390, 4);
    double indicatorLeft() => tester
        .widget<AnimatedPositioned>(find.byType(AnimatedPositioned))
        .left!;
    expect(indicatorLeft(), closeTo(0, 0.01));

    await tester.tap(find.byKey(const ValueKey('v13-tab-slot-2')));
    set(() {});
    await tester.pumpAndSettle();
    expect(indicatorLeft(), closeTo(slotW * 2, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected slot uses its filled icon; semantics selected', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(3, 1.0, 0, reduce: true));
    await tester.pump();
    final slot0Icon = tester.widget<Icon>(
      find
          .descendant(
            of: find.byKey(const ValueKey('v13-tab-slot-0')),
            matching: find.byType(Icon),
          )
          .first,
    );
    final slot3Icon = tester.widget<Icon>(
      find
          .descendant(
            of: find.byKey(const ValueKey('v13-tab-slot-3')),
            matching: find.byType(Icon),
          )
          .first,
    );
    expect(slot0Icon.icon, activeDestinations[0].icon);
    expect(slot3Icon.icon, activeDestinations[3].selectedIcon);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('v13-tab-slot-3'))),
      isSemantics(
        label: 'Profile',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
      ),
    );
    handle.dispose();
  });
}
