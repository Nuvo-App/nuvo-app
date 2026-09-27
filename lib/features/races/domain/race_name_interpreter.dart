import 'motion_activity.dart';
import 'motion_activity_catalog.dart';
import 'race_draft.dart';

/// What kind of proof an interpreted race name needs. This is a *need*, not
/// a verifier: the capability layer decides downstream whether automatic
/// verification exists for it. Never carries release ids, model paths, or
/// package internals.
enum ProofNeed { motionReps, motionDuration, distance, timeResult, numeric, photo, manual }

enum InterpretationConfidence { high, assumed, low }

/// One-shot result of [interpretRaceName]: a structured race draft plus the
/// provenance needed to populate the composer without hiding assumptions.
///
/// SMART AT THE EDGE — this is the only place a free-text title becomes
/// race fields. The composer and every quick-start entry point funnel here
/// (or pass a structured draft directly); nothing else may reinterpret.
class FlexiRaceInterpretation {
  const FlexiRaceInterpretation({
    required this.input,
    required this.goalKind,
    required this.metric,
    required this.format,
    required this.targetValue,
    required this.proofNeed,
    required this.confidence,
    required this.inferredFields,
    this.activity,
    this.manualGoalName,
    this.manualUnit,
    this.attemptDurationSeconds,
    this.recurrence = RaceRecurrence.none,
    this.scoreDirection = 'higher',
    this.assumptions = const [],
    this.question,
  });

  /// The title as entered — preserved verbatim for the draft.
  final String input;

  /// Preset activity when the name matched the catalog; null for custom
  /// subjects (manual/honor-logged goals).
  final MotionActivityDefinition? activity;

  final RaceGoalKind goalKind;
  final RaceMetric metric;
  final RaceFormat format;
  final int targetValue;
  final int? attemptDurationSeconds;
  final RaceRecurrence recurrence;

  /// 'higher' = most/best value wins; 'lower' = lowest value wins (golf,
  /// fastest time). Canonical — maps to `minimum_attempt` on the wire.
  final String scoreDirection;

  /// For [RaceGoalKind.manual]: the normalized subject ("Math test grade").
  final String? manualGoalName;

  /// For [RaceGoalKind.manual]: inferred or hinted unit ("pages", "percent").
  final String? manualUnit;

  final ProofNeed proofNeed;
  final InterpretationConfidence confidence;

  /// Fields the interpretation populated — the merge uses this to know which
  /// draft fields it may set and which the user already owns.
  final Set<RaceField> inferredFields;

  /// Human-readable notes for values that were guessed, not stated.
  final List<String> assumptions;

  /// At most one — only when the name can't be responsibly filled.
  final String? question;

  bool get isPreset => activity != null;
}

