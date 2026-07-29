import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_icons.dart';

class BoardMovedArgs {
  const BoardMovedArgs({
    required this.raceId,
    required this.raceName,
    required this.value,
    this.unit,
    this.status = 'accepted',
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

/// Full-screen rank-up celebration shown right after a proof is verified —
/// the emotional payoff moment. Every number here comes from the just-
/// submitted proof's real response (rankBefore/rankAfter/peoplePassed),
/// never invented.
class BoardMovedScreen extends StatelessWidget {
  const BoardMovedScreen({super.key, required this.raceId, required this.args});

  final String raceId;
  final BoardMovedArgs args;

  bool get _isChecked =>
      args.status == 'accepted' || args.status == 'ai_verified';

  bool get _isRejected =>
      args.status == 'ai_failed' || args.status == 'rejected';

  bool get _isPending => !_isChecked && !_isRejected;

  bool get _movedUp =>
      args.rankAfter != null &&
      args.rankBefore != null &&
      args.rankAfter! < args.rankBefore!;

  int get _spotsMoved => _movedUp ? (args.rankBefore! - args.rankAfter!) : 0;

  String get _valueLabel =>
      '+${args.value}${args.unit != null ? ' ${args.unit}' : ''}';

  String get _headline {
    if (_isPending) return 'Proof logged';
    if (_movedUp) return 'Board moved';
    if ((args.peoplePassed ?? 0) > 0) return 'You passed crew';
    return 'Progress added';
  }

  String get _supportingLine {
    if (_isPending) return 'The move is on the board while it is reviewed.';
    if (_movedUp) {
      return 'You jumped $_spotsMoved ${_spotsMoved == 1 ? 'spot' : 'spots'} on the leaderboard.';
    }
    if ((args.peoplePassed ?? 0) > 0) {
      return 'You passed ${args.peoplePassed} ${args.peoplePassed == 1 ? 'person' : 'people'} with that proof.';
    }
    return 'Your race total is updated. Stack another proof when ready.';
  }

  @override
  Widget build(BuildContext context) {
    if (_isRejected) return _RejectedView(raceId: raceId, args: args);

    return Scaffold(
      backgroundColor: NuvoColors.navy,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 40, 28, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      _isPending ? 'Proof logged' : 'Nuvo counted it',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _BoardMoveBurst(
                          valueLabel: _valueLabel,
                          statusLabel: _isPending
                              ? 'On the board'
                              : 'Board moved',
                        )
                        .animate()
                        .scale(
                          begin: const Offset(0.78, 0.78),
                          end: const Offset(1, 1),
                          duration: 360.ms,
                          curve: Curves.easeOutBack,
                        )
                        .fadeIn(duration: 160.ms),
                    const SizedBox(height: 24),
                    Text(
                      _headline,
                      style: AppTextStyles.headlineMedium.copyWith(
                        color: Colors.white,
                        letterSpacing: 0,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _supportingLine,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: Colors.white.withValues(alpha: 0.74),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (args.rankAfter != null) ...[
                      const SizedBox(height: 18),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (args.rankBefore != null && _movedUp) ...[
                            Text(
                              '#${args.rankBefore}',
                              style: AppTextStyles.number(
                                22,
                                color: Colors.white.withValues(alpha: 0.4),
                              ),
                            ),
                            const SizedBox(width: 14),
                            const NuvoIcon(
                              NuvoIconType.arrow,
                              color: NuvoColors.paleSlate,
                              size: 16,
                            ),
                            const SizedBox(width: 14),
                          ],
                          Text(
                            '#${args.rankAfter}',
                            style: AppTextStyles.number(
                              46,
                              color: Colors.white,
                              weight: FontWeight.w800,
                            ),
                          ),
                        ],
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
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => safePopOrGo(context, '/race/$raceId'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: NuvoColors.navy,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: Text(
                        'See leaderboard',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: NuvoColors.navy,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () => context.pushReplacement('/race/$raceId/proof'),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'Stack another proof',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w600,
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
    );
  }
}

class _BoardMoveBurst extends StatelessWidget {
  const _BoardMoveBurst({required this.valueLabel, required this.statusLabel});

  final String valueLabel;
  final String statusLabel;
  static const _green = Color(0xFF20C66B);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 28, 18, 24),
      decoration: BoxDecoration(
        color: _green,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: NuvoColors.white, width: 3),
        boxShadow: const [
          BoxShadow(
            color: NuvoColors.navy,
            blurRadius: 0,
            offset: Offset(8, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            valueLabel,
            textAlign: TextAlign.center,
            style: AppTextStyles.displayLarge.copyWith(
              color: NuvoColors.white,
              fontSize: 82,
              height: 0.9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            statusLabel,
            style: AppTextStyles.headlineMedium.copyWith(
              color: NuvoColors.navy,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Rejected view — kept as a light page, this isn't a celebration ────────────

class _RejectedView extends StatelessWidget {
  const _RejectedView({required this.raceId, required this.args});
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
              child: Row(
                children: [
                  NuvoBackButton(
                    onPressed: () => safePopOrGo(context, '/race/$raceId'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Proof didn't count",
                        style: AppTextStyles.brandLabel.copyWith(
                          color: NuvoColors.danger,
                          letterSpacing: 0,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Run it back with a cleaner frame.',
                        style: AppTextStyles.headlineLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: NuvoColors.white,
                          borderRadius: BorderRadius.circular(NuvoRadii.lg),
                          border: Border.all(color: NuvoColors.border),
                        ),
                        child: Text(
                          'Keep your full movement visible, stay centered, and let AI Motion Proof see the rep from start to finish.',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: NuvoColors.textMuted,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: FilledButton(
                onPressed: () => context.pushReplacement('/race/$raceId/proof'),
                style: FilledButton.styleFrom(
                  backgroundColor: NuvoColors.navy,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: const Text('Run it back'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
