import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/v13/v13.dart';
import '../../data/race_models.dart';
import 'submit_proof_sheet.dart';

/// The single "Submit proof" entry for the v13 shell. Every v13 surface
/// (Arena race cards, nudges, Race detail, Compete live cards) calls this,
/// so the proof flow is swapped in exactly one place.
///
/// Opens the v13 bottom sheet; on a logged manual proof the sheet hands back
/// the server submission result and this fires the reward moment — toast
/// always, confetti when the racer took the lead.
Future<void> openSubmitProof(
  BuildContext context,
  WidgetRef ref,
  Race race,
) async {
  final outcome = await showV13Sheet<SubmitProofOutcome>(
    context,
    builder: (_) => SubmitProofV13Sheet(race: race),
  );
  if (outcome == null || !context.mounted) return;
  final result = outcome.result;
  final rank = result?.newRank;
  final passed = result?.peoplePassed ?? 0;
  final message = switch ((result?.raceCompleted ?? false, rank, passed)) {
    (true, _, _) => 'Proof logged — you crossed the finish line.',
    (_, 1, _) => '+${outcome.value} — you took the lead.',
    (_, final r?, > 0) =>
      '+${outcome.value} — passed $passed ${passed == 1 ? 'racer' : 'racers'}, now #$r.',
    (_, final r?, _) => '+${outcome.value} logged — you are #$r.',
    _ => '+${outcome.value} logged.',
  };
  if (outcome.tookLead) showV13Confetti(context);
  showV13Toast(context, message);
}
