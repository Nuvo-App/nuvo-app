import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/data/auth_api.dart';
import '../domain/motion_activity.dart';
import '../domain/motion_activity_catalog.dart';
import '../domain/race_draft.dart';
import 'create_race_screen.dart';
import 'race_controller.dart';
import 'teach_nuvo_screen.dart';

class RaceComposerScreen extends ConsumerStatefulWidget {
  const RaceComposerScreen({super.key, this.prefill});

  final RaceCreatePrefill? prefill;

  @override
  ConsumerState<RaceComposerScreen> createState() => _RaceComposerScreenState();
}

class _RaceComposerScreenState extends ConsumerState<RaceComposerScreen> {
  late RaceDraft _draft;
  late final TextEditingController _targetController;
  late final TextEditingController _customActionController;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _draft = _initialDraft();
    _targetController = TextEditingController(text: '${_draft.targetValue}');
    _customActionController = TextEditingController();
  }

  @override
  void dispose() {
    _targetController.dispose();
    _customActionController.dispose();
    super.dispose();
  }

  RaceDraft _initialDraft() {
    final idea = widget.prefill?.idea;
    if (idea != null) {
      final parsed = draftFromIdea(idea);
      if (parsed != null) return parsed;
    }
    return draftForActivity(motionActivityDefinitions.first);
  }

  void _setDraft(RaceDraft draft) {
    setState(() {
      _draft = draft;
      _error = null;
    });
    if (_targetController.text != '${draft.targetValue}') {
      _targetController.text = '${draft.targetValue}';
    }
  }

  void _setActivity(MotionActivityDefinition activity) {
    final nextTarget = _draft.targetValue.clamp(1, 99999);
    final customAction = _cleanCustomAction();
    _setDraft(
      _draft.copyWith(
        title:
            activity.type == MotionActivityType.universalAi &&
                customAction.isNotEmpty
            ? 'First to $nextTarget $customAction'
            : null,
        activity: activity,
        metric: activity.metric,
        format: activity.supportedFormats.contains(_draft.format)
            ? _draft.format
            : RaceFormat.firstToGoal,
        targetValue: nextTarget,
        hasCustomName:
            activity.type == MotionActivityType.universalAi &&
            customAction.isNotEmpty,
      ),
    );
  }

  void _setTarget(int value) {
    final clamped = value.clamp(1, 99999);
    final customAction = _cleanCustomAction();
    _setDraft(
      _draft.copyWith(
        title:
            _draft.activity.type == MotionActivityType.universalAi &&
                customAction.isNotEmpty
            ? 'First to $clamped $customAction'
            : null,
        targetValue: clamped,
        hasCustomName:
            _draft.activity.type == MotionActivityType.universalAi &&
            customAction.isNotEmpty,
      ),
    );
  }

  void _setVisibility(String visibility) {
    _setDraft(_draft.copyWith(visibility: visibility));
  }

  String _cleanCustomAction() => _customActionController.text
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .toLowerCase();

  void _setCustomAction(String value) {
    if (_draft.activity.type != MotionActivityType.universalAi) return;
    final action = value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    _setDraft(
      _draft.copyWith(
        title: action.isEmpty ? null : 'First to ${_draft.targetValue} $action',
        hasCustomName: action.isNotEmpty,
      ),
    );
  }

  Future<void> _startRace() async {
    if (_loading) return;
    final target = int.tryParse(_targetController.text.trim());
    if (target == null || target <= 0) {
      setState(() => _error = 'Enter a finish line greater than 0.');
      return;
    }
    final customAction = _cleanCustomAction();
    if (_draft.activity.type == MotionActivityType.universalAi &&
        customAction.isEmpty) {
      setState(() => _error = 'Tell Nuvo what to count.');
      return;
    }
    final draft = _draft.copyWith(
      title: _draft.activity.type == MotionActivityType.universalAi
          ? 'First to $target $customAction'
          : null,
      targetValue: target,
      hasCustomName: _draft.activity.type == MotionActivityType.universalAi,
    );
    setState(() {
      _draft = draft;
      _error = null;
    });
    if (draft.activity.type == MotionActivityType.universalAi) {
      context.push(
        '/races/teach-nuvo',
        extra: TeachNuvoArgs(draft: draft, actionName: customAction),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final payload = draft.toCreatePayload();
      final race = await ref
          .read(raceControllerProvider.notifier)
          .createRace(
            title: payload['title'] as String,
            description: payload['description'] as String,
            category: payload['category'] as String,
            goalType: payload['goalType'] as String,
            targetValue: payload['targetValue'] as int,
            unit: payload['unit'] as String,
            proofRequirement: payload['proofRequirement'] as String,
            proofReviewMode: payload['proofReviewMode'] as String,
            visibility: payload['visibility'] as String,
            aiActivityType: payload['aiActivityType'] as String,
            activityId: payload['activityId'] as String,
            metric: payload['metric'] as String,
            format: payload['format'] as String,
            recurrence: payload['recurrence'] as String,
            targetUnit: payload['targetUnit'] as String,
            proofMode: payload['proofMode'] as String,
          );
      if (!mounted) return;
      final wantsInvite = draft.visibility == 'invite_code';
      context.go(wantsInvite ? '/race/${race.id}/invite' : '/race/${race.id}');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Race could not start. Try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isInvite = _draft.visibility == 'invite_code';

    return Scaffold(
      backgroundColor: NuvoColors.page,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: NuvoColors.white,
              borderRadius: BorderRadius.circular(NuvoRadii.lg),
              border: Border.all(color: NuvoColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: NuvoPrimaryButton(
                label: _loading ? 'Starting race' : 'Start race',
                icon: Icons.flag_rounded,
                expand: true,
                loading: _loading,
                onPressed: _loading ? null : _startRace,
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          children: [
            NuvoBackButton(onPressed: () => safePopOrGo(context, '/compete')),
            const SizedBox(height: 14),
            _ComposerHero(draft: _draft),
            const SizedBox(height: 16),
            _ComposerSection(
              icon: Icons.directions_run_rounded,
              title: 'Activity',
              subtitle: 'Pick the move. Nuvo watches for clean progress.',
              child: _ActivityPicker(
                selected: _draft.activity,
                onSelected: _setActivity,
              ),
            ),
            if (_draft.activity.type == MotionActivityType.universalAi) ...[
              const SizedBox(height: 14),
              _ComposerSection(
                icon: Icons.auto_awesome_rounded,
                title: 'Nuvo AI counts',
                subtitle: 'Name the action. Nuvo reads sampled camera frames.',
                child: _CustomActionEditor(
                  controller: _customActionController,
                  onChanged: _setCustomAction,
                ),
              ),
            ],
            const SizedBox(height: 14),
            _ComposerSection(
              icon: Icons.flag_rounded,
              title: 'Finish line',
              subtitle: 'Make it loud enough to chase, small enough to start.',
              child: _FinishLineEditor(
                draft: _draft,
                controller: _targetController,
                onTargetChanged: _setTarget,
              ),
            ),
            const SizedBox(height: 14),
            _ComposerSection(
              icon: Icons.group_add_rounded,
              title: 'Crew',
              subtitle: 'Race solo now or pull people to the start line.',
              child: _CrewModePicker(
                inviteCrew: isInvite,
                onChanged: (invite) =>
                    _setVisibility(invite ? 'invite_code' : 'private'),
              ),
            ),
            const SizedBox(height: 14),
            _RaceSummary(draft: _draft),
            if (_error != null) ...[
              const SizedBox(height: 14),
              _ErrorBox(message: _error!),
            ],
          ],
        ),
      ),
    );
  }
}

class _ComposerHero extends StatelessWidget {
  const _ComposerHero({required this.draft});

  final RaceDraft draft;

  @override
  Widget build(BuildContext context) {
    final unit = draft.metric == RaceMetric.seconds
        ? 'seconds'
        : draft.activity.proofLabel;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: NuvoColors.navy,
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
        border: Border.all(color: NuvoColors.navy, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Build the board',
            style: AppTextStyles.headlineLarge.copyWith(
              color: NuvoColors.white,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Set the finish line. Nuvo counts the proof. The leaderboard moves when you do.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: NuvoColors.white.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeroPill(label: draft.activity.title),
              _HeroPill(label: '${draft.targetValue} $unit'),
              _HeroPill(
                label: draft.visibility == 'invite_code'
                    ? 'Pull in crew'
                    : 'Start solo',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: NuvoColors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(NuvoRadii.pill),
        border: Border.all(color: NuvoColors.white.withValues(alpha: 0.16)),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelMedium.copyWith(
          color: NuvoColors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ComposerSection extends StatelessWidget {
  const _ComposerSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: NuvoColors.panelLight,
                  borderRadius: BorderRadius.circular(NuvoRadii.md),
                  border: Border.all(color: NuvoColors.border),
                ),
                child: Icon(icon, color: NuvoColors.navy, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: NuvoColors.navy,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: NuvoColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ActivityPicker extends StatelessWidget {
  const _ActivityPicker({required this.selected, required this.onSelected});

  final MotionActivityDefinition selected;
  final ValueChanged<MotionActivityDefinition> onSelected;

  static const _icons = {
    MotionActivityType.pushUps: Icons.fitness_center_rounded,
    MotionActivityType.squats: Icons.person_outline_rounded,
    MotionActivityType.jumpingJacks: Icons.accessibility_new_rounded,
    MotionActivityType.lunges: Icons.directions_walk_rounded,
    MotionActivityType.highKnees: Icons.directions_run_rounded,
    MotionActivityType.armRaises: Icons.sports_gymnastics_rounded,
    MotionActivityType.plankHold: Icons.timer_outlined,
    MotionActivityType.universalAi: Icons.auto_awesome_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 380;
        return GridView.builder(
          itemCount: motionActivityDefinitions.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: twoColumns ? 2 : 1,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: twoColumns ? 2.85 : 4.8,
          ),
          itemBuilder: (context, index) {
            final activity = motionActivityDefinitions[index];
            return _ActivityOption(
              activity: activity,
              selected: selected.type == activity.type,
              icon: _icons[activity.type] ?? Icons.sports_rounded,
              onTap: () => onSelected(activity),
            );
          },
        );
      },
    );
  }
}

class _ActivityOption extends StatelessWidget {
  const _ActivityOption({
    required this.activity,
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  final MotionActivityDefinition activity;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      semanticLabel: 'Choose ${activity.title}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? NuvoColors.actionBlue.withValues(alpha: 0.08)
              : NuvoColors.white,
          borderRadius: BorderRadius.circular(NuvoRadii.md),
          border: Border.all(
            color: selected ? NuvoColors.actionBlue : NuvoColors.border,
            width: selected ? 2 : 1.25,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? NuvoColors.actionBlue : NuvoColors.navy,
              size: 21,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                activity.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.titleMedium.copyWith(
                  color: selected ? NuvoColors.actionBlue : NuvoColors.navy,
                ),
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.check_circle_rounded,
                color: NuvoColors.actionBlue,
                size: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CustomActionEditor extends StatelessWidget {
  const _CustomActionEditor({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.done,
      textCapitalization: TextCapitalization.words,
      onChanged: onChanged,
      style: AppTextStyles.titleMedium.copyWith(
        color: NuvoColors.navy,
        fontWeight: FontWeight.w800,
      ),
      decoration: InputDecoration(
        hintText: 'basketball shots, free throws, clean passes...',
        hintStyle: AppTextStyles.bodyMedium.copyWith(
          color: NuvoColors.textMuted,
        ),
        filled: true,
        fillColor: NuvoColors.panelLight,
        prefixIcon: const Icon(
          Icons.bolt_rounded,
          color: NuvoColors.actionBlue,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NuvoRadii.md),
          borderSide: const BorderSide(color: NuvoColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NuvoRadii.md),
          borderSide: const BorderSide(color: NuvoColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NuvoRadii.md),
          borderSide: const BorderSide(color: NuvoColors.actionBlue, width: 2),
        ),
      ),
    );
  }
}

class _FinishLineEditor extends StatelessWidget {
  const _FinishLineEditor({
    required this.draft,
    required this.controller,
    required this.onTargetChanged,
  });

  final RaceDraft draft;
  final TextEditingController controller;
  final ValueChanged<int> onTargetChanged;

  int get _target => int.tryParse(controller.text.trim()) ?? draft.targetValue;

  void _setTarget(int value) {
    final clamped = value.clamp(1, 99999);
    controller.text = '$clamped';
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    onTargetChanged(clamped);
  }

  int get _step {
    if (_target < 10) return 1;
    if (_target < 100) return 5;
    if (_target < 1000) return 25;
    return 100;
  }

  @override
  Widget build(BuildContext context) {
    final unit = draft.metric == RaceMetric.seconds
        ? 'seconds'
        : draft.activity.proofLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _StepButton(
              icon: Icons.remove_rounded,
              label: 'Decrease finish line',
              onTap: () => _setTarget(_target - _step),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: NuvoColors.panelLight,
                  borderRadius: BorderRadius.circular(NuvoRadii.md),
                  border: Border.all(color: NuvoColors.border),
                ),
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(5),
                  ],
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null && parsed > 0) onTargetChanged(parsed);
                  },
                  style: AppTextStyles.displaySmall.copyWith(
                    color: NuvoColors.navy,
                    height: 1.08,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            _StepButton(
              icon: Icons.add_rounded,
              label: 'Increase finish line',
              onTap: () => _setTarget(_target + _step),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            unit,
            style: AppTextStyles.labelMedium.copyWith(
              color: NuvoColors.muted,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final target in draft.activity.suggestedTargets.take(4))
              _TargetChip(
                label: '$target',
                selected: _target == target,
                onTap: () => _setTarget(target),
              ),
          ],
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: NuvoColors.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NuvoColors.border),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: NuvoColors.navy, size: 22),
      ),
    );
  }
}

class _TargetChip extends StatelessWidget {
  const _TargetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      semanticLabel: 'Set finish line to $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? NuvoColors.actionBlue : NuvoColors.panelLight,
          borderRadius: BorderRadius.circular(NuvoRadii.pill),
          border: Border.all(
            color: selected ? NuvoColors.actionBlue : NuvoColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelLarge.copyWith(
            color: selected ? NuvoColors.white : NuvoColors.navy,
          ),
        ),
      ),
    );
  }
}

