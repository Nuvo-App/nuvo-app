import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/network/api_base.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_loading_indicator.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../crew/application/crew_controller.dart';
import '../data/race_models.dart';
import 'race_controller.dart';

class ProofReviewScreen extends ConsumerStatefulWidget {
  const ProofReviewScreen({
    super.key,
    required this.raceId,
    required this.proofId,
  });

  final String raceId;
  final String proofId;

  @override
  ConsumerState<ProofReviewScreen> createState() => _ProofReviewScreenState();
}

class _ProofReviewScreenState extends ConsumerState<ProofReviewScreen> {
  final _summaryController = TextEditingController();
  Race? _race;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _accessToken;

  RaceProof? get _proof {
    final race = _race;
    if (race == null) return null;
    for (final proof in race.recentProofs) {
      if (proof.id == widget.proofId) return proof;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _summaryController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final race = await ref
          .read(raceControllerProvider.notifier)
          .getRaceDetail(widget.raceId);
      // Evidence media is participant-gated — fetched with the Bearer header,
      // not as a public URL.
      final token = await ref.read(secureTokenStoreProvider).getAccessToken();
      if (mounted) {
        setState(() {
          _race = race;
          _accessToken = token;
          _summaryController.text = _proof?.verificationSummary ?? '';
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load move review.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _review(String status) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final summary = _summaryController.text.trim();
      final race = await ref
          .read(raceControllerProvider.notifier)
          .reviewProof(
            widget.raceId,
            widget.proofId,
            status: status,
            summary: summary.isEmpty ? null : summary,
          );
      if (mounted) context.go('/race/${race.id}');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _saving = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not review move.';
          _saving = false;
        });
      }
    }
  }

  /// Veto reasons mirror the server's VETO_REASONS — a veto disputes whether
  /// this proof should count in THIS race (distinct from Report, which goes
  /// to the Nuvo team and doesn't affect the leaderboard).
  static const _vetoReasons = [
    ('not_shown', "Doesn't show the result"),
    ('wrong_result', 'Wrong result'),
    ('stale_proof', 'Old or unrelated proof'),
    ('other', 'Other'),
  ];

