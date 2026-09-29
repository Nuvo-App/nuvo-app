import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' hide Factory;
import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

import '../../domain/motion_activity.dart';
import '../movement_preview/remote_movement_preview.dart';
import '../movement_preview/rive_movement_sequences.dart';
import '../movement_preview/rive_pose_controller.dart';
import '../movement_preview/rive_pose_frame.dart';
import '../movement_preview/side_rig_movement_sequences.dart';
import '../movement_preview/side_rig_treadmill_preview.dart';

const _previewDisplayScale = 1.35;
const _previewVisualCenterOffsetX = -12.0;
const _previewBaseOffsetY = -44.0;
const _sidePreviewDisplayScale = 1.35;
const _sidePreviewVisualCenterOffsetX = 0.0;
const _sidePreviewBaseOffsetY = -16.0;

/// Backward-compatible jumping-jack entry point for existing call sites.
class RiveJumpingJackPreview extends StatelessWidget {
  const RiveJumpingJackPreview({super.key, required this.fallback});

  final Widget fallback;

  @override
  Widget build(BuildContext context) => RiveMovementPreview(
    movement: MotionActivityType.jumpingJacks,
    fallback: fallback,
  );
}

/// Data-bound Rive preview for the supported pre-verification movements.
///
/// This widget is decorative only. The camera screen and its verifier remain
/// the source of truth for accepted repetitions.
class RiveMovementPreview extends StatefulWidget {
  const RiveMovementPreview({
    super.key,
    required this.movement,
    required this.fallback,
    this.remotePreviewJson,
  });

  final MotionActivityType movement;
  final Widget fallback;

  /// Decorative pre-verify preview spec fetched from the motion catalog
  /// (`MotionCatalogActivity.previewSequence`). When present and valid, it
  /// drives the animation instead of the bundled compiled sequence — a new
  /// or changed spec reaches installed apps on their next catalog fetch, no
  /// app update needed. Absent/invalid falls back exactly as before.
  final Map<String, dynamic>? remotePreviewJson;

  static bool supports(
    MotionActivityType movement, {
    Map<String, dynamic>? remotePreviewJson,
  }) =>
      hasRiveMovementPreview(movement) ||
      RemotePreviewSpec.tryParse(remotePreviewJson) != null;

  @override
  State<RiveMovementPreview> createState() => _RiveMovementPreviewState();
}

