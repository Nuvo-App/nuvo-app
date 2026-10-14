import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/widgets/nuvo_focused_stage.dart';

Widget _wrap(Widget child, {Size size = const Size(390, 844)}) => MediaQuery(
  data: MediaQueryData(size: size),
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  testWidgets('content is vertically and horizontally centred', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _wrap(
        NuvoFocusedStage(
          icon: Icons.videocam_rounded,
          title: 'Teach Nuvo Pull Ups',
          body: 'Do it 3 times.',
          primaryLabel: 'Start',
          onPrimary: () {},
        ),
      ),
    );
    final title = tester.getCenter(find.text('Teach Nuvo Pull Ups'));
    expect(title.dx, closeTo(195, 1));
    // Group (icon .. button) is centred, so the title sits above the middle
    // but the whole block's midpoint is the screen's midpoint.
    final top = tester.getTopLeft(find.byIcon(Icons.videocam_rounded)).dy;
    final bottom = tester.getBottomLeft(find.text('Start')).dy;
    expect((top + bottom) / 2, closeTo(844 / 2, 60));
  });

  testWidgets('primary, secondary and links all fire', (tester) async {
    var taps = <String>[];
    await tester.pumpWidget(
      _wrap(
        NuvoFocusedStage(
          title: 'Done',
          primaryLabel: 'Use it',
          onPrimary: () => taps.add('primary'),
          secondaryLabel: 'Test again',
          onSecondary: () => taps.add('secondary'),
          links: [('Change name', () => taps.add('link'))],
        ),
      ),
    );
    await tester.tap(find.text('Use it'));
    await tester.tap(find.text('Test again'));
    await tester.tap(find.text('Change name'));
    expect(taps, ['primary', 'secondary', 'link']);
  });

  testWidgets('scrolls instead of overflowing on a tiny screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _wrap(
        NuvoFocusedStage(
          icon: Icons.check_circle_rounded,
          title: 'Nuvo can count Pull Ups',
          body: 'It watched your 3 examples and learned the motion. ' * 3,
          primaryLabel: 'Use this movement',
          onPrimary: () {},
          secondaryLabel: 'Test it',
          onSecondary: () {},
          links: [('Retry', () {}), ('Change name', () {})],
        ),
        size: const Size(320, 420),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Use this movement'), findsOneWidget);
  });
}
