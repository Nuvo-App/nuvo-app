import 'dart:math' as math;
import 'replay_fixture.dart';

/// Generates augmented variants of a base fixture for robustness testing.
///
/// TECH DEBT: This is rough internal tooling. Variants are simple but
/// sufficient for stress-testing tolerance.
class FixtureAugmenter {
  FixtureAugmenter({int? seed}) : _rng = math.Random(seed);

  final math.Random _rng;

  /// Generates all standard variants of a base fixture.
  List<ReplayFixture> generateVariants(ReplayFixture base) {
    return [
      _dropFrames(base),
      _duplicateFrames(base),
      _timeStretch(base),
      _timeCompress(base),
      _coordinateJitter(base),
      _confidenceDegradation(base),
      _ankleDropout(base),
      _bodyTranslation(base),
      _scaleChange(base),
      _mirror(base),
    ];
  }

  /// Drops ~10% of frames randomly.
  ReplayFixture _dropFrames(ReplayFixture base) {
    final frames = <RecordedFrame>[];
    for (final f in base.frames) {
      if (_rng.nextDouble() > 0.10) {
        frames.add(f);
      }
    }
    return _variant(base, 'drop_frames', frames);
  }

  /// Duplicates ~10% of frames.
  ReplayFixture _duplicateFrames(ReplayFixture base) {
    final frames = <RecordedFrame>[];
    for (final f in base.frames) {
      frames.add(f);
      if (_rng.nextDouble() < 0.10) {
        frames.add(f);
      }
    }
    return _variant(base, 'duplicate_frames', frames);
  }

  /// Time stretch: inserts interpolated frames (~1.5x duration).
  ReplayFixture _timeStretch(ReplayFixture base) {
    final frames = <RecordedFrame>[];
    for (var i = 0; i < base.frames.length; i++) {
      frames.add(base.frames[i]);
      if (i + 1 < base.frames.length && _rng.nextDouble() < 0.5) {
        frames.add(_interpolate(base.frames[i], base.frames[i + 1]));
      }
    }
    return _variant(base, 'time_stretch', frames);
  }

  /// Time compress: drops every 3rd frame.
  ReplayFixture _timeCompress(ReplayFixture base) {
    final frames = <RecordedFrame>[];
    for (var i = 0; i < base.frames.length; i++) {
      if (i % 3 != 2) {
        frames.add(base.frames[i]);
      }
    }
    return _variant(base, 'time_compress', frames);
  }

  /// Adds ±0.01 jitter to all landmark coordinates.
  ReplayFixture _coordinateJitter(ReplayFixture base) {
    final frames = base.frames.map((f) {
      final landmarks = <String, RecordedLandmark>{};
      for (final e in f.landmarks.entries) {
        final jx = (_rng.nextDouble() - 0.5) * 0.02;
        final jy = (_rng.nextDouble() - 0.5) * 0.02;
        landmarks[e.key] = RecordedLandmark(
          (e.value.x + jx).clamp(0.0, 1.0),
          (e.value.y + jy).clamp(0.0, 1.0),
          e.value.z,
          e.value.likelihood,
        );
      }
      return RecordedFrame(
        landmarks: landmarks,
        frameIndex: f.frameIndex,
        imageWidth: f.imageWidth,
        imageHeight: f.imageHeight,
      );
    }).toList();
    return _variant(base, 'coordinate_jitter', frames);
  }

  /// Reduces all landmark likelihoods by 0.15.
  ReplayFixture _confidenceDegradation(ReplayFixture base) {
    final frames = base.frames.map((f) {
      final landmarks = <String, RecordedLandmark>{};
      for (final e in f.landmarks.entries) {
        landmarks[e.key] = RecordedLandmark(
          e.value.x,
          e.value.y,
          e.value.z,
          (e.value.likelihood - 0.15).clamp(0.0, 1.0),
        );
      }
      return RecordedFrame(
        landmarks: landmarks,
        frameIndex: f.frameIndex,
        imageWidth: f.imageWidth,
        imageHeight: f.imageHeight,
      );
    }).toList();
    return _variant(base, 'confidence_degradation', frames);
  }

  /// Drops ankle landmarks in ~8% of frames.
  ReplayFixture _ankleDropout(ReplayFixture base) {
    final frames = base.frames.map((f) {
      if (_rng.nextDouble() < 0.08) {
        final landmarks = Map<String, RecordedLandmark>.from(f.landmarks);
        landmarks.remove('leftAnkle');
        landmarks.remove('rightAnkle');
        return RecordedFrame(
          landmarks: landmarks,
          frameIndex: f.frameIndex,
          imageWidth: f.imageWidth,
          imageHeight: f.imageHeight,
        );
      }
      return f;
    }).toList();
    return _variant(base, 'ankle_dropout', frames);
  }

