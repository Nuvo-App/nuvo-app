import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// One shared entrance treatment so rolling motion out to a static screen is
/// a one-line change instead of hand-writing a `.animate()` chain each time.
/// Per the design guide: "no part of the app that doesn't feel responsive or
/// interactive" — a static list/column on first load is the cheapest miss to
/// fix, and the cheapest to fix consistently is a single extension.
extension NuvoEntranceX on Widget {
  /// Fade + slide-up entrance. `delay` staggers list items (e.g.
  /// `Duration(milliseconds: 40 * index)`).
  Widget nuvoEnter({Duration delay = Duration.zero}) {
    return animate(delay: delay)
        .fadeIn(duration: 220.ms, curve: Curves.easeOut)
        .slideY(begin: 0.03, end: 0, duration: 260.ms, curve: Curves.easeOut);
  }
}
