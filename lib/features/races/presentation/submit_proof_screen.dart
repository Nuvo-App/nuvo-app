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

  List<Widget> _loadingContent() => [
    Align(
      alignment: Alignment.centerLeft,
      child: NuvoBackButton(
        onPressed: () => safePopOrGo(context, '/race/${widget.raceId}'),
      ),
    ),
    const SizedBox(height: 120),
    const Center(child: CircularProgressIndicator()),
  ];

  List<Widget> _errorContent() => [
    Align(
      alignment: Alignment.centerLeft,
      child: NuvoBackButton(
        onPressed: () => safePopOrGo(context, '/race/${widget.raceId}'),
      ),
    ),
    const SizedBox(height: 80),
    NuvoErrorState(message: _raceError!, onRetry: _loadRace),
  ];

  List<Widget> _successContent() => [
    Align(
      alignment: Alignment.centerLeft,
      child: NuvoBackButton(
        onPressed: () => safePopOrGo(context, '/race/${widget.raceId}'),
      ),
    ),
    const SizedBox(height: 60),
    const Center(
      child: Icon(Icons.check_circle_rounded, color: NuvoColors.blue, size: 72),
    ),
    const SizedBox(height: 20),
    Text(
      'Proof submitted!',
      style: AppTextStyles.headlineLarge,
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 8),
    Text(
      'Your proof has been logged. If this race uses owner review, progress moves after approval.',
      style: AppTextStyles.bodyLarge.copyWith(color: NuvoColors.muted),
      textAlign: TextAlign.center,
    ),
  ];

  List<Widget> _formContent(Race race) {
    final isAiRace = race.isSupportedAiMotionRace;
    final showingAiDirect = isAiRace && !_showManualFallback;
    final definition = motionActivityForBackendValue(race.aiActivityType);
    final target = race.targetValue ?? definition?.defaultTarget ?? 10;
    final targetLabel =
        definition?.targetLabel(target) ?? '$target ${race.unit ?? 'reps'}';

    if (showingAiDirect) {
      return [
        Row(
          children: [
            NuvoBackButton(
              onPressed: () => safePopOrGo(context, '/race/${widget.raceId}'),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI Motion Proof', style: AppTextStyles.titleLarge),
                  const SizedBox(height: 2),
                  Text(
                    'Nuvo verifies $targetLabel with your iPhone camera.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _AiMotionProofCard(race: race),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => setState(() => _showManualFallback = true),
          behavior: HitTestBehavior.opaque,
          child: Center(
            child: Text(
              'Use manual proof instead',
              style: AppTextStyles.bodySmall.copyWith(
                color: NuvoColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ];
    }

    return [
      Align(
        alignment: Alignment.centerLeft,
        child: NuvoBackButton(
          onPressed: () => safePopOrGo(context, '/race/${widget.raceId}'),
        ),
      ),
      const SizedBox(height: 12),
      Text('Submit proof', style: AppTextStyles.headlineLarge),
      const SizedBox(height: 6),
      Text(
        isAiRace
            ? 'Log progress manually. Camera proof is recommended for this race.'
            : 'Log your progress with proof and move the leaderboard.',
        style: AppTextStyles.bodyLarge.copyWith(color: NuvoColors.muted),
      ),
      const SizedBox(height: 24),
      if (isAiRace) ...[
        _AiMotionProofCard(race: race),
        const SizedBox(height: 16),
        Text('Manual fallback', style: AppTextStyles.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Use this only if camera proof is not available. Progress may still need review.',
          style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
        ),
        const SizedBox(height: 16),
        ..._manualFields(),
      ] else ...[
        _ManualProofIntro(race: race),
        const SizedBox(height: 14),
        const _DisabledAiCard(),
        const SizedBox(height: 18),
        ..._manualFields(),
      ],
    ];
  }

  List<Widget> _manualFields() => [
    Text('Manual proof', style: AppTextStyles.titleLarge),
    const SizedBox(height: 6),
    Text(
      'Log your progress with a note.',
      style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
    ),
    const SizedBox(height: 16),
    Text('Progress amount', style: AppTextStyles.titleMedium),
    const SizedBox(height: 8),
    TextField(
      controller: _valueController,
      keyboardType: TextInputType.number,
      onChanged: (_) => setState(() {}),
      decoration: _inputDecoration('e.g. 3'),
    ),
    const SizedBox(height: 16),
    Text('Note (optional)', style: AppTextStyles.titleMedium),
    const SizedBox(height: 8),
    TextField(
      controller: _noteController,
      maxLines: 3,
      decoration: _inputDecoration('What did you do?'),
    ),
    if (_error != null) ...[
      const SizedBox(height: 12),
      Text(_error!, style: AppTextStyles.bodySmall.copyWith(color: Colors.red)),
    ],
  ];

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
    filled: true,
    fillColor: NuvoColors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: NuvoColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: NuvoColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: NuvoColors.blue, width: 1.6),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}

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
      decoration: BoxDecoration(
        color: NuvoColors.navy,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0xB007152B),
            blurRadius: 0,
            offset: Offset(5, 6),
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
                  borderRadius: BorderRadius.circular(14),
                ),
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
          const SizedBox(height: 12),
          Text(
            'Use your iPhone camera to verify reps live.',
            style: AppTextStyles.bodyMedium.copyWith(
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

class _ManualProofIntro extends StatelessWidget {
  const _ManualProofIntro({required this.race});

  final Race race;

  @override
  Widget build(BuildContext context) {
    final goal = race.targetValue == null
        ? 'Track progress toward the finish line.'
        : 'Finish line: ${race.targetValue} ${race.unit ?? 'units'}.';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: NuvoColors.icyBlue,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.edit_note_rounded, color: NuvoColors.blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Manual proof', style: AppTextStyles.titleLarge),
                const SizedBox(height: 4),
                Text(
                  '$goal Add a note so your crew can follow your progress.',
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

class _DisabledAiCard extends StatelessWidget {
  const _DisabledAiCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NuvoColors.icyBlue,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: NuvoColors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.directions_run_rounded,
              color: NuvoColors.muted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI Motion Proof', style: AppTextStyles.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'AI Motion Proof is coming soon for this movement.',
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
