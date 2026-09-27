import 'motion_activity.dart';
import 'motion_activity_catalog.dart';
import 'race_draft.dart';

/// What kind of proof an interpreted race name needs. This is a *need*, not
/// a verifier: the capability layer decides downstream whether automatic
/// verification exists for it. Never carries release ids, model paths, or
/// package internals.
enum ProofNeed {
  motionReps,
  motionDuration,
  distance,
  timeResult,
  // A recorded location activity — distance, duration, pace from a GPS
  // session. The race contract names the capability; a device resolver
  // decides whether this hardware can provide it.
  gpsActivity,
  numeric,
  photo,
  video,
  link,
  note,
  manual,
}

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
    this.deadline,
    this.requiredDistanceValue,
    this.requiredDistanceUnit,
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

  /// The race finish line as written ("friday", "tonight", "in 2 weeks") —
  /// NEVER a computed DateTime: interpretation records what was said, the
  /// composer/server resolve it. Distinct from [attemptDurationSeconds]:
  /// "most jacks in 30 seconds" is an attempt window, "most steps by Friday"
  /// is a race deadline, and a race may carry both.
  final String? deadline;

  /// When the race measures TIME over a stated distance ("fastest mile",
  /// "fastest 5k"), the requirement is the distance while the score is the
  /// clock. Null when distance is the metric itself or no bar is stated.
  final double? requiredDistanceValue;
  final String? requiredDistanceUnit;

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
  final assumptions = <String>[];

  // Clauses: the race phrase is the head; everything after ',' / ';' is a
  // modifier clause — proof instructions, constraints, or contradicting
  // rules. "Highest grade, photo proof required" and "Most books, but
  // lowest wins" must not smear their tails into the subject.
  final clauses = input
      .split(RegExp('[,;]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final head = clauses.isEmpty ? '' : clauses.first;
  final tails = clauses.skip(1).toList();

  var core = _normalize(head)
      .replaceAll(RegExp(r'(\d)\s*%\s*\+'), '\$1 percent');
  if (core.isEmpty) {
    return FlexiRaceInterpretation(
      input: input.trim(),
      goalKind: RaceGoalKind.manual,
      metric: RaceMetric.reps,
      format: RaceFormat.firstToGoal,
      targetValue: 1,
      proofNeed: ProofNeed.manual,
      confidence: InterpretationConfidence.low,
      inferredFields: const {},
      assumptions: assumptions,
      question: 'Enter a race idea.',
    );
  }

  // Intent phrasing is not the subject — "who can get the highest grades"
  // must reach the same grammar as "highest grades". Strip iteratively:
  // "who can do the most pushups" sheds one leading word per pass.
  for (var pass = 0; pass < 5; pass++) {
    final next = core
        .replaceFirst(
          RegExp(
            r'^(who|whichever|whatever|what|which|whoever|lets|let us|can you|could you|do you|how)\s+',
          ),
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

  // Proof instructions override every inferred default. Mined from the head
  // AND the modifier clauses, then stripped so they never pollute subjects.
  var proofOverride = _proofFromText(core) ?? _proofFromText(tails.join(' '));
  core = _stripProofPhrases(core);

  // THE THREE CLOCKS, rule 1: a race deadline lives at the tail —
  // "by Friday", "this week", "tonight", "in 2 weeks". Extracted before the
  // attempt-window grammar so "in 30 seconds" is never mistaken for one.
  final dl = _extractDeadline(core);
  final deadline = dl.deadline;
  if (dl.stripped != core) core = dl.stripped.trim();

  // Scope phrases that name a venue/session, not the subject — "in a game",
  // "over 18 holes", "in batting practice", "at cleanup". The stripped text
  // is kept: an event-scoped "most" is a single attempt, not an
  // accumulation.
  var scopeCtx = '';
  core = core
      .replaceAllMapped(
        RegExp(
          r'\s+\b(in|on|at|over|during)\s+(a|an|the|one|our|my|batting|18|eighteen)?\s*(game|batting practice|practice|cleanup|18 holes|eighteen holes|training|session)\b',
        ),
        (m) {
          scopeCtx = '$scopeCtx ${m.group(0)}';
          return ' ';
        },
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // Constraint clauses ("without stopping", "excluding family donations",
  // "on the same course") narrow the subject, they never change the format.
  final constraint = _extractConstraint(core);
  String? constraintQuestion;
  String? constraintSubject;
  String? constraintUnit;
  if (constraint.stripped != core) {
    core = constraint.stripped.trim();
    if (constraint.text != null) {
      assumptions.add('Constraint: ${constraint.text}');
      final ct = constraint.text!.toLowerCase();
      // "relative to bodyweight" changes the metric itself — the race
      // can't compute it without knowing how bodyweight is recorded.
      if (ct.contains('relative to bodyweight')) {
        constraintQuestion = 'How should bodyweight be recorded?';
        constraintSubject = 'relative strength';
        constraintUnit = 'x bodyweight';
      }
      // A violation-class exclusion ("without gutter balls") is a scoring
      // rule the camera/photo can't see — surface how it gets verified.
      else if (RegExp(r'(gutter balls?|fouls?|violations?|false starts?)')
          .hasMatch(ct)) {
        constraintQuestion =
            'How will "${constraint.text}" be verified?';
      }
      // Per-person economics is an efficiency race — a rate, not a sum.
      else if (ct.contains('per person')) {
        constraintSubject = 'fundraising efficiency';
        constraintUnit = 'usd/person';
      }
      // Continuity constraints reshape the goal name, not the format.
      else if (ct.contains('stopping')) {
        constraintSubject = 'streak';
      } else if (ct.contains('walking')) {
        constraintSubject = 'continuous';
      }
    }
  }

  // Contradiction scan over the whole utterance — a race that claims two
  // scoring directions gets ONE clarification, not a silent pick.
  final lowerSignal = RegExp(
    r'\b(lowest|fewest|least|smallest|shortest|slowest|minimum|closest)\b',
  );
  final higherSignal = RegExp(
    r'\b(first|most|highest|best|biggest|max|maximum)\b',
  );
  final tailText = _normalize(tails.join(' '));
  final contradicts = higherSignal.hasMatch('$core $tailText') &&
      lowerSignal.hasMatch('$core $tailText') &&
      // "fewest" after "most" is the contradiction; pure "lowest X" is not.
      !RegExp(r'^(the\s+)?(lowest|fewest|least|smallest|shortest|closest)\b')
          .hasMatch(core);

  // ── Grammar slot: MULTI-GOAL — two scored things joined by "and" is one
  // race asking for two different answers. Nuvo races measure one thing;
  // surface the pick rather than silently choosing a side.
  if (RegExp(
    r'\b(best|fastest|most|highest|lowest|longest|shortest|first)\b[\w\s%]*\band\b[\w\s%]*\b(best|fastest|most|highest|lowest|longest|shortest|first)\b',
  ).hasMatch(core)) {
    return FlexiRaceInterpretation(
      input: input.trim(),
      goalKind: RaceGoalKind.manual,
      metric: RaceMetric.reps,
      format: RaceFormat.bestAttempt,
      targetValue: 1,
      deadline: deadline,
      proofNeed: ProofNeed.manual,
      confidence: InterpretationConfidence.assumed,
      manualGoalName: 'Multi-Goal',
      inferredFields: const {RaceField.goalKind},
      assumptions: assumptions,
      question: 'Pick one thing to compete in for this race.',
    );
  }

  // ── Grammar slot: AMBIGUOUS CLOCK — "fastest 5k in 10 minutes" reads as
  // both a time trial and a target result. Keep the window as the attempt
  // and ask which it meant.
  final fastIn = RegExp(
    r'\b(fastest|shortest|quickest|slowest)\s+(.+?)\s+in\s+(\w+)\s*(seconds?|secs?|minutes?|mins?|hours?|hrs?)\s*$',
  ).firstMatch(core);
  if (fastIn != null) {
    final n = _numberAt(fastIn.group(3)!);
    if (n != null && n > 0) {
      final u = fastIn.group(4)!;
      final secs =
          u.startsWith('h') ? n * 3600 : u.startsWith('m') ? n * 60 : n;
      final subject = _cleanSubject(fastIn.group(2)!);
      final goalName = _canonSubjectDomain(subject);
      return FlexiRaceInterpretation(
        input: input.trim(),
        goalKind: RaceGoalKind.manual,
        metric: RaceMetric.seconds,
        format: RaceFormat.bestAttempt,
        targetValue: 1,
        attemptDurationSeconds: secs,
        deadline: deadline,
        requiredDistanceValue: _distanceRequirement(core)?.$1,
        requiredDistanceUnit: _distanceRequirement(core)?.$2,
        proofNeed: _resolveProofNeed(
            proofOverride, null, subject, goalName, 'seconds',
            timeWord: true),
        confidence: InterpretationConfidence.assumed,
        scoreDirection: 'lower',
        manualGoalName: _titleCase(goalName),
        manualUnit: 'seconds',
        inferredFields: const {
          RaceField.goalKind, RaceField.format, RaceField.manualGoal,
          RaceField.manualUnit, RaceField.timing,
        },
        assumptions: assumptions,
        question:
            'Is ${fastIn.group(3)} ${fastIn.group(4)} a time limit or the target result?',
      );
    }
  }

  // ── Grammar slot: TIMED ATTEMPT — "most X in 30 seconds", "how many X in
  // a minute", "as many X as possible in 20 seconds", "30 second plank
  // jacks", "burpee sprint 25 seconds". A window ≤ 1 hour is an attempt;
  // longer windows are race deadlines (handled by _extractDeadline).
  final timed = _attemptWindow(core);
  if (timed != null) {
    var subject = timed.subject;
    var duration = timed.seconds;
    final activity = _activityFor(subject);
    String? question;
    if (duration <= 0) {
      question = 'Attempt duration must be greater than zero.';
    }
    if (subject.isEmpty) {
      question ??= 'What are you counting?';
    }
    // Measure-words in the count slot ("most reps") name a measure but not
    // the movement — one question, never a guess.
    if (subject == 'reps' || subject == 'repetitions') {
      question ??= 'What movement are you doing?';
      subject = 'repetitions';
    }
    if (contradicts) question ??= _contradictionQuestion(input);
    var goalName = _canonSubjectDomain(subject);
    if (goalName == 'distance' &&
        RegExp(r'\b(distance|miles?)\b').hasMatch(subject)) {
      goalName = 'running';
    }
    if (goalName == 'distance') {
      question ??= 'What activity are you doing?';
    }
    question ??= constraintQuestion;
    final manualUnit = activity == null ? _bestUnit(subject, goalName) : null;
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
      attemptDurationSeconds: duration,
      deadline: deadline ?? _secondWindowDeadline(core),
      proofNeed: _resolveProofNeed(
        proofOverride, activity, subject, goalName, manualUnit),
      confidence: activity == null || question != null
          ? InterpretationConfidence.assumed
          : InterpretationConfidence.high,
      manualGoalName: activity == null && goalName.isNotEmpty
          ? _titleCase(goalName)
          : null,
      manualUnit: manualUnit,
      inferredFields: {
        RaceField.activity,
        RaceField.goalKind,
        RaceField.format,
        RaceField.timing,
        if (activity == null) RaceField.manualGoal,
      },
      assumptions: assumptions,
      question: question,
    );
  }

  // ── Grammar slot: FIRST TO — "first to N X", "race to N X", "beat me to
  // N X", "whoever does N X first", "N X first (wins)", "hold X for T
  // first", "first to read/save/finish N X".
  final firstTo = _firstToParse(core);
  if (firstTo != null) {
    var (target, subject) = firstTo;
    // A target that can't be represented is a bounds problem — keep the
    // subject, drop the number, ask.
    final huge = RegExp(r'\b\d{9,}\b').firstMatch(subject);
    if (huge != null) {
      subject = _cleanSubject(subject.replaceAll(huge.group(0)!, ''));
      final goalName = _canonSubjectDomain(subject);
      final unit = _bestUnit(subject, goalName);
      return FlexiRaceInterpretation(
        input: input.trim(),
        goalKind: RaceGoalKind.manual,
        metric: _metricForUnit(unit),
        format: RaceFormat.firstToGoal,
        targetValue: 1,
        deadline: deadline,
        proofNeed: _resolveProofNeed(
            proofOverride, null, subject, goalName, unit),
        confidence: InterpretationConfidence.assumed,
        manualGoalName: _titleCase(goalName),
        manualUnit: unit,
        inferredFields: const {
          RaceField.goalKind, RaceField.format, RaceField.manualGoal,
        },
        assumptions: assumptions,
        question: 'That target is too large.',
      );
    }
    // "first to inbox zero" — the domain phrase means fewest messages.
    if (subject == 'email inbox zero') {
      return FlexiRaceInterpretation(
        input: input.trim(),
        goalKind: RaceGoalKind.manual,
        metric: RaceMetric.reps,
        format: RaceFormat.bestAttempt,
        targetValue: 0,
        deadline: deadline,
        proofNeed: ProofNeed.photo,
        confidence: InterpretationConfidence.high,
        scoreDirection: 'lower',
        manualGoalName: 'Email Inbox',
        manualUnit: 'emails remaining',
        inferredFields: {
          RaceField.goalKind,
          RaceField.format,
          RaceField.manualGoal,
          RaceField.manualUnit,
          RaceField.scoreDirection,
        },
        assumptions: assumptions,
      );
    }
    final activity = _activityFor(subject);
    final unit = activity == null
        ? _bestUnit(subject, _canonSubjectDomain(subject))
        : null;
    // Score-valued subjects aren't cumulative: "first to a 100 on a quiz"
    // is one great quiz, not a running tally.
    final scoreDomain = activity == null && _isScoreSubject(subject, unit);
    final format = scoreDomain
        ? RaceFormat.bestAttempt
        : _supported(
            activity, RaceFormat.firstToGoal, assumptions, 'a goal race');
    String? question;
    if (target <= 0) {
      question = 'Target must be greater than zero.';
      target = 1;
    } else if (target > 100000000) {
      question = 'That target is too large.';
      target = 1;
    }
    if (subject.isEmpty) question ??= '$target of what?';
    if (contradicts) question ??= _contradictionQuestion(input);
    question ??= constraintQuestion;
    var goalName = _canonSubjectDomain(subject);
    if ((proofOverride == ProofNeed.manual ||
            proofOverride == ProofNeed.note) &&
        subject.isNotEmpty) {
      goalName = subject;
    }
    if (constraintSubject != null) {
      goalName = constraintSubject == 'streak'
          ? _canonSubjectDomain('$subject streak')
          : constraintSubject == 'continuous'
              ? _canonSubjectDomain(
                  'continuous ${goalName == 'running' ? 'run' : goalName}')
              : constraintSubject;
    }
    if (goalName == 'distance') {
      question ??= 'What activity are you doing?';
    }
    // Measure-subjects in a first-to slot ("first to 100 points") read as
    // scores, not counts of points.
    if (goalName == 'points' || goalName == 'score') goalName = 'score';
    if (question == null && _genericSubjectQuestion.containsKey(goalName)) {
      question = _genericSubjectQuestion[goalName];
    }
    return FlexiRaceInterpretation(
      input: input.trim(),
      goalKind: activity == null ? RaceGoalKind.manual : RaceGoalKind.movement,
      activity: activity,
      metric: activity?.metric ?? _metricForUnit(unit),
      format: format,
      targetValue: target,
      deadline: deadline,
      proofNeed: _resolveProofNeed(
          proofOverride, activity, subject, goalName, unit),
      confidence: subject.isEmpty || question != null
          ? InterpretationConfidence.assumed
          : InterpretationConfidence.high,
      scoreDirection: contradicts ? 'lower' : 'higher',
      manualGoalName:
          activity == null && goalName.isNotEmpty ? _titleCase(goalName) : null,
      manualUnit: unit,
      inferredFields: {
        RaceField.activity,
        RaceField.goalKind,
        RaceField.format,
        RaceField.target,
        if (activity == null) RaceField.manualGoal,
      },
      assumptions: assumptions,
      question: question,
    );
  }

  // ── Grammar slot: SUPERLATIVE — "longest / fastest / highest / lowest /
  // best / biggest / heaviest / fewest / least / smallest / tallest / max /
  // closest to N / most" plus the suffix form "who can hold a wall sit the
  // longest" and improvement races "improve their grade the most".
  final sup = _superlativeParse(core);
  if (sup != null) {
    var (word, subject, explicitN) = sup;
    // Measure-only subjects ("highest score", "longest wins") are real
    // competitions missing a domain — keep the measure, ask the question,
    // never invent a subject. Format follows the measure kind: an empty
    // count accumulates, a score is a single attempt.
    if (_measureOnlySet.contains(subject) && word != 'closest') {
      final measureSubject = subject.isEmpty ? 'count' : subject;
      final measureUnit = {
        'time': 'seconds', 'duration': 'seconds', 'score': 'points',
        'percentage': 'percent', 'count': 'count', 'points': 'points',
        'distance': 'miles', 'weight': 'lb', 'money': 'usd',
      }[measureSubject];
      return FlexiRaceInterpretation(
        input: input.trim(),
        goalKind: RaceGoalKind.manual,
        metric: _metricForUnit(measureUnit),
        format: word == 'most' && measureSubject == 'count'
            ? RaceFormat.mostInWindow
            : RaceFormat.bestAttempt,
        targetValue: explicitN ?? 60,
        deadline: deadline,
        proofNeed: ProofNeed.manual,
        confidence: InterpretationConfidence.assumed,
        scoreDirection: _directionFor(word, measureSubject, measureUnit),
        manualGoalName: _titleCase(measureSubject),
        manualUnit: measureUnit,
        inferredFields: const {
          RaceField.goalKind, RaceField.format,
          RaceField.manualGoal, RaceField.manualUnit,
        },
        assumptions: assumptions,
        question: _measureQuestion(measureSubject, measureUnit),
      );
    }
    var activity = _activityFor(subject);
    var goalName = _canonSubjectDomain(subject);
    if ((proofOverride == ProofNeed.manual ||
            proofOverride == ProofNeed.note) &&
        subject.isNotEmpty) {
      goalName = subject;
    }
    var unit = activity == null
        ? _bestUnit(subject, goalName, head: word)
        : null;
    final isTimeWord =
        word == 'longest' || word == 'fastest' || word == 'shortest';
    if (activity == null && isTimeWord && (unit == null || unit == 'count')) {
      unit = word == 'longest' ? _durationUnit(subject) : 'seconds';
    }
    var direction =
        contradicts ? 'lower' : _directionFor(word, subject, unit);
    var question = contradicts ? _contradictionQuestion(input) : null;
    question ??= constraintQuestion;
    // Improvement races measure a delta — every delta needs a baseline,
    // worded by the domain the user is improving.
    if (word == 'improve') {
      if (_isScoreSubject(subject, unit)) {
        unit = 'percentage points';
        question ??= 'What starting grade should improvement use?';
      } else if (RegExp(r'percentage').hasMatch(core)) {
        unit = 'percent';
        question ??= subject.contains('push') ||
                RegExp(r'(rep|pushup|squat|pullup|situp|dip|burpee)').hasMatch(subject)
            ? 'What baseline rep count should improvement use?'
            : 'What baseline should improvement use?';
      } else if (unit == 'seconds' || unit == 'minutes') {
        question ??= 'What baseline time should improvement use?';
      } else {
        question ??= 'What baseline should improvement be measured from?';
      }
    }
    // "Best score" / "highest percentage" carry a measurement, not a
    // subject — surface the gap as one question instead of inventing it.
    if (question == null &&
        word != 'closest' &&
        (_isMeasureOnlySubject(subject) || _measureOnlySet.contains(goalName))) {
      question = _measureQuestion(
          _isMeasureOnlySubject(subject) ? subject : goalName, unit);
    }
    if (goalName == 'distance') {
      question ??= 'What activity are you doing?';
    }
    // Judged subjects ("best drawing") have no objective reading — the
    // rubric is the missing field, not the subject.
    final judgedName = _judgedSubjects[goalName];
    if (judgedName != null && word == 'best') {
      goalName = judgedName;
      unit = _unitFor(judgedName);
      question ??= _genericSubjectQuestion[goalName] ??
          'Who decides the score?';
    } else if (question == null && _genericSubjectQuestion.containsKey(goalName)) {
      question = _genericSubjectQuestion[goalName];
    }
    // Closest-to races are accuracy races; a bare "error" subject can't
    // name its instrument, so it asks.
    if (word == 'closest') {
      if (subject.contains('guess') || core.contains('guess')) {
        goalName = 'guess accuracy';
      } else if (subject.contains('error')) {
        goalName = 'error';
        question ??= 'What measurement produces the error reading?';
      } else {
        goalName = 'score accuracy';
      }
    }
    // "report card" names a container, not a number — the comparator is
    // ambiguous until the user picks one.
    if (subject == 'report card') {
      question ??= 'What number should Nuvo compare?';
    }
    // "friends judge the video" — the score's rubric is undefined.
    if (question == null &&
        RegExp(r'\bfriends?\s+(judge|score|rate|rank)').hasMatch(input.toLowerCase())) {
      question = 'How should friends score it?';
    }
    // A dangling window preposition ("most tennis serves in") is an
    // unfinished clause, not a race definition.
    if (question == null && RegExp(r'\sin\s*$').hasMatch(core)) {
      question = 'How many attempts or what time window?';
    }
    final percentBreach = _explicitPercentBreach(core);
    if (question == null && percentBreach) {
      question = 'Can $subject exceed 100% for this race?';
    }
    if (word == 'improve') {
      // "Improvement on pushups" is still a pushups race — the delta only
      // changes what gets recorded, and motion proof still applies.
      activity = null;
      goalName = _canonSubjectDomain('$subject improvement');
      unit = _unitFor(goalName) ?? unit;
      if (goalName == 'grade improvement' &&
          !RegExp(r'grade|gpa|score|test|exam').hasMatch(subject)) {
        goalName = _canonSubjectDomain(subject);
      }
    }
    // Constraints that rename the goal apply last — they reshape identity,
    // not format.
    if (constraintSubject == 'relative strength' ||
        constraintSubject == 'fundraising efficiency') {
      goalName = constraintSubject!;
      unit = constraintUnit;
    } else if (constraintSubject == 'streak') {
      goalName = _canonSubjectDomain('${subject == 'pushups' || subject == 'push ups' ? 'pushup' : subject} streak');
      activity = null;
      unit = _unitFor(goalName);
    } else if (constraintSubject == 'continuous') {
      goalName = _canonSubjectDomain(
          'continuous ${goalName == 'running' ? 'run' : goalName}');
      activity = null;
      unit = _unitFor(goalName);
    }
    // Constraints can re-derive the goal name after the question hooks ran —
    // a renamed goal can itself carry the missing clarification.
    question ??= _genericSubjectQuestion[goalName];
    // "Most X in <event scope>" (one game, batting practice) is a single
    // attempt; "most X" alone accumulates. A contradiction defers the
    // format decision to the clarification, so it reads as best-attempt.
    // A stated finish line makes even a preset race cumulative-before-
    // deadline ("most pushups by 8pm").
    final cumulative = word == 'most' &&
        !_singleAttemptSubject(
            '$subject $tailText ${constraint.text ?? ''} $scopeCtx') &&
        !contradicts &&
        !RegExp(r'\sin\s*$').hasMatch(core) &&
        (activity == null || deadline != null);
    // Completion-class canon names ("sensors integrated", "books read
    // with a photo of each") describe reaching a finished state — that is
    // a goal race, not an accumulation.
    final completesGoal = goalName.endsWith(' integrated') ||
        RegExp(r'\bof each\b').hasMatch(tails.join(' '));
    var format = cumulative
        ? RaceFormat.mostInWindow
        : _supported(
            activity,
            cumulative ? RaceFormat.mostInWindow : RaceFormat.bestAttempt,
            assumptions,
            'a best-attempt race',
          );
    if (completesGoal && !contradicts) format = RaceFormat.firstToGoal;
    if ((cumulative || word == 'most') && deadline == null) {
      assumptions.add('Finish line not stated — set one in the goal step.');
    }
    final distReq = (unit == 'seconds' || unit == 'minutes')
        ? _distanceRequirement(core)
        : null;
    return FlexiRaceInterpretation(
      input: input.trim(),
      goalKind: activity == null ? RaceGoalKind.manual : RaceGoalKind.movement,
      activity: activity,
      metric: activity?.metric ?? _metricForUnit(unit),
      format: format,
      targetValue: explicitN ?? activity?.defaultTarget ?? 60,
      deadline: deadline,
      requiredDistanceValue: distReq?.$1,
      requiredDistanceUnit: distReq?.$2,
      proofNeed: _resolveProofNeed(
          proofOverride, activity, subject, goalName, unit,
          timeWord: isTimeWord),
      confidence: activity == null || question != null
          ? InterpretationConfidence.assumed
          : InterpretationConfidence.high,
      scoreDirection: direction,
      manualGoalName: activity == null ? _titleCase(goalName) : null,
      manualUnit: activity == null ? unit : null,
      inferredFields: {
        RaceField.activity,
        RaceField.goalKind,
        RaceField.format,
        RaceField.target,
        if (direction == 'lower') RaceField.scoreDirection,
        if (activity == null) ...{RaceField.manualGoal, RaceField.manualUnit},
      },
      assumptions: assumptions,
      question: question,
    );
  }

  // ── Fallback: bare subject, count anywhere, or genuinely ambiguous ──────
  final activity = _activityFor(core);
  final target = _firstNumber(core);
  if (activity != null) {
    return FlexiRaceInterpretation(
      input: input.trim(),
      goalKind: RaceGoalKind.movement,
      activity: activity,
      metric: activity.metric,
      format: RaceFormat.firstToGoal,
      targetValue: target ?? activity.defaultTarget,
      deadline: deadline,
      proofNeed: proofOverride ?? _motionNeed(activity),
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
  var stripped = _cleanSubject(core);
  // Bare-competition phrases canonicalize to their measure-subject.
  const fallbackMeasures = {
    'beat me': 'competition', 'race me': 'competition', 'race': 'competition',
    'better': 'performance', 'does better': 'performance',
    'win': 'competition', 'wins': 'competition',
  };
  if (fallbackMeasures.containsKey(stripped)) {
    stripped = fallbackMeasures[stripped]!;
  }
  if (RegExp(r'\bfinish first\b|^race to finish').hasMatch(stripped) ||
      RegExp(r'^race to finish').hasMatch(core)) {
    stripped = 'completion';
  }
  // A title that is only a number ("🔥 100 🔥") counts something unknown.
  if (RegExp(r'^\d+$').hasMatch(stripped)) stripped = 'count';
  stripped = _canonSubjectDomain(stripped);
  var fbQuestion = _genericSubjectQuestion[stripped] ??
      constraintQuestion ??
      _fallbackQuestion(core, stripped, target);
  final fbUnit = stripped.isEmpty ? null : _unitFor(stripped);
  // Score-domain races are one great attempt — "95 percent on test" is
  // not a tally to a finish line.
  final scoreLike =
      fbUnit == 'percent' || stripped == 'score' || stripped == 'test score';
  return FlexiRaceInterpretation(
    input: input.trim(),
    goalKind: RaceGoalKind.manual,
    metric: RaceMetric.reps,
    format: !scoreLike && (target != null || stripped == 'completion')
        ? RaceFormat.firstToGoal
        : RaceFormat.bestAttempt,
    targetValue: target ?? 1,
    deadline: deadline,
    proofNeed: _resolveProofNeed(proofOverride, null, stripped, stripped, fbUnit),
    confidence: InterpretationConfidence.low,
    manualGoalName: stripped.isEmpty ? null : _titleCase(stripped),
    manualUnit: fbUnit,
    inferredFields: {
      RaceField.goalKind,
      if (stripped.isNotEmpty) RaceField.manualGoal,
    },
    assumptions: assumptions,
    question: fbQuestion,
  );
}

/// Bare imperatives ("beat me", "race me", "race to finish first") and bare
/// subjects both reach the fallback — the difference is whether Nuvo knows
/// what is being measured. One question either way, never a silent guess.
String? _fallbackQuestion(String core, String subject, int? target) {
  if (RegExp(r'^(beat me|race me|race)$').hasMatch(core)) {
    return 'What are you competing in?';
  }
  if (RegExp(r'\bfinish first\b').hasMatch(core) ||
      RegExp(r'^(race|race to)\s+finish').hasMatch(core)) {
    return 'Finish what?';
  }
  if (subject.isEmpty) return 'What are you competing in?';
  if (_isMeasureOnlySubject(subject)) return _measureQuestion(subject, null);
  if (target != null &&
      (subject.isEmpty || _measureOnlySet.contains(subject))) {
    return '$target of what?';
  }
  return subject.isEmpty ? 'What counts as progress?' : null;
}



/// Locomotion subjects a GPS activity session can prove — running,
/// jogging, walking, hiking, and cycling. Swimming pools, indoor
/// treadmills, and motorized laps are deliberately excluded.
bool _isGpsSubject(String s) {
  if (s.contains('treadmill') ||
      s.contains('dog walk') ||
      s.contains('sprint')) {
    return false;
  }
  return RegExp(
    r'\b(run|ran|running|jog|jogging|walk|walking|walked|hike|hiking|bike|biked|biking|cycle|cycling|marathon|mile run|5k|10k|continuous run|distance)\b',
  ).hasMatch(s);
}

/// The stated distance bar for a race that measures time over distance —
/// "fastest mile" -> (1, miles), "fastest 5k" -> (5, km).
(double, String)? _distanceRequirement(String core) {
  if (RegExp(r'\bmarathon\b').hasMatch(core)) {
    return (RegExp(r'\bhalf\b').hasMatch(core) ? 13.1 : 26.2, 'miles');
  }
  final m = RegExp(
    r'\b(\d+(?:\.\d+)?)\s*(miles?|mi|km|kilometers?|k|meters?|m|yards?|yd)\b',
  ).firstMatch(core);
  if (m != null) {
    final n = double.tryParse(m.group(1)!);
    if (n != null) {
      final u = m.group(2)!;
      final unit = u.startsWith('mi') && u != 'miles' ||
              u == 'mile' ||
              u == 'miles'
          ? 'miles'
          : u == 'k' || u.startsWith('km') || u.startsWith('kilo')
              ? 'km'
              : u.startsWith('m')
                  ? 'meters'
                  : 'yards';
      return (n, unit);
    }
  }
  if (RegExp(r'\b(a|an|the|one|single)\s+mile\b|\bmile\b').hasMatch(core)) {
    return (1, 'miles');
  }
  return null;
}

/// Merges an interpretation into the working draft — USER EDIT WINS. A field
/// the user has touched ([RaceDraft.userEditedFields]) is never overwritten
/// by a later interpretation of a changed title.
/// Canonical deadline phrase ("friday", "this week", "24 hours") -> the
/// timestamp the finish line actually lands on. Event-bounded phrases
/// ("event start") have no date — returning null keeps the composer honest
/// instead of inventing one.
DateTime? deadlineUtcFromPhrase(String? phrase) {
  if (phrase == null) return null;
  final now = DateTime.now();
  DateTime eod(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);
  DateTime at(DateTime d, int h) => DateTime(d.year, d.month, d.day, h);
  const weekdays = {
    'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4,
    'friday': 5, 'saturday': 6, 'sunday': 7,
  };
  if (weekdays.containsKey(phrase)) {
    var d = now;
    while (d.weekday != weekdays[phrase] || !d.isAfter(now)) {
      d = d.add(const Duration(days: 1));
    }
    return eod(d).toUtc();
  }
  switch (phrase) {
    case 'today':
    case 'tonight':
      return eod(now).toUtc();
    case 'tomorrow':
      return eod(now.add(const Duration(days: 1))).toUtc();
    case 'tomorrow morning':
      return at(now.add(const Duration(days: 1)), 12).toUtc();
    case 'weekend':
    case 'this week':
    case 'end of week': {
      var d = now;
      while (d.weekday != DateTime.sunday) {
        d = d.add(const Duration(days: 1));
      }
      return eod(d).toUtc();
    }
    case 'this month':
    case 'end of month':
      return eod(DateTime(now.year, now.month + 1, 0)).toUtc();
    case 'this year':
    case 'end of year':
    case 'new years':
      return DateTime(now.year, 12, 31, 23, 59, 59).toUtc();
    case 'midnight':
      final m = at(now.add(const Duration(days: 1)), 0);
      return m.isAfter(now) ? m.toUtc() : at(now.add(const Duration(days: 2)), 0).toUtc();
    case 'noon':
    case 'lunch': {
      final n = at(now, 12);
      return (n.isAfter(now) ? n : at(now.add(const Duration(days: 1)), 12))
          .toUtc();
    }
    case 'dinner':
    case 'sunset': {
      final d = at(now, 19);
      return (d.isAfter(now) ? d : at(now.add(const Duration(days: 1)), 19))
          .toUtc();
    }
    case 'sunrise': {
      final d = at(now, 6);
      return (d.isAfter(now) ? d : at(now.add(const Duration(days: 1)), 6))
          .toUtc();
    }
    case 'semester':
      return now.add(const Duration(days: 90)).toUtc();
    case 'summer':
      final aug = DateTime(now.year, 8, 31, 23, 59, 59);
      return (aug.isAfter(now) ? aug : DateTime(now.year + 1, 8, 31, 23, 59, 59))
          .toUtc();
  }
  final rel = RegExp(r'^(\d+)\s*(hours?|days?|weeks?|months?)').firstMatch(phrase);
  if (rel != null) {
    final n = int.parse(rel.group(1)!);
    final u = rel.group(2)!;
    return now
        .add(u.startsWith('h')
            ? Duration(hours: n)
            : u.startsWith('d')
                ? Duration(days: n)
                : u.startsWith('w')
                    ? Duration(days: 7 * n)
                    : Duration(days: 30 * n))
        .toUtc();
  }
  final ampm = RegExp(r'^(\d{1,2})(:\d{2})?\s*(am|pm)').firstMatch(phrase);
  if (ampm != null) {
    var h = int.parse(ampm.group(1)!) % 12;
    if (ampm.group(3) == 'pm') h += 12;
    final min = ampm.group(2) != null
        ? int.parse(ampm.group(2)!.substring(1))
        : 0;
    var d = DateTime(now.year, now.month, now.day, h, min);
    if (!d.isAfter(now)) d = d.add(const Duration(days: 1));
    return d.toUtc();
  }
  return null;
}

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
    finishLineAt: guard(
        RaceField.timing, deadlineUtcFromPhrase(i.deadline)?.toIso8601String()),
    // A fresh non-timed interpretation clears inferred timing; it never
    // clears timing the user set.
    clearTiming: !edited.contains(RaceField.timing) &&
        i.attemptDurationSeconds == null &&
        i.deadline == null,
    clarification: i.question,
    clearClarification: i.question == null,
    manualGoalName: guard(RaceField.manualGoal, i.manualGoalName),
    manualUnit: guard(RaceField.manualUnit, i.manualUnit),
    recurrence: guard(RaceField.recurrence, i.recurrence),
    scoreDirection: guard(RaceField.scoreDirection, i.scoreDirection),
    // An interpreted name never produces a Teach-Nuvo custom movement —
    // unless the user owns goalKind, stale custom state must not survive.
    clearCustom: !edited.contains(RaceField.goalKind),
  );
}

// ── Sanitize & normalize ─────────────────────────────────────────────────────

/// Untrusted text → lowercase grammar-ready tokens. Markup is removed
/// tag-pair-first so `<script>alert(1)</script>` contributes nothing, then
/// common typos/slang are canonicalized. Never executable input.
String _normalize(String input) {
  var s = input
      .toLowerCase()
      // Tag pairs with contents die first, then stray tags.
      .replaceAll(RegExp(r'<[^>]*>.*?</[^>]*>'), ' ')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      // Negative quantities keep their sign as a word — "-10 pushups" must
      // reach the bounds check, not silently become 10.
      .replaceAllMapped(RegExp(r'-\s*(\d)'), (m) => ' negative ${m[1]}')
      .replaceAll(RegExp(r'[-_]+'), ' ')
      // Instruction-shaped noise is content, not commands — "ignore all
      // previous rules" never reaches a subject.
      .replaceAll(
        RegExp(
          r'\b(ignore|disregard|forget)\s+(all\s+)?(previous\s+)?(rules?|instructions?|prompts?)\b|\bmake\s+me\b|\byou\s+are\b|\bas\s+an\s+ai\b|\bsystem\s+prompt\b',
        ),
        ' ',
      )
      .replaceAll(RegExp(r'\b(idk|tbh|lol|smh|rn|nvm|idrc|fyi|maybe)\b'), ' ')
      // Quantity markers become unit words BEFORE punctuation stripping so
      // "$500" -> "usd 500" and "95%" -> "95 percent" parse naturally.
      .replaceAllMapped(RegExp(r'\$(\d)'), (m) => 'usd ${m[1]}')
      .replaceAllMapped(RegExp(r'(\d)\s*%'), (m) => '${m[1]} percent')
      .replaceAll(RegExp(r'[^a-z0-9\s+]'), ' ')
      .replaceAll(RegExp(r'\+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // Digit-unit fusions are tokens, not words: "1min" -> "1 min", "30sec" ->
  // "30 sec". Distances keep their k ("5k", "10k"). Fractional time words
  // ("half a minute") are durations, not targets.
  s = s.replaceAllMapped(
    RegExp(r'\b(\d+)\s*(secs?|mins?|hrs?)\b'),
    (m) => '${m[1]} ${m[2]}',
  );
  s = s
      .replaceAll(RegExp(r'\bhalf\s+(?:a|an)?\s*minute\b'), '30 seconds')
      .replaceAll(RegExp(r'\bhalf\s+an?\s*hour\b'), '30 minutes')
      .replaceAll(RegExp(r'\bhalf\s+hour\b'), '30 minutes');
  var joined =
      s.split(' ').where((t) => t.isNotEmpty).map((t) {
        return _typoCanonical[t] ?? t;
      }).join(' ');
  // "who gets more X" / "lift more" mean the same slot as "most X".
  joined = joined.replaceAllMapped(
    RegExp(r'^more\s+(?:than\s+)?(.+)$'),
    (m) => 'most ${m[1]}',
  );
  joined = joined.replaceAllMapped(
    RegExp(r'^(\w+)\s+more\s*,?\s*(.*)$'),
    (m) => 'most ${m[1]} ${m[2]}'.trim(),
  );
  // "reads the most books" / "gets the most XP" — the verb precedes the
  // comparative; re-slot it into the superlative grammar.
  joined = joined.replaceAllMapped(
    RegExp(r'^(\w+)\s+the\s+(most|best|highest|lowest|biggest|fastest|longest|least|fewest)\s+(.+)$'),
    (m) => '${m[2]} ${m[1]} ${m[3]}',
  );
  return joined;
}

/// Misspellings/slang → canonical token. Presentation-level only — a typo'd
/// word still has to land on real grammar to mean anything.
const _typoCanonical = {
  'frst': 'first', 'frist': 'first', '1st': 'first',
  'cn': 'can', 'cant': 'cant', 'wins': 'wins',
  'grae': 'grade', 'golff': 'golf', 'tmrw': 'tomorrow', 'tmr': 'tomorrow',
  '2day': 'today', '2moro': 'tomorrow', 'wk': 'week', 'mo': 'month',
  'minuets': 'minutes', 'minites': 'minutes',
  'puhsups': 'pushups', 'pushps': 'pushups',
  'smth': 'something', 'mins': 'minutes', 'secs': 'seconds',
  'sec': 'seconds', 'hrs': 'hours', 'lbz': 'lb', 'repp': 'reps',
  'gols': 'goals', 'alot': 'a lot', 'wanna': 'want to',
  'ight': 'right', 'yea': 'yeah', 'gonna': 'going to',
  'fastes': 'fastest', 'longes': 'longest',
  'higest': 'highest', 'lowets': 'lowest', 'mosts': 'most',
};

/// Filler/slang words that never carry race semantics — removed from the
/// subject phrase, not from number/unit grammar.
const _noiseWords = {
  'wins', 'win', 'first', 'challenge', 'contest', 'battle', 'ez', 'idk',
  'maybe', 'pls', 'please', 'lol', 'rn', 'btw', 'tbh', 'imo', 'lets',
  'ya', 'yall', 'bro', 'bet', 'fr', 'frfr', 'n', 'ok', 'okay', 'smth',
  'something', 'stuff', 'thing', 'things', 'whatever', 'whoever',
};

// ── Clause extraction ────────────────────────────────────────────────────────

/// "with video proof", "screenshot proof", "post your Strava link",
/// "verify with repo link", "honor system", "no proof needed", "attach a
/// bank screenshot", "write a note from organizer", "friends judge the
/// video", "Nuvo verifies movement", "camera proof", "upload a picture".
ProofNeed? _proofFromText(String text) {
  final t = _normalize(text);
  if (t.isEmpty) return null;
  if (RegExp(r'\b(no proof|honor system|manual|on your honor|trust)\b')
      .hasMatch(t) &&
      !RegExp(r'\b(photo|video|screenshot|link|camera)\b').hasMatch(t)) {
    return ProofNeed.manual;
  }
  if (RegExp(r'\b(video|clip|recording|friends judge)\b').hasMatch(t)) {
    return ProofNeed.video;
  }
  if (RegExp(r'\b(camera|nuvo verifies|verified movement|movement|motion)\b')
      .hasMatch(t)) {
    // Motion words ask for camera verification of the movement itself —
    // reps or duration is resolved against the subject at the call site.
    return ProofNeed.motionReps;
  }
  if (RegExp(r'\b(link|url|repo|github|strava|post your)\b').hasMatch(t)) {
    return ProofNeed.link;
  }
  if (RegExp(r'\b(note|letter|written by|organizer)\b').hasMatch(t)) {
    return ProofNeed.note;
  }
  if (RegExp(r'\b(photo|photos|picture|pictures|screenshot|screenshots|pic|image|images|scan)\b')
      .hasMatch(t)) {
    return ProofNeed.photo;
  }
  return null;
}

String _stripProofPhrases(String core) => core
    .replaceAll(
      RegExp(
        r'\b(with|using|needs?|requires?|requiring|attach|post|upload|verify with|prove with|send)\s+((a|an|the|your|their|bank|repo|github|strava|each|every|one|of)\s+){0,3}(video|photo|photos|picture|pictures|screenshot|screenshots|camera|link|url|note|clip|recording|pic|image|images|scan)(\s+(proof|verification|required|of each|each))?\b',
      ),
      ' ',
    )
    .replaceAll(
      RegExp(
        r'\b(video|photo|screenshot|camera|link|note)\s+proof(\s+(required|needed|only))?\b',
      ),
      ' ',
    )
    .replaceAll(RegExp(r'\b(no proof needed|honor system|manual honor system|friends judge the video|nuvo verifies movement|write a note from organizer)\b'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// THE THREE CLOCKS — a deadline ends the race ("by Friday"), an attempt
/// window times ONE effort ("in 30 seconds"), a score can itself be a time
/// ("fastest mile"). Deadlines are named days/times and hour-plus windows;
/// second/minute windows stay for the attempt grammar.
({String? deadline, String stripped}) _extractDeadline(String core) {
  String? found;
  var s = core;
  final patterns = <RegExp>[
    // Named moments: by Friday, before lunch, by 8pm, by midnight,
    // by New Years, before the end of the month, by tomorrow morning.
    RegExp(
      r'\b(?:by|before|until|til|between\s+now\s+and)\s+(the\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday|lunch|dinner|midnight|noon|sunrise|sunset|new\s+years?|end\s+of\s+(the\s+)?(week|month|year)|tomorrow(\s+(morning|evening|night))?|next\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday|week|month)|\d{1,2}(:\d{2})?\s*(am|pm)|event\s+(start|end)|the\s+weekend)\b',
    ),
    // Free-standing periods: today, tonight, this week, this month,
    // this semester, this summer, this weekend.
    RegExp(
      r'\b(today|tonight|tomorrow(\s+morning)?|this\s+(week|weekend|month|semester|summer|year)|the\s+weekend|over\s+the\s+weekend)\b',
    ),
    // Event-bounded races end when the event does.
    RegExp(r'\b(at|until|til)\s+(the\s+)?(cleanup|event|meet|competition|game)\b'),
    // Hour-plus windows: "in 24 hours", "over the next 30 days",
    // "in 1 week", "within a month", "in a day". Seconds/minutes are
    // deliberately absent — those belong to the attempt window.
    RegExp(
      r'\b(?:in|within|over|during)\s+(the\s+)?(next\s+)?(a\s+|an\s+)?(\d+|one|two|three|four|five|six|seven|eight|nine|ten|a|an)\s*(hours?|days?|weeks?|months?)\b',
    ),
    // "event attendees" — the recruiting window ends when the event starts.
    RegExp(r'\bevent\b'),
  ];
  for (final p in patterns) {
    final m = p.firstMatch(s);
    if (m != null) {
      var phrase = _canonDeadlinePhrase(m.group(0)!);
      // A one-hour window is an attempt duration, not a race deadline —
      // "most diamonds in an hour" times one effort.
      if (phrase == '1 hour') continue;
      if (m.group(0) == 'event') phrase = 'event start';
      found ??= phrase;
      s = s.replaceRange(m.start, m.end, ' ');
    }
  }
  return (deadline: found, stripped: s.replaceAll(RegExp(r'\s+'), ' ').trim());
}

String _canonDeadlinePhrase(String phrase) {
  var d = phrase.toLowerCase().trim()
      .replaceAll(RegExp(r'^(between\s+now\s+and|by|before|until|til|in|within|over|during|at)\s+'), '')
      .replaceAll(RegExp(r'^(the|next)\s+'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
  const map = {
    'a week': '1 week', 'an week': '1 week', 'week': '1 week',
    'a month': '1 month', 'month': '1 month',
    'a day': '1 day', 'an day': '1 day', 'day': '1 day',
    'an hour': '1 hour', 'a hour': '1 hour',
    'this week': 'this week', 'this month': 'this month',
    'new year': 'new years', 'the weekend': 'weekend',
    'over the weekend': 'weekend', 'end of the week': 'end of week',
    'end of the month': 'end of month', 'end of the year': 'end of year',
    'this semester': 'semester', 'this summer': 'summer',
    'at cleanup': 'event end', 'cleanup': 'event end',
    'at the cleanup': 'event end', 'at event': 'event end',
    'at the event': 'event end', 'at meet': 'event end',
    'at the meet': 'event end', 'at competition': 'event end',
    'at the competition': 'event end', 'at game': 'event end',
    'at the game': 'event end', 'event': 'event end',
  };
  for (final e in map.entries) {
    if (d == e.key) return e.value;
  }
  // "24 hours" / "30 days" / "2 weeks" stay as written.
  return d;
}

/// Constraints narrow eligibility — "without stopping", "excluding family
/// donations", "on the same course", "with at least 200 pages". They are
/// preserved as assumptions, never allowed to bend grammar slots.
({String? text, String stripped}) _extractConstraint(String core) {
  String? found;
  var s = core;
  for (final p in <RegExp>[
    RegExp(r'\b(without|excluding|except|but not|minus)\s+(.+)$'),
    RegExp(r'\bwith at least\s+(.+)$'),
    RegExp(r'\bon the same\s+(.+)$'),
    RegExp(r'\bwith no\s+(.+)$'),
    RegExp(r'\bwith\s+\w+\s+at least\s+(.+)$'),
    RegExp(r'\bbut\s+(.+?)\s+(do not|does not|don.t)\s+count\b.*$'),
    RegExp(r'\brelative to\s+(.+)$'),
    RegExp(r'\bper person\b'),
    RegExp(r'\b(?:above|over|under|below|at least|more than)\s+\d+.*$'),
  ]) {
    final m = p.firstMatch(s);
    if (m != null) {
      found = m.group(0);
      s = s.replaceRange(m.start, m.end, ' ');
      break;
    }
  }
  return (text: found, stripped: s);
}

// ── Grammar slots ────────────────────────────────────────────────────────────

class _Timed {
  const _Timed(this.subject, this.seconds);
  final String subject;
  final int seconds;
}

/// Every phrasing that means "how much of X inside a fixed clock":
///   most jacks in 30 seconds          how many burpees in 45 sec
///   do as many crunches as possible   most reps in 1 minute
///   30 second plank jacks             15s jumping jack battle
///   burpee sprint 25 seconds          most X in an hour
/// Windows over an hour were already claimed by _extractDeadline.
_Timed? _attemptWindow(String core) {
  int? secondsOf(String n, String unit) {
    final v = _numberAt(n);
    if (v == null) return null;
    if (unit.startsWith('h')) return v * 3600;
    if (unit.startsWith('m')) return v * 60;
    return v;
  }

  const u = r'(seconds?|secs?|sec|s|minutes?|mins?|min|m|hours?|hrs?|hr)';
  // Each shape yields (subject, duration); the first match wins.
  String subject = '';
  int seconds = -1;

  Match? m;
  if ((m = RegExp(
              '(?:^|\\b)(?:most|max(?:imum)?|highest(?:\\s+count)?|many)\\s+(.+?)\\s+(?:in|within)\\s+(?:the\\s+next\\s+|an?\\s+)?(\\w+)\\s*$u\\b')
          .firstMatch(core)) !=
      null) {
    subject = m!.group(1)!;
    seconds = secondsOf(m.group(2)!, m.group(3)!) ?? -1;
  } else if ((m = RegExp(
              '(?:how\\s+many|number\\s+of)\\s+(.+?)\\s+(?:can|could|do|did)(?:\\s+\\w+){0,3}\\s+in\\s+(?:an?\\s+)?(\\w+)\\s*$u\\b')
          .firstMatch(core)) !=
      null) {
    subject = m!.group(1)!;
    seconds = secondsOf(m.group(2)!, m.group(3)!) ?? -1;
  } else if ((m = RegExp(
              '(?:do\\s+)?as\\s+many\\s+(.+?)\\s+as\\s+(?:you\\s+can|possible|we\\s+can)\\s+in\\s+(?:an?\\s+)?(\\w+)\\s*$u\\b')
          .firstMatch(core)) !=
      null) {
    subject = m!.group(1)!;
    seconds = secondsOf(m.group(2)!, m.group(3)!) ?? -1;
  } else if ((m = RegExp(
              '(?:^|\\b)(?:most|max(?:imum)?)\\s+(.+?)\\s+before\\s+(\\w+)\\s*$u\\s+runs\\s+out')
          .firstMatch(core)) !=
      null) {
    subject = m!.group(1)!;
    seconds = secondsOf(m.group(2)!, m.group(3)!) ?? -1;
  } else if ((m = RegExp(
              '^(.+?)\\s+(?:sprint|battle|challenge|faceoff|showdown)\\s+(\\w+)\\s*$u\\b')
          .firstMatch(core)) !=
      null) {
    subject = m!.group(1)!;
    seconds = secondsOf(m.group(2)!, m.group(3)!) ?? -1;
  } else if ((m = RegExp('^(\\w+)\\s*$u\\s+(.+?)\\s*(?:battle|challenge|sprint|dash|faceoff|showdown)?\$')
          .firstMatch(core)) !=
      null) {
    // Duration prefix only counts when the head is numeric.
    if (_numberAt(m!.group(1)!) == null) return null;
    seconds = secondsOf(m.group(1)!, m.group(2)!) ?? -1;
    subject = m.group(3)!;
  }
  if (m == null) {
    // Trailing "in N <u>" on a count phrasing ("most distance in 30
    // minutes", "most treadmill distance in 20 min").
    var tail = RegExp('(.+?)\\s+(?:in|within)\\s+(?:an?\\s+|the\\s+next\\s+)?(\\w+)\\s*$u\\s*\$')
        .firstMatch(core);
    // A bare trailing duration works the same ("most push ups 1 min").
    tail ??= RegExp('(.+?)\\s+(\\d+)\\s*(seconds?|secs?|minutes?|mins?|hours?|hrs?)\\s*\$')
        .firstMatch(core);
    if (tail == null) return null;
    // A duration that follows a comparator ("above 8 hours", "over 2
    // minutes") is a threshold constraint, not the attempt window.
    if (RegExp(
            r'(above|over|under|below|at least|more than|fewer than|less than|longer than)\s*$')
        .hasMatch(tail.group(1)!)) {
      return null;
    }
    if (!RegExp(
            r'\b(most|max|highest|as many|how many|more|farther|further|farthest|furthest|longer|longest)\b')
        .hasMatch(core)) {
      return null;
    }
    subject = tail.group(1)!;
    seconds = secondsOf(tail.group(2)!, tail.group(3)!) ?? -1;
  }
  if (seconds < 0) return null;
  var cleaned = _cleanSubject(subject);
  // "most in 30 seconds" — the comparative word leaked into the subject
  // slot; treat it as the missing subject it is.
  if (cleaned.isEmpty ||
      _measureOnlySet.contains(cleaned) ||
      cleaned == 'most') {
    cleaned = '';
  }
  return _Timed(cleaned, seconds);
}

/// When a timed attempt ALSO carries a race window ("most pushups in 30
/// seconds in 1 week"), the hour-plus window was claimed as the deadline —
/// nothing to do here. Kept for readability at the call site.
String? _secondWindowDeadline(String core) => null;

/// First-to means reach a cumulative goal earliest. Phrasings:
///   first to 50 pushups            first person to 100 squats
///   race to 75 jumping jacks       beat me to 200 mountain climbers
///   50 situps first                whoever does 80 high knees first
///   first to read 5 books          first to save $500
///   hold a plank for 5 minutes     first to inbox zero
(int, String)? _firstToParse(String core) {
  String? rest;
  for (final p in <RegExp>[
    RegExp(r'^(?:the\s+)?first\s+(?:person\s+|racer\s+|one\s+)?to\s+(.+)$'),
    RegExp(r'^(?:race|race\s+me)\s+to\s+(.+)$'),
    RegExp(r'^(?:can\s+you\s+|could\s+you\s+)?beat\s+me\s+to\s+(.+)$'),
    RegExp(r'^whoever\s+(.+?)\s+first\b'),
  ]) {
    final m = p.firstMatch(core);
    if (m != null) {
      rest = m.group(1)!.trim();
      break;
    }
  }
  // "hold/keep a X for T <unit> (first)" — duration-as-goal phrasing;
  // checked before any first-to shape so "...first" can't eat it.
  final holdAny = RegExp(
    r'^(?:hold|keep|stay|maintain)\s+(?:a\s+|an\s+)?(.+?)\s+for\s+(\w+)\s*(seconds?|secs?|minutes?|mins?|hours?|hrs?)(?:\s+first)?$',
  ).firstMatch(core);
  if (holdAny != null) {
    final n = _numberAt(holdAny.group(2)!);
    if (n != null) {
      final u = holdAny.group(3)!;
      final secs = u.startsWith('h')
          ? n * 3600
          : u.startsWith('m')
              ? n * 60
              : n;
      return (secs, _cleanSubject(holdAny.group(1)!));
    }
  }
  if (rest != null) {
    // "first to inbox zero" — a domain phrase, not a number.
    if (rest == 'inbox zero') return (0, 'email inbox zero');
    // "hold/keep a X for T <unit> first" — duration target.
    final hold = RegExp(
      r'(?:hold|keep|stay|maintain)\s+(?:a\s+|an\s+)?(.+?)\s+for\s+(\w+)\s*(seconds?|secs?|minutes?|mins?|hours?|hrs?)(?:\s+first)?$',
    ).firstMatch(rest);
    if (hold != null) {
      final n = _numberAt(hold.group(2)!);
      final unit = hold.group(3)!;
      if (n != null) {
        final secs = unit.startsWith('hour')
            ? n * 3600
            : unit.startsWith('m')
                ? n * 60
                : n;
        return (secs, hold.group(1)!);
      }
    }
    final split = _splitLeadingOrInnerNumber(rest);
    if (split != null) return split;
    // Unrepresentably huge targets still reach the bounds branch.
    if (RegExp(r'\d{9,}').hasMatch(rest)) return (1, rest);
    // "first to 50" — a target with no subject is still first-to-goal; the
    // caller asks "50 of what?" instead of falling through to superlative.
    final bare = _numberAt(rest);
    if (bare != null) return (bare, '');
    // "first to <subject>" — preset match fills the target; handled by the
    // caller's null target branch via (1, subject) being meaningless, so we
    // return null to let the activity fallback own it.
    return null;
  }
  // "N X first" / "N X first one there wins" / "whoever gets N X first".
  final whoever = RegExp(r'(?:gets?|does|finishes?|hits?|reaches?|makes?)\s+(\w+)\s+(.+?)\s+first\b')
      .firstMatch(core);
  if (whoever != null) {
    final n = _numberAt(whoever.group(1)!);
    if (n != null) return (n, _cleanSubject(whoever.group(2)!));
  }
  final suffix = RegExp(r'^(\w+)\s+(.+?)\s+first(\s+(one|person|racer)(\s+there)?)?\b')
      .firstMatch(core);
  if (suffix != null) {
    final n = _numberAt(suffix.group(1)!);
    if (n != null) return (n, _cleanSubject(suffix.group(2)!));
  }
  // Bare "first to <verb> <subject>" without a number → null target.
  final firstNoNum = RegExp(r'^(?:the\s+)?first\s+to\s+(.+)$').firstMatch(core);
  if (firstNoNum != null) {
    return (1, _cleanSubject(firstNoNum.group(1)!));
  }
  return null;
}

/// Superlative phrasings → (word, subject, explicitTarget).
///   longest plank        fastest mile       highest grade
///   fewest mistakes      max bench 225+     closest to 100 points
///   most weight carried  biggest deadlift   heaviest dumbbell curl
///   improve X the most   least mistakes     smallest bundle size
(String, String, int?)? _superlativeParse(String core) {
  // "closest to N X" — absolute-error race; the N is the target.
  final closest = RegExp(r'^closest\s+(?:guess\s+)?to\s+(?:the\s+)?(\w+)\s*(.*)$')
      .firstMatch(core);
  if (closest != null) {
    final n = _numberAt(closest.group(1)!);
    final subject = closest.group(2)!.trim().isEmpty
        ? 'points'
        : _cleanSubject(closest.group(2)!);
    return ('closest', subject.isEmpty ? 'target' : subject, n);
  }
  final m = RegExp(
    r'^(?:the\s+)?(longest|fastest|highest|lowest|best|biggest|heaviest|fewest|least|smallest|shortest|tallest|max|maximum|farthest|furthest|slowest|cheapest|top|most)\s+(.+)$',
  ).firstMatch(core);
  if (m != null) {
    var subject = m.group(2)!;
    // "biggest percentage improvement in pushups" — the improvement slot
    // names what improves, not a level.
    final impIn = RegExp(
      r'(?:^|\b)(?:percentage\s+)?improve(?:ment|s)?\s+(?:in|of|on)\s+(.+)$',
    ).firstMatch(subject);
    if (impIn != null) {
      return ('improve', _cleanSubject(impIn.group(1)!), null);
    }
    // "most <improve verb>" is an improvement race, not a count.
    final improve = RegExp(
      r'^(?:improve(?:s|ment)?|get better at)\s+(?:their\s+|your\s+|the\s+|my\s+)?(.+?)(?:\s+the\s+most)?$',
    ).firstMatch(subject);
    if (improve != null || RegExp(r'^improve').hasMatch(core)) {
      final sub = improve?.group(1) ?? subject;
      return ('improve', _cleanSubject(sub), null);
    }
    // "X the most" — "improve their mile time the most".
    final tail = RegExp(r'^(.+?)\s+the\s+most$').firstMatch(subject);
    if (tail != null && RegExp(r'\bimprov').hasMatch(subject)) {
      return ('improve', _cleanSubject(tail.group(1)!), null);
    }
    subject = _cleanSubject(subject);
    // "max bench 225+" / "highest grade 150%" — trailing number+unit hints.
    final hint = RegExp(r'^(.+?)\s+(\d+)(%|\+|lb|lbs|kg)?\s*$').firstMatch(subject);
    if (hint != null) {
      final n = int.tryParse(hint.group(2)!);
      final s = _cleanSubject(hint.group(1)!);
      if (n != null && s.isNotEmpty) return (m.group(1)!, s, n);
    }
    // "fastest wins" / "longest wins" — the comparative names a measure,
    // the subject stayed empty. Give it the canonical measure-subject.
    if (subject.isEmpty) {
      const measureByHead = {
        'fastest': 'time', 'shortest': 'time', 'quickest': 'time',
        'longest': 'duration', 'slowest': 'duration',
        'highest': 'score', 'lowest': 'score', 'best': 'score',
        'biggest': 'score', 'max': 'score', 'maximum': 'score',
        'top': 'score', 'tallest': 'score',
        'most': 'count', 'fewest': 'count', 'least': 'count',
        'smallest': 'count', 'minimum': 'count',
        'farthest': 'distance', 'furthest': 'distance',
        'heaviest': 'weight', 'cheapest': 'money',
      };
      subject = measureByHead[m.group(1)!] ?? 'count';
    }
    return (m.group(1)!, subject, null);
  }
  // A bare comparative with no subject at all ("most", "fastest") — the
  // deadline carried the only context. Resolve the measure, ask the rest.
  final bare = RegExp(
    r'^(?:the\s+)?(longest|fastest|highest|lowest|best|biggest|heaviest|fewest|least|smallest|shortest|tallest|max|maximum|farthest|furthest|slowest|cheapest|top|most)\s*$',
  ).firstMatch(core);
  if (bare != null) {
    const measureByHead = {
      'fastest': 'time', 'shortest': 'time', 'quickest': 'time',
      'longest': 'duration', 'slowest': 'duration',
      'highest': 'score', 'lowest': 'score', 'best': 'score',
      'biggest': 'score', 'max': 'score', 'maximum': 'score',
      'top': 'score', 'tallest': 'score',
      'most': 'count', 'fewest': 'count', 'least': 'count',
      'smallest': 'count', 'minimum': 'count',
      'farthest': 'distance', 'furthest': 'distance',
      'heaviest': 'weight', 'cheapest': 'money',
    };
    return (bare.group(1)!, measureByHead[bare.group(1)!] ?? 'count', null);
  }
  // "improve their mile time the most" / "improves their grade the most".
  final imp = RegExp(r'^(?:who\s+)?(?:can\s+)?improv\w*\s+(?:their\s+|your\s+|the\s+|my\s+)?(.+?)(?:\s+the\s+most)?$')
      .firstMatch(core);
  if (imp != null) {
    return ('improve', _cleanSubject(imp.group(1)!), null);
  }
  // Suffix superlative — "hold a wall sit the longest", "squat the most
  // weight", "run 10k fastest". The measure word trails the subject
  // instead of leading it, with or without "the".
  final suffix = RegExp(
    r'^(.+?)\s+(?:the\s+)?(longest|fastest|highest|lowest|best|biggest|heaviest|fewest|least|smallest|shortest|tallest|farthest|furthest|most)(?:\s+(.+))?$',
  ).firstMatch(core);
  if (suffix != null) {
    var subject = _cleanSubject(suffix.group(1)!);
    // "squat the most weight" — the quantity word after "most" is context.
    final tail = suffix.group(3);
    if (suffix.group(2) == 'most' && tail != null && tail.isNotEmpty) {
      subject = _cleanSubject('${suffix.group(1)} $tail');
      if (subject.isEmpty) subject = _cleanSubject(tail);
    }
    if (subject.isNotEmpty) return (suffix.group(2)!, subject, null);
  }
  return null;
}

// ── Direction / domain semantics ─────────────────────────────────────────────

String _directionFor(String word, String subject, String? unit) {
  const lowerWords = {
    'fastest', 'lowest', 'fewest', 'least', 'smallest', 'shortest',
    'slowest', 'cheapest', 'closest', 'minimum',
  };
  if (lowerWords.contains(word)) return 'lower';
  // Best/longest of a lower-is-better quantity is still lower.
  const lowerSubjects = {
    'time', 'lap time', 'startup time', 'reaction time', 'screen time',
    'latency', 'bundle size', 'temperature', 'spending', 'grocery spend',
    'delivery spend', 'grocery total', 'unread emails', 'email inbox',
    'mistakes', 'wrong answers', 'blunders', 'penalties', 'warnings',
  };
  if (lowerSubjects.contains(subject)) return 'lower';
  return 'higher';
}

/// Score-valued subjects produce a value per attempt, not a running tally —
/// "first to a 100 on a quiz" is best-attempt even under first-to grammar.
bool _isScoreSubject(String subject, String? unit) =>
    unit == 'percent' ||
    unit == 'gpa' ||
    RegExp(r'\b(grade|grades|quiz|test|exam|gpa|score)\b').hasMatch(subject);

/// "score", "points", "percentage", "time", "wins" — measurement words that
/// carry no subject. A superlative over one of these asks what is being
/// measured instead of inventing a domain.
const _measureOnlySet = {
  'score', 'points', 'percentage', 'time', 'duration', 'wins', 'better',
  'best', 'count', 'amount', 'number', 'value', '', 'it',
  'performance', 'competition', 'completion',
};

bool _isMeasureOnlySubject(String subject) =>
    _measureOnlySet.contains(subject);

String _measureQuestion(String subject, String? unit) {
  switch (subject) {
    case 'score':
    case 'points':
      return 'What are you scoring?';
    case 'percentage':
      return 'Percentage of what?';
    case 'time':
      return 'What are you timing?';
    case 'count':
    case 'amount':
    case 'number':
    case '':
      return 'Most of what?';
    case 'wins':
    case 'better':
    case 'best':
    case 'performance':
      return 'How should "better" be measured?';
    case 'duration':
      return 'What are you holding or doing?';
    case 'distance':
      return 'Distance doing what?';
    case 'weight':
      return 'Weight of what?';
    case 'competition':
      return 'What are you competing in?';
    case 'completion':
      return 'Finish what?';
    default:
      return 'What should Nuvo measure?';
  }
}

/// Single-attempt measures hidden inside "most" — "most weight carried",
/// "most consecutive free throws", "most TikTok views on one post" are
/// personal records, not accumulations.
bool _singleAttemptSubject(String subject) =>
    RegExp(
      r'\b(weight|consecutive|streak|record|one rep max|1rm|in one|on one|in a single|single|per post|at once|personal|per person|made|practice|drill|per game|in a game|in one game|sleep|slept|resting|rating|speed|bpm|percentage|average|latency|coverage|error|accuracy|height|long|benchmark|stack(ed)?|stopping|without|efficiency)\b',
    ).hasMatch(subject);

/// Keep the rule in one place: percent ceilings over 100 are possible
/// (extra credit) — but the race must confirm rather than silently allow.
bool _explicitPercentBreach(String core) {
  final m = RegExp(r'\b(\d{3,})\s*(%|percent|pct)\b').firstMatch(core);
  return m != null && int.parse(m.group(1)!) > 100;
}

/// Subjects that name a judged thing, not a measurable one — "best
/// drawing" can't be read off a stopwatch, so the rubric becomes the one
/// clarification question.
const _judgedSubjects = {
  'drawing': 'drawing score',
  'painting': 'drawing score',
  'artwork': 'drawing score',
  'budget score': 'budget score',
  'community score': 'community score',
  'code': 'code quality',
  'code quality': 'code quality',
  'study performance': 'study performance',
  'health score': 'health score',
  'gaming score': 'gaming score',
  'room makeover': 'room makeover',
};

/// Domain-generic subjects — they name a kind of competition, not the
/// measure inside it. One targeted question each.
const _genericSubjectQuestion = {
  'lifting': 'What lift are you measuring?',
  'temperature': 'What temperature are you measuring?',
  'static hold': 'What hold are you measuring?',
  'repetitions': 'What movement are you doing?',
  'fitness': 'What do you want to measure?',
  'report card': 'What number should Nuvo compare?',
  'health score': 'How should "healthiest" be measured?',
  'budget score': 'How should budgeting be measured?',
  'community score': 'How should "best" be measured?',
  'study performance': 'How should "best" be measured?',
  'drawing score': 'Who decides the score?',
  'room makeover': 'How should the makeover be scored?',
  'code quality': 'How should code quality be scored?',
  'gaming score': 'How should "best gamer" be measured?',
  'fundraising efficiency': 'How should participant count be verified?',
  'multi-goal': 'Pick one thing to compete in for this race.',
  'mistakes': 'Mistakes on what?',
};

// ── Unit inference ───────────────────────────────────────────────────────────

/// Domain lexicon: subject keywords → canonical unit. Ordered by
/// specificity — longest keyword wins. This is a *hint* for custom
/// subjects; explicit words in the title ("in kg", "95%", "$500") override.
String? _unitFor(String subject, {String head = ''}) {
  if (subject.isEmpty) return 'count';
  // Numbered quantities inside the subject are scope or a bound, not the
  // declared unit — "sleep streak above 8 hours" still counts days.
  final s = subject.toLowerCase().replaceAll(
        RegExp(
          r'\b\d+\s*(hours?|hrs?|minutes?|mins?|seconds?|secs?|miles?|km|kilometers?|meters?|pages?|words?|reps?|days?|weeks?|pounds?|lbs?|kg)\b|\b(above|below|over|under|at least)\s+\d+\s*\w*\b',
        ),
        ' ',
      );
  // Exercise nouns carry their own unit: rep movements count reps, static
  // holds count clock time, weighted lifts count load.
  const repMovements = {
    'situps', 'sit ups', 'crunches', 'dips', 'toe touches', 'pullups',
    'pull ups', 'plank jacks', 'jumping jacks', 'high knees',
    'mountain climbers', 'burpees', 'lunges', 'squats', 'pushups',
    'push ups', 'calf raises', 'arm raises', 'step ups', 'butt kicks',
    'lateral steps', 'squat jacks', 'jump squats', 'lunge jumps',
    'sumo squats', 'side lunges', 'deep squats', 'flutter kicks',
    'running in place', 'walking in place', 'marching in place',
    'dribbling', 'consecutive passes', 'volleyball serves',
    'boxing round', 'climbers',
    'pushup streak',
  };
  const holdMovements = {
    'plank', 'wall sit', 'dead hang', 'hollow body hold', 'handstand',
    'l-sit', 'single leg balance', 'squat hold', 'static hold',
    'boxing round', 'plank hold',
  };
  const liftMovements = {
    'bench press', 'back squat', 'deadlift', 'overhead press', 'leg press',
    'dumbbell curl', 'farmer carry', 'snatch', 'clean and jerk', 'lifting',
  };
  // Time-trial heads measure the clock itself — "fastest 500m swim" is
  // seconds even though "500m" looks like a distance. Only timed things
  // go through this shortcut; "fastest car wash" keeps its domain unit.
  if (head == 'fastest' ||
      head == 'shortest' ||
      head == 'quickest' ||
      head == 'slowest') {
    if (RegExp(
      r'\b(mile|miles|5k|10k|marathon|sprint|lap|laps|run|running|treadmill|swim|swimming|row|rowing|bike|cycling|kart|karting|freestyle|track|walk|hike|ski|kayak|paddleboard|jog|ride|reel|solve|solves|rubik|minecraft|mario|speedrun|level|game|edit|tie|shoe)\b',
    ).hasMatch(s)) {
      return 'seconds';
    }
  }
  // Measurement nouns inside the subject are the declared unit — "run
  // miles" is miles, "quiz mistakes" is mistakes. "made" wraps the shot
  // noun into its made-form ("free throws made" -> made shots).
  final toks = s.split(' ').where((w) => w.isNotEmpty).toList();
  // A handful of domains outrank a raw measure-noun: "wrong answers on the
  // vocab quiz" counts wrong answers; "money raised" counts dollars.
  if (s.contains('vocab quiz')) return 'wrong answers';
  if (s.contains('per person')) return 'usd/person';
  if (s.contains('raised')) return 'usd';
  // "X time" resolves against its domain before the bare "time" token
  // claims seconds — dashboards report milliseconds, chores minutes.
  if (RegExp(r'(reaction|startup|response|latency)').hasMatch(s)) {
    return 'milliseconds';
  }
  if (RegExp(r'(screen time|room cleaning|car wash)').hasMatch(s)) {
    return 'minutes';
  }
  if (s.contains('mile improvement')) return 'seconds';
  if (s.contains('relative strength')) return 'x bodyweight';
  if (s.contains('volunteer hours')) return 'hours';
  if (s.contains('juggling')) return 'touches';
  if (s.contains('win streak')) return 'wins';
  if (s.contains('free throw streak')) return 'shots';
  if (s.contains('continuous run')) return 'minutes';
  if (s.contains('cup tower') || s.contains('card tower') ||
      s.contains('tower')) {
    return 'inches';
  }
  if (s.contains('spending')) return 'usd';
  if (s.contains('pull requests merged')) return 'prs';
  if (s.contains('event recruiting')) return 'people';
  if (s.contains('puzzle')) return 'minutes';
  if (s.contains('domino')) return 'dominoes';
  if (s.contains('mistake')) return 'mistakes';
  if (s.contains('passing tests')) return 'tests';
  if (RegExp(r'practice (test|score)').hasMatch(s)) return 'points';
  if (RegExp(r'\btest\b').hasMatch(s) && !s.contains('tests')) {
    return 'percent';
  }
  if (toks.contains('made')) {
    const madeForms = {
      'throws': 'shots', 'shots': 'shots', 'serves': 'serves',
      'goals': 'goals', 'flips': 'flips',
    };
    for (final t in toks) {
      if (madeForms.containsKey(t)) return 'made ${madeForms[t]}';
    }
  }
  // Golf scores are always strokes — "score" would otherwise claim points.
  if (s.contains('golf')) return 'strokes';
  // "Fastest/lowest mile|5k|lap" measures the clock over locomotion —
  // the distance nouns are the course, not the unit.
  const locomotion = {
    'running', 'walking', 'swimming', 'cycling', 'rowing', 'kart lap',
    'treadmill running', 'jogging', 'marathon', 'skiing', 'kayaking',
  };
  if (head == 'lowest' ||
      head == 'fastest' ||
      head == 'shortest' ||
      head == 'quickest' ||
      head == 'slowest') {
    if (locomotion.contains(s)) return 'seconds';
  }
  // Movement classes outrank the noun lexicon — "squat hold" is a hold
  // (seconds), not a lift (lb); "plank jacks" are reps, not a plank hold.
  for (final m in repMovements) {
    if (s.contains(m)) return 'reps';
  }
  for (final m in holdMovements) {
    if (s.contains(m)) return 'seconds';
  }
  // Canonical subjects resolve their domain unit before raw count-nouns:
  // "tennis serves" is successful serves, "cup tower" is inches. A lexicon
  // key also matches its simple plural ("flashcard" -> "flashcards").
  for (final e in _unitLexicon.entries) {
    final pat =
        '\\b${RegExp.escape(e.key)}s?\\b';
    if (RegExp(pat).hasMatch(s)) return e.value;
  }
  for (final m in liftMovements) {
    if (s.contains(m)) return 'lb';
  }
  for (final t in toks) {
    if (_unitTokens.contains(t)) {
      return _unitAliases[t] ?? t;
    }
  }
  if (head == 'longest') return _durationUnit(subject);
  // Trailing-noun fallback: "origami cranes" -> cranes, "hot dogs" ->
  // hot dogs. The noun IS the unit for count races — with aliases for the
  // canonical unit spellings ("grams" -> g, "dollars" -> usd).
  const pastParticiple = {
    'made', 'done', 'solved', 'completed', 'finished', 'merged',
    'reviewed', 'recruited', 'fixed', 'closed', 'integrated', 'read',
    'written', 'drawn', 'built', 'taken', 'raised', 'earned', 'won',
    'cleaned', 'studied', 'learned', 'watched', 'played',
  };
  final words = s.split(' ').where((w) => w.isNotEmpty).toList();
  if (words.isNotEmpty) {
    final last = words.last;
    if (_unitAliases.containsKey(last)) return _unitAliases[last];
    if (_genericUnits.contains(last)) return last;
    final singular = last.endsWith('s') ? last.substring(0, last.length - 1) : last;
    if (_unitAliases.containsKey(singular)) return _unitAliases[singular];
    if (_genericUnits.contains(singular)) return last;
    // Any trailing noun is a countable unit — but a trailing past
    // participle is the activity verb, not the measure.
    if (!pastParticiple.contains(last) && !last.endsWith('ed')) return last;
  }
  return 'count';
}

/// Canonical unit spellings — measurement nouns normalize to their
/// abbreviated forms.
const _unitAliases = {
  'grams': 'g', 'gram': 'g', 'dollars': 'usd', 'dollar': 'usd',
  'pounds': 'lb', 'pound': 'lb', 'kilos': 'kg', 'kilograms': 'kg',
  'kilogram': 'kg', 'kilometers': 'km', 'kilometer': 'km',
  'liters': 'liters', 'liter': 'liters', 'ounces': 'oz', 'ounce': 'oz',
  'percentage': 'percent', 'inbox zero': 'emails remaining',
  'minutes': 'minutes', 'hours': 'hours', 'seconds': 'seconds',
  'distance': 'miles', 'mile': 'miles', 'level': 'levels',
  'time': 'seconds', 'throws': 'shots', 'pointer': 'points',
  'pointers': 'made shots', 'wins': 'wins', 'farther': 'miles',
  'further': 'miles', 'win': 'wins',
};

/// Tokens that ARE the unit wherever they appear in a subject.
const _unitTokens = {
  'miles', 'mile', 'meters', 'km', 'kilometers', 'yards', 'feet', 'inches',
  'seconds', 'minutes', 'hours', 'milliseconds', 'laps', 'lengths',
  'strokes', 'points', 'percent', 'reps', 'pages', 'books', 'words',
  'steps', 'commits', 'tickets', 'lessons', 'modules', 'songs', 'photos',
  'views', 'likes', 'diamonds', 'kills', 'games', 'matches', 'meetings',
  'people', 'plants', 'meals', 'walks', 'bags', 'cans', 'signatures',
  'invites', 'donations', 'bugs', 'issues', 'tests', 'warnings', 'sensors',
  'items', 'things', 'tasks', 'chores', 'rooms', 'loads', 'darts', 'shots',
  'serves', 'hits', 'touches', 'goals', 'attempts', 'blunders',
  'penalties', 'flips', 'cranes', 'dominoes', 'airplanes', 'solves',
  'xp', 'rating', 'levels', 'emails', 'mistakes', 'grams', 'dollars',
  'pounds', 'kilos', 'lb', 'kg', 'g', 'oz', 'liters', 'wpm', 'bpm',
  'usd', 'wins', 'win', 'days', 'workouts',
  'farther', 'further',
  'sessions', 'cards', 'problems', 'lines',
  'followers', 'subscribers', 'calories', 'kcal',
};

/// Prefers the unit read straight off the raw subject ("laps swum" ->
/// laps); when the raw phrase only offers a generic count, the canonical
/// domain name carries the domain unit ("running" -> miles).
String? _bestUnit(String raw, String canon, {String head = ''}) {
  // Clock heads measure the stopwatch over a timed event — the course
  // nouns are context, not the unit ("fastest mile" -> seconds).
  final clock = _clockUnit(raw, canon, head);
  if (clock != null) return clock;
  // A measure unit spelled out in the title outranks the domain default —
  // "run 20 miles" is miles even though "running" defaults to miles too,
  // and "press in kg" is kg despite the lift's default lb.
  final rtoks = raw.split(' ');
  if (rtoks.contains('made')) {
    const madeForms = {
      'throws': 'shots', 'shots': 'shots', 'serves': 'serves',
      'goals': 'goals', 'flips': 'flips',
    };
    for (final t in rtoks) {
      if (madeForms.containsKey(t)) return 'made ${madeForms[t]}';
    }
  }
  for (final t in rtoks) {
    if (_explicitMeasureUnits.contains(t)) return _unitAliases[t] ?? t;
  }
  var unit = _unitFor(canon, head: head);
  if (canon != raw && _isEchoUnit(unit, canon)) {
    unit = _unitFor(raw, head: head) ?? unit;
  }
  return unit;
}

/// A resolved unit "echoes" the canonical name when it is just the name
/// itself ("meeting attendance" -> attendance) or a generic placeholder —
/// the raw phrase then gets a chance to name the real unit.
bool _isEchoUnit(String? unit, String canon) {
  if (unit == null || unit == 'count' || unit == 'score') return true;
  final last = canon.split(' ').last;
  return unit == last &&
      !_genericUnits.contains(last) &&
      !_unitTokens.contains(last) &&
      !_unitAliases.containsKey(last);
}

/// Units written literally in the title — measurement nouns, not subject
/// nouns. Their presence is an explicit declaration, never a default.
const _explicitMeasureUnits = {
  'miles', 'mile', 'meters', 'km', 'kilometers', 'yards', 'feet', 'inches',
  'seconds', 'minutes', 'mins', 'hours', 'milliseconds', 'days',
  'kg', 'kilos', 'kilograms', 'g', 'grams', 'lb', 'lbs', 'pounds',
  'oz', 'ounces', 'liters', 'litres', 'percent', 'dollars', 'usd',
  'wpm', 'bpm', 'xp', 'levels', 'gpa', 'steps', 'laps', 'lengths',
};

/// Time-trial heads plus a locomotion/time-event noun mean the clock is
/// the score — applies to "fastest", "lowest" and their siblings only.
String? _clockUnit(String raw, String canon, String head) {
  const clockHeads = {
    'fastest', 'shortest', 'quickest', 'slowest', 'lowest'
  };
  if (!clockHeads.contains(head)) return null;
  const locomotion = {
    'running', 'walking', 'swimming', 'cycling', 'rowing', 'kart lap',
    'treadmill running', 'jogging', 'marathon', 'skiing', 'kayaking',
  };
  if (locomotion.contains(canon) || locomotion.contains(raw)) {
    return 'seconds';
  }
  if (head != 'lowest' &&
      RegExp(
        r'\b(mile|miles|5k|10k|marathon|sprint|lap|laps|run|running|treadmill|swim|swimming|row|rowing|bike|cycling|kart|karting|freestyle|track|walk|hike|ski|kayak|paddleboard|jog|ride|reel|solve|solves|rubik|minecraft|mario|speedrun|level|game|edit|tie|shoe)\b',
      ).hasMatch('$raw $canon')) {
    return 'seconds';
  }
  return null;
}

/// Hold/focus/study durations phrase in minutes; physical holds in seconds.
String _durationUnit(String subject) {
  const minutesSubjects = {
    'study session', 'focus session', 'reading focus session',
    'guitar practice', 'meditation', 'phone-free focus', 'no-phone focus block',
    'practice session', 'focus block', 'study', 'reading', 'continuous run',
  };
  for (final m in minutesSubjects) {
    if (subject.contains(m)) return 'minutes';
  }
  // A "longest throw/drive" is a field mark, not a stopwatch or mileage.
  const yardSubjects = {'throw', 'toss', 'drive', 'cast', 'punt', 'kick'};
  for (final m in yardSubjects) {
    if (subject.contains(m)) return 'yards';
  }
  // Endurance "longest" races measure ground covered, not clock time.
  const distanceSubjects = {
    'swim', 'pool', 'ride', 'bike', 'cycl', 'paddleboard', 'ski', 'kayak',
    'mile', 'jog', 'run', 'walk', 'hike', 'distance', 'rowing', 'row',
  };
  for (final m in distanceSubjects) {
    if (subject.contains(m)) return 'miles';
  }
  return 'seconds';
}

const _genericUnits = {
  'reps', 'pages', 'books', 'words', 'cards', 'lessons', 'modules',
  'problems', 'steps', 'tasks', 'items', 'things', 'photos', 'songs',
  'meals', 'plants', 'walks', 'rooms', 'chores', 'loads', 'bags', 'cans',
  'invites', 'signatures', 'donations', 'meetings', 'mentors', 'bugs',
  'issues', 'tickets', 'tests', 'warnings', 'sensors', 'lines', 'commits',
  'solves', 'flips', 'cranes', 'dominoes', 'airplanes', 'attempts',
  'blunders', 'penalties', 'darts', 'shots', 'serves', 'hits', 'touches',
  'goals', 'wins', 'kills', 'levels', 'diamonds', 'views', 'likes',
  'edits', 'emails', 'workouts', 'sessions', 'mistakes', 'streaks',
  'hot dogs', 'people', 'members', 'races', 'games', 'matches',
};

const _unitLexicon = {
  // academics — check before generic 'score'
  'gpa': 'gpa', 'sat': 'points',
  'test': 'percent', 'quiz': 'percent', 'exam': 'percent',
  'grade improvement': 'percentage points',
  'pushup improvement': 'percent',
  'grade': 'percent', 'test grade': 'percent',
  'homework': 'percent', 'report card': 'percent',
  'coverage': 'percent',
  'typing': 'wpm', 'typing speed': 'wpm',
  'vocab': 'words', 'flashcard': 'cards', 'anki streak': 'days',
  'vocab words': 'words', 'win streak': 'wins',
  'response': 'milliseconds', 'api latency': 'milliseconds',
  'mile improvement': 'seconds', 'relative strength': 'x bodyweight',
  'spending': 'usd', 'score accuracy': 'points',
  'pull requests merged': 'prs',
  'event recruiting': 'people', 'puzzle completion': 'minutes',
  'domino': 'dominoes',
  'sponsorships': 'usd',
  'free throw streak': 'shots',
  'streak': 'days', 'duolingo': 'xp', 'khan academy': 'points',
  'extra credit': 'points', 'wrong answer': 'wrong answers',
  'mistake': 'mistakes',
  'health score': '', 'budget score': '', 'community score': '',
  'gaming score': '', 'study performance': '',
  'fortnite kills': 'kills', 'game xp': 'xp', 'game level': 'levels',
  'music tempo': 'bpm', 'trick shot attempts': 'attempts',
  'meeting attendance': 'meetings', 'club meeting': 'meetings',
  'meditation streak': 'minutes',
  'sat practice test': 'points', 'practice test': 'points',
  'practice score': 'points',
  'pushup streak': 'reps', 'tasks': 'tasks',
  'running': 'miles', 'walking': 'miles', 'jogging': 'miles',
  'swimming': 'miles', 'skiing': 'miles',
  'hiking': 'miles', 'kayaking': 'meters',
  'score': 'points', 'drawing score': 'points', 'room makeover': 'points',
  'trick shot': 'points', 'code quality': 'points', 'error': 'points',
  'guess accuracy': 'items', 'repetitions': 'reps', 'count': 'count',
  'performance': '',
  'competition': '', 'multi-goal': '', 'distance': 'miles',
  'time': 'seconds', 'duration': 'seconds', 'percentage': 'percent',
  'items': 'items', 'completion': 'count', 'lifting': 'lb',
  'static hold': 'seconds', 'fitness': '',
  'kart lap': 'seconds', 'hot dogs': 'hot dogs',
  'three-pointers': 'made shots', 'soccer goals': 'goals',
  'video game goals': 'goals',
  'pickup game score': 'points', 'golf drive': 'yards',
  // strength
  'bench': 'lb', 'press': 'lb', 'deadlift': 'lb', 'curl': 'lb',
  'squat': 'lb', 'leg press': 'lb', 'pullup': 'lb', 'pull up': 'lb',
  'snatch': 'kg', 'clean and jerk': 'kg', 'clean': 'kg',
  'farmer': 'lb', 'lift': 'lb', 'overhead': 'lb',
  'bodyweight': 'x bodyweight',
  // distance & time sports
  'mile': 'seconds', '5k': 'seconds', '10k': 'seconds',
  'marathon': 'seconds', 'sprint': 'seconds', 'lap': 'seconds',
  'freestyle': 'seconds', 'speedrun': 'seconds', 'karting': 'seconds',
  'kart': 'seconds', 'run': 'miles', 'dog walk': 'walks',
  'walk': 'miles', 'hike': 'miles',
  'cycling': 'miles', 'bike': 'miles', 'ride': 'miles', 'swim': 'miles',
  'pool lengths': 'lengths', 'laps swum': 'laps', 'row': 'meters',
  'rowing': 'meters', 'ski': 'miles', 'paddleboard': 'miles',
  'kayak': 'seconds', 'treadmill': 'miles',
  'broad jump': 'feet',
  'vertical jump': 'inches', 'card tower': 'inches', 'cup tower': 'inches',
  'paper airplane flight': 'feet', 'yo-yo': 'seconds', 'coin spin': 'seconds',
  'car wash': 'minutes', 'room cleaning': 'minutes', 'shoe tying': 'seconds',
  'lego': 'minutes', 'puzzle': 'minutes', 'reaction': 'milliseconds',
  'startup': 'milliseconds', 'latency': 'milliseconds', 'api': 'milliseconds',
  'inference': 'milliseconds',
  // health
  'water': 'oz', 'liter': 'liters', 'sleep streak': 'days',
  'sleep': 'hours', 'slept': 'hours',
  'heart rate': 'bpm', 'calories': 'kcal', 'kcal': 'kcal', 'active': 'minutes',
  'screen time': 'minutes', 'breath': 'seconds', 'temperature': 'degrees',
  'meditation': 'minutes', 'focus session': 'minutes',
  'study session': 'minutes', 'study time': 'minutes',
  'continuous run': 'minutes', 'phone-free focus': 'minutes',
  'workouts': 'workouts', 'workout': 'workouts',
  // productivity & coding
  'pomodoro': 'sessions', 'focus': 'minutes', 'deep work': 'minutes',
  'study': 'minutes', 'commit': 'commits', 'github': 'commits',
  'leetcode': 'problems', 'lines of code': 'lines', 'code written': 'lines',
  'bundle': 'mb', 'pull request': 'prs', 'pr': 'prs',
  'inbox': 'emails remaining', 'unread email': 'emails', 'email': 'emails',
  'test coverage': 'percent', 'passing tests': 'tests',
  'compiler warning': 'warnings', 'benchmark': 'points',
  // money
  'savings rate': 'percent',
  'save': 'usd', 'savings': 'usd', 'saved': 'usd', 'money': 'usd',
  'debt': 'usd', 'spend': 'usd', 'spent': 'usd', 'bill': 'usd',
  'dollar': 'usd', 'fundraising': 'usd', 'fundrais': 'usd',
  'donations raised': 'usd', 'raised': 'usd', 'earn': 'usd',
  'earned': 'usd', 'earnings': 'usd', 'trading return': 'percent',
  'grocery': 'usd', 'delivery spend': 'usd',
  'receipt total': 'usd', 'sponsorship': 'usd', 'per person': 'usd/person',
  'mowing': 'usd', 'budget': 'points',
  // sports & gaming
  'golf': 'strokes', 'mini golf': 'strokes', 'bowling': 'points',
  'fortnite': 'wins', 'valorant': 'kills', 'brawl stars': 'wins',
  'rocket league': 'points', 'minecraft diamonds': 'diamonds',
  'minecraft': 'seconds', 'mario kart': 'seconds', 'chess rating': 'rating',
  'chess': 'blunders', 'game': 'points',
  'level': 'levels', 'xp': 'xp', 'free throw': 'shots',
  'juggling': 'touches', 'volleyball serves': 'made serves',
  'tennis serves': 'successful serves',
  'bottle flip': 'successful flips', 'rubik': 'solves',
  'nhl': 'goals', 'pickup game': 'points',
  // community & creative & chores
  'tutor': 'people', 'club': 'people', 'recruit': 'mentors',
  'attendees': 'people', 'signups': 'people', 'petition': 'signatures',
  'service hours': 'hours', 'volunteer hours': 'hours', 'volunteering': 'hours',
  'discord': 'invites', 'cleanup': 'bags', 'trash': 'bags',
  'laundry': 'loads',
  'tiktok': 'views', 'youtube': 'views', 'instagram': 'likes',
  'reel likes': 'likes', 'video edits': 'edits', 'animation': 'seconds',
  'video editing': 'seconds', 'drawing': 'pages', 'writing': 'words',
  'words written': 'words', 'pages drawn': 'pages', 'photos taken': 'photos',
  'music': 'songs', 'guitar': 'minutes', 'bpm': 'bpm',
  'improve': 'percentage points',
};

RaceMetric _metricForUnit(String? unit) {
  const timeUnits = {
    'seconds', 'minutes', 'hours', 'milliseconds', 'days', 'minutes remaining'
  };
  return timeUnits.contains(unit) ? RaceMetric.seconds : RaceMetric.reps;
}

/// Resolves the final proof modality in one place: an explicit user proof
/// instruction always wins, then a camera-verifiable preset, then the
/// subject's domain default. A "camera/motion" override only binds to
/// subjects that are actually movements — "camera proof" on a books race
/// degrades to ordinary video.
ProofNeed _resolveProofNeed(
  ProofNeed? override,
  MotionActivityDefinition? activity,
  String subject,
  String goalName,
  String? unit, {
  bool timeWord = false,
}) {
  if (override == ProofNeed.motionReps) {
    if (activity != null) return _motionNeed(activity);
    const holdNouns = {
      'plank', 'wall sit', 'dead hang', 'hollow body', 'handstand',
      'l-sit', 'single leg balance', 'squat hold', 'static hold',
      'breath hold',
    };
    const repNouns = {
      'pushup', 'push up', 'situp', 'sit up', 'crunch', 'dip', 'pullup',
      'pull up', 'burpee', 'lunge', 'squat', 'jack', 'climber', 'kick',
      'raise', 'step', 'toe touch', 'knee', 'plank jack', 'rep',
      'in place',
    };
    final s = '$subject $goalName';
    for (final m in holdNouns) {
      if (s.contains(m)) return ProofNeed.motionDuration;
    }
    for (final m in repNouns) {
      if (s.contains(m)) return ProofNeed.motionReps;
    }
    return ProofNeed.video;
  }
  if (override != null) return override;
  if (activity != null) return _motionNeed(activity);
  return _proofFor(subject, unit ?? '', canon: goalName, timeWord: timeWord);
}

// ── Proof inference ──────────────────────────────────────────────────────────

/// Subject-class → evidence modality. Camera-verifiable presets already went
/// through [_motionNeed]; these are the manual-subject defaults, ordered so
/// the most specific keyword wins.
ProofNeed _proofFor(
  String subject,
  String unit, {
  bool timeWord = false,
  String canon = '',
}) {
  final s = '$subject $canon'.toLowerCase();
  // Measure-only and honor-logged subjects have no artifact to attach.
  const manualSubjects = {
    'score', 'count', 'time', 'duration', 'points', 'percentage',
    'mistakes', 'repetitions', 'error', 'competition', 'completion',
    'performance', 'multi-goal', 'fitness', 'static hold',
    'health score', 'budget score', 'community score', 'gaming score',
    'study performance',
    'guess accuracy', 'score accuracy',
    'breath hold', 'focus session', 'meditation', 'study session',
    'study time', 'phone-free focus', 'deep work', 'pomodoros',
    'homework completion', 'vocab words learned', 'focus time', 'tasks',
  };
  if (manualSubjects.contains(canon.isNotEmpty ? canon : subject) ||
      manualSubjects.contains(subject)) {
    return ProofNeed.manual;
  }
  // Racing games photograph their result screen; real karting uses a clock.
  if (s.contains('mario kart')) return ProofNeed.photo;
  // Locomotion races prove distance and time with a recorded GPS
  // activity — a session yields the route's distance, duration, and pace.
  // This beats the generic distance/time-result artifacts below.
  if (_isGpsSubject(s) &&
      ({'miles', 'meters', 'km', 'yards', 'feet', 'seconds', 'minutes'}
              .contains(unit) ||
          timeWord)) {
    return ProofNeed.gpsActivity;
  }
  // Distance-unit races prove with a track/map artifact — this beats the
  // sport-name time-trial rule ("longest bike ride" is miles, not a clock).
  const distanceSports = {
    'run', 'walk', 'cycling', 'bike', 'ride', 'swim', 'row', 'rowing',
    'ski', 'paddleboard', 'hike', 'miles', 'distance', 'jog', 'marathon',
    'kayak', 'continuous run',
  };
  if (unit == 'miles' ||
      unit == 'meters' ||
      unit == 'km' ||
      unit == 'yards' ||
      unit == 'feet') {
    for (final k in distanceSports) {
      if (RegExp('\\b${RegExp.escape(k)}\\b').hasMatch(s)) {
        return ProofNeed.distance;
      }
    }
  }
  // An uninterrupted run is proven by the route artifact, not a clock.
  if (s.contains('continuous run')) return ProofNeed.distance;
  // Explicit locomotion time trials get a clock result, not a photo.
  const timeResultSports = {
    'mile', '5k', '10k', 'marathon', 'sprint', 'lap', 'track', 'swim',
    'freestyle', 'row', 'rowing', 'cycling', 'bike', 'karting', 'kart',
    'running', 'treadmill', 'jog', 'race',
  };
  if (timeWord || unit == 'seconds' || unit == 'minutes') {
    for (final k in timeResultSports) {
      if (RegExp('\\b${RegExp.escape(k)}\\b').hasMatch(s)) {
        return ProofNeed.timeResult;
      }
    }
  }
  // Camera-verifiable movement nouns that aren't preset releases still take
  // motion proof — the proof modality belongs to the movement class.
  const motionRepNouns = {
    'situps', 'sit ups', 'crunches', 'dips', 'toe touches', 'pullups',
    'pull ups', 'plank jacks', 'jumping jacks', 'high knees',
    'mountain climbers', 'burpees', 'lunges', 'squats', 'pushups',
    'push ups', 'calf raises', 'arm raises', 'step ups', 'butt kicks',
    'lateral steps', 'squat jacks', 'jump squats', 'lunge jumps',
    'sumo squats', 'side lunges', 'deep squats', 'flutter kicks',
    'dribbling', 'pushup', 'running in place', 'walking in place',
    'marching in place', 'steps in place', 'pushup streak',
    'pushup improvement',
  };
  const motionDurationNouns = {
    'plank', 'wall sit', 'dead hang', 'hollow body', 'handstand',
    'l-sit', 'single leg balance', 'squat hold',
  };
  for (final m in motionRepNouns) {
    if (RegExp('\\b${RegExp.escape(m)}\\b').hasMatch(s)) {
      return ProofNeed.motionReps;
    }
  }
  for (final m in motionDurationNouns) {
    if (RegExp('\\b${RegExp.escape(m)}\\b').hasMatch(s)) {
      return ProofNeed.motionDuration;
    }
  }
  // Laps/lengths are self-reported counts even in the pool.
  if (unit == 'laps' || unit == 'lengths') return ProofNeed.manual;
  for (final e in _proofLexicon.entries) {
    if (RegExp('\\b${RegExp.escape(e.key)}s?\\b').hasMatch(s)) return e.value;
  }
  // Time as the score on non-sport subjects is still a stopwatch result;
  // millisecond-scale latencies photograph a dashboard instead.
  if (timeWord && unit == 'seconds') return ProofNeed.timeResult;
  if (unit == 'milliseconds') return ProofNeed.photo;
  if (unit == 'seconds') return ProofNeed.timeResult;
  // A concrete measurable noun defaults to photographic evidence; pure
  // honor-logged things (no unit at all) stay manual.
  return unit.isEmpty || unit == 'count' ? ProofNeed.manual : ProofNeed.photo;
}

const _proofLexicon = {
  // note-verified — an organizer's word is the evidence
  'people tutored': ProofNeed.note, 'organizer': ProofNeed.note,
  'donations raised': ProofNeed.link, 'raised': ProofNeed.photo,
  'fundraising': ProofNeed.link, 'code quality': ProofNeed.link,
  'win streak': ProofNeed.photo, 'sleep streak': ProofNeed.photo,
  'domino': ProofNeed.photo, 'origami': ProofNeed.photo,
  'sensors': ProofNeed.photo, 'rooms cleaned': ProofNeed.photo,
  'cleaned': ProofNeed.photo, 'event recruiting': ProofNeed.photo,
  'workouts completed': ProofNeed.photo,
  'puzzle completion': ProofNeed.video, 'lifting': ProofNeed.video,
  // academics read as artifacts
  'grade': ProofNeed.photo, 'test': ProofNeed.photo, 'quiz': ProofNeed.photo,
  'exam': ProofNeed.photo, 'gpa': ProofNeed.photo, 'sat': ProofNeed.photo,
  'homework': ProofNeed.photo, 'report card': ProofNeed.photo,
  'vocab': ProofNeed.photo, 'flashcard': ProofNeed.photo,
  'anki': ProofNeed.photo, 'duolingo': ProofNeed.photo,
  'khan': ProofNeed.photo, 'extra credit': ProofNeed.photo,
  'mistake': ProofNeed.photo, 'wrong answer': ProofNeed.photo,
  'coverage': ProofNeed.photo, 'screen time': ProofNeed.photo,
  'typing': ProofNeed.photo,
  // strength: full-body/explosive lifts want motion captured; isolated and
  // machine work photographs fine on the bar.
  'one rep max': ProofNeed.video, '1rm': ProofNeed.video,
  'rep max': ProofNeed.video,
  'deadlift': ProofNeed.video, 'overhead': ProofNeed.video,
  'pullup': ProofNeed.video, 'pull up': ProofNeed.video,
  'farmer': ProofNeed.video, 'clean and jerk': ProofNeed.video,
  'clean': ProofNeed.video, 'snatch': ProofNeed.video,
  'lift': ProofNeed.video,
  'bench': ProofNeed.photo, 'squat': ProofNeed.photo,
  'curl': ProofNeed.photo, 'leg press': ProofNeed.photo,
  'press': ProofNeed.photo,
  // linked proof — platform-native counts
  'commit': ProofNeed.link, 'github': ProofNeed.link, 'gitlab': ProofNeed.link,
  'leetcode': ProofNeed.link, 'lines of code': ProofNeed.link,
  'code': ProofNeed.link, 'pull request': ProofNeed.link, 'pr': ProofNeed.link,
  'donations': ProofNeed.photo,
  'issue': ProofNeed.link, 'ticket': ProofNeed.link, 'bug': ProofNeed.link,
  'strava': ProofNeed.link, 'tiktok': ProofNeed.link,
  'youtube': ProofNeed.link, 'instagram': ProofNeed.link,
  'fundrais': ProofNeed.link,
  'video edits': ProofNeed.link, 'edits': ProofNeed.link,
  // performance sports are watchable
  'free throw': ProofNeed.video, 'juggling': ProofNeed.video,
  'volleyball': ProofNeed.video, 'tennis': ProofNeed.video,
  'baseball': ProofNeed.video, 'football throw': ProofNeed.video,
  'vertical jump': ProofNeed.video, 'broad jump': ProofNeed.video,
  'trick shot': ProofNeed.video, 'bottle flip': ProofNeed.video,
  'rubik': ProofNeed.video, 'speedrun': ProofNeed.video,
  'room cleaning': ProofNeed.video, 'car wash': ProofNeed.video,
  'shoe tying': ProofNeed.video, 'animation': ProofNeed.video,
  'video editing': ProofNeed.video, 'guitar': ProofNeed.video,
  'music': ProofNeed.video, 'songs': ProofNeed.video, 'bpm': ProofNeed.video,
  'soccer': ProofNeed.video, 'pointers': ProofNeed.video,
  'cornhole': ProofNeed.video,
  'goalkeeper': ProofNeed.video, 'football': ProofNeed.video,
  'lego': ProofNeed.video, 'puzzle': ProofNeed.video,
  'coin spin': ProofNeed.video, 'hot dogs': ProofNeed.video,
  'yo-yo': ProofNeed.video, 'yoyo': ProofNeed.video,
  'paper airplanes': ProofNeed.video,
  'airplane': ProofNeed.video,
  'kart lap': ProofNeed.timeResult,
  'karting': ProofNeed.timeResult, 'track event': ProofNeed.photo,
  // stills everywhere else
  'step': ProofNeed.photo, 'water': ProofNeed.photo, 'sleep': ProofNeed.photo,
  'heart rate': ProofNeed.photo, 'calories': ProofNeed.photo,
  'savings': ProofNeed.photo, 'money': ProofNeed.photo,
  'spend': ProofNeed.photo, 'debt': ProofNeed.photo, 'bill': ProofNeed.photo,
  'receipt': ProofNeed.photo, 'grocery': ProofNeed.photo,
  'trading': ProofNeed.photo, 'earnings': ProofNeed.photo,
  'books': ProofNeed.photo, 'pages': ProofNeed.photo, 'read': ProofNeed.photo,
  'drawing': ProofNeed.photo, 'photos': ProofNeed.photo,
  'words written': ProofNeed.photo, 'writing': ProofNeed.photo,
  'tasks': ProofNeed.photo, 'chores': ProofNeed.photo,
  'rooms': ProofNeed.photo, 'plants': ProofNeed.photo,
  'laundry': ProofNeed.photo, 'meals': ProofNeed.photo,
  'walks': ProofNeed.photo, 'donate': ProofNeed.photo,
  'petition': ProofNeed.photo, 'cans': ProofNeed.photo,
  'inbox': ProofNeed.photo, 'unread': ProofNeed.photo,
  'fortnite': ProofNeed.photo, 'valorant': ProofNeed.photo,
  'brawl stars': ProofNeed.photo, 'rocket league': ProofNeed.photo,
  'minecraft diamonds': ProofNeed.photo, 'mario kart': ProofNeed.photo,
  'chess': ProofNeed.photo, 'game': ProofNeed.photo, 'level': ProofNeed.photo,
  'xp': ProofNeed.photo, 'nhl': ProofNeed.photo, 'pickup': ProofNeed.photo,
  'bowling': ProofNeed.photo, 'golf': ProofNeed.photo, 'darts': ProofNeed.photo,
  'penalties': ProofNeed.photo, 'blunders': ProofNeed.photo,
  'temperature': ProofNeed.photo, 'bundle': ProofNeed.photo,
  'warning': ProofNeed.photo, 'startup': ProofNeed.photo,
  'latency': ProofNeed.photo, 'benchmark': ProofNeed.photo,
  'attendance': ProofNeed.photo, 'meetings': ProofNeed.photo,
  'signups': ProofNeed.photo, 'service hours': ProofNeed.photo,
  'volunteer': ProofNeed.photo, 'tutor': ProofNeed.photo,
  'club': ProofNeed.photo, 'sponsorship': ProofNeed.photo,
  'makeover': ProofNeed.photo, 'score': ProofNeed.photo,
  // honor-logged rhythms
  'pomodoro': ProofNeed.manual, 'focus': ProofNeed.manual,
  'deep work': ProofNeed.manual, 'study': ProofNeed.manual,
  'meditation': ProofNeed.manual, 'breath': ProofNeed.manual,
  'sessions': ProofNeed.manual,
  'static hold': ProofNeed.manual,
};

// ── Small shared helpers ─────────────────────────────────────────────────────

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

String _contradictionQuestion(String input) {
  final t = input.toLowerCase();
  if (t.contains('lowest') || t.contains('fewest') || t.contains('least')) {
    return 'Do you want first to the goal, or the lowest score to win?';
  }
  return 'These rules conflict — which should win?';
}

/// Preset lookup with domain vetoes: a static hold or a weighted lift is a
/// DIFFERENT race than the rep-count homonym ("squat hold" ≠ squats, "squat
/// the most weight" ≠ squats). General rule, applied everywhere.
MotionActivityDefinition? _activityFor(String subject) {
  final a = motionActivityFromText(subject);
  if (a == null) return null;
  final holdPhrase = RegExp(
    r'\b(hold|hang|wall sit|hollow|handstand|balance|static|stance)\b',
  ).hasMatch(subject);
  final aliasIsHold = RegExp(
    r'\b(hold|hang|wall sit)\b',
  ).hasMatch(a.aliases.join(' '));
  if (a.metric == RaceMetric.reps && holdPhrase && !aliasIsHold) return null;
  if (a.metric == RaceMetric.reps &&
      RegExp(
        r'\b(weight|lb|lbs|kg|kilos?|heaviest|rep max|1rm|one rep|max effort|loads?)\b',
      ).hasMatch(subject)) {
    return null;
  }
  // Generic alias overreach: a bare "jacks" inside a longer non-preset
  // movement name ("plank jacks") is a different exercise.
  if (a.type == MotionActivityType.jumpingJacks &&
      !RegExp(r'\bjumping\b').hasMatch(subject) &&
      RegExp(r'\w+\s+jacks\b').hasMatch(subject)) {
    return null;
  }
  // In-place presets only bind to in-place phrasing — "most walking
  // distance" is an outdoor walk, not camera-verifiable marching.
  if ((a.type == MotionActivityType.walkingInPlace ||
          a.type == MotionActivityType.runningInPlace ||
          a.type == MotionActivityType.marchingInPlace ||
          a.type == MotionActivityType.treadmillRunning) &&
      !RegExp(r'\b(in place|treadmill|indoor)\b').hasMatch(subject)) {
    return null;
  }
  // Locomotion phrasing (distance, laps, timed routes) describes manual
  // endurance races, not camera-counted reps — even on a treadmill.
  if (RegExp(
    r'\b(miles?|km|kilometers?|meters?|yards?|distance|laps?|lengths|fastest|freestyle|course|route|kart|karting)\b',
  ).hasMatch(subject)) {
    return null;
  }
  return a;
}

/// Canonical domain naming — the same competition described ten ways ("most
/// miles run", "first to run 20 miles", "fastest 5k") lands on ONE subject
/// name. Specific→generic ordering; first hit wins. Domain lexicon, not
/// per-case branching.
String _canonSubjectDomain(String subject) {
  var t = ' ${subject.toLowerCase().trim()} ';
  if (t.trim().isEmpty) return 'count';
  // Structural rewrites first — these change phrase shape, not naming.
  t = t
      .replaceAll(RegExp(r'\bwrong answers\b'), 'mistakes')
      .replaceAll(RegExp(r'\bnumber of\s+'), ' ')
      .replaceAllMapped(
        RegExp(r'\b(test|quiz|exam)\s+(score|percentage)\b'),
        (m) => m[1]!,
      )
      .replaceAll(RegExp(r'\bsat practice\b'), 'sat practice test')
      .replaceAll(RegExp(r'\bhold plank\b'), 'plank')
      .replaceAll(RegExp(r'\s+'), ' ');
  // Strip leading distance/duration scope that slipped into the subject.
  t = t
      .replaceAll(
        RegExp(
          r'\b\d+\s+(miles?|mile|km|kms?|kilometers?|meters?|seconds?|secs?|minutes?|mins?|hours?|hrs?)\b',
        ),
        ' ',
      )
      .replaceAll(RegExp(r'\b(a|an|the)\b'), ' ');
  const rules = <List<String>>[
    ['steps in place', 'running in place'],
    ['running in place|run in place', 'running in place'],
    ['treadmill', 'treadmill running'],
    ['plank jacks', 'plank jacks'],
    ['plank hold|hold plank|\\bplank\\b', 'plank'],
    ['wall sit', 'wall sit'],
    ['dead hang', 'dead hang'],
    ['hollow body', 'hollow body hold'],
    ['handstand', 'handstand'],
    ['l sit|lsit|l-sit', 'l-sit'],
    ['squat hold', 'squat hold'],
    ['static hold', 'static hold'],
    ['breath hold', 'breath hold'],
    ['balance on one leg|one leg balance|single leg balance', 'single leg balance'],
    ['meditation|meditate', 'meditation'],
    ['focus session|reading focus', 'focus session'],
    ['squat jacks', 'squat jacks'],
    ['jump squats|squat jumps|plyometric squats', 'jump squats'],
    ['lunge jumps|jumping lunges', 'lunge jumps'],
    ['sumo squats?|sumo\\b', 'sumo squats'],
    ['side lunges?|lateral lunges?', 'side lunges'],
    ['deep squats?|ass to grass|atg squats?', 'deep squats'],
    ['burpees?|burpee', 'burpees'],
    ['high knees?', 'high knees'],
    ['arm raises?', 'arm raises'],
    ['calf raises?|heel raises?', 'calf raises'],
    ['step ups|step-ups', 'step ups'],
    ['butt kicks|heel kicks', 'butt kicks'],
    ['lateral steps?|side steps?', 'lateral steps'],
    ['mountain climbers?|climbers', 'mountain climbers'],
    ['marching in place|march in place', 'marching in place'],
    ['walking in place|walk in place', 'walking in place'],
    ['toe touches?', 'toe touches'],
    ['pullups|pull ups|pull-ups', 'pullups'],
    ['situps|sit ups|sit-ups', 'situps'],
    ['crunches?', 'crunches'],
    ['dips', 'dips'],
    ['flutter kicks', 'flutter kicks'],
    ['boxing round', 'boxing round'],
    ['benchmark', 'benchmark score'],
    ['\\bbench( press)?\\b', 'bench press'],
    ['overhead press|ohp', 'overhead press'],
    ['deadlift', 'deadlift'],
    ['leg press', 'leg press'],
    ['dumbbell curl|bicep curl', 'dumbbell curl'],
    ['weighted pullup|weighted pull up', 'weighted pullup'],
    ['farmer', 'farmer carry'],
    ['clean and jerk|clean & jerk', 'clean and jerk'],
    ['\\bsnatch\\b', 'snatch'],
    ['back squat|one rep max squat|1rm squat|rep max squat', 'back squat'],
    ['\\bsquat\\b', 'back squat'],
    ['\\blift', 'lifting'],
    ['\\bbike\\b|bik(ed|ing)\\b|bicycl|cycling|\\bride\\b|long ride', 'cycling'],
    ['\\bswim|freestyle|lengths|laps|pool', 'swimming'],
    ['\\brow|rowing|meters rowed', 'rowing'],
    ['kayak', 'kayaking'],
    ['\\bski', 'skiing'],
    ['paddleboard', 'paddleboarding'],
    ['dog walks?|walks the dog|walking the dog', 'dog walks'],
    ['\\bwalk', 'walking'],
    ['\\bmarathon\\b', 'marathon'],
    ['\\bsprint\\b', 'running'],
    ['mario kart', 'mario kart lap'],
    ['karting|kart lap|lap time in karting|\\bkart\\b', 'kart lap'],
    ['\\bstrokes\\b|18 holes|eighteen holes', 'golf score'],
    ['walking distance', 'walking'],
    ['^distance\$|^miles?\$', 'distance'],
    ['\\bplank hold\\b', 'plank'],
    ['\\byo[- ]yo sleeper\\b|\\byo[- ]yo\\b', 'yo-yo sleeper'],
    ['rubiks? cubes? solved', 'rubiks cube solves'],
    ['\\brubiks? cubes?( solves?)?\\b|rubix', "rubik's cube"],
    ['\\bscore percent\\b', 'score'],
    ['pushups? improvement', 'pushup improvement'],
    ['grades? improvement', 'grade improvement'],
    ['mile time improvement|mile improvement', 'mile improvement'],
    ['volunteer hours?|volunteering', 'volunteering'],
    ['\\bbudget(er|ing)\\b', 'budget score'],
    ['\\bgamer\\b|gaming', 'gaming score'],
    ['continuous run|run without walking', 'continuous run'],
    ['\\bmiles? run\\b|\\brun\\b|running|\\bjog\\b|\\bmile\\b|5k|10k|half marathon|\\blap\\b|track|\\bdistance\\b', 'running'],
    ['^\\s*miles?\\s*\$', 'distance'],
    ['\\bfarther\\b|\\bfurther\\b|go far|\\bgo\\b', 'distance'],
    // academics & learning
    ['sat practice', 'sat practice test'],
    ['extra credit', 'extra credit'],
    ['study session', 'study session'],
    ['study minutes|study hours|study time|study', 'study time'],
    ['donations raised', 'donations raised'],
    ['per person', 'fundraising efficiency'],
    ['sponsorship dollars|sponsorships?|sponsors', 'sponsorships'],
    ['money raised|fundraising|fundrais|\\braised\\b', 'fundraising'],
    ['win streak', 'win streak'],
    ['soccer juggling|juggling streak|juggling', 'soccer juggling'],
    ['basketball points|points in a game', 'basketball points'],
    ['attempts.*trick shot|trick shot attempts', 'trick shot attempts'],
    ['trick shot', 'trick shot'],
    ['chess blunders|blunders', 'chess blunders'],
    ['chess rating|elo', 'chess rating'],
    ['nhl', 'video game goals'],
    ['fortnite kills', 'fortnite kills'],
    ['fortnite', 'fortnite wins'],
    ['brawl stars', 'brawl stars wins'],
    ['minecraft speedrun|speedrun', 'minecraft speedrun'],
    ['minecraft diamonds|diamonds|minecraft', 'minecraft diamonds'],
    ['duolingo', 'duolingo xp'],
    ['xp earned|game xp|\\bxp\\b', 'game xp'],
    ['valorant', 'valorant kills'],
    ['rocket league', 'rocket league score'],
    ['levels completed|completed levels', 'levels completed'],
    ['game level|level \\d|\\blevels?\\b', 'game level'],
    ['gaming score|\\bgamer\\b', 'gaming score'],
    ['\\btasks?\\b|tasks completed|finish(ed)? tasks', 'tasks completed'],
    ['\\bworkouts?\\b', 'workouts completed'],
    ['prs? merged|pull requests? merged|pull requests?', 'pull requests merged'],
    ['issues? closed|close.*issues?', 'issues closed'],
    ['community member', 'community score'],
    ['budgeter|budgeting', 'budget score'],
    ['app startup|startup', 'startup time'],
    ['api response|response time|api latency', 'api latency'],
    ['rubiks? cubes?|rubiks?', "rubik's cube solves"],
    ['\\bpuzzle', 'puzzle completion'],
    ['complete.*lessons|lessons completed', 'lessons completed'],
    ['finish.*lessons|\\blessons?\\b', 'lessons'],
    ['pages\\s*\$', 'pages read'],
    ['pushup streak|pushups streak', 'pushup streak'],
    ['meditation streak|meditation', 'meditation'],
    ['anki streak|anki|flashcard streak', 'anki streak'],
    ['volleyball serves', 'volleyball serves'],
    ['tennis serves|serves', 'tennis serves'],
    ['\\breaction\\b', 'reaction time'],
    ['fewest penalties|\\bpenalties\\b', 'penalties'],
    ['vertical jump|vertical', 'vertical jump'],
    ['broad jump', 'broad jump'],
    ['football throw|longest throw', 'football throw'],
    ['free throw streak|consecutive free throws', 'free throw streak'],
    ['cubes solved|rubiks? cubes? solved', "rubik's cube solves"],
    ['rubiks?|rubik', "rubik's cube"],
    ['shoe tying', 'shoe tying'],
    ['tower of cups|cup tower', 'cup tower'],
    ['card tower|tower of cards', 'card tower'],
    ['origami', 'origami cranes'],
    ['dominoes|domino', 'domino stack'],
    ['yo-?yo|yoyo', 'yo-yo sleeper'],
    ['coin spin', 'coin spin'],
    ['hot dogs|hotdogs', 'hot dogs eaten'],
    ['bottle flips?|bottle flipping', 'bottle flips'],
    ['paper airplane flight|airplane flight', 'paper airplane flight'],
    ['paper airplanes?|airplanes?', 'paper airplanes'],
    ['lego', 'lego build'],
    ['500 piece|puzzle', 'puzzle completion'],
    ['dribbling|dribbles', 'dribbling'],
    ['study session', 'study session'],
    ['studies|study\\s*\$|study\\b(?! time| session)', 'study performance'],
    ['focused hours|focused minutes|focus time', 'focus time'],
    ['deep work', 'deep work'],
    ['focus block|no phone|phonefree|no-phone', 'phonefree focus'],
    ['vocab quiz mistakes|mistakes.*vocab|vocab quiz', 'vocab quiz mistakes'],
    ['physics test mistakes|mistakes.*physics|physics test', 'physics test mistakes'],
    ['vocab words learned|learn.*vocab|vocab words', 'vocab words learned'],
    ['chemistry quiz', 'chemistry quiz'],
    ['apush', 'apush test'],
    ['sat practice test|sat', 'sat practice test'],
    ['homework average', 'homework average'],
    ['homework completion|finish.*homework', 'homework completion'],
    ['final exam', 'final exam'],
    ['on a quiz|a 100 on', 'quiz score'],
    ['test score|percent on.*test|on.*test', 'test score'],
    ['report card', 'report card'],
    ['\\bgpa\\b', 'gpa'],
    ['grades', 'grades'],
    ['math test grade|math test', 'math test grade'],
    ['\\bgrade\\b', 'grade'],
    ['flashcards|anki cards', 'flashcards reviewed'],
    ['anki', 'anki streak'],
    ['khan academy|khan', 'khan academy points'],
    ['course modules|modules', 'course modules'],
    ['active minutes', 'active minutes'],
    ['calories burned|calories', 'calories burned'],
    ['resting heart rate|heart rate', 'resting heart rate'],
    ['sleep streak', 'sleep streak'],
    ['workouts completed|\\bworkouts?\\b', 'workouts'],
    ['healthiest|health score', 'health score'],
    ['books read|reads books|read books|most books|\\bbooks?\\b', 'books read'],
    ['pages read|finish.*pages|read.*pages', 'pages read'],
    ['lessons completed|finish.*lessons|complete.*lessons', 'lessons completed'],
    ['lines of code|code written', 'code written'],
    ['course modules|modules completed', 'course modules'],
    ['tickets completed|resolve tickets|finish tickets|finish.*tickets', 'tickets completed'],
    ['bugs fixed|fix bugs|bugs', 'bugs fixed'],
    ['issues closed|close issues|issues', 'issues closed'],
    ['pull requests merged|merge prs|merged prs|prs merged|pull requests|prs', 'pull requests merged'],
    ['test coverage|coverage', 'test coverage'],
    ['app startup|startup time|startup', 'startup time'],
    ['bundle size|bundle', 'bundle size'],
    ['api response|api latency|response time', 'api latency'],
    ['benchmark points|benchmark', 'benchmark score'],
    ['passing tests|tests pass', 'passing tests'],
    ['compiler warnings|warnings', 'compiler warnings'],
    ['github', 'github commits'],
    ['\\bcommits?\\b', 'commits'],
    ['sensors integrated|sensors', 'sensors integrated'],
    ['model inference|inference latency|model latency', 'model latency'],
    ['leetcode', 'leetcode problems'],
    ['code quality|best code|code wins', 'code quality'],
    ['typing speed|typing', 'typing speed'],
    ['screen time', 'screen time'],
    ['pomodoros?|pomodoro', 'pomodoros'],
    ['unread emails', 'unread emails'],
    ['inbox', 'email inbox'],
    ['fitness', 'fitness'],
    ['homework', 'homework completion'],
    ['repetitions|\\breps\\b', 'repetitions'],
    ['temperature', 'temperature'],
    ['mini golf', 'mini golf'],
    ['golf drive|long drive|driving distance', 'golf drive'],
    ['golf score|\\bgolf\\b', 'golf score'],
    ['bowling score|bowling', 'bowling score'],
    ['\\berror\\b|zero error', 'error'],
    ['quiz\\s*\$', 'quiz score'],
    // health & lifestyle
    ['plants watered|water.*plants', 'plants watered'],
    ['\\bwater\\b|liters drank|drank|drink|hydration', 'water intake'],
    ['hours slept|slept|sleep streak|sleep\\b', 'sleep'],
    ['sugar', 'sugar intake'],
    ['protein', 'protein intake'],
    ['calorie|kcal', 'calories burned'],
    ['screen time', 'screen time'],
    ['heart rate|resting heart', 'resting heart rate'],
    ['jokes', 'jokes told'],
    // community & social
    ['people to join|join the club|club signups|club members', 'club signups'],
    ['recruit mentors|mentors recruited', 'mentor recruitment'],
    ['volunteer signups|volunteers signed', 'volunteer signups'],
    ['people tutored|tutor.*people|tutoring', 'people tutored'],
    ['donation cans|donate cans|collect.*cans|cans for|cans donated', 'donation cans'],
    ['beach cleanup', 'beach cleanup'],
    ['trash bags|bags picked|trash collected|\\btrash\\b|cleanup', 'trash collected'],
    ['photos taken|take photos', 'photos taken'],
    ['petition signatures|signatures', 'petition signatures'],
    ['discord invites|server invites|invites', 'discord invites'],
    ['volunteer signups', 'volunteer signups'],
    ['volunteer hours|volunteering', 'volunteer hours'],
    ['service hours', 'service hours'],
    ['event attendees|attendees recruited|event recruiting', 'event recruiting'],
    ['people tutored|people helped|helped at tutoring|tutoring|help.*tutor', 'people tutored'],
    ['club signups|club sign ups|join the club', 'club signups'],
    ['meetings attended|club meetings|meeting attendance', 'meeting attendance'],
    ['recruit.*mentors|mentor recruitment|mentors recruited', 'mentor recruitment'],
    ['sponsorship dollars|sponsorships?|sponsors', 'sponsorships'],
    ['community member|community score', 'community score'],
    ['donation count|\\bdonations\\b', 'donations'],
    ['words written|write.*words|writing|\\bwords\\b', 'writing'],
    ['pages drawn|draw.*pages|drawing|drawings|\\bdrawn\\b', 'drawing'],
    ['songs practiced|music practice|\\bsongs\\b|songs practiced', 'music practice'],
    ['guitar practice|guitar', 'guitar practice'],
    ['bpm played|\\bbpm\\b|tempo', 'music tempo'],
    ['tiktok views|tiktok', 'tiktok views'],
    ['youtube views|youtube', 'youtube views'],
    ['instagram reel likes|instagram likes|instagram|reel likes', 'instagram likes'],
    ['video edits|edits finished|\\bedits\\b', 'video edits'],
    ['animation duration|animation rendered|animation', 'animation duration'],
    ['edit.*reel|to edit|video editing|reel edit', 'video editing'],
    ['rooms cleaned|clean.*rooms|rooms clean', 'rooms cleaned'],
    ['chores completed|\\bchores\\b', 'chores completed'],
    ['room cleaning', 'room cleaning'],
    ['wash.*laundry|loads.*laundry|laundry loads|laundry', 'laundry loads'],
    ['items organized|organize.*items', 'items organized'],
    ['items donated|donate.*items', 'items donated'],
    ['meals cooked|cook.*meals|meals', 'meals cooked'],
    ['car wash|wash.*car', 'car wash'],
    ['room makeover|makeover', 'room makeover'],
    ['grocery receipt|receipt total|grocery total', 'grocery total'],
    ['grocery bill|grocery spend', 'grocery spend'],
    // money
    ['savings rate', 'savings rate'],
    ['dollars saved|money saved|saved\\b|save\\b|savings', 'savings'],
    ['pay off.*debt|debt paid|\\bdebt\\b', 'debt paid'],
    ['food delivery|delivery spend|delivery spending', 'delivery spend'],
    ['money earned|earnings|\\bearn|side jobs|lawns|mowing', 'earnings'],
    ['trading return|paper trading', 'trading return'],
    ['budget score|budgeter|budgeting|\\bbudget\\b', 'budget score'],
    ['spending|spent|spend', 'spending'],
    ['dribbling|dribbles', 'dribbling'],
    ['passes in a row|passes in', 'consecutive passes'],
    ['free throws?', 'free throws'],
    ['batting practice', 'batting practice'],
    ['3 pointers|three pointers|3-pointers|threes|three-pointers', 'three-pointers'],
    ['points scored in a pickup game|pickup game', 'pickup game score'],
    ['volleyball serves?|serves in volleyball', 'volleyball serves'],
    ['tennis rally|rally', 'tennis rally'],
    ['cornhole', 'cornhole'],
    ['darts|bulls?eyes?|dart throws?', 'darts'],
    ['soccer goals|goals in a soccer game', 'soccer goals'],
    ['baseball hits?|hits in batting', 'baseball hits'],
    ['steps', 'steps'],
    ['battles|matches', 'matches'],
    ['goalkeeper drills', 'goalkeeper drills'],
    ['longest golf drive|driving distance|long drive', 'longest golf drive'],
    ['shots? (block|stop)', 'shots blocked'],
    ['\\bgoal', 'goals'],
  ];
  for (final r in rules) {
    if (RegExp(r[0]).hasMatch(t)) return r[1];
  }
  // Verb-inversion: "read books" / "complete lessons" canonicalize to the
  // measured noun + past participle ("books read", "lessons completed").
  // Only fires when the verb LEADS the phrase — "grade" is a noun in
  // "math test grade".
  MapEntry<String, String>? hit;
  final lead = t.trim().split(' ').first;
  for (final e in _verbPast.entries) {
    if (lead == e.key) {
      hit = e;
      break;
    }
  }
  if (hit != null) {
    final nouns = t
        .replaceAll(RegExp('\\b${hit.key}\\b'), ' ')
        .replaceAll(RegExp(r'\b(to|the|a|an|your|my|our|his|her|their)\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (nouns.isNotEmpty) {
      final past = hit.value == 'completed' &&
              RegExp(r'\b(pages?|books?)\b').hasMatch(nouns)
          ? 'read'
          : hit.value;
      return '$nouns $past'.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
  }
  return t.trim();
}

/// Leading verb → canonical past participle for subject canonicalization.
const _verbPast = {
  'read': 'read',
  'reads': 'read',
  'writes': 'written',
  'finishes': 'completed',
  'completes': 'completed',
  'drinks': 'drank',
  'eats': 'eaten',
  'sleeps': 'slept',
  'studies': 'studied',
  'finish': 'completed',
  'complete': 'completed',
  'learn': 'learned',
  'write': 'written',
  'fix': 'fixed',
  'close': 'closed',
  'merge': 'merged',
  'cook': 'cooked',
  'clean': 'cleaned',
  'wash': 'washed',
  'organize': 'organized',
  'donate': 'donated',
  'water': 'watered',
  'eat': 'eaten',
  'take': 'taken',
  'make': 'made',
  'save': 'saved',
  'earn': 'earned',
  'raise': 'raised',
  'collect': 'collected',
  'draw': 'drawn',
  'practice': 'practiced',
  'help': 'helped',
  'tutor': 'tutored',
  'review': 'reviewed',
  'watch': 'watched',
  'solve': 'solved',
  'stack': 'stacked',
  'submit': 'submitted',
  'log': 'logged',
  'run': 'run',
  'swim': 'swum',
  'lift': 'lifted',
  'drink': 'drank',
  'attend': 'attended',
  'bake': 'baked',
  'paint': 'painted',
  'fold': 'folded',
  'recite': 'recited',
  'recruit': 'recruited',
  'babysit': 'babysat',
  'mow': 'mowed',
  'shovel': 'shoveled',
  'rake': 'raked',
  'grade': 'graded',
  'dodge': 'dodged',
};

/// Strips noise words and dangling verbs/prepositions from a subject phrase,
/// preserving specificity ("math test grade" survives; "on our physics
/// test" reorders into "physics test mistakes" upstream).
String _cleanSubject(String raw) {
  var s = raw.trim();
  // "mistakes/errors/wrong answers on our physics test" -> "physics test
  // mistakes" — the fault noun belongs after its artifact.
  final fault = RegExp(
    r'^(mistakes|errors|wrong answers|blunders|penalties)\s+on\s+(?:the\s+|our\s+|a\s+|your\s+)?(.+)$',
  ).firstMatch(s);
  if (fault != null) {
    s = '${fault.group(2)} ${fault.group(1)}';
  }
  // "run 10k fastest" — leading locomotion verb folds into the domain.
  s = s.replaceAll(RegExp(r'\b(wins|win(?! streak)|first|there|there wins|wins first)\b'), '');
  // Trailing hedges ("225 or higher") and leading articles/hold-verbs are
  // framing, not subject.
  s = s.replaceAll(
      RegExp(r'\s+or\s+(higher|more|better|above|lower|less|faster|longer)\b.*$'),
      '');
  s = s.replaceAll(RegExp(r'\s+or\s+higher\b.*$'), '');
  var tokens = s.split(' ').where((t) => t.isNotEmpty).toList();
  const leadNoise = {'a', 'an', 'the', 'hold', 'holding', 'keep', 'keeping',
      'stay', 'maintain', 'do', 'your', 'my', 'our', 'their', 'you', 'we',
      'on', 'in', 'of', 'at', 'to', 'for', 'number', 'amount'};
  while (tokens.isNotEmpty && leadNoise.contains(tokens.first)) {
    tokens.removeAt(0);
  }
  // Trailing stop-verbs and prepositions never belong to a subject.
  const stopTail = {
    'wins', 'win', 'first', 'to', 'the', 'a', 'an', 'of', 'in', 'on', 'at',
    'for', 'by', 'with', 'and', 'or', 'but',
  };
  while (tokens.isNotEmpty && stopTail.contains(tokens.last)) {
    tokens.removeLast();
  }
  while (tokens.isNotEmpty && _noiseWords.contains(tokens.last)) {
    tokens.removeLast();
  }
  return tokens.join(' ').trim();
}

const _numberWords = {
  'a': 1, 'an': 1, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
  'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11,
  'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15, 'sixteen': 16,
  'seventeen': 17, 'eighteen': 18, 'nineteen': 19, 'twenty': 20, 'thirty': 30,
  'forty': 40, 'fifty': 50, 'sixty': 60, 'seventy': 70, 'eighty': 80,
  'ninety': 90, 'hundred': 100, 'half': 0,
};

int? _numberAt(String token) {
  final direct = int.tryParse(token) ??
      _numberWords[token] ??
      const {'a': 1, 'an': 1}[token];
  if (direct != null) return direct;
  final k = RegExp(r'^(\d+)k$').firstMatch(token);
  if (k != null) return int.parse(k.group(1)!) * 1000;
  return null;
}

int? _firstNumber(String normalized) {
  for (final token in normalized.split(' ')) {
    final n = _numberAt(token);
    if (n != null && n > 0) return n;
  }
  return null;
}

/// Splits "100 pushups" → (100, 'pushups') or "read 5 books" → (5, 'read
/// books'). Returns null when no usable number+subject pair exists.
/// "a/an/one" is a quantity only when it isn't followed by a bigger number
/// or a time-unit — "a 2 minute wall sit" is an article, not a target.
(int, String)? _splitLeadingOrInnerNumber(String rest) {
  // "a 2 minute wall sit" / "a 5 minute plank" — the duration IS the goal
  // (seconds), and the remainder is the subject.
  final durFirst = RegExp(
    r'^(?:a\s+|an\s+)?(\w+)\s*(seconds?|secs?|minutes?|mins?|hours?|hrs?)\s+(.+)$',
  ).firstMatch(rest);
  if (durFirst != null) {
    final dn = _numberAt(durFirst.group(1)!);
    if (dn != null && dn > 0) {
      final unit = durFirst.group(2)!;
      final secs = unit.startsWith('h')
          ? dn * 3600
          : unit.startsWith('m')
              ? dn * 60
              : dn;
      final sub = _cleanSubject(durFirst.group(3)!);
      if (sub.isNotEmpty) return (secs, sub);
    }
  }
  final tokens = rest.split(' ').where((t) => t.isNotEmpty).toList();
  for (var i = 0; i < tokens.length; i++) {
    var n = _numberAt(tokens[i]);
    if (n == null) continue;
    if (i + 2 < tokens.length &&
        (tokens[i] == 'a' || tokens[i] == 'an') &&
        _numberAt(tokens[i + 1]) != null) {
      continue; // "a 2 minute X" — the article isn't the target
    }
    final negative = i > 0 && tokens[i - 1] == 'negative';
    if (negative) n = -n;
    final remaining = List.of(tokens)..removeAt(i);
    if (negative) remaining.removeAt(i - 1);
    final subject = remaining.join(' ');
    var cleaned = _cleanSubject(subject);
    if (cleaned.isEmpty) continue;
    // Duration prefixes are scope, not subject: "a 2 minute wall sit",
    // "a 10 mile bike ride", "first to a 5k run".
    final dur = RegExp(
      r'^(\w+)\s*(seconds?|secs?|minutes?|mins?|hours?|hrs?)\s+(.+)$',
    ).firstMatch(cleaned);
    if (dur != null) {
      final dn = _numberAt(dur.group(1)!);
      final unit = dur.group(2)!;
      if (dn != null) {
        final secs = unit.startsWith('h')
            ? dn * 3600
            : unit.startsWith('m')
                ? dn * 60
                : dn;
        return (secs, _cleanSubject(dur.group(3)!));
      }
    }
    final dist = RegExp(
      r'^(\w+)\s*(miles?|mile|kilometers?|kms?|km|meters?|m|yards?|yds?|k)\s+(.+)$',
    ).firstMatch(cleaned);
    if (dist != null && _numberAt(dist.group(1)!) != null) {
      // The number was already consumed as the target; the distance phrase
      // is context ("first to run 20 miles" -> subject 'run').
      cleaned = _cleanSubject(dist.group(3)!);
      if (cleaned.isEmpty) continue;
    }
    if (cleaned.isNotEmpty) return (n, cleaned);
  }
  return null;
}
