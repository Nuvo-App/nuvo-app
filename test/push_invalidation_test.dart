import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/notifications/domain/push_invalidation.dart';

void main() {
  const n = PushDomain.notifications;
  const r = PushDomain.races;
  const a = PushDomain.arena;
  const c = PushDomain.crew;
  const act = PushDomain.activity;
  const p = PushDomain.progression;

  final table = <String, Set<PushDomain>>{
    'race_invite': {n, r, a, act},
    'race_joined': {n, r, a, act},
    'race_starting': {n, r, a, act},
    'passed_on_leaderboard': {n, r, a, act},
    'race_completed': {n, r, a, act, p},
    'proof_accepted': {n, r, a, act, p},
    'proof_rejected': {n, r, a, act, p},
    'proof_disputed': {n, r, a, act, p},
    'crew_request': {n, c, act},
    'crew_request_accepted': {n, c, act},
    'crew_connected': {n, c, act},
    'reaction': {n, act},
  };

  table.forEach((cat, expected) {
    test('$cat maps correctly', () {
      expect(pushDomainsFor(cat), expected);
    });
  });

  test('unknown, empty and null categories invalidate notifications only', () {
    expect(pushDomainsFor('something_new'), {n});
    expect(pushDomainsFor(''), {n});
    expect(pushDomainsFor(null, destType: 'race'), {n});
  });

  test('every mapping includes notifications', () {
    for (final s in table.keys) {
      expect(pushDomainsFor(s), contains(n));
    }
  });
}
