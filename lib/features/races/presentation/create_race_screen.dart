import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../auth/data/auth_api.dart';
import '../domain/motion_activity.dart';
import '../domain/motion_activity_catalog.dart';
import '../domain/race_draft.dart';
import 'custom_pose/learned_custom_movement_provider.dart';
import 'race_controller.dart';

class RaceCreatePrefill {
  const RaceCreatePrefill({required this.idea});

  final String idea;

  static const pushups = RaceCreatePrefill(idea: 'First to 100 Pushups');
  static const squats = RaceCreatePrefill(idea: 'First to 15 Squats');
  static const jumpingJacks = RaceCreatePrefill(
    idea: 'First to 500 Jumping Jacks',
  );
  static const lunges = RaceCreatePrefill(idea: 'First to 40 Lunges');
  static const plank = RaceCreatePrefill(idea: 'First to 300 Plank Seconds');
}

const _quickStarts = [
  'First to 100 Pushups',
  'First to 15 Pushups',
  'First to 15 Squats',
  'First to 500 Jumping Jacks',
  'First to 40 Lunges',
  'First to 300 Plank Seconds',
];

class CreateRaceScreen extends ConsumerStatefulWidget {
  const CreateRaceScreen({super.key, this.prefill});

  final RaceCreatePrefill? prefill;

  @override
  ConsumerState<CreateRaceScreen> createState() => _CreateRaceScreenState();
}

class _CreateRaceScreenState extends ConsumerState<CreateRaceScreen> {
  late final TextEditingController _ideaController;
  late final TextEditingController _targetController;
  late RaceDraft _draft;
  bool _loading = false;
  bool _inviteCrew = false;
  String? _error;
  bool _isCustom = false;
  LearnedCustomMovement? _customMovement;

  @override
  void initState() {
    super.initState();
    final learned = ref.read(learnedCustomMovementProvider);
    if (learned != null) {
      _isCustom = true;
      _customMovement = learned;
      _ideaController = TextEditingController(text: learned.movementName);
      _draft = draftForActivity(motionActivityDefinitions.first);
      _targetController = TextEditingController(text: '10');
    } else {
      final idea = widget.prefill?.idea ?? _quickStarts.first;
      _ideaController = TextEditingController(text: idea);
      _draft =
          draftFromIdea(idea) ??
          draftForActivity(motionActivityDefinitions.first);
      _targetController = TextEditingController(text: '${_draft.targetValue}');
    }
  }

