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
        _showManualFallback = !race.isSupportedAiMotionRace;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _raceError = 'Could not load proof options.';
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: _submitted
                  ? NuvoOutlineButton(
                      label: 'Back to race',
                      expand: true,
                      onPressed: () =>
                          safePopOrGo(context, '/race/${widget.raceId}'),
                    )
                  : !showManualSubmit
                  ? const SizedBox.shrink()
                  : NuvoPrimaryButton(
                      label: 'Submit proof',
                      icon: Icons.check_rounded,
                      expand: true,
                      loading: _loading,
                      onPressed: _loading ? null : _submit,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Loading ───────────────────────────────────────────────────────────────────

  List<Widget> _loadingContent() => [
    NuvoBackNavRow(
      onBack: () => safePopOrGo(context, '/race/${widget.raceId}'),
      title: 'Submit proof',
    ),
    const SizedBox(height: 100),
    const Center(child: CircularProgressIndicator()),
  ];

  // ── Error ─────────────────────────────────────────────────────────────────────

  List<Widget> _errorContent() => [
    NuvoBackNavRow(
      onBack: () => safePopOrGo(context, '/race/${widget.raceId}'),
      title: 'Submit proof',
    ),
    const SizedBox(height: 60),
    NuvoErrorState(message: _raceError!, onRetry: _loadRace),
  ];

  // ── Success ───────────────────────────────────────────────────────────────────

  List<Widget> _successContent() => [
    NuvoBackNavRow(
      onBack: () => safePopOrGo(context, '/race/${widget.raceId}'),
      title: 'Submit proof',
    ),
    const SizedBox(height: 40),
    _ProofSuccessBoard(race: _race, value: _submittedValue),
  ];

  // ── Form ──────────────────────────────────────────────────────────────────────

  List<Widget> _formContent(Race race) {
    final isAiRace = race.isSupportedAiMotionRace;
    final showingAiDirect = isAiRace && !_showManualFallback;

    return [
      NuvoBackNavRow(
        onBack: () => safePopOrGo(context, '/race/${widget.raceId}'),
        title: 'Submit proof',
      ),
      const SizedBox(height: 22),
      _RaceContextCard(race: race),
      const SizedBox(height: 22),
      if (showingAiDirect) ...[
        _AiMotionProofCard(race: race),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () => setState(() => _showManualFallback = true),
          behavior: HitTestBehavior.opaque,
          child: Center(
            child: Text(
              'Log progress manually instead',
              style: AppTextStyles.bodySmall.copyWith(
                color: NuvoColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ] else if (isAiRace) ...[
        _AiMotionProofCard(race: race),
        const SizedBox(height: 22),
        const NuvoSectionHeader(
          title: 'Log progress manually',
          bottomPadding: 6,
        ),
        Text(
          'Log progress if camera proof is not available.',
          style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
        ),
        const SizedBox(height: 16),
        ..._manualFields(),
      ] else ...[
        const NuvoSectionHeader(
          title: 'Log progress manually',
          bottomPadding: 6,
        ),
        Text(
          'Log your progress and move the board.',
          style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
        ),
        const SizedBox(height: 16),
        ..._manualFields(),
      ],
    ];
  }

  List<Widget> _manualFields() => [
    NuvoTextInput(
      controller: _valueController,
      label: 'Progress amount',
      hint: 'e.g. 3',
      keyboardType: TextInputType.number,
      onChanged: (_) => setState(() => _error = null),
      errorText: _error,
    ),
    const SizedBox(height: 16),
    NuvoTextInput(
      controller: _noteController,
      label: 'Note (optional)',
      hint: 'What did you do?',
      maxLines: 3,
    ),
  ];
}

// ── Race context card ─────────────────────────────────────────────────────────

class _RaceContextCard extends StatelessWidget {
  const _RaceContextCard({required this.race});

  final Race race;

  @override
  Widget build(BuildContext context) {
    final isAi = race.isSupportedAiMotionRace;
    final finishLine = race.targetValue == null
        ? null
        : '${race.targetValue} ${race.unit ?? 'units'}';

    return NuvoCompactCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isAi ? NuvoColors.navy : NuvoColors.icyBlue,
              borderRadius: BorderRadius.circular(13),
            ),
            alignment: Alignment.center,
            child: Icon(
              isAi ? Icons.directions_run_rounded : Icons.edit_note_rounded,
              color: isAi ? NuvoColors.white : NuvoColors.blue,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  race.title,
                  style: AppTextStyles.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    NuvoPill(
                      label: isAi ? 'AI Motion Proof' : 'Manual proof',
                      color: isAi ? NuvoColors.blue : NuvoColors.navy,
                    ),
                    if (finishLine != null)
                      Text(
                        'Finish line: $finishLine',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: NuvoColors.muted,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── AI Motion Proof card ──────────────────────────────────────────────────────

class _AiMotionProofCard extends StatelessWidget {
  const _AiMotionProofCard({required this.race});

  final Race race;

  @override
  Widget build(BuildContext context) {
    final definition = motionActivityForBackendValue(race.aiActivityType);
    final target = race.targetValue ?? definition?.defaultTarget ?? 10;
    final targetLabel =
        definition?.targetLabel(target) ?? '$target ${race.unit ?? 'reps'}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: NuvoColors.navy,
        borderRadius: BorderRadius.all(Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1407152B),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
          BoxShadow(
            color: Color(0x0B07152B),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: NuvoColors.blue,
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.directions_run_rounded,
                  color: NuvoColors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Motion Proof',
                      style: AppTextStyles.titleLarge.copyWith(
                        color: NuvoColors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      targetLabel,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: NuvoColors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Use your iPhone camera to verify reps live.',
            style: AppTextStyles.bodySmall.copyWith(
              color: NuvoColors.white.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: 14),
          NuvoPrimaryButton(
            label: 'Start AI proof',
            icon: Icons.arrow_forward_rounded,
            expand: true,
            onPressed: () => context.push('/race/${race.id}/proof/ai-motion'),
          ),
        ],
      ),
    );
  }
}

// ── Proof success board ───────────────────────────────────────────────────────

class _ProofSuccessBoard extends StatelessWidget {
  const _ProofSuccessBoard({required this.race, required this.value});

  final Race? race;
  final int value;

  @override
  Widget build(BuildContext context) {
    final unit = race?.unit;
    final valueLabel = value > 0
        ? (unit == null ? '+$value' : '+$value $unit')
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NuvoColors.navy, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1407152B),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
          BoxShadow(
            color: Color(0x0B07152B),
            blurRadius: 4,
            offset: Offset(0, 2),
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
          if (race != null) ...[
            const SizedBox(height: 6),
            Text(
              race!.title,
              style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
              textAlign: TextAlign.center,
            ),
          ],
          if (valueLabel != null) ...[
            const SizedBox(height: 14),
            NuvoPill(label: valueLabel, color: NuvoColors.success),
          ],
          const SizedBox(height: 16),
          const Divider(height: 1, thickness: 0.5, color: NuvoColors.border),
          const SizedBox(height: 16),
          Text(
            'Your proof has been logged. Progress moves once it is accepted.',
            style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
