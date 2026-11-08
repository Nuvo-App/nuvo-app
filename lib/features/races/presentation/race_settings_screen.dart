import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/v13/v13.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/race_models.dart';
import '../domain/camera_verification_resolver.dart';
import '../domain/motion_activity.dart';
import 'motion_catalog_provider.dart';
import 'race_controller.dart';

/// `/race/:id/settings` — owner-only race settings. Edit the details, goal,
/// and rules; archive, cancel, or delete the race behind confirm sheets.
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
      if (mounted) {
        showV13Toast(context, 'Race updated.');
        context.go('/race/${race.id}');
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyApiError(e);
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
    required String toastLabel,
    required Future<void> Function() action,
    bool destructive = false,
    bool returnToArena = false,
  }) async {
    final confirmed = await showV13ConfirmSheet(
      context,
      title: title,
      body: message,
      cancelLabel: 'Keep race',
      confirmLabel: confirmLabel,
      destructive: destructive,
    );
    if (confirmed != true) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      showV13Toast(context, toastLabel);
      context.go(returnToArena ? '/arena' : '/race/${widget.raceId}');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyApiError(e);
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

    return Scaffold(
      backgroundColor: V13.bg,
      body: SafeArea(
        child: Column(
          children: [
            V13BackBar(
              title: 'Edit race',
              onBack: () => safePopOrGo(context, '/race/${widget.raceId}'),
            ),
            Expanded(
              child: V13AsyncView<Race>.state(
                status: _loading
                    ? V13AsyncStatus.loading
                    : _race == null
                    ? V13AsyncStatus.error
                    : !isOwner
                    ? V13AsyncStatus.empty
                    : V13AsyncStatus.data,
                dataValue: _race,
                errorValue: _error,
                errorTitle: 'Could not load race settings',
                emptyIcon: Icons.lock_outline_rounded,
                emptyTitle: 'Only the race creator can edit race settings.',
                emptyAction: V13Button.secondary(
                  label: 'Back to race',
                  onPressed: () => context.go('/race/${widget.raceId}'),
                ),
                onRetry: _load,
                builder: (race) => _form(race),
              ),
            ),
            if (!_loading && _race != null && isOwner)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  V13.pagePad,
                  0,
                  V13.pagePad,
                  V13.gapLg,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    V13Button.primary(
                      label: 'Save changes',
                      icon: Icons.check_rounded,
                      fullWidth: true,
                      loading: _saving,
                      onPressed: _saving ? null : _save,
                    ),
                    const SizedBox(height: V13.gapMd),
                    V13Button.secondary(
                      label: 'Back to race',
                      fullWidth: true,
                      onPressed: _saving
                          ? null
                          : () => context.go('/race/${widget.raceId}'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _form(Race race) {
    final eligibility = resolveCameraVerification(
      race,
      remoteDefinitions: _remoteDefinitions,
    );
    final isCameraRace = eligibility.isCameraVerifiable;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        V13.pagePad,
        V13.gapMd,
        V13.pagePad,
        V13.gapXxl * 2,
      ),
      children: [
        Text(
          'Change your race details, rules, and status.',
          style: V13.body.copyWith(color: V13.muted),
        ),
        const SizedBox(height: V13.gapXl),
        const V13SectionHeader(title: 'Basic details'),
        const SizedBox(height: V13.gapMd),
        V13TextInput(controller: _titleController, label: 'Title'),
        const SizedBox(height: V13.gapMd),
        _MultilineInput(
          controller: _descriptionController,
          label: 'Description',
          maxLines: 3,
        ),
        const SizedBox(height: V13.gapMd),
        V13TextInput(controller: _categoryController, label: 'Category'),
        const SizedBox(height: V13.gapSection),
        const V13SectionHeader(title: 'Goal'),
        const SizedBox(height: V13.gapMd),
        if (isCameraRace) ...[
          _MovementSummary(eligibility: eligibility),
          const SizedBox(height: V13.gapMd),
          V13TextInput(
            controller: _targetController,
            label: 'Target',
            hint: _targetHint(eligibility),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: V13.gapMd),
          V13TextInput(
            controller: _startLineController,
            label: 'Start',
            hint: 'Add start date',
          ),
          const SizedBox(height: V13.gapMd),
          V13TextInput(
            controller: _finishLineController,
            label: 'Finish',
            hint: 'Add finish date',
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: V13TextInput(
                  controller: _targetController,
                  label: 'Target value',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: V13.gapMd),
              Expanded(
                child: V13TextInput(controller: _unitController, label: 'Unit'),
              ),
            ],
          ),
          const SizedBox(height: V13.gapMd),
          V13TextInput(
            controller: _startLineController,
            label: 'Start',
            hint: 'Add start date',
          ),
          const SizedBox(height: V13.gapMd),
          V13TextInput(
            controller: _finishLineController,
            label: 'Finish',
            hint: 'Add finish date',
          ),
        ],
        const SizedBox(height: V13.gapSection),
        const V13SectionHeader(title: 'Rules'),
        const SizedBox(height: V13.gapMd),
        _MultilineInput(
          controller: _rulesController,
          label: 'Race rules',
          hint: 'How the winner is decided.',
          maxLines: 5,
        ),
        const SizedBox(height: V13.gapSection),
        const V13SectionHeader(title: 'Race actions'),
        const SizedBox(height: V13.gapMd),
        V13Card(
          padding: const EdgeInsets.symmetric(horizontal: V13.gapLg),
          child: Column(
            children: [
              V13ListRow(
                title: 'Archive race',
                subtitle: 'Move it out of active races',
                leading: const V13IconTile(
                  icon: Icons.archive_rounded,
                  color: V13.sun,
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: V13.muted,
                ),
                onTap: _saving
                    ? null
                    : () => _runLifecycleAction(
                        title: 'Archive race?',
                        message:
                            'This race will leave active competition but stay in your race history.',
                        confirmLabel: 'Archive',
                        toastLabel: 'Race archived.',
                        action: () => ref
                            .read(raceControllerProvider.notifier)
                            .archiveRace(widget.raceId),
                      ),
              ),
              V13ListRow(
                title: 'Cancel race',
                subtitle: 'Stop this race before the finish line',
                leading: const V13IconTile(
                  icon: Icons.cancel_outlined,
                  color: V13.coral,
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: V13.muted,
                ),
                onTap: _saving
                    ? null
                    : () => _runLifecycleAction(
                        title: 'Cancel race?',
                        message:
                            'Cancel this race only if the start line or rules no longer apply.',
                        confirmLabel: 'Cancel race',
                        toastLabel: 'Race cancelled.',
                        action: () => ref
                            .read(raceControllerProvider.notifier)
                            .cancelRace(widget.raceId),
                      ),
              ),
              V13ListRow(
                title: 'Delete race',
                subtitle: 'Remove it from Arena and race history',
                leading: const V13IconTile(
                  icon: Icons.delete_outline_rounded,
                  color: V13.coral,
                ),
                trailing: _saving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: V13.navy,
                        ),
                      )
                    : const Icon(Icons.chevron_right_rounded, color: V13.muted),
                showDivider: false,
                onTap: _saving
                    ? null
                    : () => _runLifecycleAction(
                        title: 'Delete race?',
                        message:
                            'This permanently removes the race. This action cannot be undone.',
                        confirmLabel: 'Delete',
                        toastLabel: 'Race deleted.',
                        destructive: true,
                        returnToArena: true,
                        action: () => ref
                            .read(raceControllerProvider.notifier)
                            .deleteRace(widget.raceId),
                      ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: V13.gapMd),
          Text(_error!, style: V13.caption.copyWith(color: V13.danger)),
        ],
      ],
    );
  }
}

/// V13TextInput is single-line; multi-line fields reuse its chrome through
/// this thin wrapper so Description/Rules keep the same look.
class _MultilineInput extends StatelessWidget {
  const _MultilineInput({
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: V13.bodyStrong),
        const SizedBox(height: V13.gapSm),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: V13.body,
          cursorColor: V13.blue,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: V13.body.copyWith(color: V13.muted),
            filled: true,
            fillColor: V13.card,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(V13.radiusButton),
              borderSide: const BorderSide(color: V13.navy, width: V13.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(V13.radiusButton),
              borderSide: const BorderSide(color: V13.blue, width: V13.outline),
            ),
          ),
        ),
      ],
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

    return V13Card(
      color: V13.sky,
      child: Row(
        children: [
          const V13IconTile(icon: Icons.videocam_rounded, color: V13.card),
          const SizedBox(width: V13.gapMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movement?.title ?? 'Movement unavailable',
                  style: V13.bodyStrong,
                ),
                const SizedBox(height: 2),
                Text(
                  'Target is measured in $unit.',
                  style: V13.caption.copyWith(color: V13.navy),
                ),
              ],
            ),
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
