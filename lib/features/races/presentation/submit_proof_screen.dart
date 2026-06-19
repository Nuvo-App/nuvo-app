import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../auth/data/auth_api.dart';
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
  bool _loading = false;
  String? _error;
  bool _submitted = false;

  @override
  void dispose() {
    _valueController.dispose();
    _noteController.dispose();
    super.dispose();
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
    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child:
                  ListView(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                        children: _submitted
                            ? _successContent()
                            : _formContent(),
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

  List<Widget> _successContent() => [
    Align(
      alignment: Alignment.centerLeft,
      child: IconButton.filledTonal(
        onPressed: () => safePopOrGo(context, '/race/${widget.raceId}'),
        icon: const Icon(Icons.arrow_back_rounded),
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

  List<Widget> _formContent() => [
    Align(
      alignment: Alignment.centerLeft,
      child: IconButton.filledTonal(
        onPressed: () => safePopOrGo(context, '/race/${widget.raceId}'),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
    ),
    const SizedBox(height: 12),
    Text('Submit proof', style: AppTextStyles.headlineLarge),
    const SizedBox(height: 6),
    Text(
      'Log your progress. Some races move the leaderboard after owner review.',
      style: AppTextStyles.bodyLarge.copyWith(color: NuvoColors.muted),
    ),
    const SizedBox(height: 24),
    _AiMotionProofCard(raceId: widget.raceId),
    const SizedBox(height: 18),
    Text('Manual proof', style: AppTextStyles.titleLarge),
    const SizedBox(height: 6),
    Text(
      'Enter your own progress amount and note.',
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
  const _AiMotionProofCard({required this.raceId});

  final String raceId;

  @override
  Widget build(BuildContext context) {
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
                      '10 jumping jacks',
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
            onPressed: () => context.push('/race/$raceId/proof/ai-motion'),
          ),
        ],
      ),
    );
  }
}