class _RiveMovementPreviewState extends State<RiveMovementPreview>
    with SingleTickerProviderStateMixin {
  late final RiveMovementSequence? _sequence;
  late final TreadmillRunningSideSequence? _sideSequence;
  late final SideRigMovementSequence? _sideMovementSequence;
  late final bool _usesSideRig;
  late RivePoseFrame _currentFrame;
  late SideRigPose _currentSideFrame;
  late final FileLoader _fileLoader;
  late final DataBind _dataBind;
  late final AnimationController _animation;
  RivePoseController? _poseController;
  SideRigPoseController? _sidePoseController;
  RiveWidgetController? _riveController;

  /// True when the Rive runtime itself can't initialize (missing native
  /// renderer — e.g. `flutter test`, where neither factory can link FFI).
  /// The preview is decorative; the honest degradation is the caller's
  /// [RiveMovementPreview.fallback], not a thrown build exception.
  bool _riveUnavailable = false;

  Factory get _riveFactory => Platform.environment.containsKey('FLUTTER_TEST')
      ? Factory.flutter
      : Factory.rive;

  @override
  void initState() {
    super.initState();
    try {
      _initRive();
    } catch (_) {
      _riveUnavailable = true;
    }
  }

  void _initRive() {
    final remoteSpec = RemotePreviewSpec.tryParse(widget.remotePreviewJson);
    final remoteSide = RemoteSideKeyframeSequence.tryParse(remoteSpec);
    final remoteFront = RemoteFrontKeyframeSequence.tryParse(remoteSpec);
    _usesSideRig = remoteSide != null ||
        (remoteFront == null &&
            (widget.movement == MotionActivityType.treadmillRunning ||
                hasSideRigMovementPreview(widget.movement)));
    _sideSequence =
        remoteSide == null && widget.movement == MotionActivityType.treadmillRunning
        ? TreadmillRunningSideSequence()
        : null;
    _sideMovementSequence = remoteSide ??
        (widget.movement == MotionActivityType.treadmillRunning
            ? null
            : hasSideRigMovementPreview(widget.movement)
            ? sideRigMovementSequenceFor(widget.movement)
            : null);
    _sequence = _usesSideRig
        ? null
        : remoteFront ?? riveMovementSequenceFor(widget.movement);
    _currentFrame = _sequence?.poseAt(0) ?? RivePoseFrame.neutral;
    _currentSideFrame = _usesSideRig ? _sidePoseAt(0) : SideRigPose.base;
    _fileLoader = FileLoader.fromAsset(
      _usesSideRig
          ? 'assets/animations/preverify/nuvo_stickman_side.riv'
          : 'assets/animations/preverify/nuvo_stickman.riv',
      riveFactory: _riveFactory,
    );
    _dataBind = DataBind.auto();
    _animation = AnimationController(
      vsync: this,
      duration: _usesSideRig
          ? _sideSequence != null
              ? TreadmillRunningSideSequence.duration
              : _sideMovementSequence!.duration
          : _sequence!.duration,
    )..addListener(_applyPose);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_riveUnavailable) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.stop();
      _applyStaticPose();
    } else if (!_animation.isAnimating) {
      _animation.repeat();
    }
  }

  void _applyStaticPose() {
    if (_usesSideRig) {
      _currentSideFrame = _sidePoseAt(0.5);
      _sidePoseController?.apply(_currentSideFrame);
      _riveController?.scheduleRepaint();
      return;
    }
    _currentFrame = _sequence!.poseAt(0.5);
    _poseController?.apply(_currentFrame);
    _riveController?.scheduleRepaint();
  }

  void _applyPose() {
    if (_usesSideRig) {
      _currentSideFrame = _sidePoseAt(_animation.value);
      final controller = _sidePoseController;
      if (controller == null) return;
      controller.apply(_currentSideFrame);
      _riveController?.scheduleRepaint();
      return;
    }
    _currentFrame = _sequence!.poseAt(_animation.value);
    final controller = _poseController;
    if (controller == null) return;
    if (widget.movement == MotionActivityType.jumpingJacks) {
      controller.applyJumpingJackMotion(_currentFrame);
    } else {
      controller.applyMotion(_currentFrame);
    }
    _riveController?.scheduleRepaint();
  }

  void _onLoaded(RiveLoaded state) {
    final instance = state.viewModelInstance;
    if (instance == null) {
      if (kDebugMode) debugPrint('Nuvo Rive preview has no View Model.');
      return;
    }
    if (_usesSideRig) {
      final sidePoseController = SideRigPoseController(instance);
      if (!sidePoseController.isUsable) {
        if (kDebugMode) {
          debugPrint(
            'Nuvo side Rive preview missing controls: '
            '${sidePoseController.missingProperties.join(', ')}',
          );
        }
        return;
      }
      _riveController = state.controller;
      _sidePoseController = sidePoseController;
      _currentSideFrame = _sidePoseAt(_animation.value);
      sidePoseController.apply(_currentSideFrame);
      if (kDebugMode) {
        debugPrint(
          'Nuvo side Rive preview initialized '
          'movement=${widget.movement.backendValue} '
          'artboard=Nuvo stickman side '
          'viewModel=NuvoAngledataset boundProperties=18 missingProperties=0',
        );
      }
      if (MediaQuery.disableAnimationsOf(context)) {
        _animation.stop();
        _applyStaticPose();
      } else if (!_animation.isAnimating) {
        _animation.repeat();
      }
      return;
    }

    final poseController = RivePoseController(instance);
    if (!poseController.isUsable) {
      if (kDebugMode) {
        debugPrint(
          'Nuvo Rive preview missing controls: '
          '${poseController.missingProperties.join(', ')}',
        );
      }
      return;
    }
    _riveController = state.controller;
    _poseController = poseController;
    _currentFrame = _sequence!.poseAt(_animation.value);
    // Initialize bound scale inputs before the first useful frame paints.
    poseController.apply(_currentFrame);
    if (kDebugMode) {
      debugPrint(
        'Nuvo Rive preview initialized '
        'movement=${widget.movement.backendValue} '
        'artboard=nuvo stickman elite viewModel=NuvoPoseModel '
        'boundProperties=18 missingProperties=0',
      );
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.stop();
      _applyStaticPose();
    } else if (!_animation.isAnimating) {
      _animation.repeat();
    }
  }

  SideRigPose _sidePoseAt(double normalizedTime) {
    final side = _sideSequence;
    if (side != null) return side.poseAt(normalizedTime);
    return _sideMovementSequence!.poseAt(normalizedTime);
  }

  @override
  void dispose() {
    if (!_riveUnavailable) {
      _animation
        ..removeListener(_applyPose)
        ..dispose();
      _fileLoader.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_riveUnavailable) return widget.fallback;
    return AnimatedBuilder(
      animation: _animation,
      child: RiveWidgetBuilder(
        fileLoader: _fileLoader,
        artboardSelector: ArtboardNamed(
          _usesSideRig ? 'Nuvo stickman side' : 'nuvo stickman elite',
        ),
        stateMachineSelector: StateMachineNamed(
          _usesSideRig ? 'Nuvo State machine' : 'Nuvo pose',
        ),
        dataBind: _dataBind,
        onLoaded: _onLoaded,
        onFailed: (error, _) {
          if (kDebugMode) debugPrint('RIVE preview failed: $error');
        },
        builder: (context, state) {
          if (state is RiveLoaded) {
            return RiveWidget(
              controller: state.controller,
              fit: Fit.contain,
              alignment: Alignment.center,
            );
          }
          if (state is RiveFailed) return widget.fallback;
          return const SizedBox(
            width: 300,
            height: 300,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        },
      ),
      builder: (context, child) => ClipRect(
        child: Align(
          alignment: Alignment.center,
          child: Transform.translate(
            offset: Offset(
              _usesSideRig
                  ? _sidePreviewVisualCenterOffsetX
                  : _previewVisualCenterOffsetX,
              _usesSideRig
                  ? _sidePreviewBaseOffsetY + _currentSideFrame.rootYOffset
                  : _previewBaseOffsetY + _currentFrame.rootYOffset,
            ),
            child: Transform.scale(
              scale: _usesSideRig
                  ? _sidePreviewDisplayScale
                  : _previewDisplayScale,
              alignment: Alignment.center,
              child: SizedBox.expand(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
