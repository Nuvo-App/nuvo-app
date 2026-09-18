import '../data/ai_motion_models.dart';

/// A detector output, not a video frame. Object interaction remains a dot/data
/// contract: the camera and detector stay on the phone, while this compact
/// representation can be recorded, replayed, and uploaded.
class NuvoObjectDot {
  const NuvoObjectDot({
    required this.id,
    required this.kind,
    required this.x,
    required this.y,
    required this.likelihood,
    this.scale = 0,
  });

  final String id;
  final String kind;
  final double x;
  final double y;
  final double likelihood;
  final double scale;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'x': x,
    'y': y,
    'likelihood': likelihood,
    if (scale > 0) 'scale': scale,
  };

  factory NuvoObjectDot.fromJson(Map<String, dynamic> json) {
    double number(Object? value, String field) {
      if (value is num && value.isFinite) return value.toDouble();
      throw FormatException('Object dot $field is invalid.');
    }

    final id = json['id'];
    final kind = json['kind'];
    if (id is! String || id.trim().isEmpty ||
        kind is! String || kind.trim().isEmpty) {
      throw const FormatException('Object dot identity is invalid.');
    }
    final x = number(json['x'], 'x');
    final y = number(json['y'], 'y');
    final likelihood = number(json['likelihood'], 'likelihood');
    final scale = json['scale'] == null ? 0.0 : number(json['scale'], 'scale').toDouble();
    if ([x, y, likelihood, scale].any((value) => value.isNaN || value.isInfinite) ||
        x < 0 || x > 1 || y < 0 || y > 1 || likelihood < 0 || likelihood > 1 ||
        scale < 0 || scale > 1) {
      throw const FormatException('Object dot values are outside the supported range.');
    }
    return NuvoObjectDot(
      id: id.trim(),
      kind: kind.trim(),
      x: x,
      y: y,
      likelihood: likelihood,
      scale: scale,
    );
  }
}

class NuvoObjectMotionFrame {
  const NuvoObjectMotionFrame({
    required this.pose,
    required this.objects,
    required this.createdAt,
  });

  final NuvoPoseFrame pose;
  final Map<String, NuvoObjectDot> objects;
  final DateTime createdAt;

  NuvoObjectDot? object(String id) => objects[id];

  Map<String, dynamic> toJson() => {
    't': createdAt.toUtc().toIso8601String(),
    'objects': [for (final object in objects.values) object.toJson()],
  };
}
