// Floating pill nav: margins, gap, single selected pill, label slide-out.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/theme/app_theme.dart';
import 'package:nuvo/core/widgets/bottom_nav.dart';

const _sizes = [
  Size(320, 568),
  Size(375, 667),
  Size(390, 844),
  Size(393, 852),
  Size(430, 932),
];

Widget _app(
  int current,
  bool dark,
  double scale,
  double inset, {
  bool reduce = false,
  ValueChanged<int>? onTap,
}) {
  return MaterialApp(
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        padding: EdgeInsets.only(bottom: inset),
        disableAnimations: reduce,
      ),
      child: child!,
    ),
    home: Scaffold(
      bottomNavigationBar: NuvoBottomNav(
        currentIndex: current,
        onTap: onTap ?? (_) {},
      ),
    ),
  );
}

void main() {
  for (final size in _sizes) {
    for (final inset in [0.0, 34.0]) {
      for (final dark in [false, true]) {
        for (final scale in [1.0, 1.4]) {
          testWidgets(
            'floating bar ${size.width.toInt()}x${size.height.toInt()} '
            'inset=$inset dark=$dark scale=$scale',
            (tester) async {
              tester.view.physicalSize = size;
              tester.view.devicePixelRatio = 1.0;
              addTearDown(tester.view.resetPhysicalSize);
              await tester.pumpWidget(_app(1, dark, scale, inset));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);

              final bar = tester.getRect(
                find
                    .ancestor(
                      of: find.byKey(const ValueKey('nuvo-nav-slot-0')),
                      matching: find.byType(Container),
                    )
                    .last,
              );
              expect(bar.left, 16);
              expect(bar.right, size.width - 16);
              expect(bar.height, NuvoBottomNav.navDockHeight);
              expect(size.height - bar.bottom, greaterThanOrEqualTo(inset + 8));

              for (var i = 0; i < 4; i++) {
                expect(
                  find.byKey(ValueKey('nuvo-nav-slot-$i')),
                  findsOneWidget,
                );
              }
              expect(
                find.byKey(const ValueKey('nuvo-nav-indicator')),
                findsOneWidget,
              );
              expect(find.text('Compete'), findsOneWidget);
              expect(find.byType(Text), findsOneWidget);
              final right = tester.getRect(
                find.byKey(const ValueKey('nuvo-nav-slot-3')),
              );
              expect(right.right, lessThanOrEqualTo(bar.right));
              final left = tester.getRect(
                find.byKey(const ValueKey('nuvo-nav-slot-0')),
              );
              expect(left.left, greaterThanOrEqualTo(bar.left));
            },
          );
        }
      }
    }
  }

  testWidgets('tapping another slot slides the label across', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    var current = 0;
    late StateSetter set;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          set = setState;
          return _app(current, false, 1.0, 34, onTap: (i) => current = i);
        },
      ),
    );
    await tester.pumpAndSettle();
    final startW = tester
        .getSize(find.byKey(const ValueKey('nuvo-nav-label-0')))
        .width;
    expect(startW, greaterThan(20));

    await tester.tap(find.byKey(const ValueKey('nuvo-nav-slot-2')));
    set(() {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    final midOld = tester.getSize(
      find.byKey(const ValueKey('nuvo-nav-label-0')),
    );
    final midNew = tester.getSize(
      find.byKey(const ValueKey('nuvo-nav-label-2')),
    );
    expect(midOld.width, lessThan(startW));
    expect(midNew.width, greaterThan(0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nuvo-nav-label-0')), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('nuvo-nav-label-2'))).width,
      greaterThan(20),
    );
    expect(find.byType(Text), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduce motion switches instantly; semantics selected', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(3, false, 1.0, 0, reduce: true));
    await tester.pump();
    expect(find.text('Profile'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('nuvo-nav-slot-3'))),
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
