// System B evaluation: run the REAL general-motion pipeline through the fixed
// QA corpus under two model releases — baseline A (bundled fp16 launch
// encoder) vs candidate B (fp32 variant) — through the exact production code
// path: MotionV2NativeRuntime.learn -> load -> update, real ONNX Runtime.
//
// Corpus: test/motion_qa/fixtures/real/yt_*.json — 30 real clips, one target
// movement (jump_squats) plus confuser movements labeled shouldMatch=false.
// Few-shot protocol mirrors Teach Nuvo: learn from 3 target clips, then
// replay every other clip and record the verdict.
//
// Output: test/motion_qa/experiment_results/model_ab_eval.json — the report
// consumed by `nuvo-motion.mjs model-evaluate` (corpusId / sampleCount /
// hardGatesPassed / metrics) plus per-clip detail.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_model_release.dart';
import 'package:nuvo/features/races/ai/motion_model_resolver.dart';
import 'package:nuvo/features/races/ai/motion_model_store.dart';
import 'package:nuvo/features/races/ai/motion_v2/engine/motion_v2_onnx_encoder.dart';
import 'package:nuvo/features/races/ai/motion_v2/motion_v2_native_runtime.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/data/race_api.dart';

const _shaB =
    '6eaabdcb0f73a895f831a90e0060376af52aa7e8995760afa27bb093123822e9';
const _versionB = 'motion_v2_encoder_fp32_2026.10.1';
const _target = 'jump_squats';
const _corpusId = 'motion_qa_real_yt_v1';

class _MemStore extends MotionModelStore {
  final Map<String, ({MotionModelRelease release, Uint8List bytes})> _byKey = {};
  final Map<String, ({MotionModelRelease release, Uint8List bytes})> _lkg = {};
  @override
  Future<void> persist(
      String family, MotionModelRelease release, Uint8List bytes) async {
    final e = (release: release, bytes: bytes);
    _byKey['$family:${release.cacheKey}'] = e;
    _lkg[family] = e;
  }

  @override
  Future<CachedMotionModel?> read(
          String family, String v, String sha) async =>
      _byKey['$family:$v:$sha'] == null
          ? null
          : CachedMotionModel(
              release: _byKey['$family:$v:$sha']!.release,
              bytes: _byKey['$family:$v:$sha']!.bytes);

  @override
  Future<CachedMotionModel?> lastKnownGood(String family) async =>
      _lkg[family] == null
          ? null
          : CachedMotionModel(
              release: _lkg[family]!.release, bytes: _lkg[family]!.bytes);
}

Map<String, dynamic> _releaseJson(String version, String sha) => {
      'modelReleaseId': 'rel-$version',
      'modelVersion': version,
      'modelFamily': kMotionV2EncoderFamily,
      'runtimeFamily': kMotionV2EncoderRuntimeFamily,
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

class _Clip {
  _Clip(this.id, this.movement, this.shouldMatch, this.expectedReps,
      this.frames);
  final String id, movement;
  final bool shouldMatch;
  final int expectedReps;
  final List<NuvoPoseFrame> frames;
}

NuvoPoseFrame _frame(Map<String, dynamic> f, int index) => NuvoPoseFrame(
      points: {
        for (final e in (f['landmarks'] as Map).entries)
          e.key as String: NuvoPosePoint(
            x: (e.value[0] as num).toDouble(),
            y: (e.value[1] as num).toDouble(),
            z: (e.value[2] as num).toDouble(),
            likelihood: (e.value[3] as num).toDouble(),
          ),
      },
      imageWidth: (f['imageWidth'] as num? ?? 0).toDouble(),
      imageHeight: (f['imageHeight'] as num? ?? 0).toDouble(),
      // 30fps synthetic clock — the streaming engine derives frame period
      // from timestamps.
      createdAt: DateTime.fromMillisecondsSinceEpoch(index * 33),
    );

List<_Clip> _corpus() {
  final dir = Directory('test/motion_qa/fixtures/real');
  final clips = <_Clip>[];
  for (final f in dir.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path))) {
    if (!f.path.endsWith('.json') || f.path.contains('import_log')) continue;
    final d = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final exp = d['expected'] as Map<String, dynamic>;
    clips.add(_Clip(
      d['id'] as String,
      d['movement'] as String,
      exp['shouldMatch'] as bool,
      (exp['reps'] as num).toInt(),
      [
        for (var i = 0; i < (d['frames'] as List).length; i++)
          _frame((d['frames'] as List)[i] as Map<String, dynamic>, i),
      ],
    ));
  }
  return clips;
}

