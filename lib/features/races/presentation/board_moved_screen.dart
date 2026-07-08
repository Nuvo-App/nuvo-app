import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
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
                    Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        color: NuvoColors.blue,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: NuvoIcon(
                          NuvoIconType.check,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _isPending
                          ? 'Move logged · under review'
                          : 'Move verified',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${args.value}${args.unit != null ? ' ${args.unit}' : ''} completed.',
                      style: AppTextStyles.headlineMedium.copyWith(
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (args.rankAfter != null) ...[
                      const SizedBox(height: 12),
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
                      const SizedBox(height: 6),
                      Text(
                        _movedUp
                            ? "You moved up $_spotsMoved ${_spotsMoved == 1 ? 'spot' : 'spots'}"
                                  '${(args.leaderGap ?? 0) > 0 ? ' · ${args.leaderGap} from #${(args.rankAfter ?? 1) - 1}' : ''}'
                            : (args.peoplePassed ?? 0) > 0
                            ? 'You passed ${args.peoplePassed} ${args.peoplePassed == 1 ? 'person' : 'people'}'
                            : 'Updating your race...',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '+${args.value}${args.unit != null ? ' ${args.unit}' : ''}',
                            style: AppTextStyles.titleLarge.copyWith(
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '1 move added',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: Colors.white.withValues(alpha: 0.66),
                            ),
                          ),
                        ],
                      ),
                    ),
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
                        'View race',
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
                        'Record again',
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
                        "MOVE DIDN'T COUNT",
                        style: AppTextStyles.brandLabel.copyWith(
                          color: NuvoColors.danger,
                          letterSpacing: 0,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Try again with a clearer move.',
                        style: AppTextStyles.headlineLarge,
                        textAlign: TextAlign.center,
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
                child: const Text('Try again'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
