import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/v13/v13.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../onboarding/presentation/first_use_guide.dart';
import '../../profile/application/progression_controller.dart';
import '../domain/proof_status.dart';

class BoardMovedArgs {
  const BoardMovedArgs({
    required this.raceId,
    required this.raceName,
    required this.value,
    this.unit,
    this.status = 'needs_review',
    this.rankBefore,
    this.rankAfter,
    this.peoplePassed,
    this.leaderName,
    this.leaderPhotoUrl,
    this.leaderGap,
    this.aiMotionProof = false,
  });

  final String raceId;
  final String raceName;
  final int value;
  final String? unit;
  final String status;
  final int? rankBefore;
  final int? rankAfter;
  final int? peoplePassed;
  final String? leaderName;
  final String? leaderPhotoUrl;
  final int? leaderGap;

  /// True when the proof came from the fullscreen camera verifier — retry
  /// actions re-enter it directly instead of stopping at the proof chooser.
  final bool aiMotionProof;
}

/// Full-screen payoff shown right after a proof resolves. The v13 reward
/// moment: a big "+N" in hero type, a rank pop when the standing changed,
/// and confetti when the racer took the lead. Pending and failed verdicts
/// stay calm. Every number comes from the proof response.
class BoardMovedScreen extends ConsumerStatefulWidget {
  const BoardMovedScreen({super.key, required this.raceId, required this.args});

  final String raceId;
  final BoardMovedArgs args;

  @override
  ConsumerState<BoardMovedScreen> createState() => _BoardMovedScreenState();
}

class _BoardMovedScreenState extends ConsumerState<BoardMovedScreen> {
  /// XP progress when the screen opened — the ring and level bar animate
  /// from here to the refreshed value, so the racer sees the XP land.
  double? _progressBefore;
  int? _levelBefore;

  String get raceId => widget.raceId;
  BoardMovedArgs get args => widget.args;

  ProofStatusPresentation get _status => proofStatusPresentation(args.status);

  bool get _isVerified => _status.status == ProofStatus.verified;
  bool get _isNotVerified => _status.status == ProofStatus.notVerified;
  bool get _isPending => !_isVerified && !_isNotVerified;

  bool get _movedUp =>
      args.rankAfter != null &&
      args.rankBefore != null &&
      args.rankAfter! < args.rankBefore!;

  int get _spotsMoved => _movedUp ? (args.rankBefore! - args.rankAfter!) : 0;

  /// Confetti condition — the racer took the lead with this proof.
  bool get _tookLead =>
      _isVerified &&
      args.rankAfter == 1 &&
      (args.rankBefore == null || args.rankBefore != 1);

  String get _valueLabel =>
      '${args.value}${args.unit != null ? ' ${args.unit}' : ''}';

  String get _rankSupportLabel {
    if (_movedUp) {
      final spots =
          'You moved up $_spotsMoved ${_spotsMoved == 1 ? 'spot' : 'spots'}';
      final gap = args.leaderGap ?? 0;
      if (gap > 0) return '$spots · $gap from #${(args.rankAfter ?? 1) - 1}';
      return spots;
    }
    final passed = args.peoplePassed ?? 0;
    if (passed > 0) {
      return 'You passed $passed ${passed == 1 ? 'person' : 'people'}';
    }
    return 'Holding #${args.rankAfter}';
  }

  String get _headline {
    final name = ref.read(authControllerProvider).user?.fullName ?? '';
    final first = name.trim().split(RegExp(r'\s+')).first;
    final who = first.isEmpty ? '' : ', $first';
    if (_tookLead) return 'You took the lead$who!';
    if (_movedUp) return 'Moving up$who!';
    return 'Nice work$who!';
  }

  String get _againRoute => args.aiMotionProof
      ? '/race/$raceId/proof/ai-motion'
      : '/race/$raceId/proof';