/// The ONE canonical entry point: race name → structured interpretation.
/// Rules-first, offline, deterministic — no remote calls, ever.
FlexiRaceInterpretation interpretRaceName(String input) {
  final normalized = _normalize(input);
  // Intent phrasing is not the subject — "who can get the highest grades"
  // must reach the same grammar as "highest grades". Strip iteratively:
  // "who can do the most pushups" sheds one leading word per pass.
  var core = normalized;
  for (var pass = 0; pass < 4; pass++) {
    final next = core
        .replaceFirst(
          RegExp(r'^(who|whichever|whatever|what|which|lets|let us)\s+'),
          '',
        )
        .replaceFirst(RegExp(r'^(can|could|do|does|did|will|would)\s+'), '')
        .replaceFirst(
          RegExp(
            r'^(get|gets|have|has|score|scores|make|makes|earn|earns|win|wins|see)\s+(the\s+)?',
          ),
          '',
        );
    if (next == core) break;
    core = next;
  }
  final assumptions = <String>[];

  // ── Grammar slot 1: "most <subject> in <N> (seconds|minutes)" ─────────────
  final timed = RegExp(
    r'(?:^|\b)most\s+(.+?)\s+in\s+([a-z0-9]+)\s*(seconds?|secs?|s|minutes?|mins?|m)\b',
  ).firstMatch(core);
  if (timed != null) {
    final subject = timed.group(1)!;
    final amount = _numberAt(timed.group(2)!);
    final unit = timed.group(3)!;
    if (amount != null) {
      final seconds = unit.startsWith('m') ? amount * 60 : amount;
      final activity = motionActivityFromText(subject);
      return FlexiRaceInterpretation(
        input: input.trim(),
        goalKind: activity == null ? RaceGoalKind.manual : RaceGoalKind.movement,
        activity: activity,
        metric: activity?.metric ?? RaceMetric.reps,
        format: _supported(
          activity,
          RaceFormat.timedAttempt,
          assumptions,
          'timed attempts',
        ),
        targetValue: activity?.defaultTarget ?? 1,
        attemptDurationSeconds: seconds,
        proofNeed: activity == null
            ? ProofNeed.manual
            : _motionNeed(activity),
        confidence: activity == null
            ? InterpretationConfidence.assumed
            : InterpretationConfidence.high,
        manualGoalName: activity == null ? _titleCase(subject) : null,
        manualUnit: activity == null ? _unitHint(subject, assumptions) : null,
        inferredFields: {
          RaceField.activity,
          RaceField.goalKind,
          RaceField.format,
          RaceField.timing,
          if (activity == null) RaceField.manualGoal,
        },
        assumptions: assumptions,
      );
    }
  }

  // ── Grammar slot 2: "first to <N> <subject>" / "first to <verb> <N> <subject>"
  final firstTo = RegExp(r'^(?:the\s+)?first\s+to\s+(.+)$').firstMatch(
    core,
  );
  if (firstTo != null) {
    final rest = firstTo.group(1)!;
    final split = _splitLeadingOrInnerNumber(rest);
    if (split != null) {
      final (target, subject) = split;
      final activity = motionActivityFromText(subject);
      return FlexiRaceInterpretation(
        input: input.trim(),
        goalKind: activity == null ? RaceGoalKind.manual : RaceGoalKind.movement,
        activity: activity,
        metric: activity?.metric ?? RaceMetric.reps,
        format: RaceFormat.firstToGoal,
        targetValue: target,
        proofNeed: activity == null
            ? ProofNeed.manual
            : _motionNeed(activity),
        confidence: InterpretationConfidence.high,
        manualGoalName: activity == null ? _titleCase(subject) : null,
        manualUnit: activity == null ? _unitHint(subject, assumptions) : null,
        inferredFields: {
          RaceField.activity,
          RaceField.goalKind,
          RaceField.format,
          RaceField.target,
          if (activity == null) RaceField.manualGoal,
        },
        assumptions: assumptions,
      );
    }
    // "First to <subject>" with no number — preset match fills the target.
    final activity = motionActivityFromText(rest);
    return FlexiRaceInterpretation(
      input: input.trim(),
      goalKind: activity == null ? RaceGoalKind.manual : RaceGoalKind.movement,
      activity: activity,
      metric: activity?.metric ?? RaceMetric.reps,
      format: RaceFormat.firstToGoal,
      targetValue: activity?.defaultTarget ?? 1,
      proofNeed: activity == null ? ProofNeed.manual : _motionNeed(activity),
      confidence: activity == null
          ? InterpretationConfidence.low
          : InterpretationConfidence.assumed,
      manualGoalName: activity == null ? _titleCase(rest) : null,
      manualUnit: activity == null ? _unitHint(rest, assumptions) : null,
      inferredFields: {
        RaceField.activity,
        RaceField.goalKind,
        RaceField.format,
        if (activity != null) RaceField.target,
        if (activity == null) RaceField.manualGoal,
      },
      assumptions: assumptions,
      question: activity == null ? 'What counts as progress?' : null,
    );
  }

  // ── Grammar slot 3: "longest / fastest / highest / lowest / best <subject>"
  final superlative = RegExp(
    r'^(?:the\s+)?(longest|fastest|highest|lowest|best|biggest)\s+(.+)$',
  ).firstMatch(core);
  if (superlative != null) {
    final word = superlative.group(1)!;
    final subject = superlative.group(2)!;
    final activity = motionActivityFromText(subject);
    final isTime = word == 'longest' || word == 'fastest';
    // "fastest"/"lowest" win on the smallest value — a real scoring
    // primitive (minimum_attempt), not an assumption.
    final lowerWins = word == 'fastest' || word == 'lowest';
    final unit = isTime ? 'seconds' : _unitHint(subject, assumptions);
    return FlexiRaceInterpretation(
      input: input.trim(),
      goalKind: activity == null ? RaceGoalKind.manual : RaceGoalKind.movement,
      activity: activity,
      metric: isTime ? RaceMetric.seconds : (activity?.metric ?? RaceMetric.reps),
      format: _supported(activity, RaceFormat.bestAttempt, assumptions, 'best attempt'),
      targetValue: activity?.defaultTarget ?? 60,
      proofNeed: activity == null
          ? (isTime ? ProofNeed.timeResult : ProofNeed.numeric)
          : _motionNeed(activity),
      confidence: activity == null
          ? InterpretationConfidence.assumed
          : InterpretationConfidence.high,
      scoreDirection: lowerWins ? 'lower' : 'higher',
      manualGoalName: activity == null ? _titleCase(subject) : null,
      manualUnit: activity == null ? unit : null,
      inferredFields: {
        RaceField.activity,
        RaceField.goalKind,
        RaceField.format,
        RaceField.target,
        if (lowerWins) RaceField.scoreDirection,
        if (activity == null) ...{RaceField.manualGoal, RaceField.manualUnit},
      },
      assumptions: assumptions,
    );
  }

  // ── Grammar slot 4: "most <subject> [today|this week|…|by friday]" ────────
  final most = RegExp(r'^(?:the\s+)?most\s+(.+)$').firstMatch(core);
  if (most != null) {
    // The deadline tail ("today", "this week", "by friday") shapes the
    // assumption, never the subject name.
    final subject = most
        .group(1)!
        .replaceAll(
          RegExp(
            r'\s*(today|tonight|this\s+(week|weekend|month|year)|by\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday|end\s+of\s+\w+))\s*$',
          ),
          '',
        )
        .trim();
    final activity = motionActivityFromText(subject);
    assumptions.add('Finish line not stated — set one in the goal step.');
    return FlexiRaceInterpretation(
      input: input.trim(),
      goalKind: activity == null ? RaceGoalKind.manual : RaceGoalKind.movement,
      activity: activity,
      metric: activity?.metric ?? RaceMetric.reps,
      format: _supported(
        activity,
        RaceFormat.mostInWindow,
        assumptions,
        'a deadline race',
      ),
      targetValue: activity?.defaultTarget ?? 1,
      proofNeed: activity == null ? ProofNeed.manual : _motionNeed(activity),
      confidence: InterpretationConfidence.assumed,
      manualGoalName: activity == null ? _titleCase(subject) : null,
      manualUnit: activity == null ? _unitHint(subject, assumptions) : null,
      inferredFields: {
        RaceField.activity,
        RaceField.goalKind,
        RaceField.format,
        if (activity == null) RaceField.manualGoal,
      },
      assumptions: assumptions,
    );
  }

  // ── Fallback: bare subject, count anywhere, or genuinely ambiguous ─────────
  final activity = motionActivityFromText(core);
  final target = _firstNumber(core);
  if (activity != null) {
    return FlexiRaceInterpretation(
      input: input.trim(),
      goalKind: RaceGoalKind.movement,
      activity: activity,
      metric: activity.metric,
      format: RaceFormat.firstToGoal,
      targetValue: target ?? activity.defaultTarget,
      proofNeed: _motionNeed(activity),
      confidence: InterpretationConfidence.assumed,
      inferredFields: {RaceField.activity, RaceField.target},
      assumptions: [
        if (target == null) 'Goal not stated — defaulted to ${activity.defaultTarget}.',
      ],
      question: target == null ? "What's the finish line?" : null,
    );
  }

  // No preset and no grammar match — a valid custom subject is still a race.
  // Fill what is known; leave the unresolved field obvious in the composer.
  final stripped = core
      .replaceAll(RegExp(r'\b(race|challenge|contest|competition)\b'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return FlexiRaceInterpretation(
    input: input.trim(),
    goalKind: RaceGoalKind.manual,
    metric: target != null ? RaceMetric.reps : RaceMetric.reps,
    format: RaceFormat.firstToGoal,
    targetValue: target ?? 1,
    proofNeed: ProofNeed.manual,
    confidence: InterpretationConfidence.low,
    manualGoalName: stripped.isEmpty ? null : _titleCase(stripped),
    manualUnit: stripped.isEmpty ? null : _unitHint(stripped, assumptions),
    inferredFields: {
      RaceField.goalKind,
      if (stripped.isNotEmpty) RaceField.manualGoal,
    },
    assumptions: assumptions,
    question: 'What counts as progress?',
  );
}

/// Merges an interpretation into the working draft — USER EDIT WINS. A field
/// the user has touched ([RaceDraft.userEditedFields]) is never overwritten
/// by a later interpretation of a changed title.
RaceDraft mergeRaceNameInterpretation(
  RaceDraft current,
  FlexiRaceInterpretation i,
) {
  final edited = current.userEditedFields;
  T? guard<T>(RaceField field, T? inferred) =>
      edited.contains(field) ? null : inferred;
  return current.copyWith(
    title: i.input,
    hasCustomName: true,
    goalKind: guard(RaceField.goalKind, i.goalKind),
    activity: guard(RaceField.activity, i.activity),
    metric: i.metric,
    format: guard(RaceField.format, i.format),
    targetValue: guard(RaceField.target, i.targetValue),
    attemptDurationSeconds: guard(RaceField.timing, i.attemptDurationSeconds),
    // A fresh non-timed interpretation clears inferred timing; it never
    // clears timing the user set.
    clearTiming: !edited.contains(RaceField.timing) &&
        i.attemptDurationSeconds == null,
    manualGoalName: guard(RaceField.manualGoal, i.manualGoalName),
    manualUnit: guard(RaceField.manualUnit, i.manualUnit),
    recurrence: guard(RaceField.recurrence, i.recurrence),
    scoreDirection: guard(RaceField.scoreDirection, i.scoreDirection),
    // An interpreted name never produces a Teach-Nuvo custom movement —
    // unless the user owns goalKind, stale custom state must not survive.
    clearCustom: !edited.contains(RaceField.goalKind),
  );
}

// ── Internals ─────────────────────────────────────────────────────────────────

String _normalize(String input) => input
    .toLowerCase()
    .replaceAll(RegExp(r'[-_]+'), ' ')
    .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

ProofNeed _motionNeed(MotionActivityDefinition activity) =>
    activity.metric == RaceMetric.seconds
        ? ProofNeed.motionDuration
        : ProofNeed.motionReps;

/// Picks [preferred] when the activity supports it; otherwise the first
/// supported format and records the degradation as an assumption.
RaceFormat _supported(
  MotionActivityDefinition? activity,
  RaceFormat preferred,
  List<String> assumptions,
  String label,
) {
  if (activity == null) return preferred;
  if (activity.supportedFormats.contains(preferred)) return preferred;
  final fallback = activity.supportedFormats.first;
  assumptions.add(
    '${activity.title} does not support $label — using "${fallback.label}".',
  );
  return fallback;
}

String _titleCase(String s) => s
    .split(' ')
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');

/// Free-text unit hint for custom subjects — a guess, always flagged.
String? _unitHint(String subject, List<String> assumptions) {
  const hints = {
    'pages': ['page', 'pages', 'book', 'books', 'read', 'reading'],
    'problems': ['problem', 'problems', 'leetcode', 'coding'],
    'steps': ['step', 'steps', 'walk'],
    'percent': ['grade', 'grades', 'test', 'exam', 'quiz'],
    'strokes': ['golf'],
    'points': ['score', 'scores', 'game'],
    'lbs': ['bench', 'press', 'lift', 'deadlift', 'squat max'],
    'oz': ['water', 'oz'],
  };
  for (final entry in hints.entries) {
    if (entry.value.any((h) => subject.contains(h))) {
      assumptions.add('Unit "${entry.key}" guessed from the name.');
      return entry.key;
    }
  }
  return null;
}

const _numberWords = {
  'a': 1, 'an': 1, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
  'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11,
  'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15, 'sixteen': 16,
  'seventeen': 17, 'eighteen': 18, 'nineteen': 19, 'twenty': 20, 'thirty': 30,
  'forty': 40, 'fifty': 50, 'sixty': 60, 'seventy': 70, 'eighty': 80,
  'ninety': 90, 'hundred': 100,
};

int? _numberAt(String token) =>
    int.tryParse(token) ?? _numberWords[token];

int? _firstNumber(String normalized) {
  for (final token in normalized.split(' ')) {
    final n = _numberAt(token);
    if (n != null) return n;
  }
  return null;
}

/// Splits "100 pushups" → (100, 'pushups') or "read 5 books" → (5, 'read books').
/// Returns null when no usable number+subject pair exists.
(int, String)? _splitLeadingOrInnerNumber(String rest) {
  final tokens = rest.split(' ').where((t) => t.isNotEmpty).toList();
  for (var i = 0; i < tokens.length; i++) {
    final n = _numberAt(tokens[i]);
    if (n != null && tokens.length > 1) {
      final subject = (tokens..removeAt(i)).join(' ');
      if (subject.trim().isNotEmpty) return (n, subject);
    }
  }
  return null;
}
