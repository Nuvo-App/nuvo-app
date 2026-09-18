import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/motion_capabilities.dart';
import '../data/motion_catalog.dart';
import '../data/motion_catalog_repository.dart';
import '../data/motion_catalog_cache.dart';
import '../data/race_api.dart';
import '../domain/motion_activity.dart';
import '../domain/motion_activity_catalog.dart';

final motionCatalogRepositoryProvider = Provider<MotionCatalogRepository>((ref) {
  return MotionCatalogRepository(RaceApi(), MotionCatalogCache());
});

final motionCapabilitiesProvider = Provider<Set<String>>((ref) {
  return MotionCapabilities.current();
});

final motionCatalogProvider = FutureProvider<MotionCatalogSnapshot>((ref) {
  return ref.watch(motionCatalogRepositoryProvider).load();
});

/// Keeps the composer API small while giving it an already validated local
/// fallback plus any compatible remote entries.
List<MotionActivityDefinition> availableMotionActivities(
  MotionCatalogSnapshot? snapshot,
  Set<String> capabilities,
) {
  if (snapshot == null) return motionActivityDefinitions;
  return snapshot.toDefinitions(capabilities);
}
