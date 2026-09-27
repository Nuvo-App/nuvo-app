import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';
import 'nuvo_number_flow.dart';
import 'pressable_scale.dart';

/// One racer's live standing — a plain-data mirror of the canonical
/// `CrewLiveParticipant` payload so the card lives in core and any surface
/// (Crew feed, Crew Races tab, Arena) can feed it without importing the
/// social feature's models.
class NuvoLiveStanding {
  const NuvoLiveStanding({
    required this.name,
    required this.score,
    this.rank,
    this.isMe = false,
  });

  final String name;
  final int score;
  final int? rank;
  final bool isMe;
}

enum NuvoLiveRaceCardVariant { primary, compact }

/// The LIVE race card — a live competition object on the standard light
/// content surface, not a dark banner.
///
/// Surface language: white face, navy type, quiet navy outline, Nuvo offset
/// depth. "Live" is communicated by the red indicator, the pulsing dot, and
/// score motion — never by flooding the card with navy. The blue Watch
/// action is the accent; the card itself is content.
///
///   primary — one highest-priority live moment: head-to-head scores with
///     a who-leads bar when the payload carries a two-person race, else a
///     ranked matchup line.
///   compact — a secondary live race: two rows, same truth.
///
/// Canonical fields only — `title`, `standings` (name/score/rank/isMe), and
/// `endsAt`. Reactions are injected via [trailing] so the card never owns
/// the reaction data flow.
class NuvoLiveRaceCard extends StatelessWidget {
  const NuvoLiveRaceCard({
    super.key,
    required this.title,
    required this.standings,
    this.endsAt,
    this.trailing,
    this.onWatch,
    this.variant = NuvoLiveRaceCardVariant.primary,
  });

  final String title;
  final List<NuvoLiveStanding> standings;
  final DateTime? endsAt;

  /// Trailing slot next to Watch — Crew passes its reaction bar here.
  final Widget? trailing;

  /// Whole-card action ("Watch") — navigates to the race room.
  final VoidCallback? onWatch;

  final NuvoLiveRaceCardVariant variant;

  List<NuvoLiveStanding> get _ranked {
    final list = [...standings];
    list.sort((a, b) => (a.rank ?? 1 << 30).compareTo(b.rank ?? 1 << 30));
    return list;
  }

  NuvoLiveStanding? get _me =>
      standings.where((p) => p.isMe).firstOrNull;

  bool get _ending {
    final ends = endsAt;
    return ends != null &&
        ends.difference(DateTime.now()).inSeconds <= 0;
  }

  String? get _timeLeft {
    final ends = endsAt;
    if (ends == null) return null;
    final s = ends.difference(DateTime.now()).inSeconds;
    if (s <= 0) return 'Ending';
    if (s < 60) return '${s}s left';
    return '${(s / 60).ceil()}m left';
  }

