import 'dart:math' as math;

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
import '../../races/presentation/race_controller.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// VERIFY — Light-Mode "Proof Studio"
// Bright, trustworthy verification experience with electric-blue accents.
// ═══════════════════════════════════════════════════════════════════════════════

class MoveScreen extends ConsumerWidget {
  const MoveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raceState = ref.watch(raceControllerProvider);
    final user = ref.watch(authControllerProvider).user;
    final uid = user?.id;

    final cameraRaces = raceState.races
        .where((race) => resolveCameraVerification(race).isCameraVerifiable)
        .toList();

    final readyRaces = cameraRaces.where((race) {
      final myPart = uid != null ? race.participantFor(uid) : null;
      return race.status == 'active' && (myPart?.progressPercent ?? 0) < 100;
    }).toList();

    final completedRaces = cameraRaces.where((race) {
      final myPart = uid != null ? race.participantFor(uid) : null;
      return (myPart?.progressPercent ?? 0) >= 100;
    }).toList();

    final recentMoves = cameraRaces
        .expand((r) => r.recentProofs.map((p) => (race: r, proof: p)))
        .take(10)
        .toList();

    void openVerification(Race race) {
      debugLogCameraVerificationDecision(
        race,
        resolveCameraVerification(race),
        routeAction: 'move_screen_to_submit_proof',
      );
      context.push('/race/${race.id}/proof').then((_) {
        ref.read(raceControllerProvider.notifier).loadRaces();
      });
    }

    final safeTop = MediaQuery.viewPaddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: NuvoColors.page,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: NuvoBottomNav.bottomPadding(context),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header ────────────────────────────────────
                    _VerifyHeader(
                      safeTop: safeTop,
                      readyCount: readyRaces.length,
                      totalVerified: completedRaces.length,
                    ),

                    // ── Content ──────────────────────────────────
                    if (raceState.loading &&
                        readyRaces.isEmpty &&
                        completedRaces.isEmpty)
                      const _LoadingState()
                    else if (readyRaces.isEmpty && completedRaces.isEmpty)
                      _EmptyState(onStart: () => context.push('/races/new'))
                    else ...[
                      // Featured verification card
                      if (readyRaces.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                          child: _ProofStudioCard(
                            race: readyRaces.first,
                            userId: uid,
                            onVerify: () =>
                                openVerification(readyRaces.first),
                          ),
                        ),

                        // Other ready races
                        if (readyRaces.length > 1) ...[
                          _SectionLabel(title: 'Ready to verify'),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: _VerifyRaceList(
                              races: readyRaces.sublist(1),
                              userId: uid,
                              onVerify: openVerification,
                            ),
                          ),
                        ],
                      ],

                      // Completed
                      if (completedRaces.isNotEmpty) ...[
                        _SectionLabel(title: 'Verified'),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _CompletedSection(
                            completedRaces: completedRaces,
                            uid: uid,
                          ),
                        ),
                      ],

                      // Recent moves
                      if (recentMoves.isNotEmpty) ...[
                        _SectionLabel(title: 'Recent moves'),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _RecentMoveGroup(entries: recentMoves),
                        ),
                      ],
                    ],
                  ],
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
// HEADER
// ═══════════════════════════════════════════════════════════════════════════════

