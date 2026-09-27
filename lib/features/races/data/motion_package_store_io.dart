import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'motion_package_store.dart';

/// Overridable root for tests — the real implementation resolves
/// `getApplicationSupportDirectory()`, tests point this at a temp dir.
String? motionPackageStoreRootOverride;

Future<Directory> _root() async {
  final override = motionPackageStoreRootOverride;
  if (override != null) return Directory(override);
  final base = await getApplicationSupportDirectory();
  return Directory('${base.path}/motion_packages');
}

Directory _packageDir(Directory root, String activityId, String releaseId) =>
    Directory('${root.path}/$activityId/$releaseId');

Directory _stagingDir(Directory root, String activityId, String releaseId) =>
    Directory('${root.path}/$activityId/$releaseId.staging');

File _manifest(Directory dir) => File('${dir.path}/manifest.json');

File _asset(Directory dir, String assetId) => File('${dir.path}/assets/$assetId');

/// Reads an installed package only when the record parses AND every asset it
/// lists exists with its declared byte size. Anything less is treated as
/// absent — the installer then performs a clean reinstall.
Future<InstalledMotionPackage?> readPackage(
  String activityId,
  String releaseId,
) async {
  try {
    final dir = _packageDir(await _root(), activityId, releaseId);
    final manifest = _manifest(dir);
    if (!manifest.existsSync()) return null;
    final decoded = jsonDecode(await manifest.readAsString());
    final package = InstalledMotionPackage.tryParse(
      decoded,
      activityId: activityId,
      releaseId: releaseId,
    );
    if (package == null) return null;
    for (final asset in package.assets) {
      final file = _asset(dir, asset.id);
      if (!file.existsSync() || file.lengthSync() != asset.bytes) {
        return null;
      }
    }
    return package;
  } catch (_) {
    return null;
  }
}

Future<void> stageAsset(
  String activityId,
  String releaseId,
  String assetId,
  Uint8List bytes,
) async {
  final staging = _stagingDir(await _root(), activityId, releaseId);
  await Directory('${staging.path}/assets').create(recursive: true);
  await _asset(staging, assetId).writeAsBytes(bytes, flush: true);
}

Future<void> stageManifest(
  String activityId,
  String releaseId,
  Map<String, dynamic> record,
) async {
  final staging = _stagingDir(await _root(), activityId, releaseId);
  await staging.create(recursive: true);
  await _manifest(staging).writeAsString(jsonEncode(record), flush: true);
}

/// Staging → final via rename. The target is removed first only inside this
/// same critical section, so a failed install can never leave the directory
/// half-populated: it is either the old verified set or the new verified set.
Future<void> promotePackage(String activityId, String releaseId) async {
  final root = await _root();
  final staging = _stagingDir(root, activityId, releaseId);
  final target = _packageDir(root, activityId, releaseId);
  if (!staging.existsSync()) {
    throw StateError('No staged package for $releaseId.');
  }
  if (target.existsSync()) await target.delete(recursive: true);
  await staging.rename(target.path);
}

Future<Uint8List?> packageAssetBytes(
  String activityId,
  String releaseId,
  String assetId,
) async {
  try {
    final file = _asset(
      _packageDir(await _root(), activityId, releaseId),
      assetId,
    );
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  } catch (_) {
    return null;
  }
}

Future<List<InstalledMotionPackage>> allPackages() async {
  final root = await _root();
  if (!root.existsSync()) return const [];
  final packages = <InstalledMotionPackage>[];
  await for (final activityEntry in root.list()) {
    if (activityEntry is! Directory) continue;
    final activityId = activityEntry.uri.pathSegments
        .where((s) => s.isNotEmpty)
        .last;
    await for (final releaseEntry in activityEntry.list()) {
      if (releaseEntry is! Directory) continue;
      final name = releaseEntry.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .last;
      if (name.endsWith('.staging')) continue;
      final package = await readPackage(activityId, name);
      if (package != null) packages.add(package);
    }
  }
  return packages;
}

Future<void> removePackage(String activityId, String releaseId) async {
  try {
    final dir = _packageDir(await _root(), activityId, releaseId);
    if (dir.existsSync()) await dir.delete(recursive: true);
    final staging = _stagingDir(await _root(), activityId, releaseId);
    if (staging.existsSync()) await staging.delete(recursive: true);
  } catch (_) {
    // Cache cleanup must never throw into app code.
  }
}

Future<void> sweepStaging() async {
  try {
    final root = await _root();
    if (!root.existsSync()) return;
    await for (final activityEntry in root.list()) {
      if (activityEntry is! Directory) continue;
      await for (final releaseEntry in activityEntry.list()) {
        if (releaseEntry is Directory &&
            releaseEntry.uri.pathSegments
                .where((s) => s.isNotEmpty)
                .last
                .endsWith('.staging')) {
          await releaseEntry.delete(recursive: true);
        }
      }
    }
  } catch (_) {
    // Staging cleanup is best-effort.
  }
}
