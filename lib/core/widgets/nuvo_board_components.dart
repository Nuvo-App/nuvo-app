import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_geometry.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';
import '../theme/nuvo_tokens.dart';
import 'competition_ring.dart';
import 'count_up_text.dart';
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
    this.title,
    this.contextLine,
    required this.rankLabel,
    required this.chaseCopy,
    required this.subcopy,
    required this.avatars,
    required this.racerCount,
    required this.onPrimary,
    this.primaryLabel = 'Submit proof',
    this.loading = false,
    this.daysLeft,
    this.badgeLabel,
    this.progressPercent,
    this.ringSize = CompetitionRingSize.medium,
    this.ringParticipants = const [],
    this.currentUserId,
    this.isComplete = false,
  });

  final String? title;
  final String? contextLine;
  final String rankLabel;
  final String? chaseCopy;
  final String subcopy;
  final List<({String initials, String? photoUrl})> avatars;
  final int racerCount;
  final VoidCallback? onPrimary;
  final String primaryLabel;
  final bool loading;
  final int? daysLeft;
  final String? badgeLabel;
  final int? progressPercent;
  final CompetitionRingSize ringSize;
  final List<CompetitionRingParticipant> ringParticipants;
  final String? currentUserId;
  final bool isComplete;

  @override
  Widget build(BuildContext context) {
    final progress = progressPercent;
    final center = rankLabel.replaceFirst('#', '');
    final showHeader = badgeLabel != null || progress != null;
    final borderColor = isComplete ? NuvoColors.success : NuvoColors.inkNavy;
    const accentBlue = NuvoColors.actionBlue;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        NuvoTokens.space16,
        NuvoTokens.space16,
        NuvoTokens.space16,
        NuvoTokens.space16,
      ),
      decoration: BoxDecoration(
        color: NuvoTokens.card,
        borderRadius: BorderRadius.circular(NuvoRadii.hero),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: AppShadows.hardShadow5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: movement badge + progress percent
          if (showHeader)
            Row(
              children: [
                if (badgeLabel != null) _HeroPill(label: badgeLabel!),
                const Spacer(),
                if (progress != null)
                  _ProgressPill(percent: progress, complete: isComplete),
              ],
            ),

          // Race title
          if (title != null) ...[
            if (showHeader) const SizedBox(height: NuvoTokens.space12),
            Text(
              title!,
              style: AppTextStyles.headlineMedium.copyWith(
                color: NuvoColors.navy,
                letterSpacing: 0,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // Context line
          if (contextLine != null) ...[
            const SizedBox(height: NuvoTokens.space4),
            Text(
              contextLine!,
              style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // Competition ring — navy track + bright blue progress arc
          if (ringParticipants.isNotEmpty) ...[
            const SizedBox(height: NuvoTokens.space16),
            Center(
              child: CompetitionRing(
                size: ringSize,
                participants: ringParticipants,
                currentUserId: currentUserId,
                centerLabel: center,
              ),
            ),
          ],

          const SizedBox(height: NuvoTokens.space16),

          // Rank / chase / avatar panel
          Container(
            padding: const EdgeInsets.all(NuvoTokens.space12),
            decoration: BoxDecoration(
              color: isComplete
                  ? NuvoColors.success.withValues(alpha: 0.08)
                  : NuvoColors.panel,
              borderRadius: BorderRadius.circular(NuvoRadii.sm),
              border: Border.all(
                color: isComplete
                    ? NuvoColors.success.withValues(alpha: 0.35)
                    : accentBlue.withValues(alpha: 0.22),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  rankLabel,
                  style: AppTextStyles.displaySmall.copyWith(
                    color: isComplete ? NuvoColors.success : accentBlue,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(width: NuvoTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chaseCopy ??
                            (isComplete
                                ? 'Finish line crossed.'
                                : 'Make your next move.'),
                        style: AppTextStyles.titleMedium.copyWith(
                          color: NuvoColors.navy,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: NuvoTokens.space4),
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
                if (avatars.isNotEmpty) ...[
                  const SizedBox(width: NuvoTokens.space8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      NuvoAvatarStack(
                        avatars: avatars,
                        total: racerCount,
                        size: 34,
                        max: 4,
                        borderColor: NuvoColors.white,
                      ),
                      if (daysLeft != null && !isComplete) ...[
                        const SizedBox(height: NuvoTokens.space4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.schedule_rounded,
                              size: 11,
                              color: NuvoColors.muted,
                            ),
                            const SizedBox(width: NuvoTokens.space4),
                            Text(
                              '${daysLeft}d left',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: NuvoColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: NuvoTokens.space16),
          NuvoPrimaryButton(
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
              ? NuvoColors.actionBlue
              : NuvoColors.inkNavy,
          width: 2,
        ),
        boxShadow: AppShadows.hardShadow4,
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
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NuvoColors.inkNavy, width: 2),
        boxShadow: AppShadows.hardShadow3,
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
      padding: const EdgeInsets.fromLTRB(
        NuvoTokens.space8,
        NuvoTokens.space4,
        NuvoTokens.space8,
        NuvoTokens.space4,
      ),
      decoration: BoxDecoration(
        color: NuvoColors.blue,
        borderRadius: BorderRadius.circular(NuvoTokens.radiusPill),
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

class _ProgressPill extends StatelessWidget {
  const _ProgressPill({required this.percent, this.complete = false});

  final int percent;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final done = complete || percent >= 100;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        NuvoTokens.space8,
        NuvoTokens.space4,
        NuvoTokens.space8,
        NuvoTokens.space4,
      ),
      decoration: BoxDecoration(
        color: done
            ? NuvoColors.success.withValues(alpha: 0.12)
            : NuvoColors.actionBlue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(NuvoTokens.radiusPill),
        border: Border.all(
          color: done ? NuvoColors.success : NuvoColors.actionBlue,
          width: 1.5,
        ),
      ),
      child: CountUpText(
        value: percent,
        suffix: '%',
        style: AppTextStyles.labelLarge.copyWith(
          color: done ? NuvoColors.success : NuvoColors.actionBlue,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
