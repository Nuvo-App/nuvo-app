import 'motion_activity.dart';
import 'race_draft.dart';
import 'race_name_interpreter.dart';

/// Which composer path the typed race name resolves to.
enum RaceIntentPath {
  /// A catalog movement — camera-verified. Skip the picker; the goal step
  /// asks whatever is still unresolved.
  movement,

  /// A non-movement goal Nuvo understood well enough to configure — the
  /// composer goes straight to the goal step as a custom (honor-logged) race.
  customGoal,

  /// The name doesn't safely say what the race is about. Show the normal
  /// activity / custom-goal decision — never invent an answer.
  ambiguous,
}

/// One canonical decision object: what the typed race name resolves to, how
/// confidently, and which composer fields are still open.
///
/// THE USER DESCRIBES THEIR RACE ONCE. The composer routes on this — it never
/// re-asks a question the name already answered, and it never lets a loose
/// substring match silently arm a verifier or a goal.
class RaceIntentResolution {
  const RaceIntentResolution({
    required this.sourceText,
    required this.path,
    required this.confidence,
    required this.interpretation,
    required this.resolvedFields,
    required this.unresolvedFields,
    required this.reason,
  });

  /// A name that resolves to nothing — empty input, or a phrase the
  /// interpreter can't structure.
  factory RaceIntentResolution.unresolved(String sourceText) =>
      RaceIntentResolution(
        sourceText: sourceText,
        path: RaceIntentPath.ambiguous,
        confidence: InterpretationConfidence.low,
        interpretation: interpretRaceName(sourceText),
        resolvedFields: const {},
        unresolvedFields: const {
          RaceField.activity,
          RaceField.goalKind,
          RaceField.manualGoal,
          RaceField.target,
        },
        reason: 'nothing resolved',
      );

  /// The name as typed — provenance anchor for every resolved field.
  final String sourceText;

  final RaceIntentPath path;

  /// Confidence of the underlying interpretation: `high` skips a step,
  /// `assumed` fills fields but leaves the step's confirmation in place
  /// (the goal page always re-confirms), `low` never routes.
  final InterpretationConfidence confidence;

  /// The full structured interpretation — metric, format, target, direction,
  /// deadline, proof need. Never duplicated or re-derived by the UI.
  final FlexiRaceInterpretation interpretation;

  /// Fields the interpretation filled (inferred from the name). Anything in
  /// [RaceDraft.userEditedFields] overrides these — USER EDIT WINS.
  final Set<RaceField> resolvedFields;

  /// Fields that still need the user. For [RaceIntentPath.movement] this is
  /// the target when the name didn't state one; for [RaceIntentPath.ambiguous]
  /// it's the subject decision itself.
  final Set<RaceField> unresolvedFields;

  /// Why the resolver decided this path — diagnostics only, never user copy.
  final String reason;

  /// The resolved movement, when [path] is [RaceIntentPath.movement].
  MotionActivityDefinition? get activity => interpretation.activity;

  /// The one question still open, if any (surfaces on the goal step).
  String? get question => interpretation.question;

  /// The proof contract the interpretation implies.
  ProofNeed get proofNeed => interpretation.proofNeed;

  /// The activity step may be skipped iff the name resolved the subject —
  /// a movement path or a custom-goal path — and nothing asked for the
  /// subject itself.
  bool get resolvesSubject => path != RaceIntentPath.ambiguous;
}

/// Phrases that name something to measure but not how — the question is the
/// subject, so the picker must answer it.
const _subjectQuestions = {
  'What are you competing in?',
  'What activity are you doing?',
  'What movement are you doing?',
  'What are you counting?',
  'What counts as progress?',
  'Finish what?',
  'Enter a race idea.',
  'Pick one thing to compete in for this race.',
};

final _subjectQuestionPattern = RegExp(r'^\d[\d,]*\s+of what\?$');

/// Units the custom-goal form can stand behind without asking — recognized
/// measures, not noun echoes. "Read 5 books" resolves because "books" is a
/// real unit; "do 20 dragon jumps" doesn't, because "jumps" is just the raw
/// noun bounced back — that shape is an unknown movement (Teach Nuvo), not
/// a custom goal.
const _trustedGoalUnits = {
  'reps', 'repetitions', 'count', 'done',
  'books', 'book', 'pages', 'page', 'chapters', 'words', 'articles',
  'hours', 'hour', 'minutes', 'minute', 'seconds', 'second', 'days', 'day',
  'weeks', 'week', 'months', 'sessions', 'times',
  'miles', 'mile', 'km', 'kilometers', 'meters', 'metres', 'yards', 'laps',
  'usd', 'dollars', 'usd/person', 'percent', 'percentage points',
  'points', 'point', 'score', 'strokes', 'goals', 'assists',
  'problems', 'questions', 'lessons', 'tasks', 'assignments', 'items',
  'mistakes', 'wrong answers', 'emails', 'emails remaining', 'messages',
  'oz', 'glasses', 'ml', 'cups', 'meals',
  'lb', 'lbs', 'pounds', 'kg', 'kilos', 'x bodyweight',
  'games', 'wins', 'matches', 'sets', 'rounds', 'levels', 'levels beaten',
};

