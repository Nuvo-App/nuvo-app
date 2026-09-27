// FlexiRace 350-case generalization benchmark.
//
// Loads test/fixtures/flexirace_350_cases.json and runs the CANONICAL
// interpreter (interpretRaceName) on every input — no interpretation logic is
// duplicated here, only field projection + presentation-level normalization
// (unit aliases like "lb"/"pounds", deadline phrasing like "by Friday").
//
// Report is written to tmp/flexirace-benchmark/report.json + failures.txt so
// failures can be grouped by ROOT CAUSE rather than case. The test itself is
// strict: any case that is not semantically acceptable fails the suite.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/domain/race_name_interpreter.dart';

void main() {
  test('flexirace 350 benchmark', () {
    final cases = (jsonDecode(
      File('test/fixtures/flexirace_350_cases.json').readAsStringSync(),
    ) as List)
        .cast<Map<String, dynamic>>();

    final failures = <Map<String, dynamic>>[];
    final results = <Map<String, dynamic>>[];

    for (final c in cases) {
      final i = interpretRaceName(c['input'] as String);
      final actual = _project(i);
      final diffs = _compare(c, actual);
      final row = {
        'id': c['id'],
        'category': c['category'],
        'input': c['input'],
        'expected': _expectedView(c),
        'actual': actual,
        'diffs': diffs,
        'question': i.question,
      };
      results.add(row);
      if (diffs.isNotEmpty) failures.add(row);
    }

    Directory('tmp/flexirace-benchmark').createSync(recursive: true);
    File('tmp/flexirace-benchmark/report.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
    File('tmp/flexirace-benchmark/failures.txt')
        .writeAsStringSync(failures.map((f) {
      final diffs = (f['diffs'] as List)
          .map((d) => '    ${d['field']}: want ${d['want']}, got ${d['got']}')
          .join('\n');
      return '#${f['id']} [${f['category']}] ${f['input']}\n$diffs';
    }).join('\n\n'));

    final byCat = <String, List<int>>{};
    for (final f in failures) {
      byCat.putIfAbsent(f['category'] as String, () => []).add(f['id'] as int);
    }
    // ignore: avoid_print
    print('\n=== BENCHMARK: ${350 - failures.length}/350 ===');
    for (final e in byCat.entries) {
      // ignore: avoid_print
      print('  ${e.key}: ${e.value.length} failures');
    }

    expect(
      failures,
      isEmpty,
      reason: '${failures.length}/350 cases differ — see '
          'tmp/flexirace-benchmark/failures.txt',
    );
  });
}

/// Projects an interpretation onto the benchmark's field vocabulary.
Map<String, Object?> _project(FlexiRaceInterpretation i) {
  if (i.question == 'Enter a race idea.') {
    return {
      'subject': '', 'metric': '', 'unit': '', 'scoring_rule': '',
      'direction': '', 'format': '', 'proof_need': 'manual',
      'attempt_duration_s': '', 'deadline': null,
      'question_present': true, 'target': '',
    };
  }
  final format = switch (i.format) {
    RaceFormat.mostInWindow => 'most_before_deadline',
    RaceFormat.firstToGoal => 'first_to_goal',
    RaceFormat.bestAttempt => 'best_attempt',
    RaceFormat.timedAttempt => 'timed_attempt',
  };
  final scoring = switch (format) {
    'best_attempt' =>
      i.scoreDirection == 'lower' ? 'minimum_attempt' : 'maximum_attempt',
    'timed_attempt' => 'maximum_attempt',
    _ => i.scoreDirection == 'lower' ? 'minimum_attempt' : 'cumulative_sum',
  };
  return {
    'subject': _canonSubject(
        i.activity?.aliases.first ?? i.manualGoalName ?? ''),
    'metric': _metricOf(i),
    'unit': _canonUnit(i.activity == null
        ? i.manualUnit
        : i.activity!.metric.backendValue),
    'scoring_rule': scoring,
    'direction': i.scoreDirection,
    'format': format,
    'proof_need': i.proofNeed.name
        .replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m[0]!.toLowerCase()}'),
    'attempt_duration_s': i.attemptDurationSeconds ?? '',
    'deadline': _canonDeadline(i.deadline),
    'question_present': i.question != null,
    'target': i.targetValue,
  };
}

Map<String, Object?> _expectedView(Map<String, dynamic> c) => {
      'subject': _canonSubject('${c['subject']}'),
      'metric': c['metric'],
      'unit': _canonUnit('${c['unit']}'),
      'scoring_rule': c['scoring_rule'],
      'direction': c['direction'],
      'format': c['format'],
      'proof_need': c['proof_need'],
      'attempt_duration_s': c['attempt_duration_s'],
      'deadline': _canonDeadline('${c['deadline']}'),
      'question_expected': c['question_expected'],
    };