  Future<void> _vetoProof(RaceProof proof) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.themeColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Veto this proof?', style: AppTextStyles.titleMedium),
              const SizedBox(height: 6),
              Text(
                'If enough racers agree, it stops counting on the leaderboard.',
                style: AppTextStyles.bodySmall
                    .copyWith(color: context.themeColors.inkMuted),
              ),
              const SizedBox(height: 16),
              for (final (value, label) in _vetoReasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: NuvoOutlineButton(
                    label: label,
                    expand: true,
                    onPressed: () => Navigator.of(ctx).pop(value),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || reason == null) return;
    setState(() => _saving = true);
    try {
      final result = await ref
          .read(raceControllerProvider.notifier)
          .vetoProof(widget.raceId, widget.proofId, reason: reason);
      // Refresh so vetoed/disputed state and any leaderboard change show up.
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.vetoed
                  ? 'Proof vetoed — it no longer counts.'
                  : result.alreadyVoted
                  ? 'You already vetoed this proof.'
                  : 'Veto counted — ${result.vetoCount} of ${result.threshold} needed.',
            ),
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not veto proof. Try again.')),
        );
      }
    }
  }

  Future<void> _reportProof(RaceProof proof) async {
    final controller = TextEditingController();
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.themeColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          20,
          24,
          24 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Report this move?', style: AppTextStyles.titleMedium),
            const SizedBox(height: 6),
            Text(
              'What\u2019s wrong? This goes to the Nuvo review team.',
              style: AppTextStyles.bodySmall
                  .copyWith(color: context.themeColors.inkMuted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(hintText: 'Optional details'),
            ),
            const SizedBox(height: 8),
            NuvoPrimaryButton(
              label: 'Send report',
              icon: Icons.flag_outlined,
              expand: true,
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            ),
          ],
        ),
      ),
    );
    if (!mounted || reason == null) return;
    try {
      await ref
          .read(crewRepositoryProvider)
          .reportContent(proof.id, reason: reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks — our team will take a look.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;

    if (_loading) {
      return Scaffold(
        backgroundColor: context.themeColors.page,
        body: const Center(child: NuvoLoadingIndicator()),
      );
    }

    // Evidence fetch needs the Bearer header — the URL alone won't serve
    // media to anyone who guesses the path.
    ImageProvider? _evidenceImage(RaceProof proof) {
      final media = proof.mediaUrl;
      final token = _accessToken;
      if (media == null || token == null) return null;
      return CachedNetworkImageProvider(
        media.startsWith('http') ? media : '$kNuvoApiBase$media',
        headers: {'Authorization': 'Bearer $token'},
      );
    }

    String _viewerStatus(RaceProof proof) {
      if (proof.vetoState == 'vetoed') {
        return 'Proof vetoed — does not count on the leaderboard.';
      }
      if (proof.vetoState == 'disputed') {
        return 'Proof disputed — ${proof.vetoCount} veto${proof.vetoCount == 1 ? '' : 's'} so far.';
      }
      return switch (proof.verificationStatus) {
        'accepted' || 'verified' || 'ai_verified' =>
          'Accepted — counts on the leaderboard.',
        'rejected' => 'Rejected — does not count on the leaderboard.',
        _ => 'Waiting on the race creator\'s review.',
      };
    }

    final race = _race;
    final proof = _proof;
    if (race == null || proof == null) {
      return Scaffold(
        backgroundColor: context.themeColors.page,
        body: SafeArea(
          child: NuvoErrorState(
            message: _error ?? 'Move not found.',
            onRetry: _load,
          ),
        ),
      );
    }

    // View ≠ review: any active participant can inspect the proof; only the
    // creator sees decision controls. Non-participants get nothing.
    final isOwner = race.creatorId == user?.id;
    final isParticipant = user != null && race.isParticipant(user.id);
    if (!isOwner && !isParticipant) {
      return Scaffold(
        backgroundColor: context.themeColors.page,
        body: SafeArea(
          child: NuvoErrorState(
            message: 'Move not found.',
            onRetry: () => context.go('/race/${widget.raceId}'),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.themeColors.page,
      body: SafeArea(
        child:
            ListView(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
                  children: [
                    NuvoBackNavRow(
                      onBack: () =>
                          safePopOrGo(context, '/race/${widget.raceId}'),
                      title: isOwner ? 'Review move' : 'Proof',
                    ),
                    const SizedBox(height: 22),
                    _MoveSummaryCard(
                      proof: proof,
                      race: race,
                      evidenceImage: _evidenceImage(proof),
                    ),
                    const SizedBox(height: 22),
                    if (!isOwner) ...[
                      Text(
                        _viewerStatus(proof),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: context.themeColors.inkMuted,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      // Race-truth action: other racers can dispute whether
                      // this proof should count. Own vetoed proofs get the
                      // replacement path — the old record stays for audit.
                      if (proof.userId != user?.id &&
                          proof.vetoState != 'vetoed') ...[
                        NuvoOutlineButton(
                          label: proof.viewerVoted
                              ? 'You vetoed this proof'
                              : 'Veto proof',
                          icon: Icons.gavel_rounded,
                          expand: true,
                          onPressed: _saving || proof.viewerVoted
                              ? null
                              : () => _vetoProof(proof),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (proof.userId == user?.id &&
                          proof.vetoState == 'vetoed') ...[
                        NuvoPrimaryButton(
                          label: 'Submit new proof',
                          icon: Icons.add_a_photo_outlined,
                          expand: true,
                          onPressed: () => context.push(
                            '/race/${widget.raceId}/proof',
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Center(
                        child: TextButton(
                          onPressed: () => _reportProof(proof),
                          child: Text(
                            'Report this move',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: context.themeColors.inkMuted,
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                    NuvoTextInput(
                      controller: _summaryController,
                      label: 'Review note (optional)',
                      hint: 'Add a note for the submitter',
                      maxLines: 4,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.semanticColors.danger.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: NuvoColors.dangerBorder),
                        ),
                        child: Text(
                          _error!,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: context.semanticColors.danger.on,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    Text('Proof decision', style: AppTextStyles.titleMedium),
                    const SizedBox(height: 10),
                    NuvoSuccessButton(
                      label: 'Accept proof',
                      icon: Icons.check_rounded,
                      expand: true,
                      loading: _saving,
                      onPressed: _saving ? null : () => _review('accepted'),
                    ),
                    const SizedBox(height: 12),
                    NuvoOutlineButton(
                      label: 'Ask for another proof',
                      icon: Icons.rate_review_rounded,
                      expand: true,
                      onPressed: _saving ? null : () => _review('needs_review'),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'The racer can submit another proof after reading your note.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: context.themeColors.inkMuted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    NuvoDangerButton(
                      label: 'Reject proof',
                      icon: Icons.close_rounded,
                      expand: true,
                      onPressed: _saving ? null : () => _review('rejected'),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'This declines the proof and keeps it out of the leaderboard.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: context.themeColors.inkMuted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    ],
                  ],
                )
                .animate()
                .fadeIn(duration: 220.ms, curve: Curves.easeOut)
                .slideY(begin: 0.03, end: 0, duration: 260.ms),
      ),
    );
  }
}

// ── Move summary card ─────────────────────────────────────────────────────────

class _MoveSummaryCard extends StatelessWidget {
  const _MoveSummaryCard({
    required this.proof,
    required this.race,
    this.evidenceImage,
  });

  final RaceProof proof;
  final Race race;

  /// Authed evidence image — null when no media or the viewer can't fetch it.
  final ImageProvider? evidenceImage;

  Color _statusColor(BuildContext context) => switch (proof.verificationStatus) {
    'accepted' || 'verified' => NuvoColors.success,
    'rejected' => NuvoColors.danger,
    'needs_review' => context.themeColors.inkMuted,
    _ => NuvoColors.blue,
  };

  String get _statusLabel {
    final s = proof.verificationStatus.replaceAll('_', ' ');
    return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final valueLabel = proof.value == null
        ? null
        : race.unit == null
        ? '+${proof.value}'
        : '+${proof.value} ${race.unit}';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.themeColors.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
        border: Border.all(color: context.themeColors.border, width: 2),
        boxShadow: AppShadows.hardSmall,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              NuvoPill(label: _statusLabel, color: _statusColor(context)),
              const SizedBox(width: 6),
              NuvoPill(
                label: proof.proofType == 'ai_motion' ? 'Verified' : 'Manual',
                color: proof.proofType == 'ai_motion'
                    ? NuvoColors.blue
                    : context.themeColors.inkMuted,
              ),
              const Spacer(),
              Text(
                proof.displayName,
                style: AppTextStyles.labelMedium.copyWith(
                  color: context.themeColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            race.title,
            style: AppTextStyles.bodySmall.copyWith(color: context.themeColors.inkMuted),
          ),
          const SizedBox(height: 3),
          if (valueLabel != null) ...[
            Text(
              valueLabel,
              style: AppTextStyles.headlineMedium.copyWith(
                color: NuvoColors.blue,
              ),
            ),
          ],
          if (evidenceImage != null) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(NuvoRadii.sm),
              child: Image(
                image: evidenceImage!,
                width: double.infinity,
                fit: BoxFit.fitWidth,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ],
          if (proof.note != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.semanticColors.neutral.surface,
                borderRadius: BorderRadius.circular(NuvoRadii.sm),
              ),
              child: Text(
                proof.note!,
                style: AppTextStyles.bodySmall.copyWith(color: context.themeColors.ink),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
