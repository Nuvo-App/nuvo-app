import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_avatar.dart';

/// One racer on the Arena podium.
class ArenaPodiumEntry {
  const ArenaPodiumEntry({
    required this.rank,
    required this.name,
    required this.score,
    required this.seed,
    required this.isMe,
    this.photoUrl,
    this.initials,
  });

  final int rank;

  /// Already display-ready: first name, or 'You' for the viewer.
  final String name;
  final String score;
  final String seed;
  final bool isMe;
  final String? photoUrl;
  final String? initials;
}

/// Block fills. Solid, mild, and the same in light and dark: every fill is
/// light enough that [arenaPodiumInk] clears 4.5:1 on it.
const Color arenaPodiumGold = Color(0xFFEDB93B);
const Color arenaPodiumSilver = Color(0xFF9DB4D6);
const Color arenaPodiumBronze = Color(0xFFD9915A);
const Color arenaPodiumInk = Color(0xFF14171D);

Color arenaPodiumFill(int rank) => switch (rank) {
  1 => arenaPodiumGold,
  2 => arenaPodiumSilver,
  _ => arenaPodiumBronze,
};

/// Kahoot-style top-3 podium: 2nd | 1st | 3rd, the winner tallest in the
/// centre. Blocks rise on first show; reduce-motion renders them static.
class ArenaPodium extends StatefulWidget {
  const ArenaPodium({
    super.key,
    required this.entries,
    required this.height,
    this.viewer,
    this.onTap,
  });

  /// Racers in rank order (only the first three are drawn).
  final List<ArenaPodiumEntry> entries;

  /// Total height granted to the podium (blocks + labels + viewer chip).
  final double height;

  /// The viewer's entry when they are outside the top three.
  final ArenaPodiumEntry? viewer;
  final VoidCallback? onTap;

  static const double chipHeight = 34;
  static const double _winnerAvatar = 42;
  static const double _otherAvatar = 36;
  static const double _minBlock = 56;

  /// Height of the label stack above a block (avatar, name, score).
  static double labelsHeight(TextScaler scaler) =>
      _winnerAvatar + 2 + scaler.scale(13) * 1.25 + scaler.scale(15) * 1.25 + 4;

  /// Smallest height at which the podium still reads (blocks + labels).
  static double minHeight(TextScaler scaler, {required bool withChip}) =>
      labelsHeight(scaler) + _minBlock / 0.9 + (withChip ? chipHeight + 8 : 0);

  @override
  State<ArenaPodium> createState() => _ArenaPodiumState();
}

class _ArenaPodiumState extends State<ArenaPodium>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Third place rises first, then second, then the winner.
  static const _intervals = {
    3: Interval(0.0, 0.6, curve: Curves.easeOutBack),
    2: Interval(0.15, 0.75, curve: Curves.easeOutBack),
    1: Interval(0.3, 1.0, curve: Curves.easeOutBack),
  };

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final chip = widget.viewer;
    final chipSpace = chip == null ? 0.0 : ArenaPodium.chipHeight + 8;
    final stageHeight = widget.height - chipSpace;
    final labels = ArenaPodium.labelsHeight(scaler);
    // 10% headroom so the back-ease overshoot never exceeds the stage.
    final blockMax = math.max(0.0, (stageHeight - labels) * 0.9);
    final byRank = {for (final e in widget.entries.take(3)) e.rank: e};

    Widget column(int rank) {
      final entry = byRank[rank];
      final frac = switch (rank) {
        1 => 1.0,
        2 => 0.74,
        _ => 0.54,
      };
      return Expanded(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final raw = _intervals[rank]!.transform(_controller.value);
            final fade = Curves.easeOut.transform(raw.clamp(0.0, 1.0));
            return Align(
              alignment: Alignment.bottomCenter,
              child: entry == null
                  ? _OpenBlock(
                      rank: rank,
                      height: math.max(0, blockMax * frac * raw),
                      fade: fade,
                    )
                  : _PodiumColumn(
                      entry: entry,
                      blockHeight: math.max(0, blockMax * frac * raw),
                      fade: fade,
                      winner: rank == 1,
                    ),
            );
          },
        ),
      );
    }

    final body = Semantics(
      button: widget.onTap != null,
      label:
          'Top three: ${[for (final e in widget.entries.take(3)) '${e.rank}, ${e.name}, ${e.score}'].join('; ')}',
      excludeSemantics: true,
      child: SizedBox(
        height: widget.height,
        child: Column(
          children: [
            SizedBox(
              height: stageHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  column(2),
                  const SizedBox(width: 8),
                  column(1),
                  const SizedBox(width: 8),
                  column(3),
                ],
              ),
            ),
            if (chip != null) ...[
              const SizedBox(height: 8),
              _ViewerChip(entry: chip),
            ],
          ],
        ),
      ),
    );
    if (widget.onTap == null) return body;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: body,
    );
  }
}

