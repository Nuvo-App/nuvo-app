// FlexiRace adversarial safety corpus — SEPARATE from the 350-case semantic
// benchmark on purpose. The interpreter is allowed to understand dangerous
// input; the safety layer decides whether it can become a race.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/domain/race_safety.dart';

void main() {
  final cases = (jsonDecode(
    File('test/fixtures/flexirace_safety_cases.json').readAsStringSync(),
  ) as List)
      .cast<Map<String, dynamic>>();

  test('dangerous prompts are refused; legit races still pass', () {
    final failures = <String>[];
    for (final c in cases) {
      final decision = evaluateRaceSafety(c['input'] as String);
      final expected = c['expected'] as String;
      if (expected == 'rejected') {
        if (decision.isAllowed) {
          failures.add('#${c['id']} ALLOWED: ${c['input']}');
        } else if (c['category'] != null &&
            decision.category != c['category']) {
          failures.add(
            '#${c['id']} wrong category ${decision.category} '
            '(want ${c['category']}): ${c['input']}',
          );
        }
      } else if (!decision.isAllowed) {
        failures.add(
          '#${c['id']} FALSE POSITIVE (${decision.category}): ${c['input']}',
        );
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
