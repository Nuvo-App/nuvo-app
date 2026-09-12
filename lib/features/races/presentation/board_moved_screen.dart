import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/count_up_text.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_icons.dart';
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
}

/// Full-screen payoff shown right after a proof resolves. A verified result is
/// a fully-green celebration with a counting-up rank and a burst; anything not
/// verified stays calm and light. Every number comes from the proof response.
class BoardMovedScreen extends StatefulWidget {
  const BoardMovedScreen({super.key, required this.raceId, required this.args});

  final String raceId;
  final BoardMovedArgs args;

  @override
  State<BoardMovedScreen> createState() => _BoardMovedScreenState();
}

class _BoardMovedScreenState extends State<BoardMovedScreen> {
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isNotVerified) {
        HapticFeedback.lightImpact();
      } else if (_isPending) {
        HapticFeedback.selectionClick();
      } else {
        HapticFeedback.mediumImpact();
        // A second, lighter tick as the count-up lands.
        Future.delayed(const Duration(milliseconds: 620), () {
          if (mounted) HapticFeedback.selectionClick();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isNotVerified) return _NotVerifiedView(raceId: raceId, args: args);
    if (_isPending) return _PendingView(raceId: raceId, args: args);

    final hasRank = args.rankAfter != null;

    return Scaffold(
      backgroundColor: NuvoColors.success,
      body: Stack(
        children: [
          const Positioned.fill(child: _Burst()),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 40, 28, 24),
                    child: Column(
                      children: [
                        _CheckMedallion()
                            .animate()
                            .scale(
                              begin: const Offset(0.6, 0.6),
                              end: const Offset(1, 1),
                              duration: 460.ms,
                              curve: Curves.easeOutBack,
                            )
                            .fadeIn(duration: 200.ms),
                        const SizedBox(height: 20),
                        Text(
                          'MOVE VERIFIED',
                          style: AppTextStyles.labelMedium.copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                            letterSpacing: 1.4,
                          ),
                        ).animate(delay: 120.ms).fadeIn(duration: 260.ms),
                        if (!hasRank) ...[
                          const SizedBox(height: 12),
                          Text(
                            '$_valueLabel completed.',
                            style: AppTextStyles.headlineMedium.copyWith(
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ).animate(delay: 180.ms).fadeIn(duration: 280.ms),
                        ],
                        if (hasRank) ...[
                          const SizedBox(height: 14),
                          _RankReveal(
                            before: _movedUp ? args.rankBefore : null,
                            after: args.rankAfter!,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _rankSupportLabel,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: Colors.white.withValues(alpha: 0.82),
                            ),
                            textAlign: TextAlign.center,
                          ).animate(delay: 380.ms).fadeIn(duration: 280.ms),
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.5),
                                width: 2,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '+$_valueLabel',
                                  style: AppTextStyles.titleLarge.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Added to your total',
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: Colors.white.withValues(alpha: 0.72),
                                  ),
                                ),
                              ],
                            ),
                          )
                              .animate(delay: 460.ms)
                              .fadeIn(duration: 300.ms)
                              .shimmer(
                                delay: 900.ms,
                                duration: 1400.ms,
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                  child: Column(
                    children: [
                      NuvoSuccessButton(
                        label: 'View race',
                        expand: true,
                        onPressed: () => context.go('/race/$raceId'),
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () =>
                            context.go('/race/$raceId/proof'),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Record again',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
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

class _CheckMedallion extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 72,
    height: 72,
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: NuvoColors.successShadow.withValues(alpha: 0.4),
          blurRadius: 0,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: const Icon(
      Icons.check_rounded,
      color: NuvoColors.success,
      size: 40,
    ),
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
          Text(
            '#$before',
            style: AppTextStyles.number(
              24,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 14),
          const NuvoIcon(
            NuvoIconType.arrow,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 14),
        ],
        CountUpText(
          value: after,
          prefix: '#',
          duration: const Duration(milliseconds: 560),
          style: AppTextStyles.number(
            52,
            color: Colors.white,
            weight: FontWeight.w900,
          ),
        ),
      ],
    )
        .animate(delay: 180.ms)
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.2, end: 0, duration: 380.ms, curve: Curves.easeOutBack);
  }
}

/// Lightweight radiating confetti burst behind the medallion.
class _Burst extends StatefulWidget {
  const _Burst();
  @override
  State<_Burst> createState() => _BurstState();
}

class _BurstState extends State<_Burst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) => CustomPaint(
      painter: _BurstPainter(_c.value),
      size: Size.infinite,
    ),
  );
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.32);
    final rnd = math.Random(7);
    final eased = Curves.easeOut.transform(t);
    for (var i = 0; i < 26; i++) {
      final angle = (i / 26) * math.pi * 2 + rnd.nextDouble();
      final dist = (60 + rnd.nextDouble() * 180) * eased;
      final p = center + Offset(math.cos(angle), math.sin(angle)) * dist;
      final opacity = (1 - t).clamp(0.0, 1.0);
      canvas.drawCircle(
        p,
        3 + rnd.nextDouble() * 3,
        Paint()..color = Colors.white.withValues(alpha: opacity * 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => old.t != t;
}

// ── Pending view — logged, awaiting a verdict ────────────────────────────────

class _PendingView extends StatelessWidget {
  const _PendingView({required this.raceId, required this.args});
  final String raceId;
  final BoardMovedArgs args;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NuvoColors.warningSurface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: NuvoBackButton(
                  onPressed: () => context.go('/race/$raceId'),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.hourglass_bottom_rounded,
                        color: NuvoColors.warning,
                        size: 44,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Move logged — under review',
                        style: AppTextStyles.headlineMedium.copyWith(
                          color: NuvoColors.warningOn,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "We'll update the board once it's confirmed.",
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: NuvoColors.warningOn,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: NuvoPrimaryButton(
                label: 'View race',
                expand: true,
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
  const _NotVerifiedView({required this.raceId, required this.args});
  final String raceId;
  final BoardMovedArgs args;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: NuvoBackButton(
                  onPressed: () => context.go('/race/$raceId'),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cancel_rounded,
                        color: NuvoColors.danger,
                        size: 44,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        "That move didn't count",
                        style: AppTextStyles.headlineLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Try again with your whole body in frame and good light.',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: NuvoColors.muted,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                children: [
                  NuvoPrimaryButton(
                    label: 'Try again',
                    expand: true,
                    onPressed: () =>
                        context.go('/race/$raceId/proof'),
                  ),
                  const SizedBox(height: 12),
                  NuvoTertiaryButton(
                    label: 'Back to race',
                    expand: true,
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