class _ClipVerdict {
  _ClipVerdict(this.clip);
  final _Clip clip;
  var reps = 0;
  var matchedEver = false;
  var bestScore = 0.0;
  var pushes = 0;
  var latencyMs = <double>[];
  var finishedState = 'warmingUp';
  bool get accepted => reps > 0;
}

Future<_ClipVerdict> _replay(
    MotionV2NativeRuntime rt, dynamic spec, _Clip clip) async {
  final v = _ClipVerdict(clip);
  await rt.load(spec);
  await rt.reset();
  // Feed in batches of 15 frames (0.5s at 30fps) — every push re-encodes the
  // whole buffer, so per-frame pushes would run ~100 ONNX passes per clip;
  // 15 keeps rep-cycle resolution while keeping the corpus runnable.
  for (var i = 0; i < clip.frames.length; i += 15) {
    final batch =
        clip.frames.sublist(i, math.min(i + 15, clip.frames.length));
    final r = await rt.update(batch);
    v.pushes++;
    v.matchedEver = v.matchedEver || r.matched;
    v.reps = math.max(v.reps, r.count);
    v.bestScore = math.max(v.bestScore, r.confidence);
    if (r.inferenceLatency > Duration.zero) {
      v.latencyMs.add(r.inferenceLatency.inMicroseconds / 1000);
    }
    v.finishedState = r.state.name;
  }
  return v;
}

