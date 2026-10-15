import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  return ref.read(profileActivityApiProvider).fetch(token);
});
