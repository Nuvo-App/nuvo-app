import '../../../../core/offline/online_gate.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/v13/v13.dart';
import '../../data/race_models.dart';
import '../../domain/race_display.dart';
import 'submit_proof_sheet.dart';
import '../../../tour/tour_fixtures.dart';
import '../../../tour/tour_practice_proof.dart';

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
  // Guided-tour practice race: client-only, never reaches the proof flow.
  if (isTourRace(race)) return openTourPracticeProof(context, ref);
  // Proof verification is server-side — never queued, never attempted
  // offline. Calm line, no sheet that can't finish.
  if (!appOnlineNow(ref)) {
    showV13Toast(
      context,
      'Proofs need internet. Try again when you\u2019re back online.',
    );
    return;
  }
  final outcome = await showV13Sheet<SubmitProofOutcome>(
    context,
    builder: (_) => SubmitProofV13Sheet(race: race),
  );
  if (outcome == null || !context.mounted) return;
  final result = outcome.result;
  final message = proofOutcomeMessage(
    accumulating: raceIsAccumulating(race),
    value: outcome.value,
    raceCompleted: result?.raceCompleted ?? false,
    newRank: result?.newRank,
    peoplePassed: result?.peoplePassed ?? 0,
  );
  if (outcome.tookLead) showV13Confetti(context);
  showV13Toast(context, message);
}

/// The toast line after a proof lands. Only an accumulating race banks the
/// value onto a running total, so only it earns "+N" copy — attempt races
/// (Best single, Timed battle, anything lower-wins) replace the score, and
/// the toast names the attempt instead of faking addition.
String proofOutcomeMessage({
  required bool accumulating,
  required int value,
  bool raceCompleted = false,
  int? newRank,
  int peoplePassed = 0,
}) => switch ((raceCompleted, newRank, peoplePassed)) {
  (true, _, _) => 'Proof logged — you crossed the finish line.',
  (_, 1, _) =>
    accumulating
        ? '+$value — you took the lead.'
        : 'New best — you took the lead.',
  (_, final r?, > 0) =>
    accumulating
        ? '+$value — passed $peoplePassed ${peoplePassed == 1 ? 'racer' : 'racers'}, now #$r.'
        : 'Attempt logged — passed $peoplePassed ${peoplePassed == 1 ? 'racer' : 'racers'}, now #$r.',
  (_, final r?, _) =>
    accumulating
        ? '+$value logged — you are #$r.'
        : 'Attempt logged — you are #$r.',
  _ => accumulating ? '+$value logged.' : 'Attempt logged.',
};