  @override
  void dispose() {
    _ideaController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  void _parseIdea() {
    final parsed = draftFromIdea(_ideaController.text);
    if (parsed == null) {
      final names = motionActivityDefinitions
          .map((d) => d.title)
          .join(', ');
      setState(() {
        _error = 'Nuvo can verify $names.';
      });
      return;
    }
    setState(() {
      _draft = parsed;
      _targetController.text = '${parsed.targetValue}';
      _error = null;
    });
  }

  void _setDraft(RaceDraft draft) {
    setState(() {
      _draft = draft;
      _ideaController.text = draft.title;
      _targetController.text = '${draft.targetValue}';
      _error = null;
    });
  }

  void _setActivity(MotionActivityDefinition activity) {
    final format = activity.supportedFormats.contains(_draft.format)
        ? _draft.format
        : RaceFormat.firstToGoal;
    _setDraft(
      _draft.copyWith(
        title: _draft.title.replaceAll(_draft.activity.title, activity.title),
        activity: activity,
        metric: activity.metric,
        format: format,
        targetValue: activity.suggestedTargets.contains(_draft.targetValue)
            ? _draft.targetValue
            : activity.defaultTarget,
      ),
    );
  }

  Future<void> _createCustomRace() async {
    final movement = _customMovement;
    if (movement == null) return;
    final title = _ideaController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Race title is required.');
      return;
    }
    final target = int.tryParse(_targetController.text.trim());
    if (target == null || target <= 0) {
      setState(() => _error = 'Enter a valid target.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final race = await ref
          .read(raceControllerProvider.notifier)
          .createCustomRace(
            title: title,
            targetValue: target,
            customActivityName: movement.movementName,
            verifierSpec: movement.verifierSpec,
          );
      if (!mounted) return;
      ref.read(learnedCustomMovementProvider.notifier).state = null;
      context.go(_inviteCrew ? '/race/${race.id}/invite' : '/race/${race.id}');
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

  Future<void> _createRace() async {
    final target = int.tryParse(_targetController.text.trim());
    if (target == null || target <= 0) {
      setState(() => _error = 'Enter a valid target.');
      return;
    }
    final draft = _draft.copyWith(targetValue: target);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final race = await ref
          .read(raceControllerProvider.notifier)
          .createRace(
            title: draft.title,
            description: '${draft.activity.title} race verified by camera.',
            category: 'fitness',
            goalType: draft.format.backendValue,
            targetValue: draft.targetValue,
            unit: draft.metric.backendValue,
            proofRequirement: 'ai_check',
            proofReviewMode: 'auto_accept',
            visibility: _inviteCrew ? 'invite_code' : 'private',
            aiActivityType: draft.activity.type.backendValue,
            activityId: draft.activity.type.backendValue,
            metric: draft.metric.backendValue,
            format: draft.format.backendValue,
            recurrence: draft.recurrence.backendValue,
            targetUnit: draft.metric.backendValue,
            proofMode: 'ai_check',
          );
      if (!mounted) return;
      context.go(_inviteCrew ? '/race/${race.id}/invite' : '/race/${race.id}');
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 120),
          children: [
            NuvoBackButton(onPressed: () => safePopOrGo(context, '/compete')),
            const SizedBox(height: 14),
            Text(
              'Create race',
              style: AppTextStyles.headlineLarge.copyWith(
                fontSize: 32,
                letterSpacing: -0.9,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isCustom
                  ? 'Review the details before the start line.'
                  : 'Describe it, then review the details before the start line.',
              style: AppTextStyles.bodyLarge.copyWith(color: NuvoColors.muted),
            ),
            const SizedBox(height: 22),
            NuvoTextInput(
              controller: _ideaController,
              label: _isCustom ? 'Race title' : 'Race idea',
              hint: _isCustom
                  ? (_customMovement?.movementName ?? 'Movement race')
                  : 'First to 100 pushups',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            if (!_isCustom)
              Align(
                alignment: Alignment.centerLeft,
                child: NuvoGhostButton(
                  label: 'Review idea',
                  small: true,
                  onPressed: _parseIdea,
                ),
              ),
            if (!_isCustom) ...[
              const SizedBox(height: 24),
              const _SectionTitle('Quick starts'),
              const SizedBox(height: 10),
              for (final quickStart in _quickStarts) ...[
                _ChoiceRow(
                  label: quickStart,
                  selected:
                      quickStart.toLowerCase() == _draft.title.toLowerCase(),
                  onTap: () => _setDraft(draftFromIdea(quickStart)!),
                ),
              ],
              const SizedBox(height: 26),
              const _SectionTitle('Activity'),
              const SizedBox(height: 10),
              Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final activity in motionActivityDefinitions)
                  _PillChoice(
                    label: activity.title,
                    selected: activity.type == _draft.activity.type,
                    onTap: () => _setActivity(activity),
                  ),
              ],
            ),
            const SizedBox(height: 26),
            const _SectionTitle('How someone wins'),
            const SizedBox(height: 10),
            for (final format in const [RaceFormat.firstToGoal])
              _ChoiceRow(
                label: format.label,
                selected: _draft.format == format,
                onTap: () => _setDraft(_draft.copyWith(format: format)),
              ),
            const SizedBox(height: 26),
            _SectionTitle('Goal \u00b7 ${_draft.metric.label}'),
            const SizedBox(height: 10),
            NuvoTextInput(
              controller: _targetController,
              label: 'Target ${_draft.metric.label}',
              keyboardType: TextInputType.number,
              hint: '${_draft.activity.defaultTarget}',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final target in _draft.activity.suggestedTargets)
                  _PillChoice(
                    label: '$target',
                    selected: _targetController.text == '$target',
                    onTap: () =>
                        setState(() => _targetController.text = '$target'),
                  ),
              ],
            ),
            const SizedBox(height: 26),
            const _SectionTitle('Repeat'),
            const SizedBox(height: 10),
            for (final recurrence in const [RaceRecurrence.none])
              _ChoiceRow(
                label: recurrence == RaceRecurrence.daily
                    ? 'Starts fresh every day'
                    : recurrence == RaceRecurrence.weekly
                    ? 'Starts fresh every week'
                    : 'One time',
                selected: _draft.recurrence == recurrence,
                onTap: () => _setDraft(_draft.copyWith(recurrence: recurrence)),
              ),
            const SizedBox(height: 26),
            const _SectionTitle('Racers'),
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _inviteCrew,
              onChanged: (value) => setState(() => _inviteCrew = value),
              title: Text('Pull in your crew', style: AppTextStyles.bodyMedium),
              subtitle: Text(
                _inviteCrew
                    ? 'Create an invite code after setup.'
                    : 'Start solo.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: NuvoColors.muted,
                ),
              ),
            ),
            const SizedBox(height: 24),
            _ReviewBlock(draft: _draft, target: _targetController.text),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: AppTextStyles.bodySmall.copyWith(
                color: NuvoColors.danger,
              ),
            ),
          ],
          if (_isCustom) ...[
            const SizedBox(height: 26),
            const _SectionTitle('Goal'),
            const SizedBox(height: 10),
            NuvoTextInput(
              controller: _targetController,
              label: 'Target reps',
              keyboardType: TextInputType.number,
              hint: '10',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 26),
            const _SectionTitle('Racers'),
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _inviteCrew,
              onChanged: (value) => setState(() => _inviteCrew = value),
              title: Text('Pull in your crew', style: AppTextStyles.bodyMedium),
              subtitle: Text(
                _inviteCrew
                    ? 'Create an invite code after setup.'
                    : 'Start solo.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: NuvoColors.muted,
                ),
              ),
            ),
          ],
        ],
        ).animate().fadeIn(duration: 240.ms).slideY(begin: 0.03, end: 0),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
          child: NuvoPrimaryButton(
            label: _isCustom ? 'Create race with this movement' : 'Create race',
            icon: Icons.flag_rounded,
            expand: true,
            loading: _loading,
            onPressed: _loading
                ? null
                : (_isCustom ? _createCustomRace : _createRace),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTextStyles.labelLarge.copyWith(color: NuvoColors.navy),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? NuvoColors.blue : NuvoColors.muted,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: selected ? NuvoColors.navy : NuvoColors.muted,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillChoice extends StatelessWidget {
  const _PillChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: selected ? NuvoColors.blue : NuvoColors.surface,
      labelStyle: AppTextStyles.labelMedium.copyWith(
        color: selected ? NuvoColors.white : NuvoColors.navy,
      ),
      side: BorderSide(color: selected ? NuvoColors.blue : NuvoColors.border),
    );
  }
}

class _ReviewBlock extends StatelessWidget {
  const _ReviewBlock({required this.draft, required this.target});

  final RaceDraft draft;
  final String target;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Activity', draft.activity.title),
      ('Win condition', draft.format.label),
      ('Goal', '$target ${draft.metric.label}'),
      ('Repeat', draft.recurrence.label),
      ('Verification', 'Camera'),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        border: Border.all(color: NuvoColors.border),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(draft.title, style: AppTextStyles.titleLarge),
          const SizedBox(height: 12),
          for (final row in rows) ...[
            Row(
              children: [
                SizedBox(
                  width: 112,
                  child: Text(
                    row.$1,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.muted,
                    ),
                  ),
                ),
                Expanded(child: Text(row.$2, style: AppTextStyles.bodyMedium)),
              ],
            ),
            if (row != rows.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
