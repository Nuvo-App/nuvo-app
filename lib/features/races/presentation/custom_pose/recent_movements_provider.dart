import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/motion_activity.dart';
import '../../domain/motion_activity_catalog.dart';

/// Persists the user's recently selected movement IDs across sessions.
///
/// Uses [FlutterSecureStorage] — the only local persistence mechanism
/// already present in the app. No new dependency is added.
///
/// Stores only canonical movement backend IDs (e.g. 'push_ups',
/// 'sumo_squats'). Stale IDs that no longer exist in the catalog are
/// silently ignored when reading.
class RecentMovementsStore {
  static const _key = 'nuvo_recent_movements';
  static const maxItems = 5;

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Reads the stored recent movement IDs, filters out any that no
  /// longer exist in the catalog, and returns them newest-first.
  Future<List<String>> readIds() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      final ids = list.cast<String>();
      // Filter stale IDs that no longer exist in the catalog
      final validIds = filterValidIds(ids);
      // If we filtered some out, persist the cleaned list
      if (validIds.length != ids.length) {
        await _writeIds(validIds);
      }
      return validIds;
    } catch (e) {
      debugPrint('[RecentMovements] read failed: $e');
      return [];
    }
  }

  /// Records a movement selection. Moves the ID to the front if it
  /// already exists, deduplicates, and trims to [maxItems].
  Future<List<String>> recordSelection(String movementId) async {
    final current = await readIds();
    final updated = addRecent(current, movementId, maxItems);
    await _writeIds(updated);
    return updated;
  }

  /// Clears all recent movements.
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (e) {
      debugPrint('[RecentMovements] clear failed: $e');
    }
  }

  Future<void> _writeIds(List<String> ids) async {
    try {
      await _storage.write(key: _key, value: jsonEncode(ids));
    } catch (e) {
      debugPrint('[RecentMovements] write failed: $e');
    }
  }
}

/// Pure function: adds a movement ID to the front of the recent list,
/// deduplicates, and trims to [maxItems].
/// Exported for testing.
List<String> addRecent(List<String> current, String movementId, int maxItems) {
  final updated = [movementId, ...current.where((id) => id != movementId)];
  return updated.take(maxItems).toList();
}

/// Pure function: filters out IDs that no longer exist in the catalog.
/// Exported for testing.
List<String> filterValidIds(List<String> ids) {
  return ids.where((id) {
    final type = MotionActivityType.fromBackendValue(id);
    return type != null;
  }).toList();
}

/// Provider for the [RecentMovementsStore] singleton.
final recentMovementsStoreProvider = Provider<RecentMovementsStore>((ref) {
  return RecentMovementsStore();
});

/// Provider for the current list of recent movement IDs.
///
/// Initialized empty and loaded asynchronously by the picker.
final recentMovementIdsProvider =
    StateNotifierProvider<RecentMovementIdsNotifier, List<String>>((ref) {
  return RecentMovementIdsNotifier(ref.read(recentMovementsStoreProvider));
});

class RecentMovementIdsNotifier extends StateNotifier<List<String>> {
  RecentMovementIdsNotifier(this._store) : super([]);

  final RecentMovementsStore _store;

  /// Loads recent IDs from storage. Call on picker init.
  Future<void> load() async {
    state = await _store.readIds();
  }

  /// Records a selection and updates state.
  Future<void> record(String movementId) async {
    state = await _store.recordSelection(movementId);
  }
}

/// Resolves recent movement IDs to catalog definitions, filtering
/// any that no longer exist. Returns newest-first.
List<MotionActivityDefinition> recentActivitiesFromIds(
  List<String> ids,
) {
  final result = <MotionActivityDefinition>[];
  for (final id in ids) {
    final def = motionActivityForBackendValue(id);
    if (def != null) result.add(def);
  }
  return result;
}
