import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_geometry.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../application/progression_controller.dart';
import '../../data/progression_models.dart';
import 'nuvo_badges.dart';

/// XP award constants — mirrors the server's XP_AWARDS table for display
/// hints only ("Finish · +25 XP"). The ledger stays server-side; a drifted
/// constant costs a wrong hint, never wrong XP.
const kXpProgressAccepted = 10;
const kXpFinish = 25;
const kXpWinBonus = 15;
const kXpPersonalBest = 5;
const kXpDiscovery = 5;

/// What one race paid out — fetched lazily by finished-race surfaces.
final raceXpProvider =
    FutureProvider.family<NuvoRaceXp, String>((ref, raceId) async {
  final token = await ref.read(secureTokenStoreProvider).getAccessToken();
  if (token == null) return const NuvoRaceXp(lines: [], totalXp: 0);
  return ref.read(progressionApiProvider).getRaceXp(token, raceId);
});

/// The finish-line reward block — "XP EARNED" with the canonical breakdown
/// for this race. Renders nothing for non-participants/empty ledgers; a
/// transient fetch failure collapses quietly rather than error the screen.
class NuvoXpEarnedBlock extends ConsumerWidget {
  const NuvoXpEarnedBlock({super.key, required this.raceId});

  final String raceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.themeColors;
    final xp = ref.watch(raceXpProvider(raceId)).valueOrNull;
    if (xp == null || xp.totalXp <= 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'XP EARNED',
          style: AppTextStyles.labelUppercase(
            10,
            color: c.inkSubtle,
          ).copyWith(color: c.inkSubtle),
        ),
        const SizedBox(height: NuvoSpacing.sm),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(NuvoRadii.md),
            border: Border.all(color: c.border, width: 2),
            boxShadow: [
              BoxShadow(
                color: c.inkShadow,
                offset: const Offset(3, 3),
                blurRadius: 0,
              ),
            ],
          ),
          child: Column(
            children: [
              for (final line in xp.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          line.label,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: c.inkSubtle,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '+${line.xp}',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: c.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(height: 1.5, color: c.divider),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Total',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: c.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '+${xp.totalXp} XP',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: NuvoColors.blue,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              if (xp.earned.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(height: 1.5, color: c.divider),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    xp.earned.length == 1
                        ? 'ACHIEVEMENT EARNED'
                        : 'ACHIEVEMENTS EARNED',
                    style: AppTextStyles.labelUppercase(
                      10,
                      color: NuvoColors.blue,
                    ).copyWith(color: NuvoColors.blue),
                  ),
                ),
                const SizedBox(height: NuvoSpacing.sm),
                for (final badge in xp.earned)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        NuvoAchievementBadge(badge: badge, size: 44),
                        const SizedBox(width: NuvoSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                badge.name,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: c.ink,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (badge.description != null)
                                Text(
                                  badge.description!,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: c.inkSubtle,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Small transient "+10 XP" acknowledgement — for Verify/proof-accepted
/// surfaces to flash when canonical progress lands. Provide it, don't
/// prescribe where it lives (Agent 1 owns Verify layout).
class NuvoXpToast extends StatelessWidget {
  const NuvoXpToast({super.key, required this.xp, this.label});

  final int xp;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: NuvoColors.blue,
        borderRadius: BorderRadius.circular(NuvoRadii.pill),
        border: Border.all(color: c.inkShadow, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: c.inkShadow,
            offset: const Offset(2, 2),
            blurRadius: 0,
          ),
        ],
      ),
      child: Text(
        label != null ? '+$xp XP · $label' : '+$xp XP',
        style: AppTextStyles.labelSmall.copyWith(
          color: NuvoColors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
