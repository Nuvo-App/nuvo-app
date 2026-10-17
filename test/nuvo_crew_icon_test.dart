import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/theme/app_colors.dart';
import 'package:nuvo/core/widgets/nuvo_icons.dart';

void main() {
  for (final dark in [false, true]) {
    for (final size in [20.0, 24.0, 28.0]) {
      testWidgets('NuvoCrewIcon renders at $size dark=$dark', (tester) async {
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: Scaffold(body: Center(child: NuvoCrewIcon(size: size))),
        ));
        expect(tester.getSize(find.byType(NuvoCrewIcon)), Size.square(size));
        expect(find.bySemanticsLabel('Crew'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('decorative crew icon has no semantics', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: NuvoCrewIcon(semanticLabel: null)),
    ));
    expect(find.bySemanticsLabel('Crew'), findsNothing);
    expect(NuvoColors.blue, isNotNull);
  });
}
