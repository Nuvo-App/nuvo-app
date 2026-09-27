import 'package:flutter/material.dart';

import '../domain/motion_activity.dart';
import '../domain/motion_activity_catalog.dart';

class MotionCatalogActivity {
  const MotionCatalogActivity({
    required this.id,
    required this.displayName,
    required this.category,
    required this.proofLabel,
    required this.measurementType,
    required this.metric,
    required this.suggestedTargets,
    required this.supportedFormats,
    required this.iconKey,
    required this.availability,
    required this.releaseId,
    required this.releaseChecksum,
    required this.requiredCapabilities,
    required this.minimumAppBuild,
    required this.engineType,
    required this.featured,
    required this.sortPriority,
    this.previewSequence,
    this.instructions = const [],
    this.cameraOrientation,
    this.aliases = const [],
  });

  final String id;
  final String displayName;
  final String category;
  final String proofLabel;
  final String measurementType;
  final String metric;
  final List<int> suggestedTargets;
  final List<String> supportedFormats;
  final String iconKey;
  final String availability;
  final String? releaseId;
  final String? releaseChecksum;
  final List<String> requiredCapabilities;
  final String? minimumAppBuild;
  final String? engineType;
  final bool featured;
  final int sortPriority;

  /// Decorative pre-verify preview animation spec (see
  /// `RemotePreviewSpec.tryParse`). Never consumed by the camera verifier —
  /// absent or invalid falls back to the bundled compiled preview.
  final Map<String, dynamic>? previewSequence;

  /// Server-published setup instructions for activities that have no
  /// compiled definition. Empty → generic remote guidance is used.
  final List<String> instructions;

  /// 'front' | 'side' | 'front_or_angle' camera hint from the registry.
  final String? cameraOrientation;

  /// Server-published search/display aliases.
  final List<String> aliases;

