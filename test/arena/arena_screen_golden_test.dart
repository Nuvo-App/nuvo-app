import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/arena/presentation/arena_screen.dart';

void main() {
  testWidgets('ArenaScreen mounts the TrackSide foundation', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(child: ArenaScreen(preview: true)),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Pushups'), findsOneWidget);
    expect(find.text('Your next move'), findsOneWidget);
    expect(find.text('CREW STANDINGS'), findsOneWidget);
    expect(find.text('Submit proof'), findsOneWidget);
  });
}
