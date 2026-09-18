import '../ai/remote_verifier_spec.dart';
import '../ai/object_composition_spec.dart';

/// An immutable verifier release fetched from the Worker control plane.
///
/// Native releases are metadata-only references to an allowlisted validator
/// already shipped in the app. Remote releases contain a bounded declarative
/// spec that the installed generic runtime can execute.
class VerifierRelease {
  const VerifierRelease({
    required this.id,
    required this.activityId,
    required this.engineType,
    required this.specSchemaVersion,
    required this.spec,
    required this.checksum,
    required this.requiredCapabilities,
    required this.minimumAppBuild,
  });

  factory VerifierRelease.fromJson(Map<String, dynamic> json) {
    final rawSpec = json['spec'];
    if (rawSpec is! Map) {
      throw const FormatException('Verifier release spec is missing.');
    }
    final spec = Map<String, dynamic>.from(rawSpec);
    final id = _required(json['id'], 'id');
    final activityId = _required(json['activityId'], 'activityId');
    final engineType = _required(json['engineType'], 'engineType');
    final checksum = _required(json['checksum'], 'checksum');
    final specReleaseId = spec['releaseId'];
    final specActivityId = spec['activityId'];
    if (specReleaseId != id || specActivityId != activityId) {
      throw const FormatException('Verifier release identity mismatch.');
    }
    if (spec['engineType'] != engineType) {
      throw const FormatException('Verifier release engine mismatch.');
    }
    if (engineType == 'native_v1') {
      final nativeKey = spec['nativeValidatorKey'];
      if (nativeKey is! String || nativeKey.trim().isEmpty) {
        throw const FormatException('Native verifier key is missing.');
      }
    } else if (engineType == 'object_composition_v1') {
      ObjectCompositionSpec.fromJson(spec);
    } else {
      // Strictly parse remote specs here so a cached release is never more
      // permissive than a freshly negotiated session.
      RemoteVerifierSpec.fromJson(spec);
    }
    return VerifierRelease(
      id: id,
      activityId: activityId,
      engineType: engineType,
      specSchemaVersion: _positiveInt(json['specSchemaVersion']),
      spec: spec,
      checksum: checksum,
      requiredCapabilities: _strings(json['requiredCapabilities']),
      minimumAppBuild: _required(json['minimumAppBuild'], 'minimumAppBuild'),
    );
  }

  final String id;
  final String activityId;
  final String engineType;
  final int specSchemaVersion;
  final Map<String, dynamic> spec;
  final String checksum;
  final List<String> requiredCapabilities;
  final String minimumAppBuild;

  Map<String, dynamic> toJson() => {
    'id': id,
    'activityId': activityId,
    'engineType': engineType,
    'specSchemaVersion': specSchemaVersion,
    'spec': spec,
    'checksum': checksum,
    'requiredCapabilities': requiredCapabilities,
    'minimumAppBuild': minimumAppBuild,
  };

  static String _required(Object? value, String name) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    throw FormatException('Verifier release $name is missing.');
  }

  static int _positiveInt(Object? value) {
    if (value is int && value > 0) return value;
    throw const FormatException('Verifier release schema version is invalid.');
  }

  static List<String> _strings(Object? value) {
    if (value is! List) {
      throw const FormatException('Verifier release capabilities are invalid.');
    }
    final values = value
        .whereType<String>()
        .map((item) => item.trim())
        .toList();
    if (values.length != value.length || values.any((item) => item.isEmpty)) {
      throw const FormatException('Verifier release capabilities are invalid.');
    }
    return List.unmodifiable(values);
  }
}
