import 'tour_anchors.dart';

/// How a stop moves on.
enum TourAdvance {
  /// The bubble carries a button; the target is not the mission.
  button,

  /// The mission is one real tap on the spotlighted target.
  targetTap,
}

/// One stop of the guided tour. The whole script lives in this file
/// ([kTourScript]); the engine only reads it.
class TourStop {
  const TourStop({
    required this.id,
    required this.anchor,
    required this.copy,
    required this.mission,
    required this.xp,
    required this.route,
    this.advance = TourAdvance.targetTap,
    this.counter,
    this.dockIndex,
    this.dockCopy,
    this.buttonLabel,
    this.targetRadius = 16,
    this.fallbackXp,
    this.completeOnTap = false,
  });

  final String id;

  /// The widget spotlighted once the user is on [route].
  final TourAnchor anchor;

  /// Bubble copy for the target, max 3 lines.
  final String copy;

  /// Short mission name (Getting started row).
  final String mission;

  final int xp;

  /// XP when the reduced path is taken (camera skipped).
  final int? fallbackXp;

  /// The shell route the target lives on.
  final String route;

  final TourAdvance advance;

  /// 1-based "Tour N of 3" counter; null for stops outside the three.
  final int? counter;

  /// Dock tab to spotlight first when the user is not yet on [route].
  final int? dockIndex;
  final String? dockCopy;

  final String? buttonLabel;
  final double targetRadius;

  /// True when the one real tap on the target IS the mission. False when
  /// the mission finishes elsewhere (the practice proof sheet, the Join pill).
  final bool completeOnTap;

  int get maxLines => 3;
}

/// Stops in order. Copy follows docs/redesign/onboarding-v2-spec.md S10-S14.
const List<TourStop> kTourScript = [
  TourStop(
    id: 'arenaRace',
    anchor: TourAnchor.arenaRaceCard,
    copy: 'This is a race. You are 3rd. Beat them.',
    mission: 'See your race',
    xp: 0,
    route: '/arena',
    dockIndex: 0,
    dockCopy: 'Head back to the Arena.',
    advance: TourAdvance.button,
    buttonLabel: 'Next',
    targetRadius: 24,
  ),
  TourStop(
    id: 'arenaProof',
    anchor: TourAnchor.submitProof,
    copy: 'Tap Submit proof. It is how you move up.',
    mission: 'Submit your first proof',
    xp: 30,
    fallbackXp: 10,
    route: '/arena',
    dockIndex: 0,
    dockCopy: 'Head back to the Arena.',
  ),
  TourStop(
    id: 'compete',
    anchor: TourAnchor.joinCard,
    copy: 'Tap Join to jump into a race.',
    mission: 'Join a race',
    xp: 10,
    route: '/compete',
    counter: 1,
    dockIndex: 1,
    dockCopy: 'Compete is where races find you.',
    targetRadius: 12,
  ),
  TourStop(
    id: 'crew',
    anchor: TourAnchor.myNuvoCode,
    copy: 'Tap your code. Anyone who scans it becomes your friend.',
    mission: 'Open My Nuvo code',
    xp: 10,
    route: '/pass',
    counter: 2,
    dockIndex: 2,
    dockCopy: 'Crew is your people.',
    targetRadius: 14,
    completeOnTap: true,
  ),
  TourStop(
    id: 'profile',
    anchor: TourAnchor.firstBadge,
    copy: 'Tap your Day One badge to show it on your profile.',
    mission: 'Open your first badge',
    xp: 5,
    route: '/profile',
    counter: 3,
    dockIndex: 3,
    dockCopy: 'Profile is you.',
    targetRadius: 12,
    completeOnTap: true,
  ),
];

/// The notification ask (S11) is a sheet, not a spotlight stop, but it is a
/// Getting started mission with its own XP.
const String kTourNotifyId = 'notify';
const int kTourNotifyXp = 5;

const String kTourNotifyTitle = 'Want a buzz when someone passes you?';
const String kTourLesson =
    'That’s how Nuvo works. Someone passes you, you take it back.';
const String kTourDone = 'That’s the whole app. Go win a race.';
const String kTourPracticeCamera =
    'Nuvo counts your reps with the camera. Video stays on your phone.';

/// All Getting started mission ids in order: the four tap stops plus notify.
const List<String> kTourMissionIds = [
  'arenaProof',
  'notify',
  'compete',
  'crew',
  'profile',
];

TourStop? tourStopById(String id) {
  for (final s in kTourScript) {
    if (s.id == id) return s;
  }
  return null;
}

String tourMissionLabel(String id) =>
    id == kTourNotifyId ? 'Turn on notifications' : tourStopById(id)!.mission;

/// "Tour N of 3".
String tourCounterLabel(int n) => 'Tour $n of 3';

/// Every beat in play order. `notify` is the S11 sheet, shown after the
/// practice proof and the "passed you" beat.
const List<String> kTourSequence = [
  'arenaRace',
  'arenaProof',
  kTourNotifyId,
  'compete',
  'crew',
  'profile',
];
