import 'dart:math' as math;

import 'object_composition_spec.dart';
import 'object_motion_models.dart';

enum ObjectCompositionState { ready, released, ascending, descending, made, missed, unsupported }

class ObjectCompositionUpdate {
  const ObjectCompositionUpdate({
    required this.state,
    required this.count,
    required this.confidence,
    required this.event,
    required this.diagnostic,
  });

  final ObjectCompositionState state;
  final int count;
  final double confidence;
  final String event;
  final String diagnostic;
}

/// Deterministic first object-composition runtime. It consumes human pose and
/// object dots only; it never receives or stores a camera frame.
class BasketballShotRuntime {
  BasketballShotRuntime({required this.spec}) : _state = ObjectCompositionState.ready;

  final ObjectCompositionSpec spec;
  ObjectCompositionState _state;
  DateTime? _releaseAt;
  DateTime? _previousAt;
  double? _previousBallX;
  double? _previousBallY;
  bool _controlled = false;
  int _controlFrames = 0;
  int _count = 0;

  ObjectCompositionState get state => _state;
  int get count => _count;

  ObjectCompositionUpdate update(NuvoObjectMotionFrame frame) {
    final ball = frame.object(spec.ballObjectId);
    final hoop = frame.object(spec.hoopObjectId);
    if (ball == null || hoop == null ||
        ball.likelihood < _likelihood(spec.ballObjectId) ||
        hoop.likelihood < _likelihood(spec.hoopObjectId) ||
        !frame.pose.hasPoints(spec.requiredLandmarks)) {
      return _update('missing_required_dots', 0.0);
    }
    final previousAt = _previousAt;
    final previousX = _previousBallX;
    final previousY = _previousBallY;
    _previousAt = frame.createdAt;
    _previousBallX = ball.x;
    _previousBallY = ball.y;

    final deltaMs = previousAt == null ? 0 : frame.createdAt.difference(previousAt).inMilliseconds;
    final validDelta = deltaMs > 0 && deltaMs <= 1000 && previousX != null && previousY != null;
    final priorY = previousY ?? ball.y;
    final velocityY = validDelta ? (ball.y - priorY) * 1000 / deltaMs : 0.0;
    final upward = velocityY <= -spec.minUpwardVelocity;
    final downward = velocityY >= spec.minDownwardVelocity;
    final nearHand = _nearEitherHand(frame, ball);

    if (_state == ObjectCompositionState.made || _state == ObjectCompositionState.missed) {
      return _update(_state == ObjectCompositionState.made ? 'made_basket' : 'shot_missed', 1.0);
    }
    if (_releaseAt != null && frame.createdAt.difference(_releaseAt!).inMilliseconds > spec.maxShotMs) {
      _state = ObjectCompositionState.missed;
      return _update('shot_timeout', 0.2);
    }

    switch (_state) {
      case ObjectCompositionState.ready:
        if (nearHand) {
          _controlFrames++;
          if (_controlFrames >= spec.stableFrames) {
            _controlled = true;
            return _update('ball_controlled', 0.75);
          }
        } else if (_controlled && upward && _distanceFromHands(frame, ball) >= spec.releaseDistance) {
          _state = ObjectCompositionState.released;
          _releaseAt = frame.createdAt;
          return _update('ball_released', 0.82);
        } else {
          _controlFrames = 0;
        }
        return _update('waiting_for_release', 0.45);
      case ObjectCompositionState.released:
        if (upward) {
          _state = ObjectCompositionState.ascending;
          return _update('ball_ascending', 0.84);
        }
        return _update('tracking_release', 0.65);
      case ObjectCompositionState.ascending:
        if (downward) {
          _state = ObjectCompositionState.descending;
          return _update('ball_descending', 0.86);
        }
        return _update('tracking_arc', 0.8);
      case ObjectCompositionState.descending:
        if (_crossedHoopPlane(previousY, ball.y, hoop.y)) {
          final made = (ball.x - hoop.x).abs() <= spec.madeRadius;
          _state = made ? ObjectCompositionState.made : ObjectCompositionState.missed;
          if (made) _count++;
          return _update(made ? 'ball_through_hoop' : 'shot_missed', made ? 0.94 : 0.7);
        }
        return _update('tracking_descent', 0.82);
      case ObjectCompositionState.unsupported:
        return _update('unsupported', 0);
      case ObjectCompositionState.made:
      case ObjectCompositionState.missed:
        return _update(_state.name, 1);
    }
  }

  double _likelihood(String id) => spec.requiredObjects.firstWhere((entry) => entry.id == id).minLikelihood;

  bool _nearEitherHand(NuvoObjectMotionFrame frame, NuvoObjectDot ball) =>
      _distance(frame.pose.point('leftWrist'), ball) <= spec.controlDistance ||
      _distance(frame.pose.point('rightWrist'), ball) <= spec.controlDistance;

  double _distanceFromHands(NuvoObjectMotionFrame frame, NuvoObjectDot ball) =>
      math.min(_distance(frame.pose.point('leftWrist'), ball), _distance(frame.pose.point('rightWrist'), ball));

  double _distance(Object? hand, NuvoObjectDot ball) {
    if (hand == null) return double.infinity;
    final point = hand as dynamic;
    return math.sqrt(math.pow(point.x - ball.x, 2) + math.pow(point.y - ball.y, 2));
  }

  bool _crossedHoopPlane(double? previousY, double currentY, double hoopY) {
    if (previousY == null) return false;
    final closeEnough = (currentY - hoopY).abs() <= spec.hoopPlaneTolerance ||
        (previousY - hoopY).abs() <= spec.hoopPlaneTolerance;
    return previousY < hoopY && currentY >= hoopY && closeEnough;
  }

  ObjectCompositionUpdate _update(String diagnostic, double confidence) => ObjectCompositionUpdate(
    state: _state,
    count: _count,
    confidence: confidence,
    event: diagnostic,
    diagnostic: diagnostic,
  );
}
