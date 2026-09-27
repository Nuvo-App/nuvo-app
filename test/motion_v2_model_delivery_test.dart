// System B acceptance: the SAME loaded encoder runtime must adopt a new remote
// model release, run real inference on it, roll back to the previous release,
// and reject a corrupt or incompatible release — with no rebuild in between.
// These tests exercise MotionV2OnnxEncoder against genuine ONNX artifacts:
//   A = fp16 launch encoder (assets/models/motion_v2_encoder.onnx)
//   B = fp32 variant (tools/motion_v2/checkpoints/…release_action.onnx)
//   C = corrupt bytes with a mismatched checksum
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_model_release.dart';
import 'package:nuvo/features/races/ai/motion_model_resolver.dart';
import 'package:nuvo/features/races/ai/motion_model_store.dart';
import 'package:nuvo/features/races/ai/motion_v2/engine/motion_v2_onnx_encoder.dart';
import 'package:nuvo/features/races/data/race_api.dart';

const _shaA =
    '8d43b34084111ad9e358f65724c1f017a3ad501221ce0ead3d2200584232a188';
const _shaB =
    '6eaabdcb0f73a895f831a90e0060376af52aa7e8995760afa27bb093123822e9';

Map<String, dynamic> _releaseJson(
  String version,
  String sha, {
  String runtime = kMotionV2EncoderRuntimeFamily,
}) => {
      'modelReleaseId': 'rel-$version',
      'modelVersion': version,
      'modelFamily': kMotionV2EncoderFamily,
      'runtimeFamily': runtime,
      'inputSchemaVersion': kMotionV2EncoderInputSchema,
      'outputSchemaVersion': kMotionV2EncoderOutputSchema,
      'preprocessingVersion': 1,
      'normalizationVersion': 1,
      'embeddingSchemaVersion': kMotionV2EncoderEmbeddingSchema,
      'minimumAppBuild': 1,
      'artifactKey': 'motion-models/$version.onnx',
      'artifactSha256': sha,
      'artifactSizeBytes': 1,
      'status': 'production',
      'supportedMotionIds': <String>[],
      'metadata': const {},
    };

class _MemStore extends MotionModelStore {
  final Map<String, ({MotionModelRelease release, Uint8List bytes})> _byKey = {};
  final Map<String, ({MotionModelRelease release, Uint8List bytes})> _lkg = {};

  @override
  Future<void> persist(
      String family, MotionModelRelease release, Uint8List bytes) async {
    final entry = (release: release, bytes: bytes);
    _byKey['$family:${release.cacheKey}'] = entry;
    _lkg[family] = entry;
  }

  @override
  Future<CachedMotionModel?> read(
      String family, String modelVersion, String sha256) async {
    final hit = _byKey['$family:$modelVersion:$sha256'];
    return hit == null
        ? null
        : CachedMotionModel(release: hit.release, bytes: hit.bytes);
  }

  @override
  Future<CachedMotionModel?> lastKnownGood(String family) async {
    final hit = _lkg[family];
    return hit == null
        ? null
        : CachedMotionModel(release: hit.release, bytes: hit.bytes);
  }
}

/// A scripted channel: returns whatever release JSON the test installs, and
/// serves artifact bytes from disk (or corrupt bytes on demand).
class _Channel {
  Map<String, dynamic>? releaseJson;
  Uint8List? Function(String version)? artifactFor;
}

MotionV2ModelSource _sourceFor(_Channel channel) => MotionV2ModelSource(
      resolveModel: (_) async => channel.releaseJson,
      fetchArtifact: (version) async => MotionModelArtifactFetch(
        bytes: channel.artifactFor?.call(version),
        modelVersion: version,
        sha256: channel.releaseJson?['artifactSha256'] as String?,
      ),
      appBuild: 1,
    );

