import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nuvo/app/app.dart';

void main() {
  testWidgets('Nuvo app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: NuvoApp()));
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
