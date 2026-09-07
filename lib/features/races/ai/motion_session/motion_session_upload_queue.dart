import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'motion_session_artifact.dart';

/// Uploads [MotionSessionArtifact]s to the cloud without ever blocking the
/// verification UI.
///
/// enqueue() stages the gzip blob + a metadata sidecar to a local directory
/// and kicks off a best-effort upload. If the upload fails (offline, 5xx, no
/// session), the artifact stays staged; flush() — called on app launch and at
/// the start of the next verification — retries everything staged. Successful
/// uploads are deleted; artifacts older than [_maxAge] or past [_maxAttempts]
/// are dropped so the directory can't grow forever.
class MotionSessionUploadQueue {
  MotionSessionUploadQueue({required this.upload, Directory? stagingDir})
    : _stagingOverride = stagingDir;

  /// Sends one artifact. Should throw on any failure (transport, auth, 5xx).
  final Future<void> Function({
    required Map<String, dynamic> metadata,
    required Uint8List gzipBytes,
  }) upload;

  /// Test seam — when set, staging uses this directory instead of
  /// `getApplicationDocumentsDirectory()`.
  final Directory? _stagingOverride;

  static const _dirName = 'motion_sessions';
  static const _maxAttempts = 6;
  static const _maxAge = Duration(days: 7);

  Directory? _dir;
  bool _flushing = false;

  Future<Directory> _stagingDir() async {
    if (_dir != null) return _dir!;
    final base = _stagingOverride ?? await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/$_dirName');
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  /// Stage the artifact and try to send it now. Never throws — a failed
  /// upload just means it's retried later by [flush].
  Future<void> enqueue(MotionSessionArtifact artifact) async {
    try {
      final dir = await _stagingDir();
      final blob = File('${dir.path}/${artifact.sessionId}.json.gz');
      final meta = File('${dir.path}/${artifact.sessionId}.meta.json');
      await blob.writeAsBytes(artifact.toGzipBytes(), flush: true);
      await meta.writeAsString(
        jsonEncode({
          'metadata': artifact.metadata(),
          'attempts': 0,
          'stagedAt': DateTime.now().toUtc().toIso8601String(),
        }),
        flush: true,
      );
    } catch (e) {
      _log('stage failed: $e');
      return;
    }
    // Fire-and-forget — the caller (a camera-frame callback) must not await.
    unawaited(flush());
  }

  /// Retry every staged artifact. Safe to call repeatedly; re-entrant calls
  /// are ignored.
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      final dir = await _stagingDir();
      final metas = (await dir.list().toList())
          .whereType<File>()
          .where((f) => f.path.endsWith('.meta.json'))
          .toList();
      for (final metaFile in metas) {
        await _tryOne(metaFile);
      }
    } catch (e) {
      _log('flush failed: $e');
    } finally {
      _flushing = false;
    }
  }

  Future<void> _tryOne(File metaFile) async {
    final sessionId =
        metaFile.uri.pathSegments.last.replaceAll('.meta.json', '');
    final blobFile = File('${metaFile.parent.path}/$sessionId.json.gz');

    Map<String, dynamic> meta;
    try {
      meta = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      await _discard(metaFile, blobFile, 'unreadable sidecar');
      return;
    }

    final stagedAt =
        DateTime.tryParse(meta['stagedAt'] as String? ?? '') ?? DateTime.now();
    final attempts = (meta['attempts'] as num?)?.toInt() ?? 0;
    if (DateTime.now().difference(stagedAt) > _maxAge ||
        attempts >= _maxAttempts) {
      await _discard(metaFile, blobFile, 'expired ($attempts attempts)');
      return;
    }
    if (!await blobFile.exists()) {
      await _discard(metaFile, blobFile, 'blob missing');
      return;
    }

    try {
      await upload(
        metadata: (meta['metadata'] as Map).cast<String, dynamic>(),
        gzipBytes: await blobFile.readAsBytes(),
      );
      await _discard(metaFile, blobFile, null); // success
      _log('uploaded $sessionId');
    } catch (e) {
      meta['attempts'] = attempts + 1;
      try {
        await metaFile.writeAsString(jsonEncode(meta), flush: true);
      } catch (_) {}
      _log('upload $sessionId failed (attempt ${attempts + 1}): $e');
    }
  }

  Future<void> _discard(File meta, File blob, String? reason) async {
    if (reason != null) _log('discard ${blob.path.split('/').last}: $reason');
    for (final f in [meta, blob]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  void _log(String m) {
    assert(() {
      debugPrint('[MotionSessionUploadQueue] $m');
      return true;
    }());
  }
}
