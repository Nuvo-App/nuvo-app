import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'competition_ring.dart';
import 'nuvo_avatar.dart';
import 'nuvo_button.dart';
import 'pressable_scale.dart';

typedef NuvoPrimaryCTA = NuvoPrimaryButton;

class NuvoBoardParticipant {
  const NuvoBoardParticipant({
    required this.rank,
    required this.name,
    required this.initials,
    required this.progressPercent,
    required this.progressLabel,
    this.photoUrl,
    this.isCurrentUser = false,
  });

  final int rank;
  final String name;
  final String initials;
  final int progressPercent;
  final String progressLabel;
  final String? photoUrl;
  final bool isCurrentUser;
}

class NuvoRaceHero extends StatelessWidget {
  const NuvoRaceHero({
    super.key,
    required this.title,
    required this.contextLine,
    required this.rankLabel,
    required this.chaseCopy,
    required this.subcopy,
    required this.avatars,
    required this.racerCount,
    required this.onPrimary,
    this.primaryLabel = 'Log Move',
    this.loading = false,
    this.daysLeft,
    this.ringParticipants = const [],
    this.currentUserId,
  });

  final String title;
  final String contextLine;
  final String rankLabel;
  final String? chaseCopy;
  final String subcopy;
  final List<({String initials, String? photoUrl})> avatars;
  final int racerCount;
  final VoidCallback? onPrimary;
  final String primaryLabel;
  final bool loading;
  final int? daysLeft;
  final List<CompetitionRingParticipant> ringParticipants;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A2C6D).withValues(alpha: 0.05),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _HeroPill(label: 'LIVE RACE'),
              const Spacer(),
              if (daysLeft != null)
                Text(
                  '${daysLeft}d left',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: NuvoColors.muted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: AppTextStyles.headlineLarge.copyWith(
              color: NuvoColors.navy,
              letterSpacing: 0,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  contextLine,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.muted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (avatars.isNotEmpty) ...[
                const SizedBox(width: 10),
                NuvoAvatarStack(
                  avatars: avatars,
                  total: racerCount,
                  size: 34,
                  max: 4,
                  borderColor: NuvoColors.white,
                ),
              ],
            ],
          ),
          if (ringParticipants.isNotEmpty) ...[
            const SizedBox(height: 20),
            Center(
              child: CompetitionRing(
                size: CompetitionRingSize.medium,
                participants: ringParticipants,
                currentUserId: currentUserId,
                centerLabel: rankLabel.replaceFirst('#', ''),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: NuvoColors.panel,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: NuvoColors.border),
            ),
            child: Row(
              children: [
                Text(
                  rankLabel,
                  style: AppTextStyles.displayLarge.copyWith(
                    color: NuvoColors.blue,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chaseCopy ?? 'Make your next move.',
                        style: AppTextStyles.titleMedium.copyWith(
                          color: NuvoColors.navy,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subcopy,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: NuvoColors.muted,
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
          const SizedBox(height: 16),
          NuvoBlueButton(
            label: primaryLabel,
            expand: true,
            loading: loading,
            onPressed: onPrimary,
          ),
        ],
      ),
    );
  }
}

class NuvoRankMoment extends StatelessWidget {
  const NuvoRankMoment({
    super.key,
    required this.rankLabel,
    required this.caption,
  });

  final String rankLabel;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          rankLabel,
          style: AppTextStyles.displayLarge.copyWith(letterSpacing: 0),
        ),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Text(
            caption,
            style: AppTextStyles.labelMedium.copyWith(color: NuvoColors.muted),
          ),
        ),
      ],
    );
  }
}

class NuvoBoardLane extends StatelessWidget {
  const NuvoBoardLane({super.key, required this.participant, this.onTap});

