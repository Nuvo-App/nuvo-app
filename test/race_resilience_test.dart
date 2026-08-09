import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/data/race_models.dart';

/// Regression tests for the "Could not load race" bug.
///
/// The live D1 database has `race_members.user_id` as a nullable column
/// (added via `ALTER TABLE race_members ADD COLUMN user_id TEXT` in
/// `live_schema_compat.sql`). Old/demo members can have `user_id = NULL`.
///
/// Previously, `RaceParticipant.fromJson` did `json['userId'] as String`
/// (non-nullable cast), which threw `TypeError: Null is not a subtype of
/// String` whenever the backend returned `userId: null`. This caused
/// `Race.fromJson` to throw, which caused `getRaceDetail` to throw, which
/// caused the race detail screen to show "Could not load race."
///
/// These tests prove the parser now handles null fields gracefully.
void main() {
  group('Race.fromJson resilience', () {
    test('parses a race with a participant whose userId is null', () {
      final json = {
        'id': 'race-1',
        'creatorId': 'user-1',
        'title': 'Test Race',
        'goalType': 'first_to_goal',
        'status': 'active',
        'createdAt': '2024-01-01T00:00:00Z',
        'updatedAt': '2024-01-01T00:00:00Z',
        'participants': [
          {
            'id': 'member-1',
            'userId': null,
            'displayName': 'Unknown',
            'progressValue': 0,
            'progressPercent': 0,
            'joinedAt': null,
          },
        ],
      };

      expect(() => Race.fromJson(json), returnsNormally);
      final race = Race.fromJson(json);
      expect(race.participants, hasLength(1));
      expect(race.participants[0].userId, '');
      expect(race.participants[0].joinedAt, '');
    });

    test('parses a race with null creatorId and title without throwing', () {
      final json = {
        'id': 'race-2',
        'creatorId': null,
        'title': null,
        'goalType': 'first_to_goal',
        'status': 'active',
        'createdAt': null,
        'updatedAt': null,
        'participants': [],
      };

      expect(() => Race.fromJson(json), returnsNormally);
      final race = Race.fromJson(json);
      expect(race.creatorId, '');
      expect(race.title, '');
      expect(race.createdAt, '');
      expect(race.updatedAt, '');
    });

    test('parses a race with a proof whose userId is null', () {
      final json = {
        'id': 'race-3',
        'creatorId': 'user-1',
        'title': 'Test Race',
        'goalType': 'first_to_goal',
        'status': 'active',
        'createdAt': '2024-01-01T00:00:00Z',
        'updatedAt': '2024-01-01T00:00:00Z',
        'participants': [],
        'recentProofs': [
          {
            'id': 'proof-1',
            'userId': null,
            'displayName': 'Unknown',
            'proofType': 'ai_motion',
            'verificationStatus': 'ai_verified',
            'createdAt': null,
          },
        ],
      };

      expect(() => Race.fromJson(json), returnsNormally);
      final race = Race.fromJson(json);
      expect(race.recentProofs, hasLength(1));
      expect(race.recentProofs[0].userId, '');
      expect(race.recentProofs[0].createdAt, '');
    });

    test('parses a race with final standings whose userId is null', () {
      final json = {
        'id': 'race-4',
        'creatorId': 'user-1',
        'title': 'Test Race',
        'goalType': 'first_to_goal',
        'status': 'completed',
        'createdAt': '2024-01-01T00:00:00Z',
        'updatedAt': '2024-01-01T00:00:00Z',
        'participants': [],
        'finalStandings': [
          {
            'userId': null,
            'displayName': 'Unknown',
            'rank': 1,
            'scoreValue': 100,
          },
        ],
      };

      expect(() => Race.fromJson(json), returnsNormally);
      final race = Race.fromJson(json);
      expect(race.finalStandings, hasLength(1));
      expect(race.finalStandings[0].userId, '');
    });

    test('parses a normal race with all fields present correctly', () {
      final json = {
        'id': 'race-5',
        'creatorId': 'user-1',
        'title': 'Pushups Race',
        'goalType': 'first_to_goal',
        'activityId': 'push_ups',
        'metric': 'reps',
        'targetValue': 25,
        'status': 'active',
        'proofRequirement': 'ai_check',
        'verificationMethod': 'camera_pose',
        'verifierType': 'preset_pose',
        'createdAt': '2024-01-01T00:00:00Z',
        'updatedAt': '2024-01-01T00:00:00Z',
        'participants': [
          {
            'id': 'member-1',
            'userId': 'user-1',
            'displayName': 'Akshay',
            'progressValue': 10,
            'progressPercent': 40,
            'rank': 1,
            'joinedAt': '2024-01-01T00:00:00Z',
          },
        ],
      };

      final race = Race.fromJson(json);
      expect(race.id, 'race-5');
      expect(race.title, 'Pushups Race');
      expect(race.participants, hasLength(1));
      expect(race.participants[0].userId, 'user-1');
      expect(race.participants[0].displayName, 'Akshay');
    });
  });
}