  factory MotionCatalogActivity.fromJson(Map<String, dynamic> json) {
    final rawTargets = json['suggestedTargets'];
    final rawFormats = json['supportedFormats'];
    return MotionCatalogActivity(
      id: _requiredString(json['id']),
      displayName: _requiredString(json['displayName']),
      category: _requiredString(json['category'], fallback: 'full_body'),
      proofLabel: _requiredString(json['proofLabel']),
      measurementType: _requiredString(
        json['measurementType'],
        fallback: 'repetitions',
      ),
      metric: _requiredString(json['metric'], fallback: 'reps'),
      suggestedTargets: rawTargets is List
          ? rawTargets
                .whereType<num>()
                .map((value) => value.toInt())
                .where((value) => value > 0)
                .take(16)
                .toList()
          : const [],
      supportedFormats: rawFormats is List
          ? rawFormats.whereType<String>().take(8).toList()
          : const [],
      iconKey: _requiredString(json['iconKey'], fallback: 'fitness_center'),
      availability: _requiredString(
        json['availability'],
        fallback: 'supported',
      ),
      releaseId:
          json['currentReleaseId'] as String? ?? json['releaseId'] as String?,
      releaseChecksum:
          json['currentReleaseChecksum'] as String? ??
          json['releaseChecksum'] as String?,
      requiredCapabilities: json['requiredCapabilities'] is List
          ? (json['requiredCapabilities'] as List).whereType<String>().toList()
          : const [],
      minimumAppBuild: json['minimumAppBuild'] as String?,
      engineType: json['engineType'] as String?,
      featured: json['featured'] == true || json['featured'] == 1,
      sortPriority: json['sortPriority'] is num
          ? (json['sortPriority'] as num).toInt()
          : 100,
      previewSequence: json['previewSequence'] is Map
          ? Map<String, dynamic>.from(json['previewSequence'] as Map)
          : null,
      instructions: json['instructions'] is List
          ? [
              for (final entry in json['instructions'] as List)
                if (entry is String && entry.trim().isNotEmpty) entry.trim(),
            ]
          : const [],
      cameraOrientation: json['cameraOrientation'] as String?,
      aliases: json['aliases'] is List
          ? [
              for (final entry in json['aliases'] as List)
                if (entry is String && entry.trim().isNotEmpty) entry.trim(),
            ]
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'category': category,
    'proofLabel': proofLabel,
    'measurementType': measurementType,
    'metric': metric,
    'suggestedTargets': suggestedTargets,
    'supportedFormats': supportedFormats,
    'iconKey': iconKey,
    'availability': availability,
    'currentReleaseId': releaseId,
    'currentReleaseChecksum': releaseChecksum,
    'requiredCapabilities': requiredCapabilities,
    'minimumAppBuild': minimumAppBuild,
    'engineType': engineType,
    'featured': featured,
    'sortPriority': sortPriority,
    if (previewSequence != null) 'previewSequence': previewSequence,
  };

  /// An unknown activity is displayable only when the release advertises a
  /// client capability the current build actually owns. Unknown engines are
  /// intentionally excluded; the client must never guess a verifier.
  bool isCompatibleWith(Set<String> capabilities) =>
      availability == 'supported' &&
      const {
        'native_v1',
        'state_machine_v1',
        'alternating_rep_v1',
        'hold_v1',
        'object_composition_v1',
      }.contains(engineType) &&
      releaseId != null &&
      releaseChecksum != null &&
      engineType != null &&
      requiredCapabilities.every(capabilities.contains);

  /// Registry camera hint → camera preference. Unknown/absent values default
  /// to front-preferred, matching the previous generic behavior.
  PreferredCameraView preferredCameraViewFromHint() => switch (
      cameraOrientation) {
    'side' => PreferredCameraView.sideOrDiagonalRequired,
    'front_or_angle' => PreferredCameraView.frontOrSlightAngle,
    _ => PreferredCameraView.frontPreferred,
  };

  MotionActivityDefinition? toDefinition(Set<String> capabilities) {
    if (!isCompatibleWith(capabilities)) return null;
    final metricValue = RaceMetric.fromBackendValue(metric) ?? RaceMetric.reps;
    final measurement = switch (measurementType) {
      'duration' => MotionMeasurementType.duration,
      'distance' => MotionMeasurementType.distance,
      _ => MotionMeasurementType.repetitions,
    };
    final formats = supportedFormats
        .map(_raceFormatFor)
        .whereType<RaceFormat>()
        .toList();
    final type = id == 'basketball_shot'
        ? MotionActivityType.basketballShot
        : MotionActivityType.remote;
    return MotionActivityDefinition(
      type: type,
      backendId: id,
      title: displayName,
      metric: metricValue,
      suggestedTargets: suggestedTargets.isEmpty ? const [1] : suggestedTargets,
      supportedFormats: formats.isEmpty
          ? const [RaceFormat.firstToGoal]
          : formats,
      aliases: [
        displayName.toLowerCase(),
        for (final alias in aliases) alias.toLowerCase(),
      ],
      proofLabel: proofLabel,
      cameraInstruction: switch (preferredCameraViewFromHint()) {
        PreferredCameraView.sideOrDiagonalRequired =>
          'Stand sideways. Keep your full body in frame.',
        PreferredCameraView.frontOrSlightAngle =>
          'Angle your body to the camera. Keep your full body in frame.',
        _ => 'Stand facing the camera. Keep your full body in frame.',
      },
      instructions: instructions.isNotEmpty
          ? instructions
          : const [
              'Keep the required body regions visible.',
              'Move at a steady pace.',
              'Finish each rep cleanly.',
            ],
      icon: _iconFor(iconKey),
      framingLabel: 'Follow the release framing guide',
      preferredCameraView: preferredCameraViewFromHint(),
      category: _categoryFor(category),
      isHold: measurement == MotionMeasurementType.duration,
      featured: featured,
      sortPriority: sortPriority,
      measurementType: measurement,
      releaseId: releaseId,
      releaseChecksum: releaseChecksum,
      engineType: engineType,
      requiredCapabilities: requiredCapabilities,
    );
  }

  static String _requiredString(Object? value, {String fallback = ''}) =>
      value is String && value.trim().isNotEmpty ? value.trim() : fallback;

  static RaceFormat? _raceFormatFor(String value) => RaceFormat.values
      .where((format) => format.backendValue == value)
      .firstOrNull;

  static MovementCategory _categoryFor(String value) => switch (value) {
    'upper_body' => MovementCategory.upperBody,
    'lower_body' => MovementCategory.lowerBody,
    'cardio' => MovementCategory.cardio,
    'core' => MovementCategory.core,
    _ => MovementCategory.fullBody,
  };

  static IconData _iconFor(String value) => switch (value) {
    'accessibility_new' => Icons.accessibility_new_rounded,
    'directions_walk' => Icons.directions_walk_rounded,
    'directions_run' => Icons.directions_run_rounded,
    'person_outline' => Icons.person_outline_rounded,
    'straighten' => Icons.straighten_rounded,
    'sports_gymnastics' => Icons.sports_gymnastics_rounded,
    'terrain' => Icons.terrain_rounded,
    'whatshot' => Icons.whatshot_rounded,
    _ => Icons.fitness_center_rounded,
  };
}

class MotionCatalogSnapshot {
  const MotionCatalogSnapshot({
    required this.catalogVersion,
    required this.activities,
    this.etag,
    this.fromCache = false,
  });

