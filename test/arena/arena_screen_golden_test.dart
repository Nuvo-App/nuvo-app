import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/widgets/bottom_nav.dart';
import 'package:nuvo/features/arena/presentation/arena_screen.dart';

void _noop(int _) {}

void main() {
  testWidgets('ArenaScreen renders the full 390x844 screen', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(390, 844),
              padding: EdgeInsets.zero,
              viewPadding: EdgeInsets.zero,
              viewInsets: EdgeInsets.zero,
              devicePixelRatio: 1.0,
              disableAnimations: true,
            ),
            child: Scaffold(
              body: ArenaScreen(preview: true),
              bottomNavigationBar: NuvoBottomNav(
                currentIndex: 0,
                onTap: _noop,
                isDark: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/arena_screen.png'),
    );
  });
}
