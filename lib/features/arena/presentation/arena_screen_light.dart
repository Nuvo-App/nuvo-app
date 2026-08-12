import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/arena_models.dart';
import 'arena_controller.dart';

/// Arena — Nuvo's light-mode home dashboard.
///
/// Answers one question on open: *what is my next move?* The composition is
/// header → Your Next Move hero (with the Momentum Path) → quick actions →
/// Crew Standings → Recent activity.
class ArenaScreen extends ConsumerStatefulWidget {
  const ArenaScreen({super.key});

  @override
  ConsumerState<ArenaScreen> createState() => _ArenaScreenState();
}

class _ArenaScreenState extends ConsumerState<ArenaScreen> {
  final _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Routes the hero's contextual action. Behaviour is unchanged from the
  /// previous Arena: the board's own action type decides the destination.
  void _runAction(ArenaBoard board) {
    switch (board.primaryActionType) {
      case 'submit_proof':
        context.push('/race/${board.id}/proof');
      case 'start_race':
        context.push('/races/new');
      case 'none':
        break;
      default:
        context.push('/race/${board.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final state = ref.watch(arenaControllerProvider);
    final snapshot = state.snapshot;
    final safeTop = MediaQuery.viewPaddingOf(context).top;

    final boards = <ArenaBoard>[
      if (snapshot?.focusBoard != null) snapshot!.focusBoard!,
      ...?snapshot?.liveBoards,
    ];
    final activity = snapshot?.activity ?? const <ArenaActivity>[];
    final activeBoard = boards.isEmpty
        ? null
        : boards[_page.clamp(0, boards.length - 1)];

    return RefreshIndicator(
      color: NuvoColors.blue,
      backgroundColor: NuvoColors.surface,
      onRefresh: () =>
          ref.read(arenaControllerProvider.notifier).loadSnapshot(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          top: safeTop + 12,
          bottom: NuvoBottomNav.bottomPadding(context),
        ),
        children: [
          _ArenaHeader(
            greeting: _greeting(user?.fullName),
            pulse: snapshot?.headerPulse ?? '',
            loading: state.loading && snapshot == null,
          ),
          const SizedBox(height: 18),

          if (state.error != null && snapshot == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: NuvoErrorState(
                message: state.error!,
                onRetry: () =>
                    ref.read(arenaControllerProvider.notifier).loadSnapshot(),
              ),
            )
          else if (state.loading && snapshot == null)
            const _HeroSkeleton()
          else if (boards.isEmpty)
            _ArenaEmptyHero(onStart: () => context.push('/races/new'))
          else ...[
            // ── Your Next Move ───────────────────────────────────────────
            SizedBox(
              height: 356,
              child: PageView.builder(
                controller: _pageController,
                itemCount: boards.length,
                onPageChanged: (i) => setState(() => _page = i),
                padEnds: false,
                itemBuilder: (context, i) => Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: boards.length == 1 ? 20 : 10,
                  ),
                  child: _NextMoveHero(
                    board: boards[i],
                    onAction: () => _runAction(boards[i]),
                  ),
                ),
              ),
            ),
            if (boards.length > 1) ...[
              const SizedBox(height: 14),
              _PageDots(count: boards.length, index: _page),
            ],
          ],

          const SizedBox(height: 26),

          // ── Quick actions ───────────────────────────────────────────────
          _QuickActions(
            hasActiveRace: activeBoard != null,
            onSubmitProof: activeBoard == null
                ? null
                : () => context.push('/race/${activeBoard.id}/proof'),
            onStart: () => context.push('/races/new'),
            onJoin: () => context.push('/races/join'),
            onInvite: activeBoard == null
                ? null
                : () => context.push('/race/${activeBoard.id}/invite'),
          ),

          // ── Crew standings ──────────────────────────────────────────────
          if (activeBoard != null &&
              activeBoard.miniLeaderboard.isNotEmpty) ...[
            const SizedBox(height: 30),
            _SectionHeader(
              label: 'Crew standings',
              action: 'View all',
              onAction: () => context.push('/race/${activeBoard.id}'),
            ),
            const SizedBox(height: 14),
            _Standings(rows: activeBoard.miniLeaderboard),
          ],

          // ── Recent activity ─────────────────────────────────────────────
          const SizedBox(height: 30),
          const _SectionHeader(label: 'Recent activity'),
          const SizedBox(height: 12),
          if (state.loading && snapshot == null)
            const _ActivitySkeleton()
          else if (activity.isEmpty)
            _ActivityEmpty(
              onAction: activeBoard != null
                  ? () => context.push('/race/${activeBoard.id}/proof')
                  : () => context.push('/races/new'),
              actionLabel:
                  activeBoard != null ? 'Submit proof' : 'Start a race',
            )
          else
            _ActivityStream(items: activity),
        ],
      ),
    );
  }
}

