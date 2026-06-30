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
import '../data/race_models.dart';
import '../domain/motion_activity_catalog.dart';
import 'board_moved_screen.dart';
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
  bool _showManualFallback = false;

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
        setState(() => _loading = false);
        context.pushReplacement(
          '/race/${widget.raceId}/board-moved',
          extra: BoardMovedArgs(
            raceId: widget.raceId,
            raceName: _race?.displayTitle ?? '',
            value: raw,
            unit: _race?.unit,
            status: 'accepted',
          ),
        );
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
        !_raceLoading && _raceError == null && _showManualFallback;

    return Scaffold(
      backgroundColor: NuvoColors.page,
      bottomNavigationBar: _bottomBar(race, showManualSubmit),
      body: SafeArea(
        child:
            ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  children: _raceLoading
                      ? _loadingContent()
                      : _raceError != null
                      ? _errorContent()
                      : _formContent(race!),
                )
                .animate()
                .fadeIn(duration: 240.ms, curve: Curves.easeOut)
                .slideY(
                  begin: 0.03,
                  end: 0,
                  duration: 280.ms,
                  curve: Curves.easeOutCubic,
                ),
      ),
    );
  }

  // ── Bottom bar ───────────────────────────────────────────────────────────────

  Widget? _bottomBar(Race? race, bool showManualSubmit) {
    if (_raceLoading || _raceError != null) return null;

    final r = race;
    if (r == null) return null;

    // AI MoveCheck bar
    if (!_showManualFallback && r.isSupportedAiMotionRace) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NuvoPrimaryButton(
                label: 'Check with MoveCheck',
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
                    'Log manually instead',
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

    // Manual log move bar
    if (showManualSubmit) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NuvoPrimaryButton(
                label: 'Log move',
                expand: true,
                loading: _loading,
                onPressed: _loading ? null : _submit,
              ),
              const SizedBox(height: 8),
              Text(
                r.proofReviewMode == 'auto_accept'
                    ? 'Move accepted immediately.'
                    : 'Your move will be reviewed.',
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
    _backRow(),
    const SizedBox(height: 100),
    const Center(child: CircularProgressIndicator(strokeWidth: 2)),
  ];

  // ── Error ────────────────────────────────────────────────────────────────────

  List<Widget> _errorContent() => [
    _backRow(),
    const SizedBox(height: 60),
    NuvoErrorState(message: _raceError!, onRetry: _loadRace),
  ];

  // ── Form ─────────────────────────────────────────────────────────────────────

  List<Widget> _formContent(Race race) {
    return [
      _backRow(),
      const SizedBox(height: 24),

      // Race context
      Text(
        'LOG MOVE',
        style: AppTextStyles.brandLabel.copyWith(color: NuvoColors.blue),
      ),
      const SizedBox(height: 4),
      Text(
        race.displayTitle,
        style: AppTextStyles.headlineMedium,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: 4),
      Text(
        _raceSubtitle(race),
        style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
      ),

      const SizedBox(height: 28),

      // MoveCheck entry (AI races)
      if (!_showManualFallback && race.isSupportedAiMotionRace) ...[
        _MoveCheckCard(race: race),
      ] else ...[
        // Manual log form — checkpoint style
        _CheckpointField(
          label: 'How many ${race.unit ?? 'reps'}?',
          controller: _valueController,
          keyboardType: TextInputType.number,
          hint: '0',
          errorText: _error,
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: 16),
        _CheckpointField(
          label: 'Note (optional)',
          controller: _noteController,
          hint: 'Add context',
          maxLines: 3,
        ),
      ],
    ];
  }

  Widget _backRow() => NuvoBackButton(
    onPressed: () => safePopOrGo(context, '/race/${widget.raceId}'),
  );

  String _raceSubtitle(Race race) {
    if (race.isSupportedAiMotionRace) {
      final activity = motionActivityForBackendValue(
        race.effectiveAiActivityType,
      );
      if (race.targetValue != null && activity != null) {
        return 'AI MoveCheck · First to ${activity.targetLabel(race.targetValue!)}';
      }
      return 'AI MoveCheck';
    }
    final parts = ['Log manually'];
    if (race.unit != null) parts.add('Track ${race.unit}');
    return parts.join(' · ');
  }
}

// ── Checkpoint field ──────────────────────────────────────────────────────────

class _CheckpointField extends StatelessWidget {
  const _CheckpointField({
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.maxLines = 1,
    this.errorText,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.labelMedium.copyWith(color: NuvoColors.muted),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          onChanged: onChanged,
          style: maxLines == 1
              ? AppTextStyles.displaySmall.copyWith(color: NuvoColors.navy)
              : AppTextStyles.bodyMedium,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                (maxLines == 1
                        ? AppTextStyles.displaySmall
                        : AppTextStyles.bodyMedium)
                    .copyWith(color: NuvoColors.border),
            filled: true,
            fillColor: NuvoColors.white,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: maxLines == 1 ? 12 : 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: NuvoColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: NuvoColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: NuvoColors.blue, width: 1.5),
            ),
            errorText: errorText,
            errorStyle: AppTextStyles.bodySmall.copyWith(
              color: NuvoColors.danger,
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: NuvoColors.danger),
            ),
          ),
        ),
      ],
    );
  }
}

// ── MoveCheck card ────────────────────────────────────────────────────────────

class _MoveCheckCard extends StatelessWidget {
  const _MoveCheckCard({required this.race});
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NuvoColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: NuvoColors.blue,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.camera_alt_rounded,
              color: NuvoColors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MoveCheck', style: AppTextStyles.titleLarge),
                const SizedBox(height: 4),
                Text(
                  _description(),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
