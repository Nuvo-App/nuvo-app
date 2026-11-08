import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/presentation/v13/submit_proof_entry.dart';

void main() {
  test('test_gap16_attempt_mode_proof_copy_is_not_additive', () {
    // Attempt races replace the banked score — the toast names the attempt
    // ("New best" / "Attempt logged") instead of faking "+N" addition.
    expect(
      proofOutcomeMessage(accumulating: false, value: 30, newRank: 1),
      'New best — you took the lead.',
    );
    expect(
      proofOutcomeMessage(
        accumulating: false,
        value: 30,
        newRank: 2,
        peoplePassed: 1,
      ),
      'Attempt logged — passed 1 racer, now #2.',
    );
    expect(
      proofOutcomeMessage(accumulating: false, value: 30, newRank: 4),
      'Attempt logged — you are #4.',
    );
    expect(
      proofOutcomeMessage(accumulating: false, value: 30),
      'Attempt logged.',
    );
    // Accumulating races keep the additive "+N" copy untouched.
    expect(
      proofOutcomeMessage(accumulating: true, value: 12, newRank: 1),
      '+12 — you took the lead.',
    );
    expect(
      proofOutcomeMessage(accumulating: true, value: 12, newRank: 2),
      '+12 logged — you are #2.',
    );
    expect(
      proofOutcomeMessage(accumulating: true, value: 12),
      '+12 logged.',
    );
    // Crossing the finish line reads the same on either mode.
    expect(
      proofOutcomeMessage(
        accumulating: false,
        value: 30,
        raceCompleted: true,
      ),
      'Proof logged — you crossed the finish line.',
    );
  });
}
