import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/presentation/race_controller.dart';

class _StarterRace {
  const _StarterRace({
    required this.title,
    required this.description,
    required this.category,
    required this.unit,
    required this.targetValue,
    this.proofRequirement = 'manual',
  });

  final String title;
  final String description;
  final String category;
  final String unit;
  final int targetValue;
  final String proofRequirement;

  bool get isAiMotion => proofRequirement == 'ai_check';
}

const _starterRaces = [
  _StarterRace(
    title: '10 Jumping Jacks',
    description: 'AI MoveCheck counts 10 reps with your iPhone camera.',
    category: 'fitness',
    unit: 'jumping jacks',
    targetValue: 10,
    proofRequirement: 'ai_check',
  ),
  _StarterRace(
    title: 'Race to a 6-pack',
    description: 'Log training sessions manually.',
    category: 'fitness',
    unit: 'sessions',
    targetValue: 20,
  ),
  _StarterRace(
    title: 'Ship a side project',
    description: 'Track milestones from idea to launch.',
    category: 'work',
    unit: 'milestones',
    targetValue: 5,
  ),
  _StarterRace(
    title: 'Most books read',
    description: 'Log each finished book with a short note.',
    category: 'reading',
    unit: 'books',
    targetValue: 10,
  ),
  _StarterRace(
    title: '30 days no scrolling',
    description: 'Mark each clean day before the finish line.',
    category: 'focus',
    unit: 'days',
    targetValue: 30,
  ),
];

class FirstRaceScreen extends ConsumerStatefulWidget {
  const FirstRaceScreen({super.key});

  @override
  ConsumerState<FirstRaceScreen> createState() => _FirstRaceScreenState();
}

class _FirstRaceScreenState extends ConsumerState<FirstRaceScreen> {
  int _selected = 0;
  bool _loading = false;
  String? _error;

  Future<void> _completeOnboardingOnly() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).completeOnboarding();
      if (mounted) context.go('/arena');
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not finish onboarding. Try again.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _startSelectedRace() async {
    final starter = _starterRaces[_selected];
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final race = await ref
          .read(raceControllerProvider.notifier)
          .createRace(
            title: starter.title,
            description: starter.description,
            category: starter.category,
            goalType: 'manual',
            targetValue: starter.targetValue,
            unit: starter.unit,
            proofRequirement: starter.proofRequirement,
            proofReviewMode: 'auto_accept',
          );
      await ref.read(authControllerProvider.notifier).completeOnboarding();
      if (mounted) context.go('/race/${race.id}');
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
          _error = 'Could not start this race. Try again.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedRace = _starterRaces[_selected];

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child:
            ListView(
                  padding: const EdgeInsets.fromLTRB(20, 30, 20, 28),
                  children: [
                    Text(
                      'Start your first race',
                      style: AppTextStyles.headlineLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Choose a race template or explore the arena first.',
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: NuvoColors.muted,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text('Quick starts', style: AppTextStyles.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      'Choose a race template',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: NuvoColors.muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (var i = 0; i < _starterRaces.length; i++)
                          ChoiceChip(
                            label: Text(_starterRaces[i].title),
                            selected: i == _selected,
                            onSelected: _loading
                                ? null
                                : (_) => setState(() => _selected = i),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _TemplateCard(starter: selectedRace),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: NuvoColors.danger,
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    NuvoPrimaryButton(
                      label: selectedRace.isAiMotion
                          ? 'Start AI race'
                          : 'Start this race',
                      icon: Icons.flag_rounded,
                      expand: true,
                      loading: _loading,
                      onPressed: _loading ? null : _startSelectedRace,
                    ),
                    const SizedBox(height: 12),
                    NuvoOutlineButton(
                      label: 'Explore app',
                      expand: true,
                      onPressed: _loading ? null : _completeOnboardingOnly,
                    ),
                  ],
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
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.starter});

  final _StarterRace starter;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: NuvoColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140A1A33),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TEMPLATE',
            style: AppTextStyles.brandLabel.copyWith(color: NuvoColors.blue),
          ),
          const SizedBox(height: 10),
          Text(starter.title, style: AppTextStyles.headlineMedium),
          const SizedBox(height: 8),
          Text(
            starter.description,
            style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: NuvoColors.icyBlue,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: NuvoColors.border),
            ),
            child: Text(
              'Finish line: ${starter.targetValue} ${starter.unit}',
              style: AppTextStyles.labelMedium.copyWith(color: NuvoColors.navy),
            ),
          ),
          if (starter.isAiMotion) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: NuvoColors.navy,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'AI MoveCheck · 10 reps',
                style: AppTextStyles.labelMedium.copyWith(
                  color: NuvoColors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
