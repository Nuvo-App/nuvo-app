import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/onboarding/auth_visuals/typewriter_text.dart';

String _shown(WidgetTester t) {
  final span = t
      .widget<Text>(find.byKey(const ValueKey('ob-login-headline')))
      .textSpan!;
  return (span as TextSpan).children!.first.toPlainText();
}

Widget _app({bool reduce = false}) => MaterialApp(
  builder: (c, child) => MediaQuery(
    data: MediaQuery.of(c).copyWith(disableAnimations: reduce),
    child: child!,
  ),
  home: const Scaffold(
    body: ObTypewriter(
      phrases: ['ab', 'cd'],
      style: TextStyle(fontSize: 20),
      typeChar: Duration(milliseconds: 100),
      deleteChar: Duration(milliseconds: 50),
      hold: Duration(milliseconds: 1000),
      gap: Duration(milliseconds: 200),
    ),
  ),
);

void main() {
  testWidgets('types, holds, backspaces, then types the next phrase', (
    t,
  ) async {
    await t.pumpWidget(_app());
    expect(_shown(t), '');
    await t.pump(const Duration(milliseconds: 100));
    expect(_shown(t), 'a');
    await t.pump(const Duration(milliseconds: 100));
    expect(_shown(t), 'ab');
    await t.pump(const Duration(milliseconds: 900)); // still holding
    expect(_shown(t), 'ab');
    await t.pump(const Duration(milliseconds: 100)); // hold over
    await t.pump(const Duration(milliseconds: 50)); // first backspace
    expect(_shown(t), 'a');
    await t.pump(const Duration(milliseconds: 50));
    expect(_shown(t), '');
    await t.pump(const Duration(milliseconds: 200)); // gap
    await t.pump(const Duration(milliseconds: 100));
    expect(_shown(t), 'c');
    await t.pump(const Duration(milliseconds: 100));
    expect(_shown(t), 'cd');
    // Box height never changes.
    expect(t.getSize(find.byType(ObTypewriter)).height, greaterThan(40));
  });

  testWidgets('reduce motion: first phrase, static', (t) async {
    await t.pumpWidget(_app(reduce: true));
    expect(_shown(t), 'ab');
    await t.pump(const Duration(seconds: 5));
    expect(_shown(t), 'ab');
  });

  testWidgets('one static semantics label', (t) async {
    await t.pumpWidget(_app());
    expect(find.bySemanticsLabel('ab'), findsOneWidget);
  });
}
