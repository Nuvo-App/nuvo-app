import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_error_state.dart';
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
      if (mounted) {
        setState(() {
          _race = race;
          _summaryController.text = _proof?.verificationSummary ?? '';
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load proof review.';
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
          _error = 'Could not review proof.';
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
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final race = _race;
    final proof = _proof;
    if (race == null || proof == null) {
      return Scaffold(
        backgroundColor: NuvoColors.page,
        body: SafeArea(
          child: NuvoErrorState(
            message: _error ?? 'Proof not found.',
            onRetry: _load,
          ),
        ),
      );
    }

    if (race.creatorId != user?.id) {
      return Scaffold(
        backgroundColor: NuvoColors.page,
        body: SafeArea(
          child: NuvoErrorState(
            message: 'Only the race creator can review proof.',
            onRetry: () => context.go('/race/${widget.raceId}'),
          ),
        ),
      );
    }

    final valueLabel = proof.value == null
        ? 'No value'
        : race.unit == null
        ? '+${proof.value}'
        : '+${proof.value} ${race.unit}';

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child:
            ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: NuvoIconAction(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'Back to race',
                        onPressed: () =>
                            safePopOrGo(context, '/race/${widget.raceId}'),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text('Review proof', style: AppTextStyles.headlineLarge),
                    const SizedBox(height: 8),
                    Text(
                      race.title,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: NuvoColors.muted,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: NuvoColors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: NuvoColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Badge(proof.verificationStatus),
                          const SizedBox(height: 16),
                          Text(
                            proof.displayName,
                            style: AppTextStyles.titleLarge,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            valueLabel,
                            style: AppTextStyles.headlineMedium.copyWith(
                              color: NuvoColors.blue,
                            ),
                          ),
                          if (proof.note != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              proof.note!,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: NuvoColors.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _summaryController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Review summary',
                        hintText: 'Accepted by race owner',
                        filled: true,
                        fillColor: NuvoColors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: NuvoColors.icyBlue,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: NuvoColors.border),
                      ),
                      child: Text(
                        'AI proof check is ready as a status path, but no AI validation runs yet.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: NuvoColors.muted,
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.red,
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    NuvoPrimaryButton(
                      label: 'Accept proof',
                      icon: Icons.check_rounded,
                      expand: true,
                      loading: _saving,
                      onPressed: _saving ? null : () => _review('accepted'),
                    ),
                    const SizedBox(height: 12),
                    NuvoOutlineButton(
                      label: 'Needs review',
                      icon: Icons.rate_review_rounded,
                      expand: true,
                      onPressed: _saving ? null : () => _review('needs_review'),
                    ),
                    const SizedBox(height: 12),
                    NuvoDangerButton(
                      label: 'Reject proof',
                      icon: Icons.close_rounded,
                      expand: true,
                      onPressed: _saving ? null : () => _review('rejected'),
                    ),
                  ],
                )
                .animate()
                .fadeIn(duration: 220.ms, curve: Curves.easeOut)
                .slideY(begin: 0.03, end: 0, duration: 260.ms),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.status);

  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: NuvoColors.icyBlue,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: AppTextStyles.labelSmall.copyWith(color: NuvoColors.navy),
      ),
    );
  }
}