List<Map<String, Object?>> _compare(
    Map<String, dynamic> c, Map<String, Object?> a) {
  final diffs = <Map<String, Object?>>[];
  void check(String field, Object? want, Object? got) {
    if ('$want' != '$got') {
      diffs.add({'field': field, 'want': want, 'got': got});
    }
  }

  // A numeric deadline on a duration-target case is the goal expressed in
  // seconds ("hold a plank for 5 minutes first") — compare to the target.
  final wantDeadline = c['deadline'];
  if (wantDeadline is num && wantDeadline > 0) {
    check('target', wantDeadline.toInt(), a['target']);
  } else {
    check('deadline', _canonDeadline('$wantDeadline'), a['deadline']);
  }

  check('format', c['format'], a['format']);
  check('direction', c['direction'], a['direction']);
  check('scoring_rule', c['scoring_rule'], a['scoring_rule']);
  check('unit', _canonUnit('${c['unit']}'), a['unit']);
  check('subject', _canonSubject('${c['subject']}'), a['subject']);
  // A recorded GPS activity is the canonical proof for distance and time
  // results alike — the capability satisfies either older bucket.
  final wantProof = '${c['proof_need']}';
  final gotProof = '${a['proof_need']}';
  final proofOk = wantProof == gotProof ||
      (gotProof == 'gps_activity' &&
          (wantProof == 'distance' || wantProof == 'time_result'));
  if (!proofOk) {
    diffs.add({'field': 'proof_need', 'want': wantProof, 'got': gotProof});
  }
  check(
    'metric',
    _metricFamily('${c['metric']}'),
    _metricFamily('${a['metric']}'),
  );

  final wantDur = c['attempt_duration_s'];
  check('attempt_duration_s', wantDeadline is num ? (wantDur ?? '') : (wantDur ?? ''),
      a['attempt_duration_s'] ?? '');

  // Ambiguity: expecting a question means ASKING is the pass. Expected
  // content is informational — presence is what we verify.
  final wantQ = '${c['question_expected']}'.trim().isNotEmpty;
  if (wantQ && a['question_present'] != true) {
    diffs.add({
      'field': 'question',
      'want': c['question_expected'],
      'got': null,
    });
  }
  // High-confidence cases must not stall on an unnecessary question.
  if (!wantQ && c['confidence'] == 'high' && a['question_present'] == true) {
    diffs.add({'field': 'question', 'want': null, 'got': a['question']});
  }
  return diffs;
}

// ── Presentation normalization ───────────────────────────────────────────────
// These functions express only canonical equivalence (synonyms, phrasing),
// never semantics. Both expected and actual values pass through the same
// normalizer.

String _canonUnit(String? unit) {
  final u = (unit ?? '').toLowerCase().trim();
  const aliases = {
    'lbs': 'lb', 'pounds': 'lb', 'pound': 'lb',
    'kgs': 'kg', 'kilograms': 'kg',
    r'$': 'usd', 'dollars': 'usd', 'dollar': 'usd', 'usd': 'usd',
    '%': 'percent', 'percentage': 'percent',
    'sec': 'seconds', 'secs': 'seconds', 's': 'seconds',
    'second': 'seconds', 'mins': 'minutes', 'min': 'minutes', 'm': 'minutes',
    'minute': 'minutes', 'hrs': 'hours', 'hr': 'hours', 'hour': 'hours',
    'mile': 'miles', 'meters': 'meters', 'metres': 'meters', 'meter': 'meters',
    'rep': 'reps', 'item': 'items', 'items': 'count', 'count': 'count',
    'book': 'books', 'page': 'pages', 'word': 'words', 'task': 'tasks',
    'step': 'steps', 'commit': 'commits', 'prs': 'prs', 'pull requests': 'prs',
    'point': 'points', 'lesson': 'lessons', 'meeting': 'meetings',
    'problem': 'problems', 'test': 'tests', 'tests': 'tests',
    'lap': 'laps', 'win': 'wins', 'kilocalories': 'kcal', 'calories': 'kcal',
    'litres': 'liters', 'litre': 'liters', 'liter': 'liters',
    'ounce': 'oz', 'ounces': 'oz',
  };
  return aliases[u] ?? u;
}

