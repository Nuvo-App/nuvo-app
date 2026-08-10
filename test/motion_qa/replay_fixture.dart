import 'dart:convert';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

/// A single recorded pose frame in compact JSON form.
///
/// Each landmark is [x, y, z, likelihood] — normalized to [0,1] for x/y.
class RecordedLandmark {
  const RecordedLandmark(this.x, this.y, this.z, this.likelihood);

  final double x;
  final double y;
  final double z;
  final double likelihood;

  List<double> toJson() => [x, y, z, likelihood];

  static RecordedLandmark fromJson(List<dynamic> json) => RecordedLandmark(
        (json[0] as num).toDouble(),
        (json[1] as num).toDouble(),
        (json[2] as num).toDouble(),
        (json[3] as num).toDouble(),
      );
}

/// A single frame in a replay fixture.
class RecordedFrame {
  const RecordedFrame({
    required this.landmarks,
    required this.frameIndex,
    this.imageWidth = 1080,
    this.imageHeight = 1920,
    this.elapsedMs,
  });

  final Map<String, RecordedLandmark> landmarks;
  final int frameIndex;
  final double imageWidth;
  final double imageHeight;
  final int? elapsedMs;

  Map<String, dynamic> toJson() => {
        'landmarks': {
          for (final e in landmarks.entries) e.key: e.value.toJson(),
        },
        'frameIndex': frameIndex,
        'imageWidth': imageWidth,
        'imageHeight': imageHeight,
        if (elapsedMs != null) 'elapsedMs': elapsedMs,
      };

  static RecordedFrame fromJson(Map<String, dynamic> json) {
    final raw = json['landmarks'] as Map<String, dynamic>;
    final landmarks = <String, RecordedLandmark>{};
    for (final e in raw.entries) {
      landmarks[e.key] = RecordedLandmark.fromJson(e.value as List<dynamic>);
    }
    return RecordedFrame(
      landmarks: landmarks,
      frameIndex: json['frameIndex'] as int,
      imageWidth: (json['imageWidth'] as num?)?.toDouble() ?? 1080,
      imageHeight: (json['imageHeight'] as num?)?.toDouble() ?? 1920,
      elapsedMs: json['elapsedMs'] as int?,
    );
  }

  /// Converts to NuvoPoseFrame for replay through production validators.
  NuvoPoseFrame toPoseFrame() {
    final points = <String, NuvoPosePoint>{};
    for (final e in landmarks.entries) {
      points[e.key] = NuvoPosePoint(
        x: e.value.x,
        y: e.value.y,
        z: e.value.z,
        likelihood: e.value.likelihood,
      );
    }
    return NuvoPoseFrame(
      points: points,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      createdAt: DateTime.now(),
    );
  }
}

/// Source metadata for a fixture.
class FixtureSource {
  const FixtureSource({
    required this.type,
    required this.name,
    this.license,
    this.reference,
    this.extractor,
    this.cameraView,
    this.qualityTier,
  });

  final String type; // 'synthetic', 'public_dataset', 'recorded'
  final String name;
  final String? license;
  final String? reference;
  final String? extractor;
  final String? cameraView;
  final String? qualityTier;

  Map<String, dynamic> toJson() => {
        'type': type,
        'name': name,
        if (license != null) 'license': license,
        if (reference != null) 'reference': reference,
        if (extractor != null) 'extractor': extractor,
        if (cameraView != null) 'cameraView': cameraView,
        if (qualityTier != null) 'qualityTier': qualityTier,
      };

  static FixtureSource fromJson(Map<String, dynamic> json) => FixtureSource(
        type: json['type'] as String,
        name: json['name'] as String,
        license: json['license'] as String?,
        reference: json['reference'] as String?,
        extractor: json['extractor'] as String?,
        cameraView: json['cameraView'] as String?,
        qualityTier: json['qualityTier'] as String?,
      );
}

/// Expected outcome for a fixture.
class FixtureExpected {
  const FixtureExpected({
    required this.reps,
    required this.shouldMatch,
  });

  final int reps;
  final bool shouldMatch;

  Map<String, dynamic> toJson() => {
        'reps': reps,
        'shouldMatch': shouldMatch,
      };

  static FixtureExpected fromJson(Map<String, dynamic> json) => FixtureExpected(
        reps: json['reps'] as int,
        shouldMatch: json['shouldMatch'] as bool,
      );
}

/// A complete replay fixture — a recorded pose sequence with metadata.
class ReplayFixture {
  const ReplayFixture({
    required this.id,
    required this.movement,
    required this.expected,
    required this.source,
    required this.frames,
    this.label,
    this.tags = const [],
  });

  final String id;
  final String movement;
  final FixtureExpected expected;
  final FixtureSource source;
  final List<RecordedFrame> frames;
  final String? label;
  final List<String> tags;

  Map<String, dynamic> toJson() => {
        'id': id,
        'movement': movement,
        'expected': expected.toJson(),
        'source': source.toJson(),
        'frames': frames.map((f) => f.toJson()).toList(),
        if (label != null) 'label': label,
        'tags': tags,
      };

  static ReplayFixture fromJson(Map<String, dynamic> json) => ReplayFixture(
        id: json['id'] as String,
        movement: json['movement'] as String,
        expected: FixtureExpected.fromJson(
            json['expected'] as Map<String, dynamic>),
        source: FixtureSource.fromJson(
            json['source'] as Map<String, dynamic>),
        frames: (json['frames'] as List<dynamic>)
            .map((f) => RecordedFrame.fromJson(f as Map<String, dynamic>))
            .toList(),
        label: json['label'] as String?,
        tags: (json['tags'] as List<dynamic>?)
                ?.map((t) => t as String)
                .toList() ??
            const [],
      );

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  static ReplayFixture fromJsonString(String json) =>
      ReplayFixture.fromJson(jsonDecode(json) as Map<String, dynamic>);
}