class _VerifyHeader extends StatelessWidget {
  const _VerifyHeader({
    required this.safeTop,
    required this.readyCount,
    required this.totalVerified,
  });
  final double safeTop;
  final int readyCount;
  final int totalVerified;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(22, safeTop + 14, 22, 16),
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
              if (readyCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: NuvoColors.success.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(NuvoRadii.pill),
                    border: Border.all(
                      color: NuvoColors.success.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: NuvoColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$readyCount ready',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: NuvoColors.success,
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Verify',
                style: AppTextStyles.screenTitle.copyWith(
                  color: NuvoColors.navy,
                  fontSize: 34,
                ),
              ),
              const Spacer(),
              if (totalVerified > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: NuvoColors.panelLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.verified_rounded,
                        color: NuvoColors.success,
                        size: 14,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$totalVerified verified',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: NuvoColors.textMuted,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Capture movement. Confirm progress.',
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
// PROOF STUDIO CARD — Signature component
// ═══════════════════════════════════════════════════════════════════════════════

class _ProofStudioCard extends StatelessWidget {
  const _ProofStudioCard({
    required this.race,
    required this.userId,
    required this.onVerify,
  });
  final Race race;
  final String? userId;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final myPart = userId != null ? race.participantFor(userId!) : null;
    final pct = myPart?.progressPercent ?? 0;
    final others = race.participants
        .where((p) => p.userId != userId)
        .take(3)
        .toList();

    return PressableScale(
      onTap: onVerify,
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
            // Top label
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: NuvoColors.blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.camera_alt_rounded,
                        size: 12,
                        color: NuvoColors.blue,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'PROOF STUDIO',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: NuvoColors.blue,
                          fontWeight: FontWeight.w900,
                          fontSize: 9,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Progress badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: pct > 75
                        ? NuvoColors.success.withValues(alpha: 0.08)
                        : NuvoColors.panelLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$pct%',
                    style: AppTextStyles.number(
                      16,
                      color: pct > 75 ? NuvoColors.success : NuvoColors.navy,
                      weight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              race.displayTitle,
              style: AppTextStyles.headlineMedium.copyWith(
                color: NuvoColors.navy,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              'Submit proof of your next movement.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: NuvoColors.textMuted,
              ),
            ),
            const SizedBox(height: 20),

            // Verification ring visual
            Center(
              child: SizedBox(
                width: 100,
                height: 100,
                child: CustomPaint(
                  painter: _VerificationRingPainter(percent: pct),
                  child: Center(
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: NuvoColors.blue.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.gpp_good_rounded,
                        color: NuvoColors.blue,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Bottom: participants + CTA
            Row(
              children: [
                if (others.isNotEmpty) ...[
                  NuvoAvatarStack(
                    avatars: others
                        .map((p) => (
                              initials: p.displayName,
                              photoUrl: p.profilePhotoUrl,
                            ))
                        .toList(),
                    total: race.participantCount,
                    size: 26,
                    max: 3,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${race.participantCount} racing',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: NuvoColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
                // Verify button
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: NuvoColors.blue,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppShadows.trackBlueGlow,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.camera_alt_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'Start proof',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
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

/// Proof Pulse — A scanning ring with motion waveform indicators.
/// Two concentric rings: outer progress arc, inner scan lines with pulse markers.
/// Inspired by Arena's circular geometry and electric-blue movement.
class _VerificationRingPainter extends CustomPainter {
  _VerificationRingPainter({required this.percent});
  final int percent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = (size.width - 8) / 2;
    final innerRadius = outerRadius - 12;
    const stroke = 3.5;

    // Outer ring background
    canvas.drawCircle(
      center,
      outerRadius,
      Paint()
        ..color = const Color(0xFFE8ECF2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    // Outer progress arc
    if (percent > 0) {
      final sweep = (percent / 100) * 2 * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: outerRadius),
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..color = NuvoColors.blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    // Inner scan ring (thinner, lighter)
    canvas.drawCircle(
      center,
      innerRadius,
      Paint()
        ..color = NuvoColors.blue.withValues(alpha: 0.06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Scan tick marks (24 around the outer ring — finer than Arena's orbit)
    for (var i = 0; i < 24; i++) {
      final angle = (i / 24) * 2 * math.pi - math.pi / 2;
      final isMajor = i % 6 == 0;
      final tickInner = outerRadius + 3;
      final tickOuter = outerRadius + (isMajor ? 7 : 5);
      final tickColor = isMajor
          ? NuvoColors.navy.withValues(alpha: 0.2)
          : const Color(0xFFD8DEE6);
      canvas.drawLine(
        Offset(center.dx + tickInner * math.cos(angle),
            center.dy + tickInner * math.sin(angle)),
        Offset(center.dx + tickOuter * math.cos(angle),
            center.dy + tickOuter * math.sin(angle)),
        Paint()
          ..color = tickColor
          ..strokeWidth = isMajor ? 1.5 : 0.8
          ..strokeCap = StrokeCap.round,
      );
    }

    // Pulse dot at progress position
    final pulseAngle = (percent / 100) * 2 * math.pi - math.pi / 2;
    final pulseX = center.dx + outerRadius * math.cos(pulseAngle);
    final pulseY = center.dy + outerRadius * math.sin(pulseAngle);
    // Outer glow
    canvas.drawCircle(
      Offset(pulseX, pulseY), 8,
      Paint()..color = NuvoColors.blue.withValues(alpha: 0.12),
    );
    // Main dot
    canvas.drawCircle(
      Offset(pulseX, pulseY), 4.5,
      Paint()..color = NuvoColors.blue,
    );
    // Core highlight
    canvas.drawCircle(
      Offset(pulseX - 1, pulseY - 1), 1.5,
      Paint()..color = const Color(0xFFB8DBFF),
    );

    // Motion waveform in inner ring (subtle pulse bars)
    for (var i = 0; i < 8; i++) {
      final barAngle = (i / 8) * 2 * math.pi - math.pi / 2;
      final barHeight = (i == 0 || i == 4) ? 8.0 : (i.isEven ? 5.0 : 3.0);
      final barCenter = innerRadius - 6;
      canvas.drawLine(
        Offset(center.dx + (barCenter - barHeight / 2) * math.cos(barAngle),
            center.dy + (barCenter - barHeight / 2) * math.sin(barAngle)),
        Offset(center.dx + (barCenter + barHeight / 2) * math.cos(barAngle),
            center.dy + (barCenter + barHeight / 2) * math.sin(barAngle)),
        Paint()
          ..color = NuvoColors.blue.withValues(alpha: 0.2)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_VerificationRingPainter old) => old.percent != percent;
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION LABEL
// ═══════════════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title});
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
// VERIFY RACE LIST
// ═══════════════════════════════════════════════════════════════════════════════

class _VerifyRaceList extends StatelessWidget {
  const _VerifyRaceList({
    required this.races,
    required this.userId,
    required this.onVerify,
  });
  final List<Race> races;
  final String? userId;
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
            _VerifyRow(
              race: races[i],
              userId: userId,
              onVerify: () => onVerify(races[i]),
            ),
            if (i < races.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 62,
                color: NuvoColors.divider,
              ),
          ],
        ],
      ),
    );
  }
}

class _VerifyRow extends StatelessWidget {
  const _VerifyRow({
    required this.race,
    required this.userId,
    required this.onVerify,
  });
  final Race race;
  final String? userId;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final myPart = userId != null ? race.participantFor(userId!) : null;
    final pct = myPart?.progressPercent ?? 0;

    return PressableScale(
      onTap: onVerify,
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
                    '${race.participantCount} racing · $pct% done',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.textMuted,
                    ),
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
                child: const Icon(
                  Icons.camera_alt_rounded,
                  color: Colors.white,
                  size: 17,
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
// COMPLETED SECTION
// ═══════════════════════════════════════════════════════════════════════════════

class _CompletedSection extends StatelessWidget {
  const _CompletedSection({required this.completedRaces, this.uid});
  final List<Race> completedRaces;
  final String? uid;

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
          for (var i = 0; i < completedRaces.length; i++) ...[
            _CompletedRow(race: completedRaces[i], userId: uid),
            if (i < completedRaces.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 50,
                color: NuvoColors.divider,
              ),
          ],
        ],
      ),
    );
  }
}

class _CompletedRow extends StatelessWidget {
  const _CompletedRow({required this.race, this.userId});
  final Race race;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: NuvoColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.check_circle_rounded,
              color: NuvoColors.success,
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: NuvoColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Complete',
              style: AppTextStyles.labelSmall.copyWith(
                color: NuvoColors.success,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RECENT MOVES
// ═══════════════════════════════════════════════════════════════════════════════

class _RecentMoveGroup extends StatelessWidget {
  const _RecentMoveGroup({required this.entries});
  final List<({Race race, RaceProof proof})> entries;

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
          for (var i = 0; i < entries.length; i++) ...[
            _RecentMoveRow(proof: entries[i].proof, race: entries[i].race),
            if (i < entries.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 58,
                color: NuvoColors.divider,
              ),
          ],
        ],
      ),
    );
  }
}

class _RecentMoveRow extends StatelessWidget {
  const _RecentMoveRow({required this.proof, required this.race});
  final RaceProof proof;
  final Race race;

  @override
  Widget build(BuildContext context) {
    final isChecked = proof.verificationStatus == 'ai_verified' ||
        proof.verificationStatus == 'accepted';
    final isRejected = proof.verificationStatus == 'ai_failed' ||
        proof.verificationStatus == 'rejected';

    final statusLabel = switch (proof.verificationStatus) {
      'ai_verified' => 'Verified',
      'accepted' => 'Verified',
      'ai_failed' => 'Not counted',
      'rejected' => 'Not counted',
      'needs_review' => 'Under review',
      _ => 'Logged',
    };

    final statusColor = isChecked
        ? NuvoColors.success
        : isRejected
            ? NuvoColors.danger
            : NuvoColors.textMuted;

    final valueStr =
        proof.value != null ? '+${proof.value} ${race.unit ?? 'reps'}' : null;

    final initial =
        proof.displayName.isNotEmpty ? proof.displayName[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          NuvoAvatar(
            initials: initial,
            photoUrl: proof.profilePhotoUrl,
            size: 36,
            bgColor: NuvoColors.panelLight,
            textColor: NuvoColors.navy,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  proof.displayName,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: NuvoColors.navy,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        race.displayTitle,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: NuvoColors.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        statusLabel,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: statusColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (valueStr != null) ...[
            const SizedBox(width: 8),
            Text(
              valueStr,
              style: AppTextStyles.labelMedium.copyWith(
                color: NuvoColors.navy,
              ),
            ),
          ],
        ],
      ),
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
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: NuvoColors.blue,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 0),
      child: Column(
        children: [
          // Verification ring empty state
          SizedBox(
            width: 100,
            height: 100,
            child: CustomPaint(
              painter: _VerificationRingPainter(percent: 0),
              child: Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: NuvoColors.blue.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    color: NuvoColors.blue,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No races to verify',
            style: AppTextStyles.headlineMedium.copyWith(
              color: NuvoColors.navy,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a race and submit proof\nof your movement to verify progress.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: NuvoColors.textMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          NuvoPrimaryButton(
            label: 'Start a race',
            expand: true,
            onPressed: onStart,
          ),
        ],
      ),
    );
  }
}