  final String catalogVersion;
  final List<MotionCatalogActivity> activities;
  final String? etag;
  final bool fromCache;

  factory MotionCatalogSnapshot.fromJson(
    Map<String, dynamic> json, {
    String? etag,
    bool fromCache = false,
  }) {
    final raw = json['activities'];
    if (raw is! List)
      throw const FormatException('Catalog activities are missing.');
    final activities = raw
        .whereType<Map<String, dynamic>>()
        .map(MotionCatalogActivity.fromJson)
        .toList();
    if (activities.isEmpty)
      throw const FormatException('Catalog contains no activities.');
    return MotionCatalogSnapshot(
      catalogVersion: json['catalogVersion'] as String? ?? 'remote-unknown',
      activities: activities,
      etag: etag ?? json['etag'] as String?,
      fromCache: fromCache,
    );
  }

  Map<String, dynamic> toJson() => {
    'catalogVersion': catalogVersion,
    'etag': etag,
    'activities': activities.map((activity) => activity.toJson()).toList(),
  };

  /// The decorative pre-verify preview spec published for [activityId], if
  /// any. Never consumed by the camera verifier.
  Map<String, dynamic>? previewSequenceFor(String activityId) {
    for (final activity in activities) {
      if (activity.id == activityId) return activity.previewSequence;
    }
    return null;
  }

  List<MotionActivityDefinition> toDefinitions(Set<String> capabilities) {
    final definitions = <MotionActivityDefinition>[];
    final remoteById = <String, MotionActivityDefinition>{};
    for (final activity in activities) {
      final definition = activity.toDefinition(capabilities);
      if (definition != null) remoteById[activity.id] = definition;
    }
    for (final bundled in motionActivityDefinitions) {
      definitions.add(remoteById.remove(bundled.activityId) ?? bundled);
    }
    // Database-published activities that were not present in the app build
    // are appended only after the known identities have been overlaid.
    definitions.addAll(remoteById.values);
    return definitions;
  }

  static MotionCatalogSnapshot bundled() => MotionCatalogSnapshot(
    catalogVersion: 'bundled',
    activities: [
      for (final activity in motionActivityDefinitions)
        MotionCatalogActivity(
          id: activity.activityId,
          displayName: activity.title,
          category: activity.category.name,
          proofLabel: activity.proofLabel,
          measurementType: activity.resolvedMeasurementType.name,
          metric: activity.metric.backendValue,
          suggestedTargets: activity.suggestedTargets,
          supportedFormats: activity.supportedFormats
              .map((format) => format.backendValue)
              .toList(),
          iconKey: activity.icon.codePoint.toString(),
          availability: 'supported',
          releaseId: null,
          releaseChecksum: null,
          requiredCapabilities: const [],
          minimumAppBuild: null,
          engineType: 'native_v1',
          featured: activity.featured,
          sortPriority: activity.sortPriority,
        ),
    ],
  );
}
