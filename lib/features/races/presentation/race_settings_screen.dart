import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_motion.dart';
import '../../../core/widgets/nuvo_confirm_dialog.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_fade_scroll.dart';
import '../../../core/widgets/nuvo_loading_indicator.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/race_models.dart';
import '../domain/camera_verification_resolver.dart';
import '../domain/motion_activity.dart';
import 'motion_catalog_provider.dart';
import 'race_controller.dart';

class RaceSettingsScreen extends ConsumerStatefulWidget {
  const RaceSettingsScreen({super.key, required this.raceId});

  final String raceId;

  @override
  ConsumerState<RaceSettingsScreen> createState() => _RaceSettingsScreenState();
}

class _RaceSettingsScreenState extends ConsumerState<RaceSettingsScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _categoryController = TextEditingController();
  final _targetController = TextEditingController();
  final _unitController = TextEditingController();
  final _rulesController = TextEditingController();
  final _startLineController = TextEditingController();
  final _finishLineController = TextEditingController();

  /// Control-plane definitions for resolving remote-only race activities
  /// (motions this build has no compiled enum for).
  List<MotionActivityDefinition> get _remoteDefinitions =>
      availableMotionActivities(
        ref.read(motionCatalogProvider).valueOrNull,
        ref.read(motionCapabilitiesProvider),
      );

  Race? _race;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _goalType = 'manual';
  String _proofRequirement = 'manual';
  String _proofReviewMode = 'auto_accept';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    _targetController.dispose();
    _unitController.dispose();
    _rulesController.dispose();
    _startLineController.dispose();
    _finishLineController.dispose();
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
      if (!mounted) return;
      _race = race;
      _titleController.text = race.title;
      _descriptionController.text = race.description ?? '';
      _categoryController.text = race.category ?? '';
      _targetController.text = race.targetValue?.toString() ?? '';
      _unitController.text = race.unit ?? '';
      _rulesController.text = race.rules ?? '';
      _startLineController.text = race.startLineAt ?? '';
      _finishLineController.text = race.finishLineAt ?? '';
      _goalType = race.goalType;
      _proofRequirement =
          resolveCameraVerification(
            race,
            remoteDefinitions: _remoteDefinitions,
          ).isCameraVerifiable
          ? 'ai_check'
          : race.proofRequirement;
      _proofReviewMode = race.proofReviewMode;
      setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load race settings.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Race title is required.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final target = int.tryParse(_targetController.text.trim());
      final existingRace = _race;
      final eligibility = existingRace == null
          ? null
          : resolveCameraVerification(
              existingRace,
              remoteDefinitions: _remoteDefinitions,
            );
      final race = await ref
          .read(raceControllerProvider.notifier)
          .updateRace(
            widget.raceId,
            title: title,
            description: _descriptionController.text.trim(),
            category: _categoryController.text.trim(),
            goalType: _goalType,
            targetValue: target,
            unit: eligibility?.isCameraVerifiable == true
                ? _unitForEligibility(eligibility!)
                : _unitController.text.trim(),
            startLineAt: _startLineController.text.trim(),
            finishLineAt: _finishLineController.text.trim(),
            rules: _rulesController.text.trim(),
            proofRequirement: eligibility?.isCameraVerifiable == true
                ? 'ai_check'
                : _proofRequirement,
            proofReviewMode: _proofReviewMode,
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
          _error = 'Could not save changes.';
          _saving = false;
        });
      }
    }
  }

  Future<void> _runLifecycleAction({
    required String title,
    required String message,
    required String confirmLabel,
    required Future<void> Function() action,
    bool returnToArena = false,
  }) async {
    final confirmed = await showNuvoConfirmDialog(
      context,
      title: title,
      message: message,
      cancelLabel: 'Keep race',
      confirmLabel: confirmLabel,
    );
    if (confirmed != true) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      context.go(returnToArena ? '/arena' : '/race/${widget.raceId}');
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
          _error = 'Could not update this race.';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final isOwner = _race?.creatorId == user?.id;
    final eligibility = _race == null
        ? null
        : resolveCameraVerification(
            _race!,
            remoteDefinitions: _remoteDefinitions,
          );
    final isCameraRace = eligibility?.isCameraVerifiable == true;

    if (_loading) {
      return Scaffold(
        backgroundColor: context.themeColors.page,
        body: const Center(child: NuvoLoadingIndicator()),
      );
    }

    if (_race == null) {
      return Scaffold(
        backgroundColor: context.themeColors.page,
        body: SafeArea(
          child: NuvoErrorState(
            message: _error ?? 'Race settings could not load.',
            onRetry: _load,
          ),
        ),
      );
    }

    if (!isOwner) {
      return Scaffold(
        backgroundColor: context.themeColors.page,
        body: SafeArea(
          child: NuvoErrorState(
            message: 'Only the race creator can edit race settings.',
            onRetry: () => context.go('/race/${widget.raceId}'),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.themeColors.page,
      body: SafeArea(
        child: NuvoFadeScroll(
          child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: NuvoBackButton(
                onPressed: () => safePopOrGo(context, '/race/${widget.raceId}'),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Edit race',
              style: AppTextStyles.headlineLarge.copyWith(
                fontSize: 32,
                letterSpacing: -0.9,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Change your race details, rules, and status.',
              style: AppTextStyles.bodyLarge.copyWith(color: context.themeColors.inkMuted),
            ),
            const SizedBox(height: 24),
            _Section(
              title: 'Basic details',
              children: [
                _Input(controller: _titleController, label: 'Title'),
                _Input(
                  controller: _descriptionController,
                  label: 'Description',
                  maxLines: 3,
                ),
                _Input(controller: _categoryController, label: 'Category'),
              ],
            ),
            _Section(
              title: 'Goal',
              children: isCameraRace
                  ? [
                      _MovementSummary(eligibility: eligibility!),
                      _Input(
                        controller: _targetController,
                        label: 'Target',
                        hint: _targetHint(eligibility),
                        keyboardType: TextInputType.number,
                      ),
                      _Input(
                        controller: _startLineController,
                        label: 'Start',
                        hint: 'Add start date',
                      ),
                      _Input(
                        controller: _finishLineController,
                        label: 'Finish',
                        hint: 'Add finish date',
                      ),
                    ]
                  : [
                      Row(
                        children: [
                          Expanded(
                            child: _Input(
                              controller: _targetController,
                              label: 'Target value',
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _Input(
                              controller: _unitController,
                              label: 'Unit',
                            ),
                          ),
                        ],
                      ),
                      _Input(
                        controller: _startLineController,
                        label: 'Start',
                        hint: 'Add start date',
                      ),
                      _Input(
                        controller: _finishLineController,
                        label: 'Finish',
                        hint: 'Add finish date',
                      ),
                    ],
            ),
            _Section(
              title: 'Rules',
              children: [
                _Input(
                  controller: _rulesController,
                  label: 'Race rules',
                  hint: 'How the winner is decided.',
                  maxLines: 5,
                ),
              ],
            ),
            if (_error != null) ...[
              Text(
                _error!,
                style: AppTextStyles.bodySmall.copyWith(
                  color: NuvoColors.danger,
                ),
              ),
              const SizedBox(height: 12),
            ],
            NuvoPrimaryButton(
              label: 'Save changes',
              icon: Icons.check_rounded,
              expand: true,
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
            const SizedBox(height: 12),
            NuvoOutlineButton(
              label: 'Back to race',
              expand: true,
              onPressed: _saving
                  ? null
                  : () => context.go('/race/${widget.raceId}'),
            ),
            const SizedBox(height: 26),
            _Section(
              title: 'Race actions',
              children: [
                _SettingsActionGroup(
                  actions: [
                    _SettingsAction(
                      icon: Icons.archive_rounded,
                      title: 'Archive race',
                      subtitle: 'Move it out of active races',
                      onPressed: _saving
                          ? null
                          : () => _runLifecycleAction(
                              title: 'Archive race?',
                              message:
                                  'This race will leave active competition but stay in your race history.',
                              confirmLabel: 'Archive',
                              action: () => ref
                                  .read(raceControllerProvider.notifier)
                                  .archiveRace(widget.raceId),
                            ),
                    ),
                    _SettingsAction(
                      icon: Icons.cancel_outlined,
                      title: 'Cancel race',
                      subtitle: 'Stop this race before the finish line',
                      onPressed: _saving
                          ? null
                          : () => _runLifecycleAction(
                              title: 'Cancel race?',
                              message:
                                  'Cancel this race only if the start line or rules no longer apply.',
                              confirmLabel: 'Cancel race',
                              action: () => ref
                                  .read(raceControllerProvider.notifier)
                                  .cancelRace(widget.raceId),
                            ),
                    ),
                    _SettingsAction(
                      icon: Icons.delete_outline_rounded,
                      title: 'Delete race',
                      subtitle: 'Remove it from Arena and race history',
                      destructive: true,
                      onPressed: _saving
                          ? null
                          : () => _runLifecycleAction(
                              title: 'Delete race?',
                              message:
                                  'This permanently removes the race. This action cannot be undone.',
                              confirmLabel: 'Delete',
                              returnToArena: true,
                              action: () => ref
                                  .read(raceControllerProvider.notifier)
                                  .deleteRace(widget.raceId),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.titleLarge),
          const SizedBox(height: 12),
          ...children.expand((child) => [child, const SizedBox(height: 12)]),
        ],
      ),
    );
  }
}

class _SettingsActionGroup extends StatelessWidget {
  const _SettingsActionGroup({required this.actions});

  final List<_SettingsAction> actions;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(NuvoRadii.lg),
      child: Container(
        decoration: BoxDecoration(
          color: context.themeColors.surface,
          borderRadius: BorderRadius.circular(NuvoRadii.lg),
          border: Border.all(color: context.themeColors.border, width: 1.25),
        ),
        child: Column(
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              actions[i],
              if (i < actions.length - 1)
                Divider(height: 1, indent: 66, color: context.themeColors.border),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsAction extends StatelessWidget {
  const _SettingsAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final titleColor = destructive ? NuvoColors.danger : context.themeColors.ink;
    final iconColor = destructive ? NuvoColors.danger : context.themeColors.ink;
    final iconBackground = destructive
        ? NuvoColors.dangerSurface
        : context.themeColors.panelLight;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: title,
      child: NuvoPressable(
        onTap: onPressed,
        haptic: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: iconColor, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: titleColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: context.themeColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: NuvoColors.paleSlate,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Input extends StatelessWidget {
  const _Input({
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return NuvoTextInput(
      controller: controller,
      label: label,
      hint: hint,
      maxLines: maxLines,
      keyboardType: keyboardType,
    );
  }
}

class _MovementSummary extends StatelessWidget {
  const _MovementSummary({required this.eligibility});

  final CameraVerificationEligibility eligibility;

  @override
  Widget build(BuildContext context) {
    final movement = eligibility.movementDefinition;
    final unit = _unitForEligibility(eligibility);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: context.themeColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.themeColors.border, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Movement',
            style: AppTextStyles.labelSmall.copyWith(color: context.themeColors.inkMuted),
          ),
          const SizedBox(height: 4),
          Text(
            movement?.title ?? 'Movement unavailable',
            style: AppTextStyles.titleMedium,
          ),
          const SizedBox(height: 2),
          Text(
            'Target is measured in $unit.',
            style: AppTextStyles.bodySmall.copyWith(color: context.themeColors.inkMuted),
          ),
        ],
      ),
    );
  }
}

String _unitForEligibility(CameraVerificationEligibility eligibility) {
  return eligibility.movementDefinition?.isHold == true ? 'seconds' : 'reps';
}

String _targetHint(CameraVerificationEligibility eligibility) {
  final unit = _unitForEligibility(eligibility);
  final target = eligibility.movementDefinition?.defaultTarget;
  return target == null ? unit : '$target $unit';
}