class _PodiumColumn extends StatelessWidget {
  const _PodiumColumn({
    required this.entry,
    required this.blockHeight,
    required this.fade,
    required this.winner,
  });
  final ArenaPodiumEntry entry;
  final double blockHeight;
  final double fade;
  final bool winner;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final size = winner ? ArenaPodium._winnerAvatar : ArenaPodium._otherAvatar;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: fade,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  NuvoAvatar(
                    initials: entry.initials ?? _initialsOf(entry.name),
                    photoUrl: entry.photoUrl,
                    size: size,
                    bgColor: nuvoAvatarColorFor(entry.seed),
                    textColor: NuvoColors.white,
                    borderColor: entry.isMe ? c.accent : c.border,
                    borderWidth: entry.isMe ? 3 : 1.5,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelMedium.copyWith(
                  fontSize: 13,
                  height: 1.25,
                  color: c.ink,
                  fontWeight: entry.isMe ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
              Text(
                entry.score,
                maxLines: 1,
                style: AppTextStyles.labelMedium.copyWith(
                  fontSize: 15,
                  height: 1.25,
                  color: c.inkMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
        Container(
          key: ValueKey('arena-podium-block-${entry.rank}'),
          height: blockHeight,
          width: double.infinity,
          alignment: Alignment.center,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: arenaPodiumFill(entry.rank),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            border: entry.isMe ? Border.all(color: c.accent, width: 3) : null,
          ),
          child: Opacity(
            opacity: fade,
            child: _Numeral(rank: entry.rank, height: blockHeight),
          ),
        ),
      ],
    );
  }
}

class _Numeral extends StatelessWidget {
  const _Numeral({required this.rank, required this.height});
  final int rank;
  final double height;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        '$rank',
        style: AppTextStyles.displayMedium.copyWith(
          color: arenaPodiumInk,
          fontSize: 40,
          height: 1,
          fontWeight: FontWeight.w900,
        ),
      ),
    ),
  );
}

class _OpenBlock extends StatelessWidget {
  const _OpenBlock({
    required this.rank,
    required this.height,
    required this.fade,
  });
  final int rank;
  final double height;
  final double fade;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return CustomPaint(
      painter: _DashedTopRect(color: c.inkSubtle),
      child: SizedBox(
        key: ValueKey('arena-podium-open-$rank'),
        height: height,
        width: double.infinity,
        child: Opacity(
          opacity: fade,
          child: ClipRect(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(
                    'Open',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: c.inkMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedTopRect extends CustomPainter {
  _DashedTopRect({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height < 2) return;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, 14)
      ..arcToPoint(const Offset(14, 0), radius: const Radius.circular(14))
      ..lineTo(size.width - 14, 0)
      ..arcToPoint(Offset(size.width, 14), radius: const Radius.circular(14))
      ..lineTo(size.width, size.height);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedTopRect old) => old.color != color;
}

class _ViewerChip extends StatelessWidget {
  const _ViewerChip({required this.entry});
  final ArenaPodiumEntry entry;
  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Container(
      key: const ValueKey('arena-podium-viewer-chip'),
      height: ArenaPodium.chipHeight,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: c.accent, width: 1.5),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          'You · ${_ordinal(entry.rank)} · ${entry.score}',
          maxLines: 1,
          style: AppTextStyles.labelMedium.copyWith(
            color: c.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

String _ordinal(int n) {
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

String _initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  final t = name.trim();
  return t.isEmpty ? '?' : t[0].toUpperCase();
}
