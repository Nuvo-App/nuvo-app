import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'bottom_nav.dart';
import '../theme/app_geometry.dart';

/// The first-viewport fold seam.
///
/// Nuvo's first viewport is a composed surface: content that fully fits
/// renders above the floating dock, and whatever can't fit whole starts
/// below it — never bisected by the dock. [SliverFold] measures the
/// remaining viewport extent at first layout and hands the caller a
/// [NuvoFoldBudget] describing how much vertical space exists before the
/// fold seam. The caller renders the portion that fits, then a
/// `SizedBox(height: fold.seam(used))`, then the rest — the seam pushes
/// the remainder beneath the dock where it scrolls in normally.
///
/// The budget is locked on the first layout pass so scrolling never
/// re-splits content mid-flight.
///
/// Usage:
/// ```dart
/// SliverFold(
///   reserve: SliverFold.reserveOf(context),
///   builder: (context, fold) {
///     final fit = fold.fitExtent ~/ rowExtent;
///     return SliverToBoxAdapter(
///       child: Column(children: [
///         ...rows.take(fit),
///         SizedBox(height: fold.seam(fit * rowExtent)),
///         ...rows.skip(fit),
///       ]),
///     );
///   },
/// )
/// ```
class SliverFold extends StatefulWidget {
  const SliverFold({super.key, required this.reserve, required this.builder});

  /// Pixels to keep clear at the bottom of the first viewport — the dock
  /// zone plus the breathing zone. Use [reserveOf] inside the shell.
  final double reserve;

  /// Builds the sliver content given the measured [NuvoFoldBudget].
  final Widget Function(BuildContext context, NuvoFoldBudget fold) builder;

  /// The shared reserve: the full dock-clearance contract (dock height,
  /// device inset, Verify's raised edge, clearance gap) plus the
  /// intentional breathing zone above the dock — see
  /// docs/ui/MAIN_SCREEN_LAYOUT_CONTRACT.md.
  static double reserveOf(BuildContext context) =>
      NuvoBottomNav.bottomPadding(context) + NuvoSpacing.dockBreathing;

  @override
  State<SliverFold> createState() => _SliverFoldState();
}

class _SliverFoldState extends State<SliverFold> {
  NuvoFoldBudget? _budget;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        // remainingPaintExtent = pixels from this sliver's start to the
        // viewport's bottom edge — the entire first-viewport budget from
        // this point down. Locked once: re-measuring on scroll would
        // move the seam and re-split sections mid-flight.
        _budget ??= NuvoFoldBudget(
          available: constraints.remainingPaintExtent,
          reserve: widget.reserve,
        );
        return widget.builder(context, _budget!);
      },
    );
  }
}

/// The measured first-viewport budget for one split point.
class NuvoFoldBudget {
  const NuvoFoldBudget({required this.available, required this.reserve});

  /// Pixels from the split point to the viewport's bottom edge.
  final double available;

  /// Pixels reserved at the bottom (dock zone + breathing zone). Content
  /// may not intrude into this region at rest.
  final double reserve;

  /// Pixels content may consume while ending fully above the fold.
  double get fitExtent => math.max(0, available - reserve);

  /// The seam height that pushes following content below the viewport,
  /// given [used] pixels already consumed by the above-fold portion.
  /// Never less than the reserve, so even an edge case can't land a row
  /// partially under the dock.
  double seam(double used) => math.max(reserve, available - used);
}
