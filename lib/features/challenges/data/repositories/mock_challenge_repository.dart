import 'package:uuid/uuid.dart';

import '../../domain/models/challenge.dart';
import '../../domain/models/participant.dart';
import '../../domain/repositories/challenge_repository.dart';

/// In-memory implementation of [ChallengeRepository] seeded with realistic
/// sample data so the Arena screen renders meaningfully on first launch.
///
/// Network latency is faked with small `Future.delayed`s so loading
/// shimmers/spinners get exercised in development.
class MockChallengeRepository implements ChallengeRepository {
  MockChallengeRepository() {
    _challenges.addAll(_seed());
  }

  static const _uuid = Uuid();
  final List<Challenge> _challenges = [];

  // --- ChallengeRepository ------------------------------------------------

  @override
  Future<List<Challenge>> fetchActive({ChallengeCategory? category}) async {
    await Future<void>.delayed(const Duration(milliseconds: 280));
    final active = _challenges
        .where((c) => c.status == ChallengeStatus.active)
        .where((c) => category == null || c.category == category)
        .toList()
      ..sort((a, b) {
        // Hot challenges float, then by soonest-ending.
        if (a.isHot != b.isHot) return a.isHot ? -1 : 1;
        return a.endDate.compareTo(b.endDate);
      });
    return active;
  }

  @override
  Future<Challenge> fetchById(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return _challenges.firstWhere(
      (c) => c.id == id,
      orElse: () => throw StateError('Challenge $id not found'),
    );
  }

  @override
  Future<Challenge> create(Challenge draft) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final persisted = draft.copyWith(
      id: _uuid.v4(),
      prizePool: _computePrizePool(draft),
    );
    _challenges.add(persisted);
    return persisted;
  }

  @override
  Future<Challenge> join(String challengeId) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final idx = _challenges.indexWhere((c) => c.id == challengeId);
    if (idx == -1) throw StateError('Challenge $challengeId not found');
    final existing = _challenges[idx];
    final updated = existing.copyWith(
      participants: [
        ...existing.participants,
        Participant(id: _uuid.v4(), username: 'you'),
      ],
      prizePool: _computePrizePool(
        existing.copyWith(
          participants: [...existing.participants, _placeholderJoiner],
        ),
      ),
    );
    _challenges[idx] = updated;
    return updated;
  }

  // --- Helpers ------------------------------------------------------------

  static const _placeholderJoiner =
      Participant(id: '__placeholder', username: 'placeholder');

  /// Prize pool = entry fee × participants, minus a 10% platform rake.
  /// Returns 0 for free challenges (they use the `glory` prize type).
  double _computePrizePool(Challenge c) {
    if (c.prizeType == PrizeType.glory) return c.participants.length * 25.0;
    return c.entryFee * c.participants.length * 0.9;
  }

  List<Challenge> _seed() {
    final now = DateTime.now();
    Participant p(String u, {int progress = 0, String? avatar}) =>
        Participant(id: _uuid.v4(), username: u, avatarUrl: avatar, progress: progress);

    return [
      Challenge(
        id: _uuid.v4(),
        title: '100 Pushups a Day',
        category: ChallengeCategory.fitness,
        startDate: now.subtract(const Duration(days: 2)),
        endDate: now.add(const Duration(days: 12)),
        entryFee: 25,
        prizePool: 25 * 8 * 0.9,
        prizeType: PrizeType.usd,
        isHot: true,
        participants: [
          p('akaash', progress: 64),
          p('shivmanas', progress: 58),
          p('shaurya', progress: 71),
          p('mira', progress: 40),
          p('jay', progress: 33),
          p('rae', progress: 22),
          p('luca', progress: 19),
          p('nico', progress: 12),
        ],
        description: 'Hit 100 verified pushups every day. Last one standing takes the pot.',
      ),
      Challenge(
        id: _uuid.v4(),
        title: 'Read 30 Min / Day',
        category: ChallengeCategory.learning,
        startDate: now.subtract(const Duration(days: 5)),
        endDate: now.add(const Duration(days: 25)),
        entryFee: 0,
        prizePool: 4 * 25.0,
        prizeType: PrizeType.glory,
        isHot: false,
        participants: [
          p('akaash', progress: 50),
          p('mira', progress: 80),
          p('nico', progress: 35),
          p('rae', progress: 60),
        ],
        description: 'No-stakes streak builder. Reading counts only if you log a 2-sentence summary.',
      ),
      Challenge(
        id: _uuid.v4(),
        title: 'No Sugar — 21 Day Reset',
        category: ChallengeCategory.habits,
        startDate: now.subtract(const Duration(days: 1)),
        endDate: now.add(const Duration(days: 20)),
        entryFee: 50,
        prizePool: 50 * 5 * 0.9,
        prizeType: PrizeType.usd,
        isHot: true,
        participants: [
          p('shivmanas', progress: 25),
          p('jay', progress: 18),
          p('luca', progress: 22),
          p('rae', progress: 12),
          p('akaash', progress: 30),
        ],
        description: 'Daily check-in selfie + food log. AI flags red-flag photos for jury review.',
      ),
      Challenge(
        id: _uuid.v4(),
        title: 'Wake at 5:30 AM',
        category: ChallengeCategory.habits,
        startDate: now.subtract(const Duration(days: 3)),
        endDate: now.add(const Duration(days: 4)),
        entryFee: 10,
        prizePool: 10 * 6 * 0.9,
        prizeType: PrizeType.usd,
        isHot: false,
        participants: [
          p('mira', progress: 90),
          p('shaurya', progress: 70),
          p('nico', progress: 88),
          p('jay', progress: 60),
          p('luca', progress: 55),
          p('akaash', progress: 80),
        ],
        description: 'Time-stamped selfie before 5:35 AM local time. Miss a day → eliminated.',
      ),
      Challenge(
        id: _uuid.v4(),
        title: 'Ship a side project in 7 days',
        category: ChallengeCategory.custom,
        startDate: now,
        endDate: now.add(const Duration(days: 7)),
        entryFee: 100,
        prizePool: 100 * 3 * 0.9,
        prizeType: PrizeType.usd,
        isHot: true,
        participants: [
          p('akaash', progress: 10),
          p('shivmanas', progress: 5),
          p('shaurya', progress: 8),
        ],
        description: 'Public Git repo + deployed link by EOW. Peer-judged.',
      ),
    ];
  }
}
