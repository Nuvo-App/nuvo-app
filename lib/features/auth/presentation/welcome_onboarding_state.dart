import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../races/domain/motion_activity.dart';

/// High-level intent the user picks at the start of onboarding.
enum OnboardingIntent {
  getFit('Get fit'),
  competeWithCrew('Compete with my crew');

  const OnboardingIntent(this.label);

  final String label;
}

/// The reason a new member is showing up to race.
///
/// This is intentionally a small onboarding preference, not a new backend
/// concept. It helps Nuvo recommend the first movement after sign-in.
enum FitnessGoal {
  strength(
    title: 'Build strength',
    description: 'Turn a few strong reps into a finish line.',
    suggestedActivity: 'Pushups',
    icon: Icons.fitness_center_rounded,
  ),
  endurance(
    title: 'Improve endurance',
    description: 'Keep moving and make the board show it.',
    suggestedActivity: 'Jumping Jacks',
    icon: Icons.directions_run_rounded,
  ),
  consistency(
    title: 'Move consistently',
    description: 'Build a rhythm your crew can see.',
    suggestedActivity: 'Squats',
    icon: Icons.calendar_today_rounded,
  ),
  crew(
    title: 'Train with my crew',
    description: 'Give your people something real to chase.',
    suggestedActivity: 'Pushups',
    icon: Icons.groups_rounded,
  ),
  milestone(
    title: 'Reach a milestone',
    description: 'Choose a target and put it on the board.',
    suggestedActivity: 'Your first race',
    icon: Icons.flag_rounded,
  );

  const FitnessGoal({
    required this.title,
    required this.description,
    required this.suggestedActivity,
    required this.icon,
  });

  final String title;
  final String description;
  final String suggestedActivity;
  final IconData icon;
}

/// A curated race action shown to the user in the race-builder flow.
///
/// For AI-verified fitness movements [activity] is set and the race is created
/// with [proofRequirement] = `ai_check`. For manual goals [activity] is null
/// and the race is created as a manual/self-reported race.
class RaceBuilderOption {
  const RaceBuilderOption({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.category,
    required this.unit,
    required this.proofRequirement,
    required this.proofTypes,
    this.activity,
    this.suggestedTargets = const [1, 5, 10, 25, 50, 100],
    this.min = 1,
    this.step = 1,
    this.recurrence = RaceRecurrence.none,
  });

  final String id;
  final String title;
  final String description;
  final IconData icon;
  final String category;
  final String unit;
  final String proofRequirement;
  final List<String> proofTypes;
  final MotionActivityDefinition? activity;
  final List<int> suggestedTargets;
  final int min;
  final int step;
  final RaceRecurrence recurrence;

  int get defaultTarget => suggestedTargets.first;

  /// The next suggested target at or above the current value.
  int nextTarget(int current) {
    for (final t in suggestedTargets) {
      if (t > current) return t;
    }
    return current + step;
  }

  /// The previous suggested target at or below the current value.
  int previousTarget(int current) {
    for (var i = suggestedTargets.length - 1; i >= 0; i--) {
      final t = suggestedTargets[i];
      if (t < current) return t;
    }
    return (current - step).clamp(min, current);
  }

  String targetLabel(int value) => '$value $unit';
}

/// Shared state for the race-builder onboarding flow.
class WelcomeOnboardingState {
  const WelcomeOnboardingState({
    this.selectedIntent,
    this.fitnessGoal,
    this.selectedOption,
    this.selectedProofType,
    this.target,
    this.customTitle,
  });

  final OnboardingIntent? selectedIntent;
  final FitnessGoal? fitnessGoal;
  final RaceBuilderOption? selectedOption;
  final String? selectedProofType;
  final int? target;
  final String? customTitle;

  RaceRecurrence get recurrence =>
      selectedOption?.recurrence ?? RaceRecurrence.none;

  WelcomeOnboardingState copyWith({
    OnboardingIntent? selectedIntent,
    FitnessGoal? fitnessGoal,
    RaceBuilderOption? selectedOption,
    String? selectedProofType,
    int? target,
    String? customTitle,
    bool clearOption = false,
    bool clearProofType = false,
    bool clearTarget = false,
    bool clearTitle = false,
  }) => WelcomeOnboardingState(
    selectedIntent: selectedIntent ?? this.selectedIntent,
    fitnessGoal: fitnessGoal ?? this.fitnessGoal,
    selectedOption: clearOption ? null : selectedOption ?? this.selectedOption,
    selectedProofType: clearProofType
        ? null
        : selectedProofType ?? this.selectedProofType,
    target: clearTarget ? null : target ?? this.target,
    customTitle: clearTitle ? null : customTitle ?? this.customTitle,
  );

  String get generatedTitle {
    if (customTitle?.trim().isNotEmpty == true) return customTitle!.trim();
    if (target == null || selectedOption == null) return 'Your first race';
    return 'First to $target ${selectedOption!.title}';
  }

  String get proofLabel =>
      selectedProofType ?? selectedOption?.proofRequirement ?? 'manual';

  bool get canProceedToAuth =>
      selectedIntent != null &&
      selectedOption != null &&
      target != null &&
      target! > 0;

  bool get hasSelectedGoal => fitnessGoal != null;
}

class WelcomeOnboardingStateNotifier
    extends StateNotifier<WelcomeOnboardingState> {
  WelcomeOnboardingStateNotifier() : super(const WelcomeOnboardingState());

  void selectIntent(OnboardingIntent intent) {
    state = state.copyWith(
      selectedIntent: intent,
      clearOption: true,
      clearProofType: true,
      clearTarget: true,
      clearTitle: true,
    );
  }

  void selectFitnessGoal(FitnessGoal goal) {
    state = state.copyWith(
      fitnessGoal: goal,
      selectedIntent: OnboardingIntent.getFit,
    );
  }

  void selectOption(RaceBuilderOption option, {String? proofType}) {
    state = state.copyWith(
      selectedOption: option,
      selectedProofType: proofType ?? option.proofRequirement,
      target: option.defaultTarget,
      clearTitle: true,
    );
  }

  void setProofType(String proofType) {
    state = state.copyWith(selectedProofType: proofType);
  }

  void setTarget(int target) {
    state = state.copyWith(target: target);
  }

  void setCustomTitle(String title) {
    state = state.copyWith(customTitle: title);
  }

  void reset() => state = const WelcomeOnboardingState();
}

final welcomeOnboardingStateProvider =
    StateNotifierProvider<
      WelcomeOnboardingStateNotifier,
      WelcomeOnboardingState
    >((ref) => WelcomeOnboardingStateNotifier());