  /// Canonical gap read — rank/score arithmetic only, never fabricated.
  String? get _gapLine {
    final r = _ranked;
    if (r.length < 2) return null;
    final leader = r.first;
    final me = _me;
    if (me == null) {
      final gap = leader.score - r[1].score;
      return gap == 0
          ? '${leader.name} and ${r[1].name} level'
          : '${leader.name} leads by $gap';
    }
    if (identical(me, leader)) {
      final gap = me.score - r[1].score;
      return gap == 0
          ? 'You and ${r[1].name} level'
          : 'You lead by $gap';
    }
    final gap = leader.score - me.score;
    return gap == 0
        ? 'Level with ${leader.name}'
        : '${leader.name} leads by $gap';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return PressableScale(
      onTap: onWatch,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border, width: 1.4),
          boxShadow: AppShadows.hardOffset(c.inkShadow),
        ),
        child: switch (variant) {
          NuvoLiveRaceCardVariant.primary => _primary(context),
          NuvoLiveRaceCardVariant.compact => _compact(context),
        },
      ),
    );
  }

  // ── Primary ────────────────────────────────────────────────────────────

  Widget _primary(BuildContext context) {
    final c = context.themeColors;
    final r = _ranked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context),
        const SizedBox(height: 5),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.titleMedium.copyWith(
            color: c.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        if (r.length == 2)
          _headToHead(context, r)
        else
          _matchupBlock(context, r),
        const SizedBox(height: 8),
        Row(
          children: [
            _watchAction(),
            const Spacer(),
            ?trailing,
          ],
        ),
      ],
    );
  }

  /// Two-person race: names over big scores, then a thin tug-of-war bar —
  /// their share vs mine. When I'm in the race I sit on the right (blue);
  /// spectator races are navy-vs-quiet.
  Widget _headToHead(
    BuildContext context,
    List<NuvoLiveStanding> ranked,
  ) {
    final c = context.themeColors;
    final meIdx = ranked.indexWhere((p) => p.isMe);
    final left = meIdx >= 0 ? ranked[1 - meIdx] : ranked[0];
    final right = meIdx >= 0 ? ranked[meIdx] : ranked[1];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _duelSide(context, left, CrossAxisAlignment.start)),
            const SizedBox(width: 10),
            Expanded(child: _duelSide(context, right, CrossAxisAlignment.end)),
          ],
        ),
        const SizedBox(height: 7),
        _splitBar(context, left, right),
        if (_gapLine != null) ...[
          const SizedBox(height: 5),
          Text(
            _gapLine!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelSmall.copyWith(
              color: c.inkMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }

  Widget _duelSide(
    BuildContext context,
    NuvoLiveStanding p,
    CrossAxisAlignment align,
  ) {
    final c = context.themeColors;
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          p.isMe ? 'You' : p.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.labelSmall.copyWith(
            color: c.inkMuted,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 1),
        NuvoNumberFlow(
          value: p.score,
          textAlign: align == CrossAxisAlignment.end
              ? TextAlign.end
              : TextAlign.start,
          style: AppTextStyles.number(
            24,
            color: p.isMe ? NuvoColors.blue : c.ink,
            weight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  /// Their share vs mine, proportional to canonical scores — the only
  /// "progress" the payload honestly supports.
  Widget _splitBar(
    BuildContext context,
    NuvoLiveStanding left,
    NuvoLiveStanding right,
  ) {
    final c = context.themeColors;
    final l = left.score <= 0 ? 1 : left.score;
    final r = right.score <= 0 ? 1 : right.score;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 4,
        child: Row(
          children: [
            Expanded(
              flex: l,
              child: ColoredBox(color: c.track),
            ),
            Expanded(
              flex: r,
              child: ColoredBox(
                color: right.isMe
                    ? NuvoColors.blue
                    : c.track.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 3+ racers (or ranks missing): the ranked matchup line — "Noah 41 ·
  /// You 39 · Maya 12". Mine reads blue.
  Widget _matchupBlock(
    BuildContext context,
    List<NuvoLiveStanding> ranked,
  ) {
    final c = context.themeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _matchupLine(context, ranked, size: 15),
        if (_me != null && _gapLine != null) ...[
          const SizedBox(height: 4),
          Text(
            _gapLine!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelSmall.copyWith(
              color: c.inkMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }

  // ── Compact ────────────────────────────────────────────────────────────

  Widget _compact(BuildContext context) {
    final c = context.themeColors;
    final r = _ranked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _LivePulseDot(),
            const SizedBox(width: 5),
            Text(
              'LIVE',
              style: AppTextStyles.labelMedium.copyWith(
                color: c.ink,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelMedium.copyWith(
                  color: c.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (_timeLeft != null) ...[
              const SizedBox(width: 8),
              _timeText(context),
            ],
          ],
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(child: _matchupLine(context, r, size: 12.5)),
            const SizedBox(width: 8),
            _watchAction(),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              Flexible(child: trailing!),
            ],
          ],
        ),
      ],
    );
  }

  // ── Shared pieces ──────────────────────────────────────────────────────

  Widget _header(BuildContext context) {
    final c = context.themeColors;
    return Row(
      children: [
        const _LivePulseDot(),
        const SizedBox(width: 5),
        Text(
          'LIVE',
          style: AppTextStyles.labelMedium.copyWith(
            color: c.ink,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const Spacer(),
        if (_timeLeft != null) _timeText(context),
      ],
    );
  }

  Widget _timeText(BuildContext context) {
    final c = context.themeColors;
    final ending = _ending;
    return Text(
      _timeLeft!,
      style: AppTextStyles.labelMedium.copyWith(
        color: ending ? NuvoColors.danger : c.inkMuted,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _matchupLine(
    BuildContext context,
    List<NuvoLiveStanding> ranked, {
    required double size,
  }) {
    final c = context.themeColors;
    final spans = <InlineSpan>[];
    final shown = ranked.take(3).toList();
    for (var i = 0; i < shown.length; i++) {
      final p = shown[i];
      if (i > 0) {
        spans.add(
          TextSpan(
            text: '  ·  ',
            style: AppTextStyles.labelMedium.copyWith(
              color: c.inkMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }
      final color = p.isMe ? NuvoColors.blue : c.ink;
      spans.addAll([
        TextSpan(
          text: p.isMe ? 'You' : p.name,
          style: AppTextStyles.labelMedium.copyWith(
            color: c.inkMuted,
            fontWeight: FontWeight.w700,
            fontSize: size,
          ),
        ),
        TextSpan(
          text: ' ${p.score}',
          style: AppTextStyles.number(
            size + 1,
            color: color,
            weight: FontWeight.w800,
          ),
        ),
      ]);
    }
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _watchAction() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Watch',
          style: AppTextStyles.labelMedium.copyWith(
            color: NuvoColors.blue,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 3),
        const Icon(
          Icons.arrow_forward_rounded,
          color: NuvoColors.blue,
          size: 15,
        ),
      ],
    );
  }
}

/// The card's live accent — a red dot whose halo breathes three times on
/// entrance, then rests. A perpetually-looping animation would keep frames
/// scheduled forever (breaking settle-based tests and adding idle GPU work
/// in the feed), so the pulse is deliberately bounded. The card itself
/// never pulses; under reduced motion the dot is static.
class _LivePulseDot extends StatefulWidget {
  const _LivePulseDot();

  @override
  State<_LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<_LivePulseDot>
    with SingleTickerProviderStateMixin {
  static const _breaths = 2;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  var _breathCount = 0;

  @override
  void initState() {
    super.initState();
    // Forward/reverse chained breaths — `repeat()`'s simulation never
    // reports done, so it can't be bounded by a status listener (and would
    // keep frames scheduled forever). Two breaths read as "just went live",
    // then the dot rests.
    _breathe();
  }

  void _breathe() {
    _pulse.forward().then((_) {
      if (mounted) return _pulse.reverse();
    }).then((_) {
      if (mounted && ++_breathCount < _breaths) _breathe();
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const dot = DecoratedBox(
      decoration: BoxDecoration(
        color: NuvoColors.danger,
        shape: BoxShape.circle,
      ),
      child: SizedBox(width: 7, height: 7),
    );
    if (MediaQuery.disableAnimationsOf(context)) return dot;
    return SizedBox(
      width: 16,
      height: 16,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (1 - _pulse.value) * 0.5,
                child: Transform.scale(
                  scale: 1 + _pulse.value * 1.3,
                  child: dot,
                ),
              ),
              dot,
            ],
          );
        },
      ),
    );
  }
}
