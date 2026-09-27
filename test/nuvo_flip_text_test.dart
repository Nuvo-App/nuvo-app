import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/widgets/nuvo_flip_text.dart';

Widget _wrap(Widget child, {bool disableAnimations = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

List<Opacity> _faceOpacities(WidgetTester tester) => tester
    .widgetList<Opacity>(
      find.descendant(
        of: find.byType(NuvoFlipText),
        matching: find.byType(Opacity),
      ),
    )
    .toList();

void main() {
  testWidgets('flips in and reports completion', (tester) async {
    var completed = false;
    await tester.pumpWidget(
      _wrap(
        NuvoFlipText(
          'Welcome to Nuvo.',
          duration: const Duration(milliseconds: 1000),
          onCompleted: () => completed = true,
        ),
      ),
    );

    expect(find.text('W'), findsOneWidget);
    expect(completed, isFalse);

    await tester.pump(const Duration(milliseconds: 500));
    expect(completed, isFalse);

    // delay 0 + stagger span 250 + 30% of 1000 → ~550ms to settle.
    await tester.pump(const Duration(milliseconds: 700));
    expect(completed, isTrue);

    // Settled: every face fully opaque.
    expect(
      _faceOpacities(tester).every((o) => o.opacity == 1),
      isTrue,
    );
  });

  testWidgets('stays hidden until play is enabled', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const NuvoFlipText(
          'Hidden',
          play: false,
          duration: Duration(milliseconds: 1000),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 2000));

    // Cell faces exist but carry zero opacity — the entrance never ran.
    expect(_faceOpacities(tester).every((o) => o.opacity == 0), isTrue);
  });

  testWidgets('replays when the text changes', (tester) async {
    var completions = 0;
    Widget build(String text) => _wrap(
      NuvoFlipText(
        text,
        duration: const Duration(milliseconds: 800),
        onCompleted: () => completions++,
      ),
    );

    await tester.pumpWidget(build('First to 10 pushups'));
    await tester.pump(const Duration(seconds: 2));
    expect(completions, 1);

    await tester.pumpWidget(build('50 jumping jacks'));
    await tester.pump(const Duration(seconds: 2));
    expect(completions, 2);
  });

  testWidgets('renders plain text under reduced motion', (tester) async {
    var completed = false;
    await tester.pumpWidget(
      _wrap(
        NuvoFlipText(
          'Welcome to Nuvo.',
          onCompleted: () => completed = true,
        ),
        disableAnimations: true,
      ),
    );

    // Whole-string Text, no per-character cells.
    expect(find.text('Welcome to Nuvo.'), findsOneWidget);
    expect(find.text('W'), findsNothing);
    await tester.pump();
    expect(completed, isTrue);
  });
}
