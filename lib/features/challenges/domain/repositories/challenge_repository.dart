import '../models/challenge.dart';

/// Boundary between the challenges feature and whatever data source backs
/// it. The arena, create-challenge, and detail screens only ever talk to
/// this interface — never to a concrete data source.
///
/// Swap [MockChallengeRepository] for a `FirebaseChallengeRepository` or a
/// `SupabaseChallengeRepository` by changing one line in
/// `challenge_providers.dart`. The rest of the app stays untouched.
abstract interface class ChallengeRepository {
  /// All currently-active challenges, optionally filtered by [category].
  /// Returns the freshest snapshot — callers using Riverpod should
  /// `invalidate` to refresh.
  Future<List<Challenge>> fetchActive({ChallengeCategory? category});

  /// A single challenge by id. Throws [StateError] if not found.
  Future<Challenge> fetchById(String id);

  /// Returns the newly-persisted challenge (with server-assigned id and
  /// computed prize pool).
  Future<Challenge> create(Challenge draft);

  /// Adds the current user to [challengeId]. Returns the updated challenge.
  Future<Challenge> join(String challengeId);
}