  @override
  void initState() {
    super.initState();
    final before = ref.read(progressionControllerProvider).valueOrNull;
    _progressBefore = before?.progress;
    _levelBefore = before?.level;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isVerified) {
        // Pull the post-proof XP so the ring/bar can fill to the new value.
        ref.read(progressionControllerProvider.notifier).load(force: true);
      }
      if (_isNotVerified) {
        V13Haptics.light();
      } else if (_isPending) {
        V13Haptics.select();
      } else {
        V13Haptics.confirm();
        // A second, lighter tick as the count-up lands.
        Future.delayed(const Duration(milliseconds: 620), () {
          if (mounted) V13Haptics.select();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isNotVerified) {
      return _NotVerifiedView(raceId: raceId, againRoute: _againRoute);
    }
    if (_isPending) return _PendingView(raceId: raceId);

    final hasRank = args.rankAfter != null;

    return Scaffold(
      backgroundColor: V13.bg,
      body: Stack(
        children: [
          // Every verified proof earns the burst; taking the lead earns a
          // bigger one.
          Positioned.fill(
            child: IgnorePointer(
              child: V13Confetti(particleCount: _tookLead ? 120 : 60),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      V13.gapXxl,
                      V13.gapSection,
                      V13.gapXxl,
                      V13.gapXxl,
                    ),
                    child: Column(
                      children: [
                        _CelebrationHero(
                          progressBefore: _progressBefore,
                          levelBefore: _levelBefore,
                        ),
                        const SizedBox(height: V13.gapLg),
                        Text(
                              _headline,
                              style: V13.title,
                              textAlign: TextAlign.center,
                            )
                            .animate(delay: 160.ms)
                            .fadeIn(duration: 260.ms)
                            .slideY(
                              begin: .25,
                              end: 0,
                              curve: V13Motion.spring,
                            ),
                        const SizedBox(height: V13.gapSm),
                        Text(
                          'MOVE VERIFIED',
                          style: V13.label.copyWith(color: V13.blue),
                        ).animate(delay: 220.ms).fadeIn(duration: 260.ms),
                        const SizedBox(height: V13.gapMd),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Count up to the proof value.
                            TweenAnimationBuilder<double>(
                              tween: Tween(
                                begin: 0,
                                end: args.value.toDouble(),
                              ),
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 700),
                              curve: Curves.easeOutCubic,
                              builder: (_, v, _) => Text(
                                '+${v.round()}',
                                style: V13.hugeNumber.copyWith(fontSize: 72),
                              ),
                            ),
                            if (args.unit != null)
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: V13.gapSm,
                                  bottom: 10,
                                ),
                                child: Text(
                                  args.unit!,
                                  style: V13.numberSm.copyWith(
                                    color: V13.muted,
                                  ),
                                ),
                              ),
                          ],
                        ).animate(delay: 260.ms).fadeIn(duration: 280.ms),
                        const SizedBox(height: V13.gapLg),
                        _LevelProgress(
                          progressBefore: _progressBefore,
                          levelBefore: _levelBefore,
                        ).animate(delay: 420.ms).fadeIn(duration: 300.ms),
                        if (!hasRank) ...[
                          const SizedBox(height: V13.gapSm),
                          Text(
                            'Added to your total.',
                            style: V13.body.copyWith(color: V13.muted),
                            textAlign: TextAlign.center,
                          ).animate(delay: 260.ms).fadeIn(duration: 280.ms),
                        ],
                        if (hasRank) ...[
                          const SizedBox(height: V13.gapLg),
                          _RankReveal(
                            before: _movedUp ? args.rankBefore : null,
                            after: args.rankAfter!,
                          ),
                          const SizedBox(height: V13.gapSm),
                          Text(
                            _rankSupportLabel,
                            style: V13.body.copyWith(color: V13.muted),
                            textAlign: TextAlign.center,
                          ).animate(delay: 380.ms).fadeIn(duration: 280.ms),
                          const SizedBox(height: V13.gapLg),
                          V13Pill(
                            label: '+$_valueLabel added to your total',
                            color: V13.mint,
                            icon: Icons.check_rounded,
                          ).animate(delay: 460.ms).fadeIn(duration: 300.ms),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    V13.gapXxl,
                    V13.gapSm,
                    V13.gapXxl,
                    V13.gapXxl,
                  ),
                  // First-race guide: this verified proof is the story's
                  // payoff — continue lands on Profile to point at the
                  // earned progress instead of dropping back on the race.
                  child: Consumer(
                    builder: (context, ref, _) {
                      final guided =
                          ref.watch(firstRaceGuideProvider) ==
                          FirstRaceGuideStep.profileReward;
                      return Column(
                        children: [
                          V13Button.primary(
                            label: guided ? 'See your progress' : 'View race',
                            icon: Icons.flag_rounded,
                            fullWidth: true,
                            onPressed: () => context.go(
                              guided ? '/profile' : '/race/$raceId',
                            ),
                          ),
                          const SizedBox(height: V13.gapMd),
                          V13Button.secondary(
                            label: 'Go again',
                            icon: Icons.replay_rounded,
                            fullWidth: true,
                            onPressed: () => context.go(_againRoute),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The reward medallion — a mint check in a navy-outlined circle with the
/// signature hard shadow.
class _CheckMedallion extends StatelessWidget {
  const _CheckMedallion({this.size = 88});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: V13.mint,
      shape: BoxShape.circle,
      border: Border.all(color: V13.navy, width: V13.outlineThick),
      boxShadow: V13.shadow4,
    ),
    child: Icon(Icons.check_rounded, color: V13.navy, size: size / 2),
  );
}

class _RankReveal extends StatelessWidget {
  const _RankReveal({this.before, required this.after});

  final int? before;
  final int after;

  @override
  Widget build(BuildContext context) {
    return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (before != null) ...[
              Text('#$before', style: V13.number.copyWith(color: V13.muted)),
              const SizedBox(width: V13.gapMd),
              const Icon(
                Icons.arrow_forward_rounded,
                color: V13.navy,
                size: 20,
              ),
              const SizedBox(width: V13.gapMd),
            ],
            Text(
              '#$after',
              style: V13.hugeNumber.copyWith(fontSize: 56, color: V13.blue),
            ),
          ],
        )
        .animate(delay: 180.ms)
        .fadeIn(duration: 300.ms)
        .slideY(
          begin: 0.2,
          end: 0,
          duration: 380.ms,
          curve: Curves.easeOutBack,
        );
  }
}

// ── Pending view — logged, awaiting a verdict ────────────────────────────────

class _PendingView extends StatelessWidget {
  const _PendingView({required this.raceId});

  final String raceId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V13.bg,
      body: SafeArea(
        child: Column(
          children: [
            V13BackBar(
              title: 'Proof',
              onBack: () => context.go('/race/$raceId'),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(V13.gapXxl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const V13IconTile(
                        icon: Icons.hourglass_bottom_rounded,
                        color: V13.sun,
                        size: 72,
                      ),
                      const SizedBox(height: V13.gapLg),
                      Text(
                        'Move logged — under review',
                        style: V13.sectionHead,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: V13.gapSm),
                      Text(
                        "We'll update the board once it's confirmed.",
                        style: V13.body.copyWith(color: V13.muted),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                V13.gapXxl,
                V13.gapSm,
                V13.gapXxl,
                V13.gapXxl,
              ),
              child: V13Button.primary(
                label: 'View race',
                icon: Icons.flag_rounded,
                fullWidth: true,
                onPressed: () => context.go('/race/$raceId'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Not-verified view — calm, not a celebration ─────────────────────────────

class _NotVerifiedView extends StatelessWidget {
  const _NotVerifiedView({required this.raceId, required this.againRoute});

  final String raceId;
  final String againRoute;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V13.bg,
      body: SafeArea(
        child: Column(
          children: [
            V13BackBar(
              title: 'Proof',
              onBack: () => context.go('/race/$raceId'),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(V13.gapXxl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const V13IconTile(
                        icon: Icons.cancel_rounded,
                        color: V13.coral,
                        size: 72,
                      ),
                      const SizedBox(height: V13.gapLg),
                      Text(
                        'Proof needs another try',
                        style: V13.sectionHead,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: V13.gapSm),
                      Text(
                        'We couldn’t verify this proof. Try again with your '
                        'whole body in frame and good light.',
                        style: V13.body.copyWith(color: V13.muted),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                V13.gapXxl,
                V13.gapSm,
                V13.gapXxl,
                V13.gapXxl,
              ),
              child: Column(
                children: [
                  V13Button.primary(
                    label: 'Try again',
                    icon: Icons.replay_rounded,
                    fullWidth: true,
                    onPressed: () => context.go(againRoute),
                  ),
                  const SizedBox(height: V13.gapMd),
                  V13Button.secondary(
                    label: 'Back to race',
                    fullWidth: true,
                    onPressed: () => context.go('/race/$raceId'),
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

/// The racer's face inside the XP ring, ring filling from the pre-proof
/// value to the fresh one, with a mint check badge popping on.
class _CelebrationHero extends ConsumerWidget {
  const _CelebrationHero({this.progressBefore, this.levelBefore});

  final double? progressBefore;
  final int? levelBefore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final now = ref.watch(progressionControllerProvider).valueOrNull;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final leveled =
        now != null && levelBefore != null && now.level > levelBefore!;
    final start = progressBefore ?? 0;
    // A level-up wraps the ring: fill to full, the level bar shows the rest.
    final end = leveled ? 1.0 : (now?.progress ?? start);
    return SizedBox.square(
      dimension: 132,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          TweenAnimationBuilder<double>(
                tween: Tween(begin: start, end: end),
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 1100),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => V13XpRing(
                  progress: v,
                  photoUrl: user?.profilePhotoUrl,
                  name: user?.fullName,
                  size: 132,
                  strokeWidth: 8,
                ),
              )
              .animate()
              .scale(
                begin: const Offset(0.6, 0.6),
                end: const Offset(1, 1),
                duration: V13Motion.medium,
                curve: V13Motion.spring,
              )
              .fadeIn(duration: 200.ms),
          Positioned(
            right: -2,
            bottom: 2,
            child: const _CheckMedallion(size: 44)
                .animate(delay: 380.ms)
                .scale(
                  begin: const Offset(0, 0),
                  end: const Offset(1, 1),
                  duration: V13Motion.medium,
                  curve: V13Motion.spring,
                ),
          ),
        ],
      ),
    );
  }
}

/// "Level N" + XP bar filling to the post-proof value, and what's left to
/// the next level. Hidden until progression has loaded once.
class _LevelProgress extends ConsumerWidget {
  const _LevelProgress({this.progressBefore, this.levelBefore});

  final double? progressBefore;
  final int? levelBefore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressionControllerProvider).valueOrNull;
    if (p == null) return const SizedBox.shrink();
    final leveled = levelBefore != null && p.level > levelBefore!;
    return V13Card(
      padding: const EdgeInsets.all(V13.gapLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Level ${p.level}', style: V13.bodyStrong),
              if (leveled) ...[
                const SizedBox(width: V13.gapSm),
                const V13Pill(
                  label: 'Level up!',
                  color: V13.sun,
                  textColor: V13.navy,
                ),
              ],
              const Spacer(),
              Text('${p.totalXp} XP', style: V13.caption),
            ],
          ),
          const SizedBox(height: V13.gapSm),
          V13ProgressBar(value: p.progress, color: V13.blue),
          const SizedBox(height: V13.gapSm),
          Text(
            p.xpToNext > 0
                ? '${p.xpToNext} XP to Level ${p.level + 1}'
                : 'Level ${p.level + 1} unlocked',
            style: V13.caption,
          ),
        ],
      ),
    );
  }
}