  final NuvoBoardParticipant participant;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pct = participant.progressPercent.clamp(0, 100);
    final isLeader = participant.rank == 1;
    final avatarSize = participant.isCurrentUser
        ? NuvoAvatarSizes.lg
        : isLeader
        ? 52.0
        : 48.0;
    final avatarOuterSize = avatarSize + 8;
    final minHeight = participant.isCurrentUser ? 128.0 : 108.0;
    final activeColor = participant.isCurrentUser
        ? NuvoColors.blue
        : NuvoColors.navy;
    final ringColor = participant.isCurrentUser
        ? NuvoColors.blue
        : isLeader
        ? const Color(0xFFC9A227)
        : NuvoColors.white;
    final content = Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        color: participant.isCurrentUser
            ? NuvoColors.icyBlue
            : NuvoColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: participant.isCurrentUser
              ? NuvoColors.blue.withValues(alpha: 0.25)
              : NuvoColors.divider,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: participant.isCurrentUser
                  ? NuvoColors.blue.withValues(alpha: 0.12)
                  : NuvoColors.panel,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${participant.rank}',
              style: AppTextStyles.labelMedium.copyWith(
                color: activeColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        participant.isCurrentUser ? 'You' : participant.name,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: NuvoColors.navy,
                          fontWeight: participant.isCurrentUser
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      participant.progressLabel,
                      style: AppTextStyles.labelMedium.copyWith(
                        color: activeColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final laneWidth = constraints.maxWidth;
                    final left = ((laneWidth - avatarOuterSize) * pct / 100)
                        .clamp(0.0, laneWidth - avatarOuterSize);
                    return SizedBox(
                      height: avatarOuterSize + 8,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.centerLeft,
                        children: [
                          Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: NuvoColors.trackBg,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: pct / 100,
                            child: Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: activeColor,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          Positioned(
                            left: left,
                            child: Container(
                              width: avatarOuterSize,
                              height: avatarOuterSize,
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: ringColor, width: 2),
                                color: NuvoColors.white,
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x1807152B),
                                    blurRadius: 10,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: NuvoAvatar(
                                initials: participant.initials,
                                photoUrl: participant.photoUrl,
                                size: avatarSize,
                                bgColor: activeColor,
                                textColor: NuvoColors.white,
                                borderColor: NuvoColors.white,
                                borderWidth: 2,
                              ),
                            ),
                          ),
                          const Positioned(
                            right: 0,
                            child: Icon(
                              Icons.flag_rounded,
                              size: 13,
                              color: NuvoColors.muted,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return PressableScale(onTap: onTap, child: content);
  }
}

class NuvoBoardMovementStrip extends StatelessWidget {
  const NuvoBoardMovementStrip({
    super.key,
    required this.label,
    required this.movers,
  });

  final String label;
  final List<({String initials, String? photoUrl})> movers;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: NuvoColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NuvoColors.divider),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.trending_up_rounded,
            color: NuvoColors.success,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.labelMedium.copyWith(color: NuvoColors.navy),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (movers.isNotEmpty)
            NuvoAvatarStack(
              avatars: movers,
              total: movers.length,
              size: 34,
              max: 3,
            ),
        ],
      ),
    );
  }
}

class NuvoConfirmSheet extends StatelessWidget {
  const NuvoConfirmSheet({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    String cancelLabel = 'Keep race',
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: NuvoColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => NuvoConfirmSheet(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 34,
                height: 3,
                decoration: BoxDecoration(
                  color: NuvoColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(title, style: AppTextStyles.headlineMedium),
            const SizedBox(height: 8),
            Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
            ),
            const SizedBox(height: 22),
            NuvoDangerButton(
              label: confirmLabel,
              expand: true,
              onPressed: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 10),
            NuvoGhostButton(
              label: cancelLabel,
              expand: true,
              onPressed: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
  }
}

class NuvoRaceRow extends StatelessWidget {
  const NuvoRaceRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.progressPercent,
    required this.avatars,
    required this.total,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final int progressPercent;
  final List<({String initials, String? photoUrl})> avatars;
  final int total;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NuvoColors.divider),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.muted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (avatars.isNotEmpty) ...[
              const SizedBox(width: 10),
              NuvoAvatarStack(avatars: avatars, total: total, size: 34, max: 3),
            ],
            const SizedBox(width: 10),
            Text(
              '$progressPercent%',
              style: AppTextStyles.labelMedium.copyWith(
                color: progressPercent >= 100
                    ? NuvoColors.success
                    : NuvoColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: NuvoColors.blue,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: NuvoColors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
