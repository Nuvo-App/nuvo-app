import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';

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

class BoardMovedScreen extends StatelessWidget {
  const BoardMovedScreen({super.key, required this.raceId, required this.args});

  final String raceId;
  final BoardMovedArgs args;

  bool get _isChecked =>
      args.status == 'accepted' || args.status == 'ai_verified';

  bool get _isRejected =>
      args.status == 'ai_failed' || args.status == 'rejected';

  bool get _isPending => !_isChecked && !_isRejected;

  bool get _boardMoved =>
      args.rankAfter != null &&
      args.rankBefore != null &&
      args.rankAfter != args.rankBefore;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: Column(
          children: [
            // ── Back row ──────────────────────────────────────────────────────
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // ── Status header ─────────────────────────────────────────
                    Text(
                      _isChecked
                          ? 'MOVE CHECKED'
                          : _isRejected
                          ? "MOVE DIDN'T COUNT"
                          : 'MOVE LOGGED',
                      style: AppTextStyles.brandLabel.copyWith(
                        color: _isChecked
                            ? NuvoColors.success
                            : _isRejected
                            ? NuvoColors.danger
                            : NuvoColors.muted,
                        letterSpacing: 0,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 12),

                    Text(
                      _isRejected
                          ? 'Try again with a clearer move.'
                          : _isPending
                          ? 'Your move is under review.'
                          : _boardMoved
                          ? 'Board moved.'
                          : 'Progress updated.',
                      style: AppTextStyles.headlineLarge,
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 32),

                    // ── Value badge ───────────────────────────────────────────
                    if (!_isRejected) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: NuvoColors.navy,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '+${args.value}${args.unit != null ? ' ${args.unit}' : ''}',
                          style: AppTextStyles.displaySmall.copyWith(
                            color: NuvoColors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                    ],

                    // ── Rank change ───────────────────────────────────────────
                    if (args.rankAfter != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: NuvoColors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: NuvoColors.divider),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '#${args.rankAfter}',
                              style: AppTextStyles.displayMedium.copyWith(
                                color: NuvoColors.navy,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _boardMoved &&
                                      args.rankBefore != null &&
                                      args.rankAfter! < args.rankBefore!
                                  ? 'Up from #${args.rankBefore}'
                                  : 'Your rank',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: NuvoColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── Passed copy ───────────────────────────────────────────
                    if ((args.peoplePassed ?? 0) > 0) ...[
                      _ContextLine(
                        text: args.peoplePassed == 1
                            ? 'You passed 1 person.'
                            : 'You passed ${args.peoplePassed} people.',
                      ),
                      const SizedBox(height: 8),
                    ],

                    // ── Chase copy ────────────────────────────────────────────
                    if (args.leaderName != null &&
                        (args.leaderGap ?? 0) > 0) ...[
                      _ContextLine(
                        leading: NuvoAvatar(
                          initials: args.leaderName![0],
                          photoUrl: args.leaderPhotoUrl,
                          size: 22,
                        ),
                        text: '${args.leaderName} leads by ${args.leaderGap}.',
                      ),
                    ],

                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),

            // ── Bottom CTAs ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                children: [
                  NuvoPrimaryButton(
                    label: 'View race',
                    expand: true,
                    onPressed: () => safePopOrGo(context, '/race/$raceId'),
                  ),
                  if (!_isRejected) ...[
                    const SizedBox(height: 10),
                    NuvoGhostButton(
                      label: 'Log another move',
                      expand: true,
                      onPressed: () =>
                          context.pushReplacement('/race/$raceId/proof'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContextLine extends StatelessWidget {
  const _ContextLine({required this.text, this.leading});
  final String text;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 8)],
        Text(
          text,
          style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
        ),
      ],
    );
  }
}
