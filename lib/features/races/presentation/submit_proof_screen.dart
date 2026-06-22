import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../auth/data/auth_api.dart';
import '../data/race_models.dart';
import '../domain/motion_activity_catalog.dart';
import 'race_controller.dart';

class SubmitProofScreen extends ConsumerStatefulWidget {
  const SubmitProofScreen({super.key, required this.raceId});

  final String raceId;

  @override
  ConsumerState<SubmitProofScreen> createState() => _SubmitProofScreenState();
}

class _SubmitProofScreenState extends ConsumerState<SubmitProofScreen> {
  final _valueController = TextEditingController();
  final _noteController = TextEditingController();
  Race? _race;
  bool _raceLoading = true;
  String? _raceError;
  bool _loading = false;
  String? _error;
  bool _submitted = false;
  // True for non-AI races on load; toggled via recovery link for AI races.
  bool _showManualFallback = false;
  int _submittedValue = 0;

  @override
  void initState() {
    super.initState();
    _loadRace();
  }

  @override
  void dispose() {
    _valueController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadRace() async {
    setState(() {
      _raceLoading = true;
      _raceError = null;
    });
    try {
      final race = await ref
          .read(raceControllerProvider.notifier)
          .getRaceDetail(widget.raceId);
      if (!mounted) return;
      setState(() {
        _race = race;
        _raceLoading = false;
        // Non-AI races go straight to the manual form.
        // AI races start with the verification entry; manual is a recovery path.
        _showManualFallback = !race.isSupportedAiMotionRace;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _raceError = 'Could not load race details.';
        _raceLoading = false;
      });
    }
  }

  Future<void> _submit() async {
    final raw = int.tryParse(_valueController.text.trim()) ?? 0;
    if (raw <= 0) {
      setState(() => _error = 'Enter a progress amount greater than 0.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final note = _noteController.text.trim();
      await ref
          .read(raceControllerProvider.notifier)
          .submitProof(
            widget.raceId,
            value: raw,
            note: note.isEmpty ? null : note,
          );
      if (mounted) {
        setState(() {
          _loading = false;
          _submitted = true;
          _submittedValue = raw;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Something went wrong. Try again.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final race = _race;
    final showManualSubmit =
        !_submitted &&
        !_raceLoading &&
        _raceError == null &&
        _showManualFallback;

    return Scaffold(
      backgroundColor: NuvoColors.page,
      bottomNavigationBar: _bottomBar(race, showManualSubmit),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child:
                  ListView(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                        children: _raceLoading
                            ? _loadingContent()
                            : _raceError != null
                            ? _errorContent()
                            : _submitted
                            ? _successContent()
                            : _formContent(race!),
                      )
                      .animate()
                      .fadeIn(duration: 280.ms, curve: Curves.easeOut)
                      .slideY(
                        begin: 0.04,
                        end: 0,
                        duration: 320.ms,
                        curve: Curves.easeOutCubic,
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _bottomBar(Race? race, bool showManualSubmit) {
    if (_raceLoading || _raceError != null) return null;

    // Success: "View race" as primary.
    if (_submitted) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          child: NuvoPrimaryButton(
            label: 'View race',
            expand: true,
            onPressed: () => safePopOrGo(context, '/race/${widget.raceId}'),
          ),
        ),
      );
    }

    final r = race;
    if (r == null) return null;

    // AI verification entry action bar.
    if (!_showManualFallback && r.isSupportedAiMotionRace) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NuvoPrimaryButton(
                label: 'Verify with Nuvo',
                icon: Icons.camera_alt_rounded,
                expand: true,
                onPressed: () =>
                    context.push('/race/${widget.raceId}/proof/ai-motion'),
              ),
              const SizedBox(height: 10),
              NuvoGhostButton(
                label: 'View race',
                expand: true,
                onPressed: () => safePopOrGo(context, '/race/${widget.raceId}'),
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => setState(() => _showManualFallback = true),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    "Can't verify? Log manually",
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.muted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Manual proof action bar.
    if (showManualSubmit) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NuvoPrimaryButton(
                label: 'Submit proof',
                icon: Icons.check_rounded,
                expand: true,
                loading: _loading,
                onPressed: _loading ? null : _submit,
              ),
              const SizedBox(height: 8),
              Text(
                r.proofReviewMode == 'auto_accept'
                    ? 'Accepted immediately.'
                    : 'Your proof will be reviewed.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: NuvoColors.muted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return null;
  }

  // ── Loading ──────────────────────────────────────────────────────────────────

  List<Widget> _loadingContent() => [
    NuvoBackNavRow(
      onBack: () => safePopOrGo(context, '/race/${widget.raceId}'),
      title: 'Submit proof',
    ),
    const SizedBox(height: 100),
    const Center(child: CircularProgressIndicator()),
  ];

  // ── Error ────────────────────────────────────────────────────────────────────

  List<Widget> _errorContent() => [
    NuvoBackNavRow(
      onBack: () => safePopOrGo(context, '/race/${widget.raceId}'),
      title: 'Submit proof',
    ),
    const SizedBox(height: 60),
    NuvoErrorState(message: _raceError!, onRetry: _loadRace),
  ];

  // ── Success ──────────────────────────────────────────────────────────────────

  List<Widget> _successContent() {
    final race = _race;
    final unit = race?.unit;
    final valueLabel = _submittedValue > 0
        ? (unit == null ? '+$_submittedValue' : '+$_submittedValue $unit')
        : null;
    final isAutoAccept = race?.proofReviewMode == 'auto_accept';

    return [
      NuvoBackNavRow(
        onBack: () => safePopOrGo(context, '/race/${widget.raceId}'),
      ),
      const SizedBox(height: 40),
      _ProofSuccessCard(
        raceTitle: race?.title,
        valueLabel: valueLabel,
        body: isAutoAccept
            ? 'Your progress is live. Check your leaderboard position.'
            : 'Your proof will update the leaderboard once accepted.',
      ),
    ];
  }

  // ── Form ─────────────────────────────────────────────────────────────────────

  List<Widget> _formContent(Race race) {
    return [
      NuvoBackNavRow(
        onBack: () => safePopOrGo(context, '/race/${widget.raceId}'),
      ),
      const SizedBox(height: 20),
      _RaceProofHeader(race: race),
      const SizedBox(height: 20),
      if (!_showManualFallback && race.isSupportedAiMotionRace) ...[
        _VerificationEntryCard(race: race),
      ] else ...[
        NuvoTextInput(
          controller: _valueController,
          label: 'Progress',
          hint: 'e.g. 3',
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() => _error = null),
          errorText: _error,
        ),
        const SizedBox(height: 14),
        NuvoTextInput(
          controller: _noteController,
          label: 'Note',
          hint: 'Optional',
          maxLines: 3,
        ),
      ],
    ];
  }
}

// ── Race proof header ─────────────────────────────────────────────────────────

class _RaceProofHeader extends StatelessWidget {
  const _RaceProofHeader({required this.race});

  final Race race;

  String _subtitle() {
    final parts = <String>[];
    if (race.isSupportedAiMotionRace) {
      parts.add('AI verified race');
      final activity = motionActivityForBackendValue(
        race.effectiveAiActivityType,
      );
      if (race.targetValue != null && activity != null) {
        parts.add('First to ${activity.targetLabel(race.targetValue!)}');
      } else if (race.targetValue != null && race.unit != null) {
        parts.add('${race.targetValue} ${race.unit}');
      }
    } else {
      parts.add('Manual proof race');
      if (race.unit != null) parts.add('Track ${race.unit}');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          race.title.toUpperCase(),
          style: AppTextStyles.headlineMedium.copyWith(
            color: NuvoColors.navy,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _subtitle(),
          style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
        ),
      ],
    );
  }
}

// ── Verification entry card ───────────────────────────────────────────────────

class _VerificationEntryCard extends StatelessWidget {
  const _VerificationEntryCard({required this.race});

  final Race race;

  String _description() {
    final activity = motionActivityForBackendValue(
      race.effectiveAiActivityType,
    );
    if (race.targetValue != null && activity != null) {
      return 'Nuvo will count your ${activity.targetLabel(race.targetValue!)} through the camera.';
    }
    if (activity != null) {
      return 'Nuvo will verify your ${activity.unit} through the camera.';
    }
    return 'Nuvo will verify your reps through the camera.';
  }

  String? _targetLine() {
    if (race.targetValue == null) return null;
    final activity = motionActivityForBackendValue(
      race.effectiveAiActivityType,
    );
    if (activity == null) return null;
    return 'Target: ${activity.targetLabel(race.targetValue!)}';
  }

  @override
  Widget build(BuildContext context) {
    final targetLine = _targetLine();
    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NuvoColors.navy, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D07152B),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
          BoxShadow(
            color: Color(0x0607152B),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: NuvoColors.blue,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.verified_rounded,
              color: NuvoColors.white,
              size: 22,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Verify with Nuvo',
            style: AppTextStyles.titleLarge.copyWith(color: NuvoColors.navy),
          ),
          const SizedBox(height: 6),
          Text(
            _description(),
            style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
          ),
          if (targetLine != null) ...[
            const SizedBox(height: 10),
            Text(
              targetLine,
              style: AppTextStyles.bodySmall.copyWith(
                color: NuvoColors.navy,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Your progress updates after proof is accepted.',
            style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
          ),
        ],
      ),
    );
  }
}

// ── Proof success card ────────────────────────────────────────────────────────

class _ProofSuccessCard extends StatelessWidget {
  const _ProofSuccessCard({
    required this.body,
    this.raceTitle,
    this.valueLabel,
  });

  final String body;
  final String? raceTitle;
  final String? valueLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NuvoColors.navy, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D07152B),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
          BoxShadow(
            color: Color(0x0607152B),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: NuvoColors.success,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.check_rounded,
              color: NuvoColors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text('Proof submitted', style: AppTextStyles.headlineMedium),
          if (raceTitle != null) ...[
            const SizedBox(height: 6),
            Text(
              raceTitle!,
              style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
              textAlign: TextAlign.center,
            ),
          ],
          if (valueLabel != null) ...[
            const SizedBox(height: 14),
            NuvoPill(label: valueLabel!, color: NuvoColors.success),
          ],
          const SizedBox(height: 16),
          const Divider(height: 1, thickness: 0.5, color: NuvoColors.border),
          const SizedBox(height: 14),
          Text(
            body,
            style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
