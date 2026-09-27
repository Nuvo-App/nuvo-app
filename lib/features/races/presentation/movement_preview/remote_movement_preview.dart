import 'rive_movement_sequences.dart';
import 'rive_pose_frame.dart';
import 'side_rig_movement_sequences.dart';
import 'side_rig_treadmill_preview.dart';

/// A pre-verify preview animation defined entirely by data fetched from the
/// Worker catalog (`motion_activities.metadata_json.previewSequence`) instead
/// of compiled Dart. Publishing a new spec for an activity changes or adds
/// its animated preview for every installed app on its next catalog fetch —
/// no app update needed.
///
/// This is strictly decorative: the camera verifier never reads this data,
/// so a malformed or missing spec only ever degrades the preview, never
/// verification. See [RemoteFrontKeyframeSequence.tryParse] /
/// [RemoteSideKeyframeSequence.tryParse] for the fail-safe entry points.
class RemotePreviewSpec {
  const RemotePreviewSpec({
    required this.rig,
    required this.durationMs,
    required this.keyframes,
  });

  /// 'front' (drives [RivePoseFrame] via [RiveMovementSequence]) or 'side'
  /// (drives [SideRigPose] via [SideRigMovementSequence]).
  final String rig;
  final int durationMs;
  final List<Map<String, dynamic>> keyframes;

  static RemotePreviewSpec? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final rig = raw['rig'];
    final durationMs = raw['durationMs'];
    final keyframes = raw['keyframes'];
    if (rig is! String || (rig != 'front' && rig != 'side')) return null;
    if (durationMs is! num || durationMs <= 0) return null;
    if (keyframes is! List || keyframes.length < 2) return null;
    final parsedKeyframes = keyframes.whereType<Map>().toList();
    if (parsedKeyframes.length != keyframes.length) return null;
    return RemotePreviewSpec(
      rig: rig,
      durationMs: durationMs.round(),
      keyframes: parsedKeyframes
          .map((k) => Map<String, dynamic>.from(k))
          .toList(),
    );
  }
}

double _smoothstepLocal(double t) {
  final amount = t.clamp(0.0, 1.0);
  return amount * amount * (3 - 2 * amount);
}

/// Generic looping keyframe interpolator for the front-facing rig, built
/// entirely from a [RemotePreviewSpec] — no per-movement Dart code needed.
class RemoteFrontKeyframeSequence extends RiveMovementSequence {
  RemoteFrontKeyframeSequence._(this.keyframes, {required super.duration});

  final List<RivePoseFrame> keyframes;

  /// Returns null (never throws) if [spec] isn't a valid front-rig spec —
  /// callers should fall back to the bundled compiled sequence in that case.
  static RemoteFrontKeyframeSequence? tryParse(RemotePreviewSpec? spec) {
    if (spec == null || spec.rig != 'front') return null;
    try {
      final frames = spec.keyframes
          .map(RivePoseFrame.fromJson)
          .toList(growable: false);
      return RemoteFrontKeyframeSequence._(
        frames,
        duration: Duration(milliseconds: spec.durationMs),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  RivePoseFrame poseAt(double normalizedTime) {
    final t = normalizedTime.isFinite
        ? normalizedTime - normalizedTime.floorToDouble()
        : 0.0;
    final segments = keyframes.length - 1;
    final scaled = t * segments;
    final index = scaled.floor().clamp(0, segments - 1);
    final local = _smoothstepLocal(scaled - index);
    return keyframes[index].lerp(keyframes[index + 1], local);
  }
}

/// Generic looping keyframe interpolator for the side-view rig, built
/// entirely from a [RemotePreviewSpec] — no per-movement Dart code needed.
class RemoteSideKeyframeSequence extends SideRigMovementSequence {
  const RemoteSideKeyframeSequence._(
    this.keyframes, {
    required super.duration,
  });

  final List<SideRigPose> keyframes;

  /// Returns null (never throws) if [spec] isn't a valid side-rig spec —
  /// callers should fall back to the bundled compiled sequence in that case.
  static RemoteSideKeyframeSequence? tryParse(RemotePreviewSpec? spec) {
    if (spec == null || spec.rig != 'side') return null;
    try {
      final frames = spec.keyframes
          .map(SideRigPose.fromJson)
          .toList(growable: false);
      return RemoteSideKeyframeSequence._(
        frames,
        duration: Duration(milliseconds: spec.durationMs),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  SideRigPose poseAt(double normalizedTime) {
    final t = normalizedTime.isFinite
        ? normalizedTime - normalizedTime.floorToDouble()
        : 0.0;
    final segments = keyframes.length - 1;
    final scaled = t * segments;
    final index = scaled.floor().clamp(0, segments - 1);
    final local = _smoothstepLocal(scaled - index);
    return keyframes[index].lerp(keyframes[index + 1], local);
  }
}
