import 'package:flutter/widgets.dart';

/// Every widget the tour can spotlight. Screens attach the matching
/// [GlobalKey] (one line, only while the tour is active) and the overlay
/// resolves the target's on-screen rect from it.
enum TourAnchor {
  arenaRaceCard,
  submitProof,
  dockArena,
  dockCompete,
  dockCrew,
  dockProfile,
  joinCard,
  myNuvoCode,
  firstBadge,
}

abstract final class TourAnchors {
  static final Map<TourAnchor, GlobalKey> _keys = {
    for (final a in TourAnchor.values)
      a: GlobalKey(debugLabel: 'tour-${a.name}'),
  };

  static GlobalKey keyOf(TourAnchor anchor) => _keys[anchor]!;

  /// The dock slot anchor for tab [index] (0 Arena, 1 Compete, 2 Crew,
  /// 3 Profile) — null for any other index.
  static GlobalKey? dockSlot(int index) => switch (index) {
    0 => _keys[TourAnchor.dockArena],
    1 => _keys[TourAnchor.dockCompete],
    2 => _keys[TourAnchor.dockCrew],
    3 => _keys[TourAnchor.dockProfile],
    _ => null,
  };

  /// The on-screen rect of [anchor] in global coordinates, or null when the
  /// target is not mounted / not laid out.
  static Rect? rectOf(TourAnchor anchor) {
    final ctx = _keys[anchor]?.currentContext;
    final box = ctx?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}
