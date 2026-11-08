// Create-payload contract tests for the v13 composer gaps — draft-level and
// HTTP-body assertions (composer widget coverage lives in
// test/v13/race_composer_setup_test.dart).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nuvo/features/races/data/race_api.dart';

Map<String, dynamic> _raceJson() => {
  'id': 'race-test',
  'creatorId': 'user-1',
  'title': 'Race',
  'goalType': 'timed_attempt',
  'status': 'active',
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': '2026-01-01T00:00:00Z',
};

void main() {
  group('create payload contract', () {
    test('test_gap6_create_race_includes_attempt_fields', () async {
      Map<String, dynamic>? body;
      final api = RaceApi(
        client: MockClient((req) async {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'race': _raceJson()}), 200);
        }),
      );
      await api.createRace(
        'token',
        title: 'Timed battle',
        format: 'timed_attempt',
        finishLineAt: '2026-12-01T00:00:00Z',
        attemptDurationSeconds: 60,
        attemptLimit: 3,
      );
      expect(body!['attemptDurationSeconds'], 60);
      expect(body!['attemptLimit'], 3);
      expect(body!['finishLineAt'], '2026-12-01T00:00:00Z');

      body = null;
      await api.createRace(
        'token',
        title: 'First to 10',
        goalType: 'first_to_goal',
        targetValue: 10,
      );
      expect(body!.containsKey('attemptDurationSeconds'), isFalse);
      expect(body!.containsKey('attemptLimit'), isFalse);
      expect(body!.containsKey('finishLineAt'), isFalse);
    });
  });
}