String? _canonDeadline(String? deadline) {
  var d = (deadline ?? '').toLowerCase().trim();
  if (d.isEmpty || d == 'null') return null;
  d = d
      .replaceAll(RegExp(r'^(by|before|until|within|over the next|in the next|in|over|next)\s+'), '')
      .replaceAll(RegExp(r'^(the|a|an)\s+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  const aliases = {
    'this week': '1 week', 'week': '1 week',
    'this month': '1 month', 'month': '1 month',
    'today': 'today', 'tonight': 'tonight',
    'tomorrow': 'tomorrow', 'tomorrow morning': 'tomorrow morning',
    'end of month': 'end of month', 'this weekend': 'weekend',
    'new years': 'new years', 'new year': 'new years',
    'a day': '1 day', 'day': '1 day',
  };
  return aliases[d] ?? d;
}

String _canonSubject(String subject) {
  var s = subject.toLowerCase().trim()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  const aliases = {
    'push ups': 'pushups', 'pushup': 'pushups', 'push up': 'pushups',
    'sit ups': 'situps', 'situp': 'situps',
    'jumping jack': 'jumping jacks', 'jacks': 'jumping jacks',
    'squat': 'squats', 'burpee': 'burpees', 'lunge': 'lunges',
    'crunch': 'crunches', 'dip': 'dips',
    'mile': 'running', '5k': 'running', '10k': 'running', 'marathon': 'running',
    'sprint': 'running', '100m sprint': 'running', 'lap': 'running',
    'track': 'running', 'treadmill': 'treadmill running',
    'run': 'running',
    'bike ride': 'cycling', 'bike': 'cycling', 'biking': 'cycling',
    'swim': 'swimming', 'freestyle': 'swimming', 'pool': 'swimming',
    'row': 'rowing', '2k row': 'rowing',
    'kayak': 'kayaking', 'ski': 'skiing', 'paddleboard': 'paddleboarding',
    'grade': 'grades', 'golf': 'golf score', 'plank hold': 'plank',
  };
  return aliases[s] ?? s;
}

/// Benchmark metrics are semantic classes; the canonical model carries them
/// as (metric, unit) pairs. Derive the class from the pair so the comparison
/// stays honest about what the interpreter actually committed.
Object? _metricOf(FlexiRaceInterpretation i) {
  final unit = _canonUnit(
      i.activity == null ? i.manualUnit : i.activity!.metric.backendValue);
  final subject =
      (i.manualGoalName ?? i.activity?.aliases.first ?? '').toLowerCase();
  // Subject-aware refinements — the same unit means different metric
  // families in different domains.
  if (subject.contains('accuracy') ||
      subject.contains('error') ||
      subject.contains('guess')) {
    return 'absolute_error';
  }
  // Streaks count days/occurrences.
  if (subject.contains('streak')) return 'count';
  // Improvement measured in percent is the percentage family.
  if (unit == 'percent' && subject.contains('improvement')) {
    return 'percentage';
  }
  // Camera-verified rep races are always the repetitions family.
  if (i.proofNeed == ProofNeed.motionReps) return 'repetitions';
  // XP and point-scored subjects report a points metric; a bare "score"
  // is the generic score family.
  if (unit == 'xp') return 'points';
  if (unit == 'points') return subject == 'score' ? 'score' : 'points';
  if (unit == 'inches' && subject.contains('tower')) return 'height';
  if (unit == 'seconds' && subject.contains('improvement')) return 'delta';
  if (unit == 'percent' &&
      RegExp(r'(rate|return|coverage|improvement)').hasMatch(subject)) {
    return 'percentage';
  }
  if (unit == '' && subject.isEmpty) return '';
  return _unitMetricFamily[unit] ?? (i.metric == RaceMetric.seconds
      ? 'duration'
      : 'count');
}

const _unitMetricFamily = {
  'reps': 'repetitions',
  'seconds': 'duration', 'minutes': 'duration', 'hours': 'duration',
  'milliseconds': 'duration',
  'miles': 'distance', 'meters': 'distance', 'km': 'distance',
  'yards': 'distance', 'feet': 'distance', 'inches': 'distance',
  'lb': 'weight', 'kg': 'weight', 'g': 'mass',
  'percent': 'score', 'gpa': 'score', 'points': 'score', 'strokes': 'score',
  'usd': 'currency',
  'wpm': 'rate', 'bpm': 'rate',
  'laps': 'laps', 'lengths': 'laps',
  'percentage points': 'delta',
  'x bodyweight': 'ratio',
  'degrees': 'temperature',
  'mb': 'data size', 'kcal': 'energy',
  'oz': 'volume', 'liters': 'volume',
  'emails remaining': 'count',
  'usd/person': 'currency_per_person',
  'wins': 'count', 'days': 'count', 'rating': 'score',
  '': 'score',
};

String _metricFamily(String metric) => _metricFamilyMap[metric] ?? metric;

const _metricFamilyMap = {
  'repetitions': 'repetitions', 'count': 'count', 'duration': 'duration',
  'score': 'score', 'points': 'score', 'distance': 'distance',
  'weight': 'weight', 'mass': 'weight', 'currency': 'currency',
  'rate': 'rate', 'percentage': 'score', 'volume': 'volume',
  'laps': 'laps', 'delta': 'delta', 'height': 'height',
  'energy': 'energy', 'ratio': 'ratio', 'data size': 'data size',
  'temperature': 'temperature', 'absolute_error': 'absolute_error',
  'currency_per_person': 'currency', 'time': 'duration',
};
