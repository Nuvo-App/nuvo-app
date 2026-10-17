import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import 'arena_podium.dart';

/// The down arrow under the podium. It nudges gently (static under
/// reduce-motion) and scrolls the page to the rest of the leaderboard.
class ArenaRestArrow extends StatefulWidget {
  const ArenaRestArrow({super.key, required this.onTap});

  static const double height = 36;

  final VoidCallback onTap;

  @override
  State<ArenaRestArrow> createState() => _ArenaRestArrowState();
}

class _ArenaRestArrowState extends State<ArenaRestArrow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _bob.stop();
      _bob.value = 0;
    } else if (!_bob.isAnimating && _bob.value == 0) {
      _bob.repeat(reverse: true, count: 6); // a few nudges, then rest
    }
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Semantics(
      button: true,
      label: 'See the rest of the leaderboard',
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('arena-rest-arrow'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          height: ArenaRestArrow.height,
          width: double.infinity,
          child: Center(
            child: AnimatedBuilder(
              animation: _bob,
              builder: (context, child) => Transform.translate(
                offset: Offset(0, 3 * Curves.easeInOut.transform(_bob.value)),
                child: child,
              ),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 32,
                color: c.inkMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Racers from 4th onwards, on the same page below the fold. Each row fades
/// in by itself as the scroll lifts it clear of the nav's top edge, so the
/// places appear one after another, driven by how far the viewer has scrolled
/// (not by a timer that fires on the first nudge).
class ArenaRestList extends StatelessWidget {
  /// Approximate height of one row, used to size the reveal and the tail.
  static double rowHeight(TextScaler s) =>
      24 + math.max(34.0, s.scale(16) * 1.4) + 4;

  /// Extra scroll room under the last row so it reaches full opacity.
  static double tailRoom(TextScaler s) => rowHeight(s) * (revealRows - 1);

  /// How many row-heights a row takes to fade from nothing to full.
  static const double revealRows = 2.4;

  const ArenaRestList({
    super.key,
    required this.entries,
    required this.foldInset,
    this.onTap,
  });

  /// Racers ranked 4th and below, in order.
  final List<ArenaPodiumEntry> entries;

  /// Distance from the bottom of the scroll view to the nav's top edge.
  final double foldInset;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('arena-rest-board'),
      children: [
        for (final (i, e) in entries.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
            child: ArenaScrollReveal(
              foldInset: foldInset,
              child: _RestRow(entry: e, onTap: onTap),
            ),
          ),
      ],
    );
  }
}

/// Fades and settles its child in as it rises above the fold line. Progress
/// is read at paint time from the child's real on-screen position, so it
/// tracks the finger exactly (a build-time read would lag a frame behind).
class ArenaScrollReveal extends SingleChildRenderObjectWidget {
  const ArenaScrollReveal({
    super.key,
    required this.foldInset,
    required super.child,
  });

  /// Distance from the bottom of the screen to the nav's top edge.
  final double foldInset;

  @override
  RenderArenaScrollReveal createRenderObject(BuildContext context) =>
      RenderArenaScrollReveal(
        foldInset: foldInset,
        screenHeight: MediaQuery.sizeOf(context).height,
        reduceMotion: MediaQuery.disableAnimationsOf(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderArenaScrollReveal renderObject,
  ) {
    renderObject
      ..foldInset = foldInset
      ..screenHeight = MediaQuery.sizeOf(context).height
      ..reduceMotion = MediaQuery.disableAnimationsOf(context)
      ..markNeedsPaint();
  }
}

class RenderArenaScrollReveal extends RenderProxyBox {
  RenderArenaScrollReveal({
    required this.foldInset,
    required this.screenHeight,
    required this.reduceMotion,
  });

  double foldInset;
  double screenHeight;
  bool reduceMotion;

  /// 0 = still below the nav's top edge, 1 = the whole row has cleared it.
  double get progress {
    if (reduceMotion) return 1;
    if (!attached || !hasSize) return 0;
    final top = localToGlobal(Offset.zero).dy;
    final line = screenHeight - foldInset;
    final t = ((line - top) / (size.height * ArenaRestList.revealRows)).clamp(
      0.0,
      1.0,
    );
    return Curves.easeInOut.transform(t);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final t = progress;
    final alpha = (t * 255).round();
    if (alpha == 0) return;
    final shifted = offset + Offset(0, 14 * (1 - t));
    if (alpha == 255) {
      context.paintChild(child, shifted);
    } else {
      context.pushOpacity(shifted, alpha, super.paint);
    }
  }
}

class _RestRow extends StatelessWidget {
  const _RestRow({required this.entry, this.onTap});

  final ArenaPodiumEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final me = entry.isMe;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: me
              ? Color.alphaBlend(c.accent.withValues(alpha: 0.10), c.surface)
              : c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border, width: 2),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${entry.rank}',
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: c.inkMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            NuvoAvatar(
              initials:
                  entry.initials ??
                  (entry.name.isEmpty ? '?' : entry.name.substring(0, 1)),
              photoUrl: entry.photoUrl,
              size: 34,
              bgColor: nuvoAvatarColorFor(entry.seed),
              textColor: NuvoColors.white,
              borderColor: me ? c.accent : c.border,
              borderWidth: me ? 2.5 : 1.5,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: c.ink,
                  fontWeight: me ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
            Text(
              entry.score,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: c.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
