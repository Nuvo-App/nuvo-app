import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_model_artifact_integrity.dart';
import 'package:nuvo/features/races/ai/remote_verifier_spec.dart';
import 'package:nuvo/features/races/data/motion_catalog.dart';
import 'package:nuvo/features/races/data/motion_package_installer.dart';
import 'package:nuvo/features/races/data/motion_package_store.dart';
import 'package:nuvo/features/races/data/motion_package_store_io.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/verifier_release.dart';
import 'package:nuvo/features/races/domain/camera_verification_resolver.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/domain/motion_capability_service.dart';

/// D2 package installer acceptance matrix.
///
/// A remote release may carry content-addressed assets. The device downloads
/// each into a staging area, verifies bytes + sha256 + per-type sanity, and
/// atomically promotes — a race never observes a partial install and a failed
/// update never corrupts the last-known-good package.
void main() {
  late Directory root;
  late Map<String, Uint8List> network;

  final checksum = 'sha256:${'a' * 64}';

  Uint8List previewBytes() => utf8.encode('{"kind":"preview"}');
  Uint8List specBytes() =>
      utf8.encode('{"engineType":"sequence_match_v1","v":1}');

  String assetUrl(String releaseId, String assetId) =>
      '/motion/releases/$releaseId/assets/$assetId';

  Map<String, dynamic> assetJson(
    String releaseId,
    String id, {
    required String type,
    required Uint8List bytes,
    bool required = true,
  }) =>
      {
        'id': id,
        'type': type,
        'sha256': sha256Hex(bytes),
        'url': assetUrl(releaseId, id),
        'bytes': bytes.length,
        'required': required,
      };

  Map<String, dynamic> specJson({
    required String releaseId,
    String activityId = 'reach_taps',
    List<Map<String, dynamic>>? assets,
  }) =>
      {
        'specSchemaVersion': 1,
        'releaseId': releaseId,
        'activityId': activityId,
        'engineType': 'alternating_rep_v1',
        'measurementType': 'repetitions',
        'requiredLandmarks': ['leftWrist', 'rightWrist'],
        'leftRules': [
          {
            'point': 'leftWrist',
            'axis': 'y',
            'operator': 'lt',
            'threshold': 0.35,
          },
        ],
        'rightRules': [
          {
            'point': 'rightWrist',
            'axis': 'y',
            'operator': 'lt',
            'threshold': 0.35,
          },
        ],
        if (assets != null)
          'package': {'packageSchemaVersion': 1, 'assets': assets},
      };

  RemoteVerifierSpec spec({
    required String releaseId,
    String activityId = 'reach_taps',
    List<Map<String, dynamic>>? assets,
  }) =>
      RemoteVerifierSpec.fromJson(
        specJson(releaseId: releaseId, activityId: activityId, assets: assets),
      );

  MotionPackageInstaller installer() => MotionPackageInstaller(
        downloader: (url, maxBytes) async => network[url],
      );

  setUp(() {
    root = Directory.systemTemp.createTempSync('nuvo_pkg_test');
    motionPackageStoreRootOverride = root.path;
    network = {};
  });

  tearDown(() {
    motionPackageStoreRootOverride = null;
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  group('install lifecycle', () {
    test('happy install — required + optional assets promote atomically',
        () async {
      final releaseId = 'reach_taps-2026.10.0';
      final preview = previewBytes();
      final engine = specBytes();
      network[assetUrl(releaseId, 'engine')] = engine;
      network[assetUrl(releaseId, 'preview')] = preview;
      final s = spec(
        releaseId: releaseId,
        assets: [
          assetJson(releaseId, 'engine', type: 'motion_v2_spec_v1',
              bytes: engine),
          assetJson(releaseId, 'preview',
              type: 'preview_v1', bytes: preview, required: false),
        ],
      );

      final result =
          await installer().ensureInstalled(s, releaseChecksum: checksum);
      expect(result.status, MotionPackageStatus.installed);
      expect(result.runnable, isTrue);

      const store = MotionPackageStore();
      final record = await store.read('reach_taps', releaseId);
      expect(record, isNotNull);
      expect(record!.assets, hasLength(2));
      expect(record.releaseChecksum, checksum);
      expect(
        await store.assetBytes('reach_taps', releaseId, 'preview'),
        preview,
      );
    });

    test('spec-only releases need no download', () async {
      final s = spec(releaseId: 'rel-spec-only');
      final result =
          await installer().ensureInstalled(s, releaseChecksum: checksum);
      expect(result.status, MotionPackageStatus.specOnly);
      expect(result.runnable, isTrue);
    });

    test('bad checksum on a required asset refuses the package', () async {
      final releaseId = 'rel-bad-sha';
      network[assetUrl(releaseId, 'engine')] = utf8.encode('{"tampered":true}');
      // Manifest declares the checksum of the REAL bytes.
      final s = spec(
        releaseId: releaseId,
        assets: [
          assetJson(releaseId, 'engine',
              type: 'motion_v2_spec_v1', bytes: specBytes()),
        ],
      );
      final result =
          await installer().ensureInstalled(s, releaseChecksum: checksum);
      expect(result.status, MotionPackageStatus.integrityFailed);
      expect(result.failureReason, 'checksum_mismatch');
      expect(
        await const MotionPackageStore().read('reach_taps', releaseId),
        isNull,
      );
    });

    test('size mismatch refuses the package', () async {
      final releaseId = 'rel-bad-size';
      final engine = specBytes();
      network[assetUrl(releaseId, 'engine')] = engine;
      final s = spec(
        releaseId: releaseId,
        assets: [
          assetJson(releaseId, 'engine',
              type: 'motion_v2_spec_v1', bytes: engine)..['bytes'] =
              engine.length + 4,
        ],
      );
      final result =
          await installer().ensureInstalled(s, releaseChecksum: checksum);
      expect(result.status, MotionPackageStatus.integrityFailed);
      expect(result.failureReason, 'size_mismatch');
    });

    test('missing required asset blocks install; nothing is promoted',
        () async {
      final releaseId = 'rel-missing';
      // downloader has no bytes for this URL.
      final s = spec(
        releaseId: releaseId,
        assets: [
          assetJson(releaseId, 'engine',
              type: 'motion_v2_spec_v1', bytes: specBytes()),
        ],
      );
      final result =
          await installer().ensureInstalled(s, releaseChecksum: checksum);
      expect(result.status, MotionPackageStatus.missingRequiredAsset);
      expect(
        await const MotionPackageStore().read('reach_taps', releaseId),
        isNull,
      );
    });

    test('optional preview failure never blocks a runnable package', () async {
      final releaseId = 'rel-optional-fail';
      final engine = specBytes();
      network[assetUrl(releaseId, 'engine')] = engine;
      // 'preview' is absent from the network — optional, must not block.
      final s = spec(
        releaseId: releaseId,
        assets: [
          assetJson(releaseId, 'engine',
              type: 'motion_v2_spec_v1', bytes: engine),
          assetJson(releaseId, 'preview',
              type: 'preview_v1', bytes: previewBytes(), required: false),
        ],
      );
      final result =
          await installer().ensureInstalled(s, releaseChecksum: checksum);
      expect(result.status, MotionPackageStatus.installed);
      expect(result.runnable, isTrue);
      final record =
          await const MotionPackageStore().read('reach_taps', releaseId);
      expect(record!.assets.map((a) => a.id), ['engine']);
    });

    test('non-first-party asset URLs are refused before any fetch', () async {
      final releaseId = 'rel-foreign';
      var fetched = 0;
      final inst = MotionPackageInstaller(
        downloader: (url, maxBytes) async {
          fetched++;
          return specBytes();
        },
      );
      final s = spec(
        releaseId: releaseId,
        assets: [
          {
            'id': 'engine',
            'type': 'motion_v2_spec_v1',
            'sha256': sha256Hex(specBytes()),
            'url': 'https://evil.example/$releaseId/engine',
            'bytes': specBytes().length,
            'required': true,
          },
        ],
      );
      final result =
          await inst.ensureInstalled(s, releaseChecksum: checksum);
      expect(result.status, MotionPackageStatus.invalidManifestAsset);
      expect(fetched, 0);
    });

    test('concurrent installs single-flight; repeat calls read the record',
        () async {
      final releaseId = 'rel-idem';
      final engine = specBytes();
      var fetches = 0;
      final inst = MotionPackageInstaller(
        downloader: (url, maxBytes) async {
          fetches++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return network[url];
        },
      );
      network[assetUrl(releaseId, 'engine')] = engine;
      final s = spec(
        releaseId: releaseId,
        assets: [
          assetJson(releaseId, 'engine',
              type: 'motion_v2_spec_v1', bytes: engine),
        ],
      );
      final results = await Future.wait([
        inst.ensureInstalled(s, releaseChecksum: checksum),
        inst.ensureInstalled(s, releaseChecksum: checksum),
      ]);
      expect(fetches, 1);
      expect(results.every((r) => r.status == MotionPackageStatus.installed),
          isTrue);
      final again =
          await inst.ensureInstalled(s, releaseChecksum: checksum);
      expect(again.status, MotionPackageStatus.installed);
      expect(fetches, 1);
    });

    test('an interrupted install leaves no visible package; retry succeeds',
        () async {
      final releaseId = 'rel-interrupted';
      final engine = specBytes();
      var calls = 0;
      final inst = MotionPackageInstaller(
        downloader: (url, maxBytes) async {
          calls++;
          if (calls == 1) throw StateError('network dropped');
          return network[url];
        },
      );
      network[assetUrl(releaseId, 'engine')] = engine;
      final s = spec(
        releaseId: releaseId,
        assets: [
          assetJson(releaseId, 'engine',
              type: 'motion_v2_spec_v1', bytes: engine),
        ],
      );
      final first =
          await inst.ensureInstalled(s, releaseChecksum: checksum);
      expect(first.status, MotionPackageStatus.missingRequiredAsset);
      expect(
        await const MotionPackageStore().read('reach_taps', releaseId),
        isNull,
      );
      final second =
          await inst.ensureInstalled(s, releaseChecksum: checksum);
      expect(second.status, MotionPackageStatus.installed);
    });
  });

  group('update + pin protection', () {
    test('old package survives a failed update — last-known-good', () async {
      const store = MotionPackageStore();
      final inst = installer();
      final engine = specBytes();
      // v1 installs cleanly.
      const v1 = 'reach_taps-2026.10.0';
      network[assetUrl(v1, 'engine')] = engine;
      final s1 = spec(
        releaseId: v1,
        assets: [
          assetJson(v1, 'engine', type: 'motion_v2_spec_v1', bytes: engine),
        ],
      );
      expect(
        (await inst.ensureInstalled(s1, releaseChecksum: checksum)).status,
        MotionPackageStatus.installed,
      );

      // v2 is published; its bytes fail integrity.
      const v2 = 'reach_taps-2026.10.1';
      network[assetUrl(v2, 'engine')] = utf8.encode('{"tampered":1}');
      final s2 = spec(
        releaseId: v2,
        assets: [
          assetJson(v2, 'engine', type: 'motion_v2_spec_v1', bytes: engine),
        ],
      );
      expect(
        (await inst.ensureInstalled(s2, releaseChecksum: checksum)).status,
        MotionPackageStatus.integrityFailed,
      );

      // The verified v1 package is still on disk and still installs cleanly.
      expect(await store.read('reach_taps', v1), isNotNull);
      final again = await inst.ensureInstalled(s1, releaseChecksum: checksum);
      expect(again.status, MotionPackageStatus.installed);
      expect(await store.read('reach_taps', v2), isNull);
    });

    test('a pinned release is never evicted by pruning', () async {
      const store = MotionPackageStore();
      var nowMs = 0;
      final inst = MotionPackageInstaller(
        downloader: (url, maxBytes) async => network[url],
        nowMs: () => nowMs,
      );
      final engine = specBytes();

      Future<void> installRelease(String id, int atMs) async {
        nowMs = atMs;
        network[assetUrl(id, 'engine')] = engine;
        final s = spec(
          releaseId: id,
          assets: [
            assetJson(id, 'engine', type: 'motion_v2_spec_v1', bytes: engine),
          ],
        );
        final result =
            await inst.ensureInstalled(s, releaseChecksum: checksum);
        expect(result.status, MotionPackageStatus.installed);
      }

      // Install four releases for one activity; cap keeps newest 2, but the
      // pinned one — however old — must survive while the oldest UNPINNED is
      // evicted.
      const oldest = 'reach_taps-2026.10.0';
      inst.pin(oldest); // simulates an active session on the oldest release
      await installRelease(oldest, 1);
      await installRelease('reach_taps-2026.10.1', 2);
      await installRelease('reach_taps-2026.10.2', 3);
      await installRelease('reach_taps-2026.10.3', 4);
      await inst.prune();

      expect(await store.read('reach_taps', oldest), isNotNull); // pinned
      expect(
        await store.read('reach_taps', 'reach_taps-2026.10.1'),
        isNull, // evicted: oldest unpinned
      );
      expect(
        await store.read('reach_taps', 'reach_taps-2026.10.2'),
        isNotNull,
      );
      expect(
        await store.read('reach_taps', 'reach_taps-2026.10.3'),
        isNotNull,
      );
    });

    test('stale staging dirs are swept; corrupt records read as absent',
        () async {
      const store = MotionPackageStore();
      final staging = Directory(
        '${root.path}/reach_taps/rel-stale.staging',
      )..createSync(recursive: true);
      File('${staging.path}/manifest.json').writeAsStringSync('{}');
      await store.sweepStaging();
      expect(staging.existsSync(), isFalse);

      // A corrupt promoted manifest reads as absent (fail closed).
      final dir = Directory('${root.path}/reach_taps/rel-corrupt')
        ..createSync(recursive: true);
      File('${dir.path}/manifest.json').writeAsStringSync('{not json');
      expect(await store.read('reach_taps', 'rel-corrupt'), isNull);
    });
  });

  group('capability service', () {
    const service = MotionCapabilityService();

    MotionCatalogActivity catalogEntry({
      String availability = 'supported',
      String? releaseId,
      String? checksumValue,
      String engineType = 'alternating_rep_v1',
      List<String> requiredCapabilities = const [],
      String measurementType = 'repetitions',
    }) =>
        MotionCatalogActivity.fromJson({
          'id': 'reach_taps',
          'displayName': 'Reach Taps',
          'measurementType': measurementType,
          'availability': availability,
          'currentReleaseId': releaseId,
          'currentReleaseChecksum': checksumValue,
          'engineType': engineType,
          'requiredCapabilities': requiredCapabilities,
        });

    VerifierRelease releaseFor(RemoteVerifierSpec s) => VerifierRelease.fromJson({
          'id': s.releaseId,
          'activityId': s.activityId,
          'engineType': 'alternating_rep_v1',
          'specSchemaVersion': 1,
          'spec': specJson(releaseId: s.releaseId),
          'checksum': checksum,
          'requiredCapabilities': [],
          'minimumAppBuild': '1',
        });

    test('spec-only release reports available', () async {
      final s = spec(releaseId: 'rel-cap');
      final release = releaseFor(s);
      final result = await service.check(
        activityId: 'reach_taps',
        catalog: MotionCatalogSnapshot(
          catalogVersion: 'test',
          activities: [
            catalogEntry(releaseId: s.releaseId, checksumValue: checksum),
          ],
        ),
        capabilities: const {'alternating_rep_v1'},
        releases: {s.releaseId: release},
      );
      expect(result.supported, isTrue);
      expect(result.status, MotionCapabilityStatus.available);
      expect(result.engineType, 'alternating_rep_v1');
      expect(result.releaseId, s.releaseId);
    });

    test('packaged release reports installPending then installed', () async {
      const releaseId = 'rel-cap-pkg';
      final engine = specBytes();
      network[assetUrl(releaseId, 'engine')] = engine;
      final s = spec(
        releaseId: releaseId,
        assets: [
          assetJson(releaseId, 'engine',
              type: 'motion_v2_spec_v1', bytes: engine),
        ],
      );
      var result = await service.checkResolvedSpec(s);
      expect(result.status, MotionCapabilityStatus.installPending);
      expect(result.supported, isTrue);
      expect(result.installPending, isTrue);
      expect(result.installed, isFalse);

      await installer().ensureInstalled(s, releaseChecksum: checksum);
      result = await service.checkResolvedSpec(s);
      expect(result.status, MotionCapabilityStatus.installed);
      expect(result.installed, isTrue);
    });

    test('unsupported capability requirement reports incompatibleRuntime',
        () async {
      final release = releaseFor(spec(releaseId: 'rel-incompat'));
      final result = await service.check(
        activityId: 'reach_taps',
        catalog: MotionCatalogSnapshot(
          catalogVersion: 'test',
          activities: [
            catalogEntry(
              releaseId: release.id,
              checksumValue: checksum,
              requiredCapabilities: const ['holographic_tracking_v9'],
            ),
          ],
        ),
        capabilities: const {'alternating_rep_v1'},
        releases: {release.id: release},
      );
      expect(result.supported, isFalse);
      expect(result.status, MotionCapabilityStatus.incompatibleRuntime);
      expect(result.reason, 'missing_capability');
    });

    test('disabled catalog entry reports disabled, never unresolved-missing',
        () async {
      final result = await service.check(
        activityId: 'reach_taps',
        catalog: MotionCatalogSnapshot(
          catalogVersion: 'test',
          activities: [catalogEntry(availability: 'disabled')],
        ),
        capabilities: const {},
        releases: const {},
      );
      expect(result.status, MotionCapabilityStatus.disabled);
      expect(result.supported, isFalse);
    });

    test('unknown remote activity ID survives end-to-end verbatim', () async {
      const exotic = 'brand_new_motion_2040';
      final s = spec(releaseId: 'rel-exotic', activityId: exotic);
      final result = await service.checkResolvedSpec(s);
      expect(result.activityId, exotic); // never normalized, never guessed
      expect(result.status, MotionCapabilityStatus.available);
    });
  });

  group('identity — remote activity never becomes pushups', () {
    test('resolver maps an unknown packaged activity to remote, not pushups',
        () {
      final race = Race.fromJson({
        'id': 'race-1',
        'creatorId': 'u1',
        'title': 'Reach taps race',
        'activityId': 'brand_new_motion_2040',
        'aiActivityType': 'brand_new_motion_2040',
        'proofMode': 'ai_check',
        'status': 'active',
        'verifierReleaseId': 'rel-exotic',
        'verifierSpec': specJson(
          releaseId: 'rel-exotic',
          activityId: 'brand_new_motion_2040',
          assets: [
            assetJson('rel-exotic', 'engine',
                type: 'motion_v2_spec_v1', bytes: specBytes()),
          ],
        )..['activity'] = {'displayName': 'Future Motion'},
        'createdAt': '',
        'updatedAt': '',
      });
      final eligibility = resolveCameraVerification(race);
      expect(eligibility.isCameraVerifiable, isTrue);
      expect(eligibility.movementType, MotionActivityType.remote);
      expect(
        eligibility.movementType,
        isNot(MotionActivityType.pushUps),
      );
      expect(
        eligibility.remoteVerifierSpec?.activityId,
        'brand_new_motion_2040',
      );
    });

    test('bad schema fails closed — unknown engine and malformed package',
        () {
      expect(
        () => RemoteVerifierSpec.fromJson(
          specJson(releaseId: 'x')..['engineType'] = 'quantum_v9',
        ),
        throwsA(isA<RemoteVerifierSpecException>()),
      );
      expect(
        () => RemoteVerifierSpec.fromJson({
          ...specJson(releaseId: 'x'),
          'package': {'assets': 'not-a-list'},
        }),
        throwsA(isA<RemoteVerifierSpecException>()),
      );
    });
  });
}
