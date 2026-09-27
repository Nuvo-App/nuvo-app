import 'dart:typed_data';

import 'motion_package_store.dart';

/// Web fallback — packages live only in memory for the page session. Remote
/// verification is camera-based and iOS-only in practice, so this just keeps
/// the shared interface compilable; nothing persists.
final Map<String, InstalledMotionPackage> _installed = {};
final Map<String, Map<String, dynamic>> _stagedManifest = {};
final Map<String, Map<String, Uint8List>> _stagedAssets = {};

String _key(String activityId, String releaseId) => '$activityId/$releaseId';

Future<InstalledMotionPackage?> readPackage(
  String activityId,
  String releaseId,
) async =>
    _installed[_key(activityId, releaseId)];

Future<void> stageAsset(
  String activityId,
  String releaseId,
  String assetId,
  Uint8List bytes,
) async {
  _stagedAssets.putIfAbsent(_key(activityId, releaseId), () => {})[assetId] =
      bytes;
}

Future<void> stageManifest(
  String activityId,
  String releaseId,
  Map<String, dynamic> record,
) async {
  _stagedManifest[_key(activityId, releaseId)] = record;
}

Future<void> promotePackage(String activityId, String releaseId) async {
  final record = _stagedManifest[_key(activityId, releaseId)];
  if (record == null) {
    throw StateError('No staged package for $releaseId.');
  }
  final package = InstalledMotionPackage.tryParse(
    record,
    activityId: activityId,
    releaseId: releaseId,
  );
  if (package == null) {
    throw StateError('Staged package for $releaseId is invalid.');
  }
  _installed[_key(activityId, releaseId)] = package;
  _installedAssets[_key(activityId, releaseId)] =
      _stagedAssets.remove(_key(activityId, releaseId)) ?? {};
  _stagedManifest.remove(_key(activityId, releaseId));
}

final Map<String, Map<String, Uint8List>> _installedAssets = {};

Future<Uint8List?> packageAssetBytes(
  String activityId,
  String releaseId,
  String assetId,
) async =>
    _installedAssets[_key(activityId, releaseId)]?[assetId];

Future<List<InstalledMotionPackage>> allPackages() async =>
    _installed.values.toList();

Future<void> removePackage(String activityId, String releaseId) async {
  _installed.remove(_key(activityId, releaseId));
  _installedAssets.remove(_key(activityId, releaseId));
  _stagedManifest.remove(_key(activityId, releaseId));
  _stagedAssets.remove(_key(activityId, releaseId));
}

Future<void> sweepStaging() async {
  _stagedManifest.clear();
  _stagedAssets.clear();
}
