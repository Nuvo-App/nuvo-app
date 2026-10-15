import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/profile/presentation/widgets/activity_heatmap.dart';

void main() {
  test('heat levels', () {
    expect(
      [0, 1, 2, 3, 4, 6, 7, 40].map(heatLevel).toList(),
      [0, 1, 2, 2, 3, 3, 4, 4],
    );
  });

  test('grid is whole Mon-Sun weeks ending this week, no future cells', () {
    final wed = DateTime(2026, 10, 14); // Wednesday
    final days = heatmapDays(wed, weeks: 20);
    expect(days.length, 140);
    expect(days.first!.weekday, DateTime.monday);
    expect(days[19 * 7], DateTime(2026, 10, 12)); // this week's Monday
    expect(days[19 * 7 + 2], DateTime(2026, 10, 14)); // today
    expect(days[19 * 7 + 3], isNull); // Thursday not yet
    expect(days.where((d) => d == null).length, 4);
  });

  testWidgets('renders 140 cells and the total', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ActivityHeatmap(
              counts: const {'2026-10-14': 3, '2026-10-13': 1},
              today: DateTime(2026, 10, 14),
            ),
          ),
        ),
      ),
    );
    expect(find.text('4 verified proofs'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
  });
}
