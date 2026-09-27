import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/widgets/nuvo_number_flow.dart';

Widget _wrap(Widget child, {bool disableAnimations = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

Future<void> _pumpValue(
  WidgetTester tester,
  ValueNotifier<int> notifier, {
  bool disableAnimations = false,
}) {
  return tester.pumpWidget(
    _wrap(
      ValueListenableBuilder<int>(
        valueListenable: notifier,
        builder: (_, v, _) => NuvoNumberFlow(value: v),
      ),
      disableAnimations: disableAnimations,
    ),
  );
}

void main() {
  testWidgets('exposes the formatted value to semantics', (tester) async {
    await tester.pumpWidget(
      _wrap(const NuvoNumberFlow(value: 12, semanticsLabel: '12 reps')),
    );
    expect(find.bySemanticsLabel('12 reps'), findsOneWidget);
  });

  testWidgets('renders plain text under reduced motion', (tester) async {
    await tester.pumpWidget(
      _wrap(const NuvoNumberFlow(value: 12), disableAnimations: true),
    );
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('settles on the new value after a change', (tester) async {
    final notifier = ValueNotifier(10);
    await _pumpValue(tester, notifier);
    notifier.value = 11;
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('11'), findsOneWidget);
  });

  testWidgets('handles digit-count growth 9 to 10', (tester) async {
    final notifier = ValueNotifier(9);
    await _pumpValue(tester, notifier);
    notifier.value = 10;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('10'), findsOneWidget);
  });

  testWidgets('rapid consecutive changes converge without hanging', (
    tester,
  ) async {
    final notifier = ValueNotifier(10);
    await _pumpValue(tester, notifier);
    for (final v in [11, 12, 13, 14]) {
      notifier.value = v;
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('14'), findsOneWidget);
  });

  testWidgets('formats through the format callback', (tester) async {
    await tester.pumpWidget(
      _wrap(NuvoNumberFlow(value: 80, format: (v) => '1 min 20 sec')),
    );
    expect(find.bySemanticsLabel('1 min 20 sec'), findsOneWidget);
  });

  testWidgets('reduced motion updates the value immediately', (tester) async {
    final notifier = ValueNotifier(9);
    await _pumpValue(tester, notifier, disableAnimations: true);
    notifier.value = 10;
    await tester.pump();
    expect(find.text('10'), findsOneWidget);
  });
}
