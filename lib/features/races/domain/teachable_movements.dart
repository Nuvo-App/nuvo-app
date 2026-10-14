/// Movements Nuvo's camera can be taught to count that are NOT in the built-in
/// catalog — "pull ups", "dips", "box jumps".
///
/// The goal reader treats everything it doesn't know as a hand-logged text
/// goal. That is right for sleep, studying, reading, money and food, and wrong
/// for a body movement a camera can see. This list is the positive evidence for
/// the second kind: a CLOSED list of exercises a camera can count (repeated
/// reps) or time (a held position). Nothing outside it is ever offered Teach
/// Nuvo, so a guess can never send someone into recording three demos for
/// "who can sleep the most".
///
/// Deliberately excluded: anything measured by distance or weight (running,
/// swimming, biking, bench press, deadlift), and anything with nothing to
/// watch (sleep, study, read, meditate, cook, drink, screen time).
class TeachableMovement {
  const TeachableMovement({required this.name, required this.unit});

  /// Display name, e.g. "Pull Ups".
  final String name;

  /// `reps` or `seconds` (a hold).
  final String unit;

  bool get isHold => unit == 'seconds';
}

class _Entry {
  const _Entry(this.name, this.unit, this.bases);
  final String name;
  final String unit;
  final List<String> bases;
}

const _reps = 'reps';
const _secs = 'seconds';

const _entries = <_Entry>[
  // Upper body
  _Entry('Pull Ups', _reps, ['pull up', 'chin up', 'pullup', 'chinup']),
  _Entry('Dips', _reps, ['dip', 'tricep dip', 'bar dip', 'bench dip']),
  _Entry('Muscle Ups', _reps, ['muscle up']),
  _Entry('Burpee Pull Ups', _reps, ['burpee pull up']),
  _Entry('Handstand Push Ups', _reps, [
    'handstand push up',
    'handstand pushup',
  ]),
  _Entry('Pike Push Ups', _reps, ['pike push up', 'pike pushup']),
  _Entry('Diamond Push Ups', _reps, ['diamond push up', 'diamond pushup']),
  _Entry('Clap Push Ups', _reps, ['clap push up', 'clap pushup']),
  _Entry('Bicep Curls', _reps, ['bicep curl', 'biceps curl', 'dumbbell curl']),
  _Entry('Shoulder Taps', _reps, ['shoulder tap']),
  // Core
  _Entry('Sit Ups', _reps, ['sit up', 'situp']),
  _Entry('Crunches', _reps, ['crunch', 'bicycle crunch']),
  _Entry('Leg Raises', _reps, ['leg raise', 'hanging leg raise']),
  _Entry('Flutter Kicks', _reps, ['flutter kick']),
  _Entry('Russian Twists', _reps, ['russian twist']),
  _Entry('V Ups', _reps, ['v up', 'vup']),
  _Entry('Toe Touches', _reps, ['toe touch']),
  _Entry('Bird Dogs', _reps, ['bird dog']),
  _Entry('Supermans', _reps, ['superman']),
  _Entry('Glute Bridges', _reps, ['glute bridge', 'hip thrust']),
  // Lower body / jumps
  _Entry('Box Jumps', _reps, ['box jump']),
  _Entry('Broad Jumps', _reps, ['broad jump']),
  _Entry('Tuck Jumps', _reps, ['tuck jump']),
  _Entry('Star Jumps', _reps, ['star jump']),
  _Entry('Skater Jumps', _reps, ['skater jump', 'skater hop']),
  _Entry('Frog Jumps', _reps, ['frog jump']),
  _Entry('Pistol Squats', _reps, ['pistol squat']),
  _Entry('Split Squats', _reps, ['split squat', 'bulgarian split squat']),
  _Entry('Sit to Stands', _reps, ['sit to stand']),
  _Entry('Jump Rope', _reps, ['jump rope', 'skipping rope', 'rope skip']),
  _Entry('Kettlebell Swings', _reps, ['kettlebell swing']),
  _Entry('Thrusters', _reps, ['thruster']),
  _Entry('Bear Crawls', _reps, ['bear crawl']),
  _Entry('Inchworms', _reps, ['inchworm']),
  // Holds (timed)
  _Entry('Wall Sit', _secs, ['wall sit']),
  _Entry('Side Plank', _secs, ['side plank']),
  _Entry('Dead Hang', _secs, ['dead hang']),
  _Entry('Handstand Hold', _secs, ['handstand hold', 'handstand']),
  _Entry('Hollow Hold', _secs, ['hollow hold', 'hollow body hold']),
  _Entry('L Sit', _secs, ['l sit']),
  _Entry('Chair Pose', _secs, ['chair pose']),
  _Entry('Squat Hold', _secs, ['squat hold']),
];

/// Everything a phrase can say that makes it NOT a camera-countable movement,
/// even if an exercise word appears in it: weights, everyday measures, and
/// verbs that mean "doing something else about it".
final _blockers = RegExp(
  r'\b(max|heaviest|1rm|one rep max|lb|lbs|pounds?|kg|kilos?|weight|'
  r'hours?|hrs?|pages?|books?|dollars?|\$|steps|miles?|km|'
  r'read|watch|study|studies|learn|buy|write|draw|cook|sleep|sleeps|eat|drink|'
  r'save|spend|post|film|video|videos|form|tutorial|tutorials|photo|photos|'
  r'recipe|recipes|sauce|chips|movie|movies|cereal)\b',
);

String _normalize(String input) => input
    .toLowerCase()
    .replaceAll(RegExp(r"[-_/']"), ' ')
    .replaceAll(RegExp(r'[^a-z0-9$ ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Alias forms for one base ("pull up"): spaced, joined, singular, plural.
Iterable<String> _forms(String base) sync* {
  yield base;
  yield '${base}s';
  yield '${base}es';
  if (base.contains(' ')) {
    final joined = base.replaceAll(' ', '');
    yield joined;
    yield '${joined}s';
  }
}

final List<(RegExp, _Entry, int)> _matchers = [
  for (final e in _entries)
    for (final base in e.bases)
      for (final f in _forms(base).toSet())
        (RegExp('\\b${RegExp.escape(f)}\\b'), e, f.length),
];

/// The teachable movement a phrase is about, or null. Longest alias wins
/// ("hanging leg raise" over "leg raise"). Any blocker word returns null: this
/// path needs positive evidence, and a doubt means "keep it a normal goal".
TeachableMovement? teachableMovementIn(String phrase) {
  final text = _normalize(phrase);
  if (text.isEmpty || _blockers.hasMatch(text)) return null;
  _Entry? best;
  var bestLen = 0;
  for (final (re, entry, len) in _matchers) {
    if (len > bestLen && re.hasMatch(text)) {
      best = entry;
      bestLen = len;
    }
  }
  if (best == null) return null;
  return TeachableMovement(name: best.name, unit: best.unit);
}
