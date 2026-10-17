import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/utils/json_safe.dart';
import 'package:nuvo/features/arena/data/arena_models.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/squads/data/squad_api.dart';

void main() {
  test('json_safe helpers never throw and coerce types', () {
    expect(jInt(null), isNull);
    expect(jInt(3.0), 3);
    expect(jInt('7'), 7);
    expect(jInt({}), isNull);
    expect(jDouble('1.5'), 1.5);
    expect(jStr(4), '4');
    expect(jBool('true'), true);
    expect(jMapList([1, {'a': 1}, null]).length, 1);
    expect(jList('x'), isEmpty);
  });

  test('Race.fromJson tolerates id-only and null-heavy payloads', () {
    expect(Race.fromJson({'id': 'r1'}).id, 'r1');
    expect(Race.fromJson(const <String, dynamic>{}).id, '');
    final r = Race.fromJson({
      'id': 'r1',
      'targetValue': null,
      'attemptLimit': 3.0,
      'attemptDurationSeconds': '60',
      'participants': [null, 5, {'id': 'p1', 'progressValue': 2.0}],
      'recentProofs': 'nope',
      'finalStandings': null,
      'viewerContext': 'x',
      'submissionResult': 3,
    });
    expect(r.targetValue, isNull);
    expect(r.attemptLimit, 3);
    expect(r.attemptDurationSeconds, 60);
    expect(r.participants.single.progressValue, 2);
    expect(r.recentProofs, isEmpty);
  });

  test('race sub-models tolerate empty and wrong-typed json', () {
    expect(() => RaceParticipant.fromJson({'id': null, 'rank': '2'}), returnsNormally);
    expect(() => PublicUser.fromJson({}), returnsNormally);
    expect(() => RaceProof.fromJson({'value': '4', 'confidence': 1}), returnsNormally);
    expect(() => RaceViewerContext.fromJson({'rank': '1'}), returnsNormally);
    expect(() => RaceSubmissionResult.fromJson({'newScore': 2.0}), returnsNormally);
    expect(() => RaceFinalStanding.fromJson({}), returnsNormally);
    expect(() => RaceLiveState.fromJson({'participants': 'x'}), returnsNormally);
  });

  test('arena models tolerate null-heavy json', () {
    expect(() => ArenaSnapshot.fromJson({}), returnsNormally);
    expect(
      () => ArenaSnapshot.fromJson({
        'focusBoard': 'x',
        'liveBoards': [null, {'id': 'b'}],
        'activity': 'y',
      }),
      returnsNormally,
    );
    expect(() => ArenaBoard.fromJson({'id': 'b'}), returnsNormally);
  });

  test('squad models tolerate null-heavy json', () {
    expect(parseCrewGroupList(null), isEmpty);
    expect(parseCrewGroupList({'squads': [null, {'id': 's1'}]}).length, 1);
    expect(() => CrewGroupDetail.fromJson({}), returnsNormally);
    expect(() => CrewMember.fromJson({'userId': null}), returnsNormally);
  });
}
