import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/demo/presentation_demo.dart';

/// The showcase account must exercise the whole Crew surface — these
/// tests pin the fixture contract so a future refactor can't quietly
/// return the demo to an empty screen, and so the fixture graph stays
/// internally consistent (live payloads agree with race standings).
void main() {
  const userId = 'demo-viewer';

  test('crew activity covers every event family', () {
    final items = PresentationDemoData.crewActivity(userId);
    final types = {for (final i in items) i.type};
    for (final t in [
      'race_live',
      'rank_changed',
      'lead_changed',
      'race_created',
      'participant_finished',
      'personal_best',
      'reaction',
      'crew_request_accepted',
      'crew_connected',
    ]) {
      expect(types, contains(t), reason: 'fixture is missing "$t"');
    }
    // For you needs real direct events — at least two must name the
    // viewer (overtaken/displaced).
    expect(
      items.where((i) => i.involvesUser(userId)).length,
      greaterThanOrEqualTo(2),
    );
  });

  test('races cover the full lifecycle', () {
    final races = PresentationDemoData.races(userId);
    expect(
      races.where((r) => r.status == 'active').length,
      greaterThanOrEqualTo(2),
      reason: 'needs 2+ active shared races',
    );
    expect(
      races.where((r) => r.status == 'scheduled').length,
      greaterThanOrEqualTo(1),
      reason: 'needs an upcoming race',
    );
    expect(
      races.where((r) => r.status == 'completed').length,
      greaterThanOrEqualTo(3),
      reason: 'needs 3 recent results',
    );
  });

  test('live payload agrees with the race standings', () {
    final items = PresentationDemoData.crewActivity(userId);
    final races = {
      for (final r in PresentationDemoData.races(userId)) r.id: r,
    };
    final liveItem = items.firstWhere((i) => i.live != null);
    final live = liveItem.live!;
    final race = races[liveItem.raceId];
    expect(
      race,
      isNotNull,
      reason: 'live race must point at a real fixture race',
    );
    for (final p in live.participants) {
      if (p.isMe) {
        expect(
          race!.participantFor(userId)?.progressValue,
          p.score,
          reason: 'live score must match the race fixture',
        );
      }
    }
    final opponent = race!.participants.firstWhere(
      (p) => p.userId == 'presentation-demo-crew-noah',
    );
    expect(
      opponent.progressValue,
      live.participants.firstWhere((p) => !p.isMe).score,
      reason: 'live opponent score must match the race fixture',
    );
  });

  test('a fresh achievement exists inside 24h for the hot status', () {
    final items = PresentationDemoData.crewActivity(userId);
    final now = DateTime.now().toUtc();
    final hot = items.where(
      (i) =>
          i.actor != null &&
          now.difference(i.occurredAt).inHours < 24 &&
          const {
            'personal_best',
            'participant_finished',
            'race_finished',
            'winner_determined',
          }.contains(i.type),
    );
    expect(hot, isNotEmpty);
  });
}