Map<String, dynamic> _summarize(String model, List<_ClipVerdict> vs,
    {required int learnMs, required int sessionMs, required int rssMb}) {
  final targets = vs.where((v) => v.clip.shouldMatch).toList();
  final confusers = vs.where((v) => !v.clip.shouldMatch).toList();
  final trueAccept = targets.where((v) => v.accepted).length;
  final falseReject = targets.where((v) => !v.accepted).length;
  final falseAccept = confusers.where((v) => v.accepted).toList();
  final lat = vs.expand((v) => v.latencyMs).toList()..sort();
  final confusion = <String, int>{};
  for (final v in falseAccept) {
    confusion[v.clip.movement] = (confusion[v.clip.movement] ?? 0) + 1;
  }
  final repErr = <int>[
    for (final v in targets.where((v) => v.accepted))
      (v.reps - v.clip.expectedReps).abs(),
  ];
  return {
    'model': model,
    'clips': vs.length,
    'targetClips': targets.length,
    'confuserClips': confusers.length,
    'trueAccept': trueAccept,
    'falseReject': falseReject,
    'falseAccept': falseAccept.length,
    'trueAcceptRate': targets.isEmpty ? null : trueAccept / targets.length,
    'confuserRejectionRate':
        confusers.isEmpty ? null : 1 - falseAccept.length / confusers.length,
    'crossMotionConfusion': confusion,
    'meanRepErrorOnAccepted': repErr.isEmpty
        ? null
        : repErr.reduce((a, b) => a + b) / repErr.length,
    'latencyMsMean': lat.isEmpty ? null : lat.reduce((a, b) => a + b) / lat.length,
    'latencyMsP95': lat.isEmpty
        ? null
        : lat[(lat.length * 0.95).floor().clamp(0, lat.length - 1)],
    'learnMs': learnMs,
    'sessionCreateMs': sessionMs,
    'processRssMb': rssMb,
    'perClip': [
      for (final v in vs)
        {
          'clipId': v.clip.id,
          'movement': v.clip.movement,
          'shouldMatch': v.clip.shouldMatch,
          'accepted': v.accepted,
          'reps': v.reps,
          'expectedReps': v.clip.expectedReps,
          'matchedEver': v.matchedEver,
          'bestScore': v.bestScore,
          'finalState': v.finishedState,
        },
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('A-vs-B corpus evaluation through the production pipeline', () async {
    final clips = _corpus();
    // Few-shot support: first 3 target clips become the teaching demos;
    // every other clip is an unseen replay (7 held-out targets + 20
    // confusers = 27 scored clips per model).
    final demos = clips.where((c) => c.movement == _target).take(3).toList();
    final evalClips = clips.where((c) => !demos.contains(c)).toList();
    expect(evalClips.length, greaterThanOrEqualTo(20));

    final rssMb = () => (ProcessInfo.currentRss / (1024 * 1024)).round();
    final results = <String, Map<String, dynamic>>{};

    for (final phase in ['A', 'B']) {
      MotionV2OnnxEncoder.resetSharedForTest();
      if (phase == 'A') {
        // Bundled launch model — exactly what the shipped app falls back to.
        MotionV2OnnxEncoder.configureModelSource(null);
      } else {
        // Candidate B resolved + verified + installed through the real
        // delivery path (release JSON -> checksum-verified artifact).
        final bytesB = File(
          'tools/motion_v2/checkpoints/onnx/'
          'motion_v2_encoder_release_action.onnx',
        ).readAsBytesSync();
        final rel = _releaseJson(_versionB, _shaB);
        MotionV2OnnxEncoder.configureModelSource(
          MotionV2ModelSource(
            resolveModel: (_) async => rel,
            fetchArtifact: (v) async => MotionModelArtifactFetch(
              bytes: v == _versionB ? bytesB : null,
              modelVersion: v,
              sha256: _shaB,
            ),
            appBuild: 1,
          ),
          store: _MemStore(),
        );
      }
      await MotionV2OnnxEncoder.load();
      final learnSw = Stopwatch()..start();
      final rt = MotionV2NativeRuntime();
      final spec = await rt.learn(
        movementName: _target,
        demos: [for (final d in demos) d.frames],
      );
      final learnMs = learnSw.elapsedMilliseconds;
      final verdicts = <_ClipVerdict>[
        for (final c in evalClips) await _replay(rt, spec, c),
      ];
      results[phase] = _summarize(
        MotionV2OnnxEncoder.activeModelVersion,
        verdicts,
        learnMs: learnMs,
        sessionMs: MotionV2OnnxEncoder.lastSessionCreateMs,
        rssMb: rssMb(),
      );
      await rt.dispose();
    }

    final a = results['A']!;
    final b = results['B']!;
    // Decision agreement: same verdict on the same unseen clip.
    final aByClip = {
      for (final c in (a['perClip'] as List).cast<Map<String, dynamic>>())
        c['clipId']: c['accepted'],
    };
    final bByClip = {
      for (final c in (b['perClip'] as List).cast<Map<String, dynamic>>())
        c['clipId']: c['accepted'],
    };
    final agree =
        aByClip.keys.where((k) => aByClip[k] == bByClip[k]).length /
            aByClip.length;

    // Hard gates — a promotion candidate must not regress the baseline:
    // 1. no recall loss (accepts at least as many true clips)
    // 2. no new false accepts on confusers
    // 3. >=90% verdict agreement with the shipped model
    final gates = {
      'noRecallRegression':
          (b['trueAccept'] as int) >= (a['trueAccept'] as int),
      'noFalseAcceptRegression':
          (b['falseAccept'] as int) <= (a['falseAccept'] as int),
      'verdictAgreementAtLeast90': agree >= 0.9,
    };
    final hardGatesPassed = gates.values.every((g) => g);

    final report = {
      'corpusId': _corpusId,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'protocol':
          'few-shot learn (3 jump_squats demos) -> replay corpus through '
              'production MotionV2NativeRuntime; accepted = >=1 rep matched',
      'sampleCount': evalClips.length,
      'hardGatesPassed': hardGatesPassed,
      'gates': gates,
      'decisionAgreement': agree,
      'baseline': 'A',
      'candidate': 'B',
      'metrics': {
        'baseline': a..remove('perClip'),
        'candidate': b..remove('perClip'),
        'decisionAgreement': agree,
      },
      'perClip': {'baseline': a['perClip'], 'candidate': b['perClip']},
    };
    File('test/motion_qa/experiment_results/model_ab_eval.json')
        .writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(report));

    // Surface the comparison in the test output for the transcript.
    // ignore: avoid_print
    print(JsonEncoder.withIndent('  ').convert({
      'hardGatesPassed': hardGatesPassed,
      'gates': gates,
      'decisionAgreement': agree,
      'baseline': results['A'],
      'candidate': results['B'],
    }));
    expect(results['A']!['clips'], evalClips.length);
  }, timeout: const Timeout(Duration(minutes: 20)));
}
