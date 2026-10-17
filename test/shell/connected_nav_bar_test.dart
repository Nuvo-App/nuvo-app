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

void main() {
  for (final dark in [false, true]) {
    for (final size in _sizes) {
      for (final inset in [0.0, 34.0]) {
        testWidgets(
          'connected bar ${size.width}x${size.height} inset $inset dark=$dark',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            var tapped = -1;
            await tester.pumpWidget(
              MediaQuery(
                data: MediaQueryData(
                  size: size,
                  padding: EdgeInsets.only(bottom: inset),
                  textScaler: const TextScaler.linear(1.4),
                ),
                child: MaterialApp(
                  theme: dark ? AppTheme.dark() : AppTheme.light(),
                  home: Scaffold(
                    bottomNavigationBar: NuvoBottomNav(
                      currentIndex: 1,
                      onTap: (i) => tapped = i,
                      rowKey: const ValueKey('row'),
                    ),
                  ),
                ),
              ),
            );
            final rect = tester.getRect(find.byType(NuvoBottomNav));
            expect(rect.left, 0);
            expect(rect.width, size.width);
            expect(rect.bottom, size.height);
            expect(rect.height - inset, inInclusiveRange(50, 54));
            expect(find.byKey(const ValueKey('nuvo-nav-indicator')),
                findsOneWidget);
            expect(tester.takeException(), isNull);
            final row = tester.getRect(find.byKey(const ValueKey('row')));
            expect(row.bottom, size.height - inset);
            for (var i = 0; i < 4; i++) {
              final x = size.width * (i + 0.5) / 4;
              await tester.tapAt(Offset(x, row.center.dy));
              expect(tapped, i);
            }
          },
        );
      }
    }
  }
}
