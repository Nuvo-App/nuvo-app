import 'dart:collection';

import 'package:flutter/widgets.dart';

/// The persistent shell state every step shares — owned by the flow host,
/// reached by steps through [OnboardingShellScope].
///
/// Two kinds of persistence live here:
/// - Track position: [trackFrom] → [trackIndex] tells each freshly-mounted
///   step's track where the camera pan starts, so the path animates across
///   a step swap instead of snapping.
/// - XP display: [xpTarget] is the flow's awarded total; [displayedXp] is
///   what the rail currently shows. The gap between them is the in-flight
///   "+N" chips ([award] queues a flight, [arriveXp] lands it).
///
/// Later parts may extend this (tilt parallax, tour overlays); the public
/// API below is the stable contract.
class OnboardingShellController extends ChangeNotifier {
  /// Step the track was last resting at — the pan's origin.
  int trackFrom = 0;

  /// Step the track should be resting at now.
  int trackIndex = 0;

  /// XP the rail shows right now (lands when a flying chip arrives).
  int displayedXp = 0;

  /// The flow's awarded total — [displayedXp] converges to this.
  int xpTarget = 0;

  /// The live rail's bounds in global coordinates — the fly-chip's target.
  /// Registered by each mounted rail; null while no rail is on screen.
  Rect? railRect;

  final Queue<int> _pendingFly = Queue<int>();

  /// Chips still in the air (or waiting for a rail to appear).
  int get pendingFlyCount => _pendingFly.length;

  /// Moves the track camera. Called by the host BEFORE the step swap so
  /// both the outgoing and incoming tracks start from the same pan.
  void panTrackTo(int index) {
    if (index == trackIndex) return;
    trackFrom = trackIndex;
    trackIndex = index;
    notifyListeners();
  }

  /// Snaps the rail to [total] with no ceremony — used for restore and any
  /// award that had no rail to land on.
  void syncXp(int total) {
    xpTarget = total;
    if (_pendingFly.isEmpty) {
      displayedXp = total;
      notifyListeners();
    }
  }

  /// Queues a "+N" flight from the CTA area into the rail.
  void award(int xp) {
    if (xp <= 0) return;
    xpTarget += xp;
    _pendingFly.add(xp);
    notifyListeners();
  }

  /// The overlay drains one pending flight per chip it launches.
  int? nextPendingFly() =>
      _pendingFly.isEmpty ? null : _pendingFly.removeFirst();

  /// Gives up on a queued flight when no rail ever appears — the XP still
  /// counts, it just doesn't fly.
  void dropPendingFly() {
    final n = nextPendingFly();
    if (n != null) arriveXp(n);
  }

  /// A chip reached the rail — the visible total grows (the rail animates
  /// the fill itself on this change).
  void arriveXp(int xp) {
    displayedXp += xp;
    if (displayedXp > xpTarget) displayedXp = xpTarget;
    notifyListeners();
  }
}

/// Hands the [OnboardingShellController] to every step: `final shell =
/// OnboardingShellScope.of(context); shell.award(awarded);`.
class OnboardingShellScope extends InheritedWidget {
  const OnboardingShellScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final OnboardingShellController controller;

  static OnboardingShellController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<OnboardingShellScope>();
    assert(scope != null, 'OnboardingShellScope missing above a step');
    return scope!.controller;
  }

  /// Non-listening read — for callbacks that fire after awaits.
  static OnboardingShellController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<OnboardingShellScope>()?.controller;

  @override
  bool updateShouldNotify(OnboardingShellScope old) =>
      controller != old.controller;
}
