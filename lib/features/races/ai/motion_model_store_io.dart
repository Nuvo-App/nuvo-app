import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'motion_model_release.dart';

const _dirName = 'nuvo_motion_models';
const _manifestName = 'manifest.json';

Future<Directory> _dir() async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory('${support.path}/$_dirName');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

String _safeName(String value) =>
    value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

Future<File> _artifactFile(String modelVersion, String sha256) async {
  final dir = await _dir();
  return File('${dir.path}/${_safeName(modelVersion)}-${sha256.substring(0, 16)}.onnx');
}

Future<File> _manifestFile() async =>
    File('${(await _dir()).path}/$_manifestName');

Future<Map<String, dynamic>> _readManifest() async {
  try {
    final file = await _manifestFile();
    if (!await file.exists()) return {};
    final decoded = jsonDecode(await file.readAsString());
    return decoded is Map<String, dynamic> ? decoded : {};
  } catch (_) {
    return {};
  }
}

Future<void> _writeManifest(Map<String, dynamic> value) async {
  final file = await _manifestFile();
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString(jsonEncode(value), flush: true);
  await tmp.rename(file.path);
}

/// Atomic install: bytes land at a temp path, are renamed into place, then the
/// manifest repoints the family's last-known-good at them. A crash anywhere
/// before the rename leaves the previous good release untouched.
Future<void> persistMotionModel(
  String family,
  MotionModelRelease release,
  Uint8List bytes,
) async {
  try {
    final file = await _artifactFile(release.modelVersion, release.artifactSha256);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
    final manifest = await _readManifest();
    final families = manifest['families'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(manifest['families'] as Map<String, dynamic>)
        : <String, dynamic>{};
    families[family] = {
      'release': release.toJson(),
      'file': file.path.split('/').last,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
    };
    manifest['families'] = families;
    await _writeManifest(manifest);
  } catch (_) {
    // Persistence failure must never block a verified model from being used
    // in this session — it just won't be available as last-known-good.
  }
}

Future<({MotionModelRelease release, Uint8List bytes})?> readMotionModel(
  String family,
  String modelVersion,
  String sha256,
) async {
  try {
    final manifest = await _readManifest();
    final families = manifest['families'];
    if (families is! Map<String, dynamic>) return null;
    for (final entry in families.values) {
      if (entry is! Map<String, dynamic>) continue;
      final release = MotionModelRelease.fromJson(
        Map<String, dynamic>.from(entry['release'] as Map),
      );
      if (release.modelVersion != modelVersion ||
          release.artifactSha256 != sha256.toLowerCase()) {
        continue;
      }
      final file = File('${(await _dir()).path}/${entry['file']}');
      if (!await file.exists()) return null;
      return (release: release, bytes: await file.readAsBytes());
    }
    return null;
  } catch (_) {
    return null;
  }
}

Future<({MotionModelRelease release, Uint8List bytes})?> readLastKnownGoodMotionModel(
  String family,
) async {
  try {
    final manifest = await _readManifest();
    final families = manifest['families'];
    if (families is! Map<String, dynamic>) return null;
    final entry = families[family];
    if (entry is! Map<String, dynamic>) return null;
    final release = MotionModelRelease.fromJson(
      Map<String, dynamic>.from(entry['release'] as Map),
    );
    final file = File('${(await _dir()).path}/${entry['file']}');
    if (!await file.exists()) return null;
    return (release: release, bytes: await file.readAsBytes());
  } catch (_) {
    return null;
  }
}
