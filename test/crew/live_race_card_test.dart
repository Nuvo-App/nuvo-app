// NuvoLiveRaceCard — the Crew LIVE component family. Pins the light-surface
// contract (content card, not a navy banner), canonical content presence,
// the primary/compact variant split, and Watch/reaction wiring.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/theme/app_colors.dart';
import 'package:nuvo/core/widgets/nuvo_live_race_card.dart';
import 'package:nuvo/core/widgets/nuvo_number_flow.dart';

Widget _wrap(Widget child, {double width = 360}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

const _h2h = [
  NuvoLiveStanding(name: 'Noah', score: 41, rank: 1),
  NuvoLiveStanding(name: 'You', score: 39, rank: 2, isMe: true),
];

NuvoLiveRaceCard _card({
  String title = 'Pushup Battle',
  List<NuvoLiveStanding> standings = _h2h,
  DateTime? endsAt,
  Widget? trailing,
  VoidCallback? onWatch,
  NuvoLiveRaceCardVariant variant = NuvoLiveRaceCardVariant.primary,
}) =>
    NuvoLiveRaceCard(
      title: title,
      standings: standings,
      endsAt: endsAt,
      trailing: trailing,
      onWatch: onWatch,
      variant: variant,
    );

void main() {
  testWidgets('primary: LIVE label, title, head-to-head scores, Watch',
      (tester) async {
    await tester.pumpWidget(_wrap(_card()));

    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('Pushup Battle'), findsOneWidget);
    expect(find.text('Noah'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    // Scores ride NuvoNumberFlow so changes roll.
    expect(
      find.byWidgetPredicate(
          (w) => w is NuvoNumberFlow && w.value == 41),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
          (w) => w is NuvoNumberFlow && w.value == 39),
      findsOneWidget,
    );
    expect(find.text('Watch'), findsOneWidget);
  });

  testWidgets('gap line is canonical rank/score arithmetic', (tester) async {
    await tester.pumpWidget(_wrap(_card()));
    expect(find.text('Noah leads by 2'), findsOneWidget);

    await tester.pumpWidget(_wrap(_card(standings: const [
      NuvoLiveStanding(name: 'Noah', score: 39, rank: 2),
      NuvoLiveStanding(name: 'You', score: 41, rank: 1, isMe: true),
    ])));
    expect(find.text('You lead by 2'), findsOneWidget);

    await tester.pumpWidget(_wrap(_card(standings: const [
      NuvoLiveStanding(name: 'Noah', score: 40, rank: 1),
      NuvoLiveStanding(name: 'You', score: 40, rank: 2, isMe: true),
    ])));
    expect(find.text('Level with Noah'), findsOneWidget);
  });

  testWidgets('time left is canonical; past end reads Ending', (tester) async {
    await tester.pumpWidget(_wrap(_card(
      endsAt: DateTime.now().add(const Duration(minutes: 35)),
    )));
    expect(find.text('35m left'), findsOneWidget);

    await tester.pumpWidget(_wrap(_card(
      endsAt: DateTime.now().subtract(const Duration(seconds: 5)),
    )));
    expect(find.text('Ending'), findsOneWidget);
  });

  testWidgets('surface is light, not the old navy block', (tester) async {
    await tester.pumpWidget(_wrap(_card()));

    // No navy-filled container anywhere inside the card.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == NuvoColors.navy,
      ),
      findsNothing,
    );
    // The card face is the standard surface with a navy outline + hard
    // offset depth.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == NuvoColors.surface &&
            (w.decoration as BoxDecoration).border != null,
      ),
      findsWidgets,
    );
  });

  testWidgets('three racers fall back to the ranked matchup line',
      (tester) async {
    await tester.pumpWidget(_wrap(_card(standings: const [
      NuvoLiveStanding(name: 'Noah', score: 41, rank: 1),
      NuvoLiveStanding(name: 'You', score: 39, rank: 2, isMe: true),
      NuvoLiveStanding(name: 'Maya', score: 12, rank: 3),
    ])));

    final matchup = find.byWidgetPredicate(
      (w) =>
          w is Text &&
          w.textSpan != null &&
          w.textSpan!.toPlainText().contains('Noah') &&
          w.textSpan!.toPlainText().contains('Maya'),
    );
    expect(matchup, findsOneWidget);
    // Gap read still surfaces when I'm in a multi-way race.
    expect(find.text('Noah leads by 2'), findsOneWidget);
  });

  testWidgets('compact: same family, tighter layout', (tester) async {
    await tester.pumpWidget(_wrap(_card(
      variant: NuvoLiveRaceCardVariant.compact,
      endsAt: DateTime.now().add(const Duration(minutes: 35)),
    )));

    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('Pushup Battle'), findsOneWidget);
    expect(find.text('35m left'), findsOneWidget);
    expect(find.text('Watch'), findsOneWidget);
    // Compact keeps the matchup line instead of the head-to-head block.
    expect(find.byType(NuvoNumberFlow), findsNothing);
  });

  testWidgets('card tap fires onWatch; trailing slot renders',
      (tester) async {
    var watched = 0;
    await tester.pumpWidget(_wrap(_card(
      onWatch: () => watched++,
      trailing: const Text('CHIPS', key: Key('chips')),
    )));

    expect(find.byKey(const Key('chips')), findsOneWidget);
    await tester.tap(find.byType(NuvoLiveRaceCard));
    expect(watched, 1);
  });

  testWidgets('no overflow at 320px for either variant', (tester) async {
    await tester.pumpWidget(_wrap(_card(
      trailing: const Text('CHIPS'),
    ), width: 320));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_wrap(_card(
      variant: NuvoLiveRaceCardVariant.compact,
      trailing: const Text('CHIPS'),
      endsAt: DateTime.now().add(const Duration(minutes: 35)),
    ), width: 320));
    expect(tester.takeException(), isNull);
  });
}
