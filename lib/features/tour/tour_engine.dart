import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tour_anchors.dart';
import 'tour_controller.dart';
import 'tour_script.dart';

/// The shell routes the tour can spotlight on. Anywhere else (a pushed
/// detail screen, a sheet's route) the overlay simply stays out of the way.
const List<String> kTourTabRoutes = ['/arena', '/compete', '/pass', '/profile'];

bool isTourTabRoute(String location) => kTourTabRoutes.any(
  (r) =>
      location == r || location.startsWith('$r/') || location.startsWith('$r?'),
);

/// The shell location the overlay keys on. The overlay layer keeps it in
/// step with the router; tests set it directly.
final tourLocationProvider = StateProvider<String>((ref) => '/arena');

enum TourPhase {
  /// Spotlight a dock tab so the user can go to the stop's screen.
  dock,

  /// Spotlight the stop's real target.
  target,

  /// The notification sheet (S11).
  sheet,

  /// The closing line.
  done,

  /// Nothing to draw right now.
  hidden,
}

/// What the overlay should draw for a beat at a location.
@immutable
class TourView {
  const TourView({
    required this.phase,
    this.stop,
    this.anchor,
    this.dockIndex,
    this.copy = '',
    this.counter,
  });

  final TourPhase phase;
  final TourStop? stop;

  /// The widget to spotlight (target phase) — null for dock/sheet/done.
  final TourAnchor? anchor;
  final int? dockIndex;
  final String copy;
  final int? counter;

  bool get spotlights => phase == TourPhase.dock || phase == TourPhase.target;

  static const TourView hidden = TourView(phase: TourPhase.hidden);
}

/// Pure: beat + location -> what to draw. The phase follows the location, so
/// pressing back or switching tabs by hand re-points the tour instead of
/// stranding it.
TourView resolveTourView(String? beat, String location) {
  if (beat == null) return TourView.hidden;
  if (beat == kTourDoneBeat) {
    return const TourView(phase: TourPhase.done, copy: kTourDone);
  }
  if (!isTourTabRoute(location)) return TourView.hidden;
  if (beat == kTourNotifyId) {
    return const TourView(phase: TourPhase.sheet, copy: kTourNotifyTitle);
  }
  final stop = tourStopById(beat);
  if (stop == null) return TourView.hidden;
  final onRoute =
      location == stop.route || location.startsWith('${stop.route}/');
  if (onRoute) {
    return TourView(
      phase: TourPhase.target,
      stop: stop,
      anchor: stop.anchor,
      copy: stop.copy,
      counter: stop.counter,
    );
  }
  if (stop.dockIndex != null) {
    return TourView(
      phase: TourPhase.dock,
      stop: stop,
      dockIndex: stop.dockIndex,
      copy: stop.dockCopy ?? stop.copy,
      counter: stop.counter,
    );
  }
  return TourView.hidden;
}