List<Float32List> _poseSeq(int t) => [
      for (var i = 0; i < t; i++)
        Float32List.fromList([
          for (var j = 0; j < 51; j++) ((i * 51 + j) % 97) / 97 - 0.5,
        ]),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final bytesA = File('assets/models/motion_v2_encoder.onnx').readAsBytesSync();
  final bytesB = File(
    'tools/motion_v2/checkpoints/onnx/motion_v2_encoder_release_action.onnx',
  ).readAsBytesSync();

  const versionA = 'motion_v2_encoder_fp16_2026.10.0';
  const versionB = 'motion_v2_encoder_fp32_2026.10.1';

  late _Channel channel;
  late _MemStore store;

  setUp(() {
    MotionV2OnnxEncoder.resetSharedForTest();
    channel = _Channel();
    store = _MemStore();
  });

  test('A -> B adoption -> real inference -> B -> A rollback -> corrupt C rejected', () async {
    // ── Channel serves release A (fp16) ──
    channel.releaseJson = _releaseJson(versionA, _shaA);
    channel.artifactFor = (v) => v == versionA ? bytesA : null;
    MotionV2OnnxEncoder.configureModelSource(_sourceFor(channel), store: store);

    var encoder = await MotionV2OnnxEncoder.load();
    expect(MotionV2OnnxEncoder.activeModelVersion, versionA);
    expect(MotionV2OnnxEncoder.activeModelSource, 'remote');
    expect(MotionV2OnnxEncoder.activeModelChecksum, _shaA);

    // Actual inference on A — real ONNX session, rep (T,17,512).
    final repA = await encoder.encode(_poseSeq(12));
    expect(repA.length, 12);
    expect(repA.first.length, 17);
    expect(repA.first.first.length, 512);

    // ── Promote release B (fp32) — same loaded runtime, no rebuild ──
    channel.releaseJson = _releaseJson(versionB, _shaB);
    channel.artifactFor = (v) => v == versionB ? bytesB : null;

    encoder = await MotionV2OnnxEncoder.load();
    expect(MotionV2OnnxEncoder.activeModelVersion, versionB);
    expect(MotionV2OnnxEncoder.activeModelChecksum, _shaB);

    // Actual inference on B: genuinely different weights must still produce
    // the contract shape (and different numbers).
    final repB = await encoder.encode(_poseSeq(12));
    expect(repB.first.first.length, 512);
    expect(repB[0][0][0], isNot(closeTo(repA[0][0][0], 1e-6)));

    // ── Roll back the channel to A — the cached A bytes are reused ──
    channel.releaseJson = _releaseJson(versionA, _shaA);
    encoder = await MotionV2OnnxEncoder.load();
    expect(MotionV2OnnxEncoder.activeModelVersion, versionA);
    expect(MotionV2OnnxEncoder.activeModelSource, 'cachedRelease');
    final repA2 = await encoder.encode(_poseSeq(12));
    expect(repA2.first.first.length, 512);

    // ── Corrupt C: checksum-invalid bytes must never install ──
    channel.releaseJson = _releaseJson('motion_v2_encoder_corrupt', 'f' * 64);
    channel.artifactFor = (_) => Uint8List.fromList([9, 9, 9, 9]);
    MotionV2OnnxEncoder.resetSharedForTest();
    MotionV2OnnxEncoder.configureModelSource(_sourceFor(channel), store: store);
    encoder = await MotionV2OnnxEncoder.load();
    // Falls to last-known-good — the last verified install (B), still
    // functional. C's bytes were rejected before they could poison anything.
    expect(MotionV2OnnxEncoder.activeModelSource, 'lastKnownGood');
    expect(MotionV2OnnxEncoder.activeModelVersion, versionB);
    final repLkg = await encoder.encode(_poseSeq(8));
    expect(repLkg.first.first.length, 512);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('incompatible release is skipped; empty channel + empty store -> bundled', () async {
    // Unknown runtime family — the installed build cannot execute it.
    channel.releaseJson = _releaseJson('motion_v2_encoder_v9', 'e' * 64,
        runtime: 'unshipped_runtime_v9');
    channel.artifactFor = (_) => bytesA;
    MotionV2OnnxEncoder.configureModelSource(_sourceFor(channel), store: store);
    final encoder = await MotionV2OnnxEncoder.load();
    expect(MotionV2OnnxEncoder.activeModelSource, 'bundled');
    expect(MotionV2OnnxEncoder.activeModelVersion, kBundledMotionEncoderVersion);
    final rep = await encoder.encode(_poseSeq(8));
    expect(rep.first.first.length, 512);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('no source configured + empty store -> bundled launch model', () async {
    MotionV2OnnxEncoder.resetSharedForTest();
    final encoder = await MotionV2OnnxEncoder.load();
    expect(MotionV2OnnxEncoder.activeModelSource, 'bundled');
    final rep = await encoder.encode(_poseSeq(6));
    expect(rep.first.first.length, 512);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
