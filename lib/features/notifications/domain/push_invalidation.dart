/// Which cached domains a received push makes stale (docs/agents/22 §5.5).
/// Pure — the push service applies the result with existing controller calls.
enum PushDomain { races, arena, crew, notifications, activity, progression }

const _raceCategories = {
  'race_invite',
  'race_joined',
  'race_starting',
  'passed_on_leaderboard',
};

/// Proof / finish outcomes also move XP and badges.
const _progressionCategories = {
  'race_completed',
  'proof_accepted',
  'proof_rejected',
  'proof_disputed',
};

const _crewCategories = {
  'crew_request',
  'crew_request_accepted',
  'crew_connected',
};

/// Domains to invalidate for a push [category]. [destType] is only used to
/// refine unknown categories. Every push invalidates [PushDomain.notifications].
Set<PushDomain> pushDomainsFor(String? category, {String? destType}) {
  final c = category ?? '';
  if (_raceCategories.contains(c)) {
    return {
      PushDomain.notifications,
      PushDomain.races,
      PushDomain.arena,
      PushDomain.activity,
    };
  }
  if (_progressionCategories.contains(c)) {
    return {
      PushDomain.notifications,
      PushDomain.races,
      PushDomain.arena,
      PushDomain.activity,
      PushDomain.progression,
    };
  }
  if (_crewCategories.contains(c)) {
    return {PushDomain.notifications, PushDomain.crew, PushDomain.activity};
  }
  if (c == 'reaction') {
    return {PushDomain.notifications, PushDomain.activity};
  }
  return {PushDomain.notifications};
}
