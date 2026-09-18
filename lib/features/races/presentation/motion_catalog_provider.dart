import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/motion_capabilities.dart';
import '../data/motion_catalog.dart';
import '../data/motion_catalog_repository.dart';
import '../data/motion_catalog_cache.dart';
import '../data/race_api.dart';
import '../data/verifier_release_cache.dart';
import '../data/verifier_release_repository.dart';
import '../domain/motion_activity.dart';
import '../domain/motion_activity_catalog.dart';

final motionCatalogRepositoryProvider = Provider<MotionCatalogRepository>((
  ref,
) {
  final api = RaceApi();
  return MotionCatalogRepository(
    api,
    MotionCatalogCache(),
    releases: VerifierReleaseRepository(api, VerifierReleaseCache()),
  );
});

final motionCapabilitiesProvider = Provider<Set<String>>((ref) {
  return MotionCapabilities.current();
});

final motionCatalogProvider = FutureProvider<MotionCatalogSnapshot>((ref) {
  return ref.watch(motionCatalogRepositoryProvider).load();
});

/// Refreshes the control plane without tying network work to a screen build.
/// The provider is invalidated only after the last-known-good snapshot and any
/// changed release specs have been persisted.
Future<void> refreshMotionCatalog(WidgetRef ref) async {
  await ref.read(motionCatalogRepositoryProvider).load(force: true);
  ref.invalidate(motionCatalogProvider);
}

/// Keeps the composer API small while giving it an already validated local
/// fallback plus any compatible remote entries.
List<MotionActivityDefinition> availableMotionActivities(
  MotionCatalogSnapshot? snapshot,
  Set<String> capabilities,
) {
  if (snapshot == null) return motionActivityDefinitions;
  return snapshot.toDefinitions(capabilities);
}