/// THE resolver: a typed race name → [RaceIntentResolution]. Wraps
/// [interpretRaceName] — the single source of structured fields — and adds
/// the routing decision the composer consumes: is the subject movement,
/// custom goal, or still undecided.
///
/// [catalog] is the merged activity catalog (bundled + remote) so
/// server-delivered movements resolve by alias.
RaceIntentResolution resolveRaceIntent(
  String sourceText, {
  Iterable<MotionActivityDefinition>? catalog,
}) {
  final input = sourceText.trim();
  if (input.isEmpty) return RaceIntentResolution.unresolved(sourceText);
  final i = interpretRaceName(input, catalog: catalog);
  final resolved = i.inferredFields;

  // A preset is trusted only when the whole phrase justifies the match —
  // the interpreter vets subjects inside grammar slots, but the composer
  // skip is a stronger claim than a field fill, so it re-verifies.
  if (i.activity != null && activityJustifiedByName(i.input, i.activity!)) {
    return RaceIntentResolution(
      sourceText: sourceText,
      path: RaceIntentPath.movement,
      confidence: i.confidence,
      interpretation: i,
      resolvedFields: resolved,
      unresolvedFields: {
        if (!resolved.contains(RaceField.target)) RaceField.target,
      },
      reason: 'movement: ${i.activity!.activityId}',
    );
  }

  // Custom goal: the interpreter committed to a manual kind AND something
  // structured backs it — a stated target ("read 5 books"), a grammar-slot
  // confidence ("most books read"), or a format decision anchored by a real
  // number ("get a 95% in math"). A bare noun echo ("summer challenge",
  // "lock in", "push my grades higher") has none of these — it stays a
  // decision for the picker.
  final structured = resolved.contains(RaceField.target) ||
      i.confidence != InterpretationConfidence.low ||
      (resolved.contains(RaceField.format) &&
          RegExp(r'\d').hasMatch(input));
  if (i.goalKind == RaceGoalKind.manual &&
      (i.manualGoalName ?? '').trim().isNotEmpty &&
      structured &&
      _trustedGoalUnits.contains(i.manualUnit ?? '') &&
      !_asksForSubject(i.question)) {
    return RaceIntentResolution(
      sourceText: sourceText,
      path: RaceIntentPath.customGoal,
      confidence: i.confidence,
      interpretation: i,
      resolvedFields: resolved,
      unresolvedFields: {
        if (!resolved.contains(RaceField.target)) RaceField.target,
        if (!resolved.contains(RaceField.manualGoal)) RaceField.manualGoal,
        if (!resolved.contains(RaceField.manualUnit)) RaceField.manualUnit,
        // A finish line is only owed when the format is deadline-shaped.
        if (i.format != RaceFormat.firstToGoal &&
            !resolved.contains(RaceField.timing))
          RaceField.timing,
      },
      reason: 'custom goal: ${i.manualGoalName} · ${i.manualUnit}',
    );
  }

  return RaceIntentResolution(
    sourceText: sourceText,
    path: RaceIntentPath.ambiguous,
    confidence: InterpretationConfidence.low,
    interpretation: i,
    resolvedFields: resolved,
    unresolvedFields: const {
      RaceField.activity,
      RaceField.goalKind,
      RaceField.manualGoal,
    },
    reason: _ambiguityReason(i),
  );
}

/// Whether the interpretation's question is asking "what is this race" —
/// the picker answers those; goal-level questions (baselines, finish lines)
/// belong to the goal step.
bool _asksForSubject(String? question) =>
    question != null &&
    (_subjectQuestions.contains(question) ||
        _subjectQuestionPattern.hasMatch(question));

/// Diagnostics note for why a name stayed ambiguous — surfaces in the debug
/// report and tests, never in user copy.
String _ambiguityReason(FlexiRaceInterpretation i) {
  if (i.activity != null) {
    return 'alias matched "${i.activity!.activityId}" but the phrase names '
        'something else';
  }
  if (i.question != null) return 'question: ${i.question}';
  if ((i.manualGoalName ?? '').isNotEmpty &&
      !_trustedGoalUnits.contains(i.manualUnit ?? '')) {
    return 'movement-shaped phrase with no catalog match';
  }
  return 'no structured intent';
}