class _CrewModePicker extends StatelessWidget {
  const _CrewModePicker({required this.inviteCrew, required this.onChanged});

  final bool inviteCrew;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _CrewModeOption(
            label: 'Pull in crew',
            icon: Icons.group_add_rounded,
            selected: inviteCrew,
            onTap: () => onChanged(true),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _CrewModeOption(
            label: 'Start solo',
            icon: Icons.person_rounded,
            selected: !inviteCrew,
            onTap: () => onChanged(false),
          ),
        ),
      ],
    );
  }
}

class _CrewModeOption extends StatelessWidget {
  const _CrewModeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? NuvoColors.actionBlue.withValues(alpha: 0.08)
              : NuvoColors.white,
          borderRadius: BorderRadius.circular(NuvoRadii.md),
          border: Border.all(
            color: selected ? NuvoColors.actionBlue : NuvoColors.border,
            width: selected ? 2 : 1.25,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 19,
              color: selected ? NuvoColors.actionBlue : NuvoColors.navy,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelLarge.copyWith(
                  color: selected ? NuvoColors.actionBlue : NuvoColors.navy,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RaceSummary extends StatelessWidget {
  const _RaceSummary({required this.draft});

  final RaceDraft draft;

  @override
  Widget build(BuildContext context) {
    final crew = draft.visibility == 'invite_code'
        ? 'Invite crew'
        : 'Start solo';
    final unit = draft.metric == RaceMetric.seconds
        ? 'seconds'
        : draft.activity.proofLabel;
    final launchLine = draft.visibility == 'invite_code'
        ? 'Invite code opens next. Your crew can jump in fast.'
        : 'Solo start. You can pull in your crew after the board is live.';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: NuvoColors.navy,
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            draft.resolvedTitle,
            style: AppTextStyles.titleLarge.copyWith(
              color: NuvoColors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          _RaceVoiceLine(
            text: draft.metric == RaceMetric.seconds
                ? 'Hold steady. Every valid second pushes the board.'
                : 'Every clean rep becomes a visible board move.',
          ),
          const SizedBox(height: 12),
          const _SummaryRow(
            icon: Icons.verified_rounded,
            label: 'Proof',
            value: 'AI Motion Proof',
          ),
          _SummaryRow(
            icon: Icons.flag_rounded,
            label: 'Finish line',
            value: '${draft.targetValue} $unit',
          ),
          _SummaryRow(icon: Icons.group_rounded, label: 'Crew', value: crew),
          const SizedBox(height: 12),
          Text(
            launchLine,
            style: AppTextStyles.bodySmall.copyWith(
              color: NuvoColors.white.withValues(alpha: 0.68),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RaceVoiceLine extends StatelessWidget {
  const _RaceVoiceLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: NuvoColors.success.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(NuvoRadii.md),
        border: Border.all(color: NuvoColors.success.withValues(alpha: 0.34)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt_rounded, color: NuvoColors.success, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodySmall.copyWith(
                color: NuvoColors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(icon, color: NuvoColors.white.withValues(alpha: 0.75), size: 18),
          const SizedBox(width: 9),
          Text(
            '$label: ',
            style: AppTextStyles.bodySmall.copyWith(
              color: NuvoColors.white.withValues(alpha: 0.62),
            ),
          ),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(
                color: NuvoColors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NuvoColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(NuvoRadii.md),
        border: Border.all(color: NuvoColors.danger.withValues(alpha: 0.28)),
      ),
      child: Text(
        message,
        style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.danger),
      ),
    );
  }
}