  /// Shifts all coordinates by a small random amount.
  ReplayFixture _bodyTranslation(ReplayFixture base) {
    final dx = (_rng.nextDouble() - 0.5) * 0.04;
    final dy = (_rng.nextDouble() - 0.5) * 0.04;
    final frames = base.frames.map((f) {
      final landmarks = <String, RecordedLandmark>{};
      for (final e in f.landmarks.entries) {
        landmarks[e.key] = RecordedLandmark(
          (e.value.x + dx).clamp(0.0, 1.0),
          (e.value.y + dy).clamp(0.0, 1.0),
          e.value.z,
          e.value.likelihood,
        );
      }
      return RecordedFrame(
        landmarks: landmarks,
        frameIndex: f.frameIndex,
        imageWidth: f.imageWidth,
        imageHeight: f.imageHeight,
      );
    }).toList();
    return _variant(base, 'body_translation', frames);
  }

  /// Scales all coordinates by ~1.05x from center.
  ReplayFixture _scaleChange(ReplayFixture base) {
    const scale = 1.05;
    const cx = 0.5;
    const cy = 0.5;
    final frames = base.frames.map((f) {
      final landmarks = <String, RecordedLandmark>{};
      for (final e in f.landmarks.entries) {
        landmarks[e.key] = RecordedLandmark(
          ((e.value.x - cx) * scale + cx).clamp(0.0, 1.0),
          ((e.value.y - cy) * scale + cy).clamp(0.0, 1.0),
          e.value.z,
          e.value.likelihood,
        );
      }
      return RecordedFrame(
        landmarks: landmarks,
        frameIndex: f.frameIndex,
        imageWidth: f.imageWidth,
        imageHeight: f.imageHeight,
      );
    }).toList();
    return _variant(base, 'scale_change', frames);
  }

  /// Mirrors left/right landmarks.
  ReplayFixture _mirror(ReplayFixture base) {
    final frames = base.frames.map((f) {
      final landmarks = <String, RecordedLandmark>{};
      for (final e in f.landmarks.entries) {
        final key = _mirrorKey(e.key);
        landmarks[key] = RecordedLandmark(
          1.0 - e.value.x,
          e.value.y,
          e.value.z,
          e.value.likelihood,
        );
      }
      return RecordedFrame(
        landmarks: landmarks,
        frameIndex: f.frameIndex,
        imageWidth: f.imageWidth,
        imageHeight: f.imageHeight,
      );
    }).toList();
    return _variant(base, 'mirror', frames);
  }

  String _mirrorKey(String key) {
    if (key.startsWith('left')) return 'right${key.substring(4)}';
    if (key.startsWith('right')) return 'left${key.substring(5)}';
    return key;
  }

  RecordedFrame _interpolate(RecordedFrame a, RecordedFrame b) {
    final landmarks = <String, RecordedLandmark>{};
    for (final key in a.landmarks.keys) {
      final la = a.landmarks[key]!;
      final lb = b.landmarks[key];
      if (lb == null) {
        landmarks[key] = la;
      } else {
        landmarks[key] = RecordedLandmark(
          (la.x + lb.x) / 2,
          (la.y + lb.y) / 2,
          (la.z + lb.z) / 2,
          (la.likelihood + lb.likelihood) / 2,
        );
      }
    }
    return RecordedFrame(
      landmarks: landmarks,
      frameIndex: a.frameIndex,
      imageWidth: a.imageWidth,
      imageHeight: a.imageHeight,
    );
  }

  ReplayFixture _variant(
    ReplayFixture base,
    String variantName,
    List<RecordedFrame> frames,
  ) {
    return ReplayFixture(
      id: '${base.id}__$variantName',
      movement: base.movement,
      expected: base.expected,
      source: FixtureSource(
        type: 'augmented',
        name: '${base.source.name}__$variantName',
        license: base.source.license,
        reference: base.source.reference,
        extractor: base.source.extractor,
        cameraView: base.source.cameraView,
        qualityTier: base.source.qualityTier,
      ),
      frames: frames,
      label: '${base.label ?? base.id} ($variantName)',
      tags: [...base.tags, 'augmented', variantName],
    );
  }
}
