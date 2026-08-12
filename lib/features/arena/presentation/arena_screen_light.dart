import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/arena_models.dart';
import 'arena_controller.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ARENA — Light-mode home dashboard.
// Clean, confident, and visually consistent with the approved light tabs.
// ═══════════════════════════════════════════════════════════════════════════════

class ArenaScreen extends ConsumerStatefulWidget {
  const ArenaScreen({super.key});

  @override
  ConsumerState<ArenaScreen> createState() => _ArenaScreenState();
}

class _ArenaScreenState extends ConsumerState<ArenaScreen> {
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
    final nextBoard = boards.isEmpty ? null : boards.first;
    final activity = snapshot?.activity ?? const <ArenaActivity>[];

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: RefreshIndicator(
        color: NuvoColors.blue,
        backgroundColor: NuvoColors.surface,
        onRefresh: () =>
            ref.read(arenaControllerProvider.notifier).loadSnapshot(),
        child: ListView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: EdgeInsets.only(
            top: safeTop + 14,
            bottom: NuvoBottomNav.bottomPadding(context),
          ),
          children: [
            _ArenaHeader(
              greeting: _greeting(user?.fullName),
              pulse: snapshot?.headerPulse ?? '',
            ),
            const SizedBox(height: 20),

                    if (state.error != null && snapshot == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: NuvoErrorState(
                          message: state.error!,
                          onRetry: () => ref
                              .read(arenaControllerProvider.notifier)
                              .loadSnapshot(),
                        ),
                      )
                    else if (state.loading && snapshot == null)
                      const _HeroSkeleton()
                    else if (nextBoard == null)
                      _EmptyHero(onStart: () => context.push('/races/new'))
                    else
                      _NextMoveHero(
                        board: nextBoard,
                        onAction: () => _runAction(nextBoard),
                      ),

                    // Crew standings
                    if (nextBoard != null &&
                        nextBoard.miniLeaderboard.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      _SectionHeader(
                        label: 'Crew standings',
                        action: 'View all',
                        onAction: () => context.push('/race/${nextBoard.id}'),
                      ),
                      const SizedBox(height: 14),
                      _Standings(rows: nextBoard.miniLeaderboard),
                    ],

                    // Recent activity
                    const SizedBox(height: 28),
                    const _SectionHeader(label: 'Recent activity'),
                    const SizedBox(height: 14),
                    if (state.loading && snapshot == null)
                      const _ActivitySkeleton()
                    else if (activity.isEmpty)
                      _ActivityEmpty(
                        onAction: nextBoard != null
                            ? () =>
                                context.push('/race/${nextBoard.id}/proof')
                            : () => context.push('/races/new'),
                        actionLabel:
                            nextBoard != null ? 'Submit proof' : 'Start a race',
                      )
                    else
                      _ActivityStream(items: activity),
          ],
        ),
      ),
    );
  }

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
  const _ArenaHeader({required this.greeting, required this.pulse});

  final String greeting;
  final String pulse;

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
                  letterSpacing: 2.0,
                  fontSize: 10,
                ),
              ),
              const Spacer(),
              if (pulse.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: NuvoColors.blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(NuvoRadii.pill),
                    border: Border.all(
                      color: NuvoColors.blue.withValues(alpha: 0.15),
                    ),
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
                      Text(
                        pulse,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: NuvoColors.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Arena',
            style: AppTextStyles.screenTitle.copyWith(
              color: NuvoColors.navy,
              fontSize: 34,
            ),
          ),
          const SizedBox(height: 6),
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
// NEXT MOVE HERO
// ═══════════════════════════════════════════════════════════════════════════════

class _NextMoveHero extends StatelessWidget {
  const _NextMoveHero({required this.board, required this.onAction});

  final ArenaBoard board;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final pct = (board.progressPercent ?? 0).clamp(0, 100);
    final parts = _splitProgress(board.progressLabel);
    final participants = board.miniLeaderboard.take(3).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(24),
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
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: NuvoColors.blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    'YOUR NEXT MOVE',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: NuvoColors.blue,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      fontSize: 9,
                    ),
                  ),
                ),
                const Spacer(),
                if (board.myRank != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: NuvoColors.panelLight,
                      borderRadius: BorderRadius.circular(NuvoRadii.pill),
                    ),
                    child: Text(
                      '#${board.myRank}',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: NuvoColors.navy,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                  ),
                if (board.daysLeft != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    board.daysLeft == 0
                        ? 'Last day'
                        : '${board.daysLeft}d left',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: NuvoColors.textMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
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
            const SizedBox(height: 16),

            // Progress number
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    parts.$1,
                    style: AppTextStyles.number(
                      46,
                      color: NuvoColors.blue,
                      weight: FontWeight.w800,
                    ),
                  ),
                  if (parts.$2.isNotEmpty)
                    Text(
                      ' / ${parts.$2}',
                      style: AppTextStyles.number(
                        26,
                        color: NuvoColors.navy,
                        weight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(width: 12),
                  if (board.racerCount != null && board.racerCount! > 0)
                    Text(
                      '${board.racerCount} racing',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: NuvoColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Progress route
            _ProgressRoute(
              percent: pct,
              participants: participants,
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

            const SizedBox(height: 18),
            _AvatarRow(users: participants),
            const SizedBox(height: 12),
            if (board.primaryActionType != 'none')
              NuvoPrimaryButton(
                label: board.primaryActionLabel,
                small: true,
                onPressed: onAction,
              ),
          ],
        ),
      ),
    );
  }
}