String _greeting(String? name) {
  final hour = DateTime.now().hour;
  final part = hour < 12
      ? 'Good morning'
      : hour < 18
          ? 'Good afternoon'
          : 'Good evening';
  if (name == null || name.trim().isEmpty) return part;
  return '$part, ${name.trim().split(' ').first}';
}

// ═══════════════════════════════════════════════════════════════════════════════
// HEADER
// ═══════════════════════════════════════════════════════════════════════════════

class _ArenaHeader extends StatelessWidget {
  const _ArenaHeader({
    required this.greeting,
    required this.pulse,
    required this.loading,
  });

  final String greeting;
  final String pulse;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'NUVO',
                style: AppTextStyles.labelSmall.copyWith(
                  color: NuvoColors.blue,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                  fontSize: 10,
                ),
              ),
              const Spacer(),
              if (pulse.isNotEmpty && !loading)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: NuvoColors.secondarySurface,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: NuvoColors.blue,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            pulse,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.labelSmall.copyWith(
                              color: NuvoColors.navy,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Arena',
            style: AppTextStyles.screenTitle.copyWith(
              color: NuvoColors.navy,
              fontSize: 36,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            greeting,
            style: AppTextStyles.bodyMedium.copyWith(
              color: NuvoColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// YOUR NEXT MOVE — hero card
// ═══════════════════════════════════════════════════════════════════════════════

class _NextMoveHero extends StatelessWidget {
  const _NextMoveHero({required this.board, required this.onAction});

  final ArenaBoard board;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final pct = (board.progressPercent ?? 0).clamp(0, 100);
    final parts = _splitProgress(board.progressLabel);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: NuvoColors.border, width: 1),
        boxShadow: AppShadows.heroShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: NuvoColors.secondarySurface,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  board.isResult ? 'RESULT' : 'YOUR NEXT MOVE',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.blue,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                    fontSize: 9,
                  ),
                ),
              ),
              const Spacer(),
              if (board.myRank != null)
                Text(
                  '#${board.myRank}',
                  maxLines: 1,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: NuvoColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              if (board.daysLeft != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    board.daysLeft == 0
                        ? 'Last day'
                        : '${board.daysLeft}d left',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: NuvoColors.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Text(
            board.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.headlineMedium.copyWith(
              color: NuvoColors.navy,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 14),

          // Oversized progress number — the Arena numeric signature.
          // Scales down rather than overflowing on long labels
          // (e.g. "1200 / 1500 seconds").
          Row(
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        parts.$1,
                        maxLines: 1,
                        style: AppTextStyles.number(
                          46,
                          color: NuvoColors.blue,
                          weight: FontWeight.w800,
                        ),
                      ),
                      if (parts.$2.isNotEmpty)
                        Text(
                          ' / ${parts.$2}',
                          maxLines: 1,
                          style: AppTextStyles.number(
                            26,
                            color: NuvoColors.navy,
                            weight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (board.racerCount != null && board.racerCount! > 0) ...[
                const SizedBox(width: 10),
                Text(
                  '${board.racerCount} racing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.textMuted,
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 16),

          // ── Momentum Path ────────────────────────────────────────────────
          _MomentumPath(
            percent: pct.toDouble(),
            competitors: board.miniLeaderboard,
          ),

          const SizedBox(height: 8),
          Text(
            board.boardContext.isNotEmpty
                ? board.boardContext
                : board.proofLabel ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(
              color: NuvoColors.textMuted,
            ),
          ),

          const Spacer(),

          if (board.primaryActionType != 'none')
            _PrimaryAction(label: board.primaryActionLabel, onTap: onAction),
        ],
      ),
    );
  }
}

/// Splits "65 / 100 reps" into ("65", "100 reps"). Falls back gracefully.
(String, String) _splitProgress(String label) {
  final idx = label.indexOf('/');
  if (idx == -1) return (label.trim(), '');
  return (label.substring(0, idx).trim(), label.substring(idx + 1).trim());
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: NuvoColors.blue,
          borderRadius: BorderRadius.circular(15),
          boxShadow: AppShadows.trackBlueGlowSubtle,
        ),
        child: Text(
          label,
          style: AppTextStyles.buttonLabel.copyWith(
            color: NuvoColors.white,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MOMENTUM PATH — Arena's signature progress component
//
// A gently curved trajectory from start to finish. Blue drawn progress over a
// pale-blue track, the user's marker at their real position, competitors as
// small hollow markers, and a flag at the finish. Deliberately not an ellipse,
// orbit, or oval running track.
// ═══════════════════════════════════════════════════════════════════════════════

class _MomentumPath extends StatelessWidget {
  const _MomentumPath({required this.percent, this.competitors = const []});

  final double percent;
  final List<ArenaMiniLeaderboardRow> competitors;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    // Derive competitor positions from their numeric values when parseable,
    // so markers sit at real standings rather than decorative spots.
    final others = <double>[];
    for (final row in competitors.where((r) => !r.isCurrentUser).take(3)) {
      final v = _leadingNumber(row.value);
      if (v != null) others.add(v.clamp(0, 100).toDouble());
    }

    return SizedBox(
      height: 62,
      // Reduce Motion renders the final state directly — no drawing animation.
      child: reduceMotion
          ? CustomPaint(
              painter: _MomentumPathPainter(percent: percent, others: others),
              size: Size.infinite,
            )
          : _AnimatedPath(percent: percent, others: others),
    );
  }
}

double? _leadingNumber(String s) {
  final m = RegExp(r'(\d+)').firstMatch(s);
  if (m == null) return null;
  return double.tryParse(m.group(1)!);
}

class _AnimatedPath extends StatefulWidget {
  const _AnimatedPath({required this.percent, required this.others});

  final double percent;
  final List<double> others;

  @override
  State<_AnimatedPath> createState() => _AnimatedPathState();
}

class _AnimatedPathState extends State<_AnimatedPath>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late Animation<double> _a;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      duration: const Duration(milliseconds: 720),
      vsync: this,
    );
    _a = Tween<double>(begin: 0, end: widget.percent)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
    _c.forward();
  }

  @override
  void didUpdateWidget(_AnimatedPath old) {
    super.didUpdateWidget(old);
    if (old.percent != widget.percent) {
      _a = Tween<double>(begin: _a.value, end: widget.percent)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
      _c
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (context, _) => CustomPaint(
        painter: _MomentumPathPainter(
          percent: _a.value,
          others: widget.others,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _MomentumPathPainter extends CustomPainter {
  _MomentumPathPainter({required this.percent, required this.others});

  final double percent;
  final List<double> others;

  /// The trajectory: a shallow rising curve across the card.
  Path _trajectory(Size size) {
    final startX = 6.0;
    final endX = size.width - 20;
    final baseY = size.height - 20;
    final riseY = 16.0;
    return Path()
      ..moveTo(startX, baseY)
      ..cubicTo(
        startX + (endX - startX) * 0.34, baseY + 2,
        startX + (endX - startX) * 0.60, riseY + 6,
        endX, riseY,
      );
  }

  Offset _pointAt(Path path, double t) {
    final metric = path.computeMetrics().first;
    final pos = metric.getTangentForOffset(metric.length * t)?.position;
    return pos ?? Offset.zero;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _trajectory(size);
    final t = (percent / 100).clamp(0.0, 1.0);

    // Pale-blue full track.
    canvas.drawPath(
      path,
      Paint()
        ..color = NuvoColors.secondarySurface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );

    // Finish marker — a small flag post at the end of the path.
    final finish = _pointAt(path, 1);
    canvas.drawLine(
      finish.translate(0, -3),
      finish.translate(0, -20),
      Paint()
        ..color = NuvoColors.border
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
    final flag = Path()
      ..moveTo(finish.dx, finish.dy - 20)
      ..lineTo(finish.dx + 11, finish.dy - 16.5)
      ..lineTo(finish.dx, finish.dy - 13)
      ..close();
    canvas.drawPath(flag, Paint()..color = NuvoColors.navy);

    // Competitor markers — hollow, quiet, behind the user's marker.
    for (final o in others) {
      final p = _pointAt(path, (o / 100).clamp(0.0, 1.0));
      canvas.drawCircle(p, 5, Paint()..color = NuvoColors.surface);
      canvas.drawCircle(
        p,
        5,
        Paint()
          ..color = NuvoColors.textMuted.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }

    // Drawn blue progress.
    if (t > 0) {
      final metric = path.computeMetrics().first;
      final travelled = metric.extractPath(0, metric.length * t);
      canvas.drawPath(
        travelled,
        Paint()
          ..color = NuvoColors.blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round,
      );

      // The user's marker with a soft halo.
      final head = _pointAt(path, t);
      canvas.drawCircle(
        head,
        13,
        Paint()..color = NuvoColors.blue.withValues(alpha: 0.13),
      );
      canvas.drawCircle(head, 7.5, Paint()..color = NuvoColors.surface);
      canvas.drawCircle(head, 5.5, Paint()..color = NuvoColors.blue);
    } else {
      // At zero, still show a clear start marker so the card never looks empty.
      final start = _pointAt(path, 0);
      canvas.drawCircle(start, 7.5, Paint()..color = NuvoColors.surface);
      canvas.drawCircle(
        start,
        5.5,
        Paint()
          ..color = NuvoColors.blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_MomentumPathPainter old) =>
      old.percent != percent || !listEquals(old.others, others);
}

bool listEquals(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ═══════════════════════════════════════════════════════════════════════════════
// PAGE DOTS
// ═══════════════════════════════════════════════════════════════════════════════

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 20 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == index
                  ? NuvoColors.blue
                  : NuvoColors.border,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// QUICK ACTIONS
// ═══════════════════════════════════════════════════════════════════════════════

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.hasActiveRace,
    required this.onSubmitProof,
    required this.onStart,
    required this.onJoin,
    required this.onInvite,
  });

  final bool hasActiveRace;
  final VoidCallback? onSubmitProof;
  final VoidCallback onStart;
  final VoidCallback onJoin;
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) {
    // Prioritised: the most relevant action is wide, the rest are compact.
    final lead = hasActiveRace
        ? _Quick(
            icon: Icons.photo_camera_outlined,
            label: 'Submit proof',
            onTap: onSubmitProof,
            emphasised: true,
          )
        : _Quick(
            icon: Icons.add_rounded,
            label: 'Start a race',
            onTap: onStart,
            emphasised: true,
          );

    final secondary = hasActiveRace
        ? [
            _Quick(icon: Icons.add_rounded, label: 'Start', onTap: onStart),
            _Quick(
                icon: Icons.group_add_outlined,
                label: 'Invite',
                onTap: onInvite),
          ]
        : [
            _Quick(
                icon: Icons.login_rounded, label: 'Join', onTap: onJoin),
            _Quick(
                icon: Icons.group_add_outlined,
                label: 'Crew',
                onTap: () => context.go('/pass')),
          ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(flex: 2, child: lead),
          const SizedBox(width: 10),
          for (final s in secondary) ...[
            Expanded(child: s),
            if (s != secondary.last) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

class _Quick extends StatelessWidget {
  const _Quick({
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasised = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = !enabled
        ? NuvoColors.disabledText
        : emphasised
            ? NuvoColors.white
            : NuvoColors.navy;

    return PressableScale(
      onTap: onTap,
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: !enabled
              ? NuvoColors.disabledSurface
              : emphasised
                  ? NuvoColors.blue
                  : NuvoColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: emphasised
              ? null
              : Border.all(color: NuvoColors.border, width: 1),
          boxShadow: emphasised
              ? AppShadows.trackBlueGlowSubtle
              : AppShadows.card,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: fg),
            if (emphasised) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION HEADER
// ═══════════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, this.action, this.onAction});

  final String label;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(width: 3, height: 13, color: NuvoColors.blue),
          const SizedBox(width: 9),
          Text(
            label.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: NuvoColors.navy,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.3,
              fontSize: 11,
            ),
          ),
          const Spacer(),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Text(
                  action!,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.blue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CREW STANDINGS — restrained podium + refined rows
// ═══════════════════════════════════════════════════════════════════════════════

class _Standings extends StatelessWidget {
  const _Standings({required this.rows});

  final List<ArenaMiniLeaderboardRow> rows;

  @override
  Widget build(BuildContext context) {
    final top = rows.take(3).toList();
    final rest = rows.skip(3).take(4).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: NuvoColors.border, width: 1),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          children: [
            // Podium: 2nd, 1st, 3rd — first place raised and larger.
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: top.length > 1
                      ? _Podium(row: top[1], place: 2)
                      : const SizedBox.shrink(),
                ),
                Expanded(
                  child: top.isNotEmpty
                      ? _Podium(row: top[0], place: 1)
                      : const SizedBox.shrink(),
                ),
                Expanded(
                  child: top.length > 2
                      ? _Podium(row: top[2], place: 3)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
            if (rest.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Divider(height: 1, color: NuvoColors.border),
              for (final r in rest)
                _StandingRow(row: r, rank: rows.indexOf(r) + 1),
            ] else
              const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.row, required this.place});

  final ArenaMiniLeaderboardRow row;
  final int place;

  @override
  Widget build(BuildContext context) {
    final first = place == 1;
    final size = first ? 58.0 : 46.0;
    final me = row.isCurrentUser;
    final accent = me ? NuvoColors.blue : NuvoColors.navy;

    return Semantics(
      label: 'Rank $place, ${row.label}, ${row.value}',
      child: Column(
        children: [
          if (first)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Icon(Icons.workspace_premium_rounded,
                  size: 18, color: NuvoColors.gold),
            ),
          Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: me
                        ? NuvoColors.blue
                        : NuvoColors.border,
                    width: me ? 2 : 1.5,
                  ),
                ),
                child: NuvoAvatar(
                  initials: _initials(row.label),
                  photoUrl: row.profilePhotoUrl,
                  size: size,
                  bgColor: NuvoColors.secondarySurface,
                  textColor: accent,
                  borderColor: Colors.transparent,
                  borderWidth: 0,
                ),
              ),
              Positioned(
                bottom: -6,
                child: Container(
                  width: 21,
                  height: 21,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: me ? NuvoColors.blue : NuvoColors.navy,
                    shape: BoxShape.circle,
                    border: Border.all(color: NuvoColors.surface, width: 2),
                  ),
                  child: Text(
                    '$place',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: NuvoColors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            me ? 'You' : row.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelSmall.copyWith(
              color: me ? NuvoColors.blue : NuvoColors.navy,
              fontWeight: FontWeight.w800,
              fontSize: first ? 13 : 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            row.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(
              color: NuvoColors.textMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({required this.row, required this.rank});

  final ArenaMiniLeaderboardRow row;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final me = row.isCurrentUser;
    return Semantics(
      label: 'Rank $rank, ${row.label}, ${row.value}',
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: NuvoColors.border)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '$rank',
                style: AppTextStyles.labelSmall.copyWith(
                  color: me ? NuvoColors.blue : NuvoColors.textMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            NuvoAvatar(
              initials: _initials(row.label),
              photoUrl: row.profilePhotoUrl,
              size: 30,
              bgColor: NuvoColors.secondarySurface,
              textColor: me ? NuvoColors.blue : NuvoColors.navy,
              borderColor: me ? NuvoColors.blue : Colors.transparent,
              borderWidth: me ? 1.5 : 0,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                me ? 'You' : row.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: me ? NuvoColors.blue : NuvoColors.navy,
                  fontWeight: me ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
            Text(
              row.value,
              style: AppTextStyles.labelSmall.copyWith(
                color: NuvoColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
      .toUpperCase();
}

// ═══════════════════════════════════════════════════════════════════════════════
// RECENT ACTIVITY
// ═══════════════════════════════════════════════════════════════════════════════

class _ActivityStream extends StatelessWidget {
  const _ActivityStream({required this.items});

  final List<ArenaActivity> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: NuvoColors.border, width: 1),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          children: [
            for (var i = 0; i < items.take(5).length; i++)
              _ActivityRow(
                item: items[i],
                last: i == items.take(5).length - 1,
              ),
          ],
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item, required this.last});

  final ArenaActivity item;
  final bool last;

  (IconData, Color) get _mark => switch (item.type) {
        'proof_submitted' => (Icons.verified_rounded, NuvoColors.success),
        'finished' => (Icons.flag_rounded, NuvoColors.blue),
        'joined' => (Icons.person_add_rounded, NuvoColors.blue),
        'leader_changed' => (Icons.trending_up_rounded, NuvoColors.warning),
        _ => (Icons.schedule_rounded, NuvoColors.textMuted),
      };

  @override
  Widget build(BuildContext context) {
    final (icon, tint) = _mark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: NuvoColors.border)),
      ),
      child: Row(
        children: [
          NuvoAvatar(
            initials: _initials(item.actorName),
            size: 34,
            bgColor: NuvoColors.secondarySurface,
            textColor: NuvoColors.navy,
            borderColor: Colors.transparent,
            borderWidth: 0,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.navy,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(icon, size: 12, color: tint),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        [
                          if (item.raceTitle != null) item.raceTitle!,
                          item.timeLabel,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: NuvoColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityEmpty extends StatelessWidget {
  const _ActivityEmpty({required this.onAction, required this.actionLabel});

  final VoidCallback onAction;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: NuvoColors.border, width: 1),
        ),
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: NuvoColors.secondarySurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.bolt_rounded,
                  color: NuvoColors.blue, size: 22),
            ),
            const SizedBox(height: 14),
            Text(
              'No verified movement yet',
              style: AppTextStyles.labelMedium.copyWith(
                color: NuvoColors.navy,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Your crew\'s proof lands here as it\nclears verification.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: NuvoColors.textMuted,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            PressableScale(
              onTap: onAction,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                decoration: BoxDecoration(
                  color: NuvoColors.blue,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  actionLabel,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: NuvoColors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EMPTY / LOADING
// ═══════════════════════════════════════════════════════════════════════════════

class _ArenaEmptyHero extends StatelessWidget {
  const _ArenaEmptyHero({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: NuvoColors.border, width: 1),
          boxShadow: AppShadows.heroShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: NuvoColors.secondarySurface,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                'START LINE',
                style: AppTextStyles.labelSmall.copyWith(
                  color: NuvoColors.blue,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                  fontSize: 9,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Set your first finish line',
              style: AppTextStyles.headlineMedium.copyWith(
                color: NuvoColors.navy,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pick a movement, set a target, and pull in your crew. '
              'Your progress shows up here.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: NuvoColors.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            const _MomentumPath(percent: 0),
            const SizedBox(height: 20),
            _PrimaryAction(label: 'Start a race', onTap: onStart),
          ],
        ),
      ),
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 300,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: NuvoColors.border, width: 1),
          boxShadow: AppShadows.card,
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Bar(width: 92, height: 18),
            SizedBox(height: 18),
            _Bar(width: 210, height: 26),
            SizedBox(height: 10),
            _Bar(width: 150, height: 44),
            SizedBox(height: 22),
            _Bar(width: double.infinity, height: 7),
            Spacer(),
            _Bar(width: double.infinity, height: 52),
          ],
        ),
      ),
    );
  }
}

class _ActivitySkeleton extends StatelessWidget {
  const _ActivitySkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: NuvoColors.border, width: 1),
        ),
        child: Column(
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == 2 ? 0 : 14),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(
                        color: NuvoColors.disabledSurface,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 11),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Bar(width: double.infinity, height: 11),
                          SizedBox(height: 6),
                          _Bar(width: 110, height: 9),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A single calm placeholder bar. No shimmer — a live demo should never show
/// continuously animating decoration.
class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: NuvoColors.disabledSurface,
        borderRadius: BorderRadius.circular(math.min(height / 2, 8)),
      ),
    );
  }
}
