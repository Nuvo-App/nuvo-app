import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/mock_challenge_repository.dart';
import '../domain/models/challenge.dart';
import '../domain/repositories/challenge_repository.dart';

/// Single seam to swap data sources.
final challengeRepositoryProvider = Provider<ChallengeRepository>(
  (_) => MockChallengeRepository(),
);

/// Currently selected category chip in the Arena. `null` means "All".
class _SelectedCategoryNotifier extends StateNotifier<ChallengeCategory?> {
  _SelectedCategoryNotifier() : super(null);

  void select(ChallengeCategory? category) => state = category;
}

final selectedCategoryProvider =
    StateNotifierProvider<_SelectedCategoryNotifier, ChallengeCategory?>(
  (_) => _SelectedCategoryNotifier(),
);

/// Active challenges, filtered by the currently selected category.
final activeChallengesProvider = FutureProvider<List<Challenge>>((ref) {
  final category = ref.watch(selectedCategoryProvider);
  return ref.read(challengeRepositoryProvider).fetchActive(category: category);
});

/// Single-challenge fetch for the detail screen.
final challengeByIdProvider =
    FutureProvider.family<Challenge, String>((ref, id) {
  return ref.read(challengeRepositoryProvider).fetchById(id);
});
