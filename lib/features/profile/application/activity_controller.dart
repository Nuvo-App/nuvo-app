import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cache_store.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/activity_api.dart';

final profileActivityApiProvider = Provider<ProfileActivityApi>(
  (ref) => ProfileActivityApi(),
);

/// Verified proofs per day for the heat map. Failure is non-fatal: the section
/// simply stays hidden.
final profileActivityProvider = FutureProvider.autoDispose<Map<String, int>>((
  ref,
) async {
  final token = await ref.read(secureTokenStoreProvider).getAccessToken();
  if (token == null) return const {};
  final store = ref.read(cacheStoreProvider);
  final account = ref.read(authControllerProvider).user?.id;
  final canCache = account != null && isValidCacheId(account);

  Map<String, int>? cached;
  if (canCache) {
    try {
      final entry = await store.read(account, 'activity', maxAge: _maxAge);
      final data = entry?.data;
      if (data is Map) {
        cached = {
          for (final e in data.entries)
            if (e.value is num) e.key.toString(): (e.value as num).toInt(),
        };
      }
    } catch (_) {
      // A bad snapshot is just a cache miss.
    }
  }

  try {
    final fresh = await ref.read(profileActivityApiProvider).fetch(token);
    if (canCache) store.write(account, 'activity', fresh);
    return fresh;
  } catch (_) {
    // Offline: the last known heat map beats an empty profile.
    if (cached != null) return cached;
    rethrow;
  }
});

const Duration _maxAge = Duration(days: 30);
