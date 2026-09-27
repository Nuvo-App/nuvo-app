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

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;

    if (_loading) {
      return const Scaffold(
        backgroundColor: NuvoColors.page,
        body: Center(child: NuvoLoadingIndicator()),
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

    String _viewerStatus(RaceProof proof) => switch (proof.verificationStatus) {
      'accepted' || 'verified' || 'ai_verified' => 'Accepted — counts on the leaderboard.',
      'rejected' => 'Rejected — does not count on the leaderboard.',
      _ => 'Waiting on the race creator\'s review.',
    };

    final race = _race;
    final proof = _proof;
    if (race == null || proof == null) {
      return Scaffold(
        backgroundColor: NuvoColors.page,
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
        backgroundColor: NuvoColors.page,
        body: SafeArea(
          child: NuvoErrorState(
            message: 'Move not found.',
            onRetry: () => context.go('/race/${widget.raceId}'),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: NuvoColors.page,
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
                          color: NuvoColors.muted,
                        ),
                        textAlign: TextAlign.center,
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
                          color: NuvoColors.dangerSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: NuvoColors.dangerBorder),
                        ),
                        child: Text(
                          _error!,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: NuvoColors.dangerOn,
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
                        color: NuvoColors.muted,
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
                        color: NuvoColors.muted,
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

  Color get _statusColor => switch (proof.verificationStatus) {
    'accepted' || 'verified' => NuvoColors.success,
    'rejected' => NuvoColors.danger,
    'needs_review' => NuvoColors.muted,
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
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
        border: Border.all(color: NuvoColors.navy, width: 2),
        boxShadow: AppShadows.hardSmall,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              NuvoPill(label: _statusLabel, color: _statusColor),
              const SizedBox(width: 6),
              NuvoPill(
                label: proof.proofType == 'ai_motion' ? 'Verified' : 'Manual',
                color: proof.proofType == 'ai_motion'
                    ? NuvoColors.blue
                    : NuvoColors.muted,
              ),
              const Spacer(),
              Text(
                proof.displayName,
                style: AppTextStyles.labelMedium.copyWith(
                  color: NuvoColors.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            race.title,
            style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
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
                color: NuvoColors.icyBlue,
                borderRadius: BorderRadius.circular(NuvoRadii.sm),
              ),
              child: Text(
                proof.note!,
                style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.navy),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
