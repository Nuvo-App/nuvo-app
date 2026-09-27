import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/widgets/nuvo_fade_scroll.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

Widget _list({int count = 30, ValueChanged<int>? onTap}) {
  return SizedBox(
    height: 300,
    child: NuvoFadeScroll(
      child: ListView.builder(
        itemCount: count,
        itemExtent: 40,
        itemBuilder: (_, i) => GestureDetector(
          onTap: onTap == null ? null : () => onTap(i),
          child: Text('item $i'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the scrollable and preserves taps', (tester) async {
    var tapped = -1;
    await tester.pumpWidget(_wrap(_list(onTap: (i) => tapped = i)));
    expect(find.text('item 0'), findsOneWidget);
    await tester.tap(find.text('item 0'));
    expect(tapped, 0);
  });

  testWidgets('scrolling still works and edge items remain tappable', (
    tester,
  ) async {
    var tapped = -1;
    await tester.pumpWidget(_wrap(_list(onTap: (i) => tapped = i)));

    // Scroll into the middle — both fades active.
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pump();
    expect(find.text('item 0'), findsNothing);

    // An item under the bottom fade is still hit-testable.
    final lastVisible = tester
        .widgetList(find.byType(Text))
        .map((w) => (w as Text).data!)
        .last;
    await tester.tap(find.text(lastVisible));
    expect(tapped, int.parse(lastVisible.split(' ').last));
  });

  testWidgets('scrolls to the bottom without mask boundary errors', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_list()));
    await tester.fling(find.byType(ListView), const Offset(0, -3000), 8000);
    await tester.pumpAndSettle();
    expect(find.text('item 29'), findsOneWidget);
  });

  testWidgets('non-scrollable content builds without a fade', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SizedBox(
          height: 300,
          child: NuvoFadeScroll(
            child: SingleChildScrollView(child: Text('short')),
          ),
        ),
      ),
    );
    expect(find.text('short'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('supports horizontal scrollables', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          height: 60,
          child: NuvoFadeScroll(
            axis: Axis.horizontal,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 20,
              itemExtent: 80,
              itemBuilder: (_, i) => Text('cell $i'),
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(-200, 0));
    await tester.pump();
    expect(find.text('cell 0'), findsNothing);
  });
}
