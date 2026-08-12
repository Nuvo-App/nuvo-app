import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/camera_verification_resolver.dart';
import '../../races/domain/race_display.dart';
import '../../races/presentation/create_race_screen.dart';
import '../../races/presentation/race_controller.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// COMPETE — Light-Mode "Race Control"
// Energetic, bright race command center with electric-blue accents.
// ═══════════════════════════════════════════════════════════════════════════════

class CompeteScreen extends ConsumerWidget {
  const CompeteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raceState = ref.watch(raceControllerProvider);
    final user = ref.watch(authControllerProvider).user;
    final uid = user?.id;

    final cameraRaces = raceState.races
        .where((race) => resolveCameraVerification(race).isCameraVerifiable)
        .toList();
    final active = cameraRaces.where(raceIsActive).toList();
    final waiting = active.where((race) => race.participantCount <= 1).toList();
    final inMotion = active.where((race) => race.participantCount > 1).toList();
    final finished = raceState.races
        .where(raceIsCompleted)
        .where((race) => resolveCameraVerification(race).isCameraVerifiable)
        .toList();

    final featured = inMotion.isNotEmpty ? inMotion.first : null;
    final queueRaces = inMotion.length > 1 ? inMotion.sublist(1) : <Race>[];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: NuvoColors.page,
        body: RefreshIndicator(
          color: NuvoColors.blue,
          backgroundColor: NuvoColors.surface,
          onRefresh: () =>
              ref.read(raceControllerProvider.notifier).loadRaces(),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: _buildBody(
                  context,
                  raceState: raceState,
                  uid: uid,
                  featured: featured,
                  queueRaces: queueRaces,
                  waiting: waiting,
                  finished: finished,
                  active: active,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required RaceState raceState,
    required String? uid,
    required Race? featured,
    required List<Race> queueRaces,
    required List<Race> waiting,
    required List<Race> finished,
    required List<Race> active,
  }) {
    final safeTop = MediaQuery.viewPaddingOf(context).top;

    return Padding(
      padding: EdgeInsets.only(bottom: NuvoBottomNav.bottomPadding(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────
          _CompeteHeader(
            safeTop: safeTop,
            activeCount: active.length,
            finishedCount: finished.length,
          ),

          // ── Content ─────────────────────────────────────────────────
          if (raceState.loading && raceState.races.isEmpty)
            const _LoadingState()
          else if (raceState.error != null && raceState.races.isEmpty)
            _ErrorState(message: raceState.error!)
          else if (active.isEmpty && finished.isEmpty)
            _EmptyState(
              onStart: () => context.push('/races/new'),
              onJoin: () => context.push('/races/join'),
            )
          else ...[
            // Featured race
            if (featured != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: _FeaturedRaceCard(
                  race: featured,
                  userId: uid,
                  onOpen: () => context.push('/race/${featured.id}'),
                  onVerify: () => context.push('/race/${featured.id}/proof'),
                ),
              ),

            // Action dock
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: _ActionDock(
                onStart: () => context.push('/races/new'),
                onJoin: () => context.push('/races/join'),
              ),
            ),

            // Race queue
            if (queueRaces.isNotEmpty) ...[
              _Section(title: 'In motion'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _RaceQueue(
                  races: queueRaces,
                  userId: uid,
                  onOpen: (r) => context.push('/race/${r.id}'),
                  onVerify: (r) => context.push('/race/${r.id}/proof'),
                ),
              ),
            ],

            // Starting grid
            if (waiting.isNotEmpty) ...[
              _Section(title: 'Starting grid'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _StartingGrid(
                  races: waiting,
                  onOpen: (r) => context.push('/race/${r.id}'),
                  onInvite: (r) => context.push('/race/${r.id}/invite'),
                ),
              ),
            ],

            // Results
            if (finished.isNotEmpty) ...[
              _Section(title: 'Results'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _ResultsList(
                  races: finished,
                  userId: uid,
                  onOpen: (r) => context.push('/race/${r.id}'),
                ),
              ),
            ],

            // Quick starts
            _Section(title: 'Quick start'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _QuickStarts(
                onTap: (p) => context.push('/races/new', extra: p),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HEADER
// ═══════════════════════════════════════════════════════════════════════════════

class _CompeteHeader extends StatelessWidget {
  const _CompeteHeader({
    required this.safeTop,
    required this.activeCount,
    required this.finishedCount,
  });
  final double safeTop;
  final int activeCount;
  final int finishedCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(22, safeTop + 14, 22, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Brand row
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
              if (activeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                        decoration: BoxDecoration(
                          color: NuvoColors.blue,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: NuvoColors.blue.withValues(alpha: 0.4),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$activeCount live',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: NuvoColors.blue,
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
          // Title
          Text(
            'Compete',
            style: AppTextStyles.screenTitle.copyWith(
              color: NuvoColors.navy,
              fontSize: 34,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Set a finish line. Pull in your crew.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: NuvoColors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              _StatPill(value: activeCount, label: 'active'),
              const SizedBox(width: 6),
              _StatPill(value: finishedCount, label: 'done'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: NuvoColors.panelLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: AppTextStyles.number(16, color: NuvoColors.navy, weight: FontWeight.w800),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: NuvoColors.textMuted,
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FEATURED RACE — Signature component
// ═══════════════════════════════════════════════════════════════════════════════

class _FeaturedRaceCard extends StatelessWidget {
  const _FeaturedRaceCard({
    required this.race,
    required this.userId,
    required this.onOpen,
    required this.onVerify,
  });
  final Race race;
  final String? userId;
  final VoidCallback onOpen;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final myPart = userId != null ? race.participantFor(userId!) : null;
    final rank = rankForUser(race, userId);
    final target = race.targetValue;
    final remaining = target != null && myPart != null
        ? (target - myPart.progressValue).clamp(0, target)
        : null;
    final ranked = serverRankedParticipants(race);

    return PressableScale(
      onTap: onOpen,
      scale: 0.98,
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
            // Status + rank
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: NuvoColors.blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'FEATURED RACE',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: NuvoColors.blue,
                      fontWeight: FontWeight.w900,
                      fontSize: 9,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const Spacer(),
                if (rank != null)
                  Text(
                    '#$rank of ${race.participantCount}',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: NuvoColors.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Title
            Text(
              race.displayTitle,
              style: AppTextStyles.headlineMedium.copyWith(
                color: NuvoColors.navy,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),

            // Progress text
            Row(
              children: [
                Text(
                  raceProgressLabel(race, myPart),
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: NuvoColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (remaining != null && remaining > 0) ...[
                  Text(
                    '  ·  ',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: NuvoColors.border,
                    ),
                  ),
                  Text(
                    '$remaining left',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: NuvoColors.blue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),

            // Momentum Lane — head-to-head visualization
            SizedBox(
              height: 56,
              child: CustomPaint(
                painter: _MomentumLanePainter(
                  participants: ranked,
                  userId: userId,
                  targetValue: race.targetValue ?? 100,
                ),
                size: Size.infinite,
              ),
            ),
            const SizedBox(height: 16),

            // Bottom: avatars + verify CTA
            Row(
              children: [
                if (race.participants.where((p) => p.userId != userId).isNotEmpty) ...[
                  NuvoAvatarStack(
                    avatars: race.participants
                        .where((p) => p.userId != userId)
                        .take(3)
                        .map((p) => (
                              initials: p.displayName,
                              photoUrl: p.profilePhotoUrl,
                            ))
                        .toList(),
                    total: race.participantCount,
                    size: 28,
                    max: 3,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${race.participantCount} competing',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: NuvoColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
                // Verify button
                Semantics(
                  button: true,
                  label: 'Submit proof',
                  child: PressableScale(
                    onTap: onVerify,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: NuvoColors.blue,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: AppShadows.trackBlueGlow,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                          const SizedBox(width: 7),
                          Text(
                            'Verify',
                            style: AppTextStyles.labelMedium.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Momentum Lane — Head-to-head dual lane visualization.
/// Two parallel lanes show user and best opponent advancing toward a finish line.
/// Inspired by Arena's track geometry: trajectory lines, precise markers, blue glow.
class _MomentumLanePainter extends CustomPainter {
  _MomentumLanePainter({
    required this.participants,
    required this.userId,
    required this.targetValue,
  });
  final List<RaceParticipant> participants;
  final String? userId;
  final int targetValue;

  @override
  void paint(Canvas canvas, Size size) {
    const laneHeight = 18.0;
    const laneGap = 6.0;
    const trackLeft = 12.0;
    final trackRight = size.width - 12.0;
    final trackWidth = trackRight - trackLeft;
    final topLaneY = (size.height - laneHeight * 2 - laneGap) / 2;
    final bottomLaneY = topLaneY + laneHeight + laneGap;

    final userPart = participants.where((p) => p.userId == userId).firstOrNull;
    final opponent = participants.where((p) => p.userId != userId).firstOrNull;

    final userProgress = _progress(userPart);
    final opponentProgress = _progress(opponent);

    // Draw lane backgrounds
    _drawLane(canvas, Offset(trackLeft, topLaneY), trackWidth, laneHeight,
        isUser: true);
    _drawLane(canvas, Offset(trackLeft, bottomLaneY), trackWidth, laneHeight,
        isUser: false);

    // Finish flag markers
    for (final laneY in [topLaneY, bottomLaneY]) {
      // Finish line (checkered pattern)
      for (var i = 0; i < 3; i++) {
        final dy = laneY + 4 + i * 4.0;
        canvas.drawRect(
          Rect.fromLTWH(trackRight - 4, dy, 4, 3),
          Paint()..color = NuvoColors.navy.withValues(alpha: i.isEven ? 0.25 : 0.08),
        );
      }
    }

    // Grid lines (quarter markers)
    for (var i = 1; i <= 3; i++) {
      final x = trackLeft + trackWidth * i / 4;
      canvas.drawLine(
        Offset(x, topLaneY),
        Offset(x, bottomLaneY + laneHeight),
        Paint()
          ..color = const Color(0xFFE2E7EE)
          ..strokeWidth = 0.5,
      );
    }

    // User progress fill (top lane)
    final userFillWidth = trackWidth * userProgress;
    if (userFillWidth > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(trackLeft, topLaneY, userFillWidth, laneHeight),
          const Radius.circular(9),
        ),
        Paint()..color = NuvoColors.blue.withValues(alpha: 0.12),
      );
    }

    // Opponent progress fill (bottom lane)
    final opFillWidth = trackWidth * opponentProgress;
    if (opFillWidth > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(trackLeft, bottomLaneY, opFillWidth, laneHeight),
          const Radius.circular(9),
        ),
        Paint()..color = const Color(0xFFE8ECF2),
      );
    }

    // User marker (top lane)
    final userX = (trackLeft + trackWidth * userProgress).clamp(
        trackLeft + 10, trackRight - 10);
    final userCenterY = topLaneY + laneHeight / 2;
    // Glow
    canvas.drawCircle(
      Offset(userX, userCenterY), 12,
      Paint()..color = NuvoColors.blue.withValues(alpha: 0.08),
    );
    // Main marker
    canvas.drawCircle(
      Offset(userX, userCenterY), 8,
      Paint()..color = NuvoColors.blue,
    );
    // Inner highlight
    canvas.drawCircle(
      Offset(userX - 2, userCenterY - 2), 3,
      Paint()..color = const Color(0xFF8ABCFF),
    );

    // Opponent marker (bottom lane)
    if (opponent != null) {
      final opX = (trackLeft + trackWidth * opponentProgress).clamp(
          trackLeft + 10, trackRight - 10);
      final opCenterY = bottomLaneY + laneHeight / 2;
      canvas.drawCircle(
        Offset(opX, opCenterY), 6,
        Paint()..color = const Color(0xFF8A9BB2),
      );
      canvas.drawCircle(
        Offset(opX, opCenterY), 3.5,
        Paint()..color = NuvoColors.surface,
      );
    }

    // Lane labels
    final userLabelPainter = TextPainter(
      text: const TextSpan(
        text: 'YOU',
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w900,
          color: NuvoColors.blue,
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    userLabelPainter.paint(
      canvas,
      Offset(trackLeft + 4, topLaneY + (laneHeight - userLabelPainter.height) / 2),
    );

    if (opponent != null) {
      final opLabelPainter = TextPainter(
        text: TextSpan(
          text: opponent.displayName.split(' ').first.toUpperCase(),
          style: const TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w700,
            color: Color(0xFF8A9BB2),
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      opLabelPainter.paint(
        canvas,
        Offset(trackLeft + 4, bottomLaneY + (laneHeight - opLabelPainter.height) / 2),
      );
    }
  }

  void _drawLane(Canvas canvas, Offset origin, double width, double height,
      {required bool isUser}) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(origin.dx, origin.dy, width, height),
      const Radius.circular(9),
    );
    canvas.drawRRect(rrect, Paint()..color = const Color(0xFFF3F6FA));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = isUser
            ? NuvoColors.blue.withValues(alpha: 0.15)
            : const Color(0xFFDDE3EB)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  double _progress(RaceParticipant? part) {
    if (part == null) return 0;
    return targetValue > 0
        ? (part.progressValue / targetValue).clamp(0.0, 1.0)
        : (part.progressPercent / 100.0).clamp(0.0, 1.0);
  }

  @override
  bool shouldRepaint(_MomentumLanePainter old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════════
// ACTION DOCK
// ═══════════════════════════════════════════════════════════════════════════════

class _ActionDock extends StatelessWidget {
  const _ActionDock({required this.onStart, required this.onJoin});
  final VoidCallback onStart;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: NuvoPrimaryButton(
            label: 'Start race',
            expand: true,
            onPressed: onStart,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: NuvoOutlineButton(
            label: 'Join race',
            expand: true,
            onPressed: onJoin,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION HEADING
// ═══════════════════════════════════════════════════════════════════════════════

class _Section extends StatelessWidget {
  const _Section({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 14),
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
            title.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: NuvoColors.textMuted,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RACE QUEUE
// ═══════════════════════════════════════════════════════════════════════════════

class _RaceQueue extends StatelessWidget {
  const _RaceQueue({
    required this.races,
    required this.userId,
    required this.onOpen,
    required this.onVerify,
  });
  final List<Race> races;
  final String? userId;
  final ValueChanged<Race> onOpen;
  final ValueChanged<Race> onVerify;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NuvoColors.border, width: 1),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < races.length; i++) ...[
            _RaceQueueRow(
              race: races[i],
              userId: userId,
              onTap: () => onOpen(races[i]),
              onVerify: () => onVerify(races[i]),
            ),
            if (i < races.length - 1)
              const Divider(height: 1, thickness: 1, indent: 62, color: NuvoColors.divider),
          ],
        ],
      ),
    );
  }
}

class _RaceQueueRow extends StatelessWidget {
  const _RaceQueueRow({
    required this.race,
    required this.userId,
    required this.onTap,
    required this.onVerify,
  });
  final Race race;
  final String? userId;
  final VoidCallback onTap;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final myPart = userId != null ? race.participantFor(userId!) : null;
    final pct = raceProgressPercent(race, myPart);
    final rank = rankForUser(race, userId);

    return PressableScale(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            // Progress ring
            SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: pct / 100.0,
                    strokeWidth: 3,
                    backgroundColor: NuvoColors.trackBg,
                    valueColor: const AlwaysStoppedAnimation(NuvoColors.blue),
                  ),
                  Text(
                    '$pct',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: NuvoColors.navy,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    race.displayTitle,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: NuvoColors.navy,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    rank != null
                        ? '#$rank · ${race.participantCount} racing'
                        : '${race.participantCount} racing',
                    style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.textMuted),
                  ),
                ],
              ),
            ),
            PressableScale(
              onTap: onVerify,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: NuvoColors.blue,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: AppShadows.hardSmall,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 17),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STARTING GRID
// ═══════════════════════════════════════════════════════════════════════════════

class _StartingGrid extends StatelessWidget {
  const _StartingGrid({
    required this.races,
    required this.onOpen,
    required this.onInvite,
  });
  final List<Race> races;
  final ValueChanged<Race> onOpen;
  final ValueChanged<Race> onInvite;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < races.length; i++) ...[
          _GridRow(
            race: races[i],
            onOpen: () => onOpen(races[i]),
            onInvite: () => onInvite(races[i]),
          ),
          if (i < races.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _GridRow extends StatelessWidget {
  const _GridRow({
    required this.race,
    required this.onOpen,
    required this.onInvite,
  });
  final Race race;
  final VoidCallback onOpen;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: NuvoColors.border, width: 1),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            // Position markers
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: i < race.participantCount
                          ? NuvoColors.blue.withValues(alpha: 0.1)
                          : NuvoColors.panelLight,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: i < race.participantCount
                            ? NuvoColors.blue.withValues(alpha: 0.3)
                            : NuvoColors.border,
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      i < race.participantCount ? Icons.person_rounded : Icons.add_rounded,
                      size: 11,
                      color: i < race.participantCount
                          ? NuvoColors.blue
                          : NuvoColors.textMuted,
                    ),
                  ),
                  if (i < 2) const SizedBox(width: 3),
                ],
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    race.displayTitle,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: NuvoColors.navy,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${race.participantCount} joined · Needs 2+ to race',
                    style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.textMuted),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onInvite,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: NuvoColors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: NuvoColors.blue.withValues(alpha: 0.2)),
                ),
                child: Text(
                  'Invite',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.blue,
                    fontWeight: FontWeight.w900,
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
// RESULTS
// ═══════════════════════════════════════════════════════════════════════════════

class _ResultsList extends StatelessWidget {
  const _ResultsList({required this.races, required this.userId, required this.onOpen});
  final List<Race> races;
  final String? userId;
  final ValueChanged<Race> onOpen;

  @override
  Widget build(BuildContext context) {
    final display = races.take(5).toList();
    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NuvoColors.border, width: 1),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < display.length; i++) ...[
            _ResultRow(race: display[i], userId: userId, onTap: () => onOpen(display[i])),
            if (i < display.length - 1)
              const Divider(height: 1, thickness: 1, indent: 50, color: NuvoColors.divider),
          ],
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.race, required this.userId, required this.onTap});
  final Race race;
  final String? userId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rank = rankForUser(race, userId);
    final won = rank == 1;

    return PressableScale(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: won
                    ? NuvoColors.amber.withValues(alpha: 0.1)
                    : NuvoColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Icon(
                won ? Icons.emoji_events_rounded : Icons.check_rounded,
                color: won ? NuvoColors.amber : NuvoColors.success,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                race.displayTitle,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: NuvoColors.navy,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (rank != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: won
                      ? NuvoColors.amber.withValues(alpha: 0.1)
                      : NuvoColors.panelLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '#$rank',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: won ? NuvoColors.amber : NuvoColors.navy,
                    fontWeight: FontWeight.w900,
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
// QUICK STARTS
// ═══════════════════════════════════════════════════════════════════════════════

class _QuickStarts extends StatelessWidget {
  const _QuickStarts({required this.onTap});
  final ValueChanged<RaceCreatePrefill> onTap;

  static const _items = [
    (Icons.fitness_center_rounded, '100 Pushups', RaceCreatePrefill.pushups),
    (Icons.accessibility_new_rounded, '500 Jumping Jacks', RaceCreatePrefill.jumpingJacks),
    (Icons.person_outline_rounded, '15 Squats', RaceCreatePrefill.squats),
    (Icons.directions_walk_rounded, '40 Lunges', RaceCreatePrefill.lunges),
    (Icons.timer_outlined, '300s Plank', RaceCreatePrefill.plank),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _items.map((item) {
        return PressableScale(
          onTap: () => onTap(item.$3),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: NuvoColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NuvoColors.border, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.$1, color: NuvoColors.blue, size: 15),
                const SizedBox(width: 8),
                Text(
                  item.$2,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STATES
// ═══════════════════════════════════════════════════════════════════════════════

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 80),
      child: Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: NuvoColors.blue),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onStart, required this.onJoin});
  final VoidCallback onStart;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 0),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: NuvoColors.blue.withValues(alpha: 0.06),
              shape: BoxShape.circle,
              border: Border.all(color: NuvoColors.blue.withValues(alpha: 0.15), width: 1.5),
            ),
            child: const Icon(Icons.emoji_events_rounded, color: NuvoColors.blue, size: 34),
          ),
          const SizedBox(height: 28),
          Text(
            'Your first race\nawaits',
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineMedium.copyWith(color: NuvoColors.navy, height: 1.2),
          ),
          const SizedBox(height: 12),
          Text(
            'Start a race, set a finish line,\nand pull in your crew to compete.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.textMuted, height: 1.5),
          ),
          const SizedBox(height: 32),
          _ActionDock(onStart: onStart, onJoin: onJoin),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: NuvoColors.danger.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.error_outline_rounded, color: NuvoColors.danger, size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