(String, String) _splitProgress(String label) {
  final idx = label.indexOf('/');
  if (idx == -1) return (label.trim(), '');
  return (label.substring(0, idx).trim(), label.substring(idx + 1).trim());
}

class _AvatarRow extends StatelessWidget {
  const _AvatarRow({required this.users});
  final List<ArenaMiniLeaderboardRow> users;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < users.length; i++) ...[
          if (i > 0)
            Transform.translate(
              offset: const Offset(-6, 0),
              child: NuvoAvatar(
                initials: _initials(users[i].label),
                photoUrl: users[i].profilePhotoUrl,
                size: 28,
                bgColor: NuvoColors.panelLight,
                textColor: NuvoColors.navy,
                borderColor: NuvoColors.surface,
                borderWidth: 2,
              ),
            )
          else
            NuvoAvatar(
              initials: _initials(users[i].label),
              photoUrl: users[i].profilePhotoUrl,
              size: 28,
              bgColor: NuvoColors.panelLight,
              textColor: NuvoColors.navy,
              borderColor: NuvoColors.surface,
              borderWidth: 2,
            ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROGRESS ROUTE
// A shallow horizontal path. Pale-blue track, electric-blue progress,
// user avatar at the tip, small flag at the finish.
// ═══════════════════════════════════════════════════════════════════════════════

class _ProgressRoute extends StatelessWidget {
  const _ProgressRoute({required this.percent, required this.participants});
  final int percent;
  final List<ArenaMiniLeaderboardRow> participants;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final others = <int>[];
    for (final p in participants.where((r) => !r.isCurrentUser)) {
      final v = _leadingNumber(p.value);
      if (v != null) others.add(v.clamp(0, 100));
    }

    return SizedBox(
      height: 56,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return reduceMotion
              ? CustomPaint(
                  size: Size(width, 56),
                  painter: _ProgressRoutePainter(
                    percent: percent,
                    others: others,
                  ),
                )
              : _AnimatedProgressRoute(percent: percent, others: others);
        },
      ),
    );
  }
}

int? _leadingNumber(String s) {
  final m = RegExp(r'(\d+)').firstMatch(s);
  if (m == null) return null;
  return int.tryParse(m.group(1)!);
}

class _AnimatedProgressRoute extends StatefulWidget {
  const _AnimatedProgressRoute({required this.percent, required this.others});
  final int percent;
  final List<int> others;

  @override
  State<_AnimatedProgressRoute> createState() => _AnimatedProgressRouteState();
}

class _AnimatedProgressRouteState extends State<_AnimatedProgressRoute>
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
    _a = Tween<double>(begin: 0, end: widget.percent / 100)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
    _c.forward();
  }

  @override
  void didUpdateWidget(_AnimatedProgressRoute old) {
    super.didUpdateWidget(old);
    if (old.percent != widget.percent) {
      _a = Tween<double>(begin: _a.value, end: widget.percent / 100)
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
        size: Size.infinite,
        painter: _ProgressRoutePainter(
          percent: (_a.value * 100).round(),
          others: widget.others,
        ),
      ),
    );
  }
}

class _ProgressRoutePainter extends CustomPainter {
  _ProgressRoutePainter({required this.percent, required this.others});

  final int percent;
  final List<int> others;

  Path _path(Size size) {
    final startX = 10.0;
    final endX = size.width - 18;
    final y = size.height / 2 + 2;
    return Path()
      ..moveTo(startX, y)
      ..quadraticBezierTo(
        (startX + endX) / 2,
        y - 8,
        endX,
        y - 4,
      );
  }

