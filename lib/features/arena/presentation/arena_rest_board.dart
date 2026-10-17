import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
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

/// Racers from 4th onwards. Sits below the fold; as the page scrolls it
/// unfolds like a curtain — rows slide down into place and fade in.
class ArenaRestBoard extends StatelessWidget {
  const ArenaRestBoard({
    super.key,
    required this.entries,
    required this.scroll,
    required this.revealExtent,
    this.onTap,
  });

  /// Racers ranked 4th and below, in order.
  final List<ArenaPodiumEntry> entries;
  final ScrollController scroll;

  /// Scroll distance over which the curtain finishes opening.
  final double revealExtent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: scroll,
      builder: (context, _) {
        final offset = scroll.hasClients ? scroll.offset : 0.0;
        final t = reduce
            ? 1.0
            : Curves.easeOutCubic.transform(
                (offset / revealExtent).clamp(0.0, 1.0),
              );
        return Opacity(
          opacity: 0.25 + 0.75 * t,
          child: Transform.translate(
            offset: Offset(0, -24 * (1 - t)),
            child: Container(
              key: const ValueKey('arena-rest-board'),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: c.border, width: 2),
                boxShadow: AppShadows.hardOffset(c.inkShadow),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, e) in entries.indexed) ...[
                    if (i > 0)
                      Divider(height: 1, thickness: 1, color: c.divider),
                    _RestRow(entry: e, onTap: onTap),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
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
      child: Container(
        color: me ? c.accent.withValues(alpha: 0.10) : null,
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
