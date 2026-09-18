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

  factory MotionCatalogActivity.fromJson(Map<String, dynamic> json) {
    final rawTargets = json['suggestedTargets'];
    final rawFormats = json['supportedFormats'];
    return MotionCatalogActivity(
      id: _requiredString(json['id']),
      displayName: _requiredString(json['displayName']),
      category: _requiredString(json['category'], fallback: 'full_body'),
      proofLabel: _requiredString(json['proofLabel']),
      measurementType: _requiredString(json['measurementType'], fallback: 'repetitions'),
      metric: _requiredString(json['metric'], fallback: 'reps'),
      suggestedTargets: rawTargets is List
          ? rawTargets.whereType<num>().map((value) => value.toInt()).where((value) => value > 0).take(16).toList()
          : const [],
      supportedFormats: rawFormats is List
          ? rawFormats.whereType<String>().take(8).toList()
          : const [],
      iconKey: _requiredString(json['iconKey'], fallback: 'fitness_center'),
      availability: _requiredString(json['availability'], fallback: 'supported'),
      releaseId: json['currentReleaseId'] as String? ?? json['releaseId'] as String?,
      releaseChecksum: json['currentReleaseChecksum'] as String? ?? json['releaseChecksum'] as String?,
      requiredCapabilities: json['requiredCapabilities'] is List
          ? (json['requiredCapabilities'] as List).whereType<String>().toList()
          : const [],
      minimumAppBuild: json['minimumAppBuild'] as String?,
      engineType: json['engineType'] as String?,
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
      };

  /// An unknown activity is displayable only when the release advertises a
  /// client capability the current build actually owns. Unknown engines are
  /// intentionally excluded; the client must never guess a verifier.
  bool isCompatibleWith(Set<String> capabilities) =>
      availability == 'supported' &&
      const {'native_v1', 'state_machine_v1', 'alternating_rep_v1', 'hold_v1'}
          .contains(engineType) &&
      releaseId != null &&
      releaseChecksum != null &&
      engineType != null &&
      requiredCapabilities.every(capabilities.contains);

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
    return MotionActivityDefinition(
      type: MotionActivityType.remote,
      backendId: id,
      title: displayName,
      metric: metricValue,
      suggestedTargets: suggestedTargets.isEmpty ? const [1] : suggestedTargets,
      supportedFormats: formats.isEmpty ? const [RaceFormat.firstToGoal] : formats,
      aliases: [displayName.toLowerCase()],
      proofLabel: proofLabel,
      cameraInstruction: 'Follow the on-screen framing guide.',
      instructions: const ['Keep the required body regions visible.', 'Move at a steady pace.', 'Finish each rep cleanly.'],
      icon: _iconFor(iconKey),
      framingLabel: 'Follow the release framing guide',
      preferredCameraView: PreferredCameraView.frontPreferred,
      category: _categoryFor(category),
      isHold: measurement == MotionMeasurementType.duration,
      featured: false,
      sortPriority: 100,
      measurementType: measurement,
      releaseId: releaseId,
      releaseChecksum: releaseChecksum,
      engineType: engineType,
      requiredCapabilities: requiredCapabilities,
    );
  }

  static String _requiredString(Object? value, {String fallback = ''}) =>
      value is String && value.trim().isNotEmpty ? value.trim() : fallback;

  static RaceFormat? _raceFormatFor(String value) => RaceFormat.values.where((format) => format.backendValue == value).firstOrNull;

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

  factory MotionCatalogSnapshot.fromJson(Map<String, dynamic> json, {String? etag, bool fromCache = false}) {
    final raw = json['activities'];
    if (raw is! List) throw const FormatException('Catalog activities are missing.');
    final activities = raw.whereType<Map<String, dynamic>>().map(MotionCatalogActivity.fromJson).toList();
    if (activities.isEmpty) throw const FormatException('Catalog contains no activities.');
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

  List<MotionActivityDefinition> toDefinitions(Set<String> capabilities) {
    final definitions = [...motionActivityDefinitions];
    for (final activity in activities) {
      if (motionActivityForBackendValue(activity.id) != null) continue;
      final definition = activity.toDefinition(capabilities);
      if (definition != null) definitions.add(definition);
    }
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
              supportedFormats: activity.supportedFormats.map((format) => format.backendValue).toList(),
              iconKey: activity.icon.codePoint.toString(),
              availability: 'supported',
              releaseId: null,
              releaseChecksum: null,
              requiredCapabilities: const [],
              minimumAppBuild: null,
              engineType: 'native_v1',
            ),
        ],
      );
}