  Offset _pointAt(Path path, double t) {
    final metric = path.computeMetrics().first;
    final pos = metric.getTangentForOffset(metric.length * t.clamp(0, 1))?.position;
    return pos ?? Offset.zero;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _path(size);
    final t = (percent / 100).clamp(0.0, 1.0);

    // Full track
    canvas.drawPath(
      path,
      Paint()
        ..color = NuvoColors.trackBg
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );

    // Finish flag
    final finish = _pointAt(path, 1);
    canvas.drawLine(
      Offset(finish.dx, finish.dy - 3),
      Offset(finish.dx, finish.dy - 18),
      Paint()
        ..color = NuvoColors.border
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
    final flag = Path()
      ..moveTo(finish.dx, finish.dy - 18)
      ..lineTo(finish.dx + 9, finish.dy - 15)
      ..lineTo(finish.dx, finish.dy - 12)
      ..close();
    canvas.drawPath(flag, Paint()..color = NuvoColors.navy);

    // Other markers
    for (final o in others) {
      final p = _pointAt(path, o / 100);
      canvas.drawCircle(p, 4.5, Paint()..color = NuvoColors.surface);
      canvas.drawCircle(
        p,
        4.5,
        Paint()
          ..color = NuvoColors.textMuted.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // Progress
    if (t > 0) {
      final metric = path.computeMetrics().first;
      final travelled = metric.extractPath(0, metric.length * t);
      canvas.drawPath(
        travelled,
        Paint()
          ..color = NuvoColors.blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      );

      // User marker
      final head = _pointAt(path, t);
      canvas.drawCircle(head, 12, Paint()..color = NuvoColors.blue.withValues(alpha: 0.12));
      canvas.drawCircle(head, 7, Paint()..color = NuvoColors.surface);
      canvas.drawCircle(head, 5, Paint()..color = NuvoColors.blue);
    } else {
      final start = _pointAt(path, 0);
      canvas.drawCircle(start, 7, Paint()..color = NuvoColors.surface);
      canvas.drawCircle(
        start,
        5,
        Paint()
          ..color = NuvoColors.blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_ProgressRoutePainter old) =>
      old.percent != percent || !_listEquals(old.others, others);

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: NuvoColors.blue,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: NuvoColors.textMuted,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
          const Spacer(),
          if (action != null)
            PressableScale(
              onTap: onAction,
              child: Text(
                action!,
                style: AppTextStyles.labelSmall.copyWith(
                  color: NuvoColors.blue,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STANDINGS
// ═══════════════════════════════════════════════════════════════════════════════

class _Standings extends StatelessWidget {
  const _Standings({required this.rows});
  final List<ArenaMiniLeaderboardRow> rows;

  @override
  Widget build(BuildContext context) {
    final top = rows.take(3).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: NuvoColors.border, width: 1),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          children: [
            for (var i = 0; i < top.length; i++)
              _StandingRow(row: top[i], rank: i + 1, isLast: i == top.length - 1),
          ],
        ),
      ),
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.row,
    required this.rank,
    this.isLast = false,
  });
  final ArenaMiniLeaderboardRow row;
  final int rank;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final me = row.isCurrentUser;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: isLast
          ? null
          : const BoxDecoration(
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
            size: 32,
            bgColor: NuvoColors.panelLight,
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelSmall.copyWith(
              color: NuvoColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
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
        clipBehavior: Clip.antiAlias,
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
            bgColor: NuvoColors.panelLight,
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: NuvoColors.border, width: 1),
        ),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: NuvoColors.panelLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.bolt_rounded,
                color: NuvoColors.blue,
                size: 22,
              ),
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
              'Your crew\'s proof lands here as it clears verification.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: NuvoColors.textMuted,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            NuvoPrimaryButton(
              label: actionLabel,
              small: true,
              onPressed: onAction,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EMPTY / LOADING / SKELETON
// ═══════════════════════════════════════════════════════════════════════════════

class _EmptyHero extends StatelessWidget {
  const _EmptyHero({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: NuvoColors.border, width: 1),
          boxShadow: AppShadows.heroShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: NuvoColors.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                'START LINE',
                style: AppTextStyles.labelSmall.copyWith(
                  color: NuvoColors.blue,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                  fontSize: 9,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Set your first finish line',
              style: AppTextStyles.headlineMedium.copyWith(
                color: NuvoColors.navy,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pick a movement, set a target, and pull in your crew.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: NuvoColors.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            NuvoPrimaryButton(
              label: 'Start a race',
              small: true,
              onPressed: onStart,
            ),
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
        height: 280,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: NuvoColors.border, width: 1),
          boxShadow: AppShadows.card,
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SkeletonBar(width: 92, height: 18),
            SizedBox(height: 16),
            _SkeletonBar(width: 210, height: 26),
            SizedBox(height: 10),
            _SkeletonBar(width: 150, height: 44),
            SizedBox(height: 22),
            _SkeletonBar(width: double.infinity, height: 7),
            Spacer(),
            _SkeletonBar(width: double.infinity, height: 46),
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
                          _SkeletonBar(width: double.infinity, height: 11),
                          SizedBox(height: 6),
                          _SkeletonBar(width: 110, height: 9),
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

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.width, required this.height});
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

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
      .toUpperCase();
}
