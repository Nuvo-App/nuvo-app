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
import '../../auth/presentation/auth_controller.dart';
import '../data/race_models.dart';
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

  Race? _race;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _goalType = 'manual';
  String _proofRequirement = 'manual';
  String _proofReviewMode = 'auto_accept';
  String _visibility = 'private';

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
      _proofRequirement = race.proofRequirement;
      _proofReviewMode = race.proofReviewMode;
      _visibility = race.visibility;
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
      final race = await ref
          .read(raceControllerProvider.notifier)
          .updateRace(
            widget.raceId,
            title: title,
            description: _descriptionController.text.trim(),
            category: _categoryController.text.trim(),
            goalType: _goalType,
            targetValue: target,
            unit: _unitController.text.trim(),
            startLineAt: _startLineController.text.trim(),
            finishLineAt: _finishLineController.text.trim(),
            rules: _rulesController.text.trim(),
            proofRequirement: _proofRequirement,
            proofReviewMode: _proofReviewMode,
            visibility: _visibility,
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep race'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
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

    if (_loading) {
      return const Scaffold(
        backgroundColor: NuvoColors.page,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_race == null) {
      return Scaffold(
        backgroundColor: NuvoColors.page,
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
        backgroundColor: NuvoColors.page,
        body: SafeArea(
          child: NuvoErrorState(
            message: 'Only the race creator can edit race settings.',
            onRetry: () => context.go('/race/${widget.raceId}'),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: NuvoIconAction(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back to race',
                onPressed: () => safePopOrGo(context, '/race/${widget.raceId}'),
              ),
            ),
            const SizedBox(height: 18),
            Text('Race settings', style: AppTextStyles.headlineLarge),
            const SizedBox(height: 8),
            Text(
              'Tune the start line, finish line, proof rules, and lifecycle.',
              style: AppTextStyles.bodyLarge.copyWith(color: NuvoColors.muted),
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
              children: [
                _Menu(
                  label: 'Goal type',
                  value: _goalType,
                  values: const {'manual': 'manual', 'photo': 'photo'},
                  onChanged: (value) => setState(() => _goalType = value),
                ),
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
                      child: _Input(controller: _unitController, label: 'Unit'),
                    ),
                  ],
                ),
                _Input(
                  controller: _startLineController,
                  label: 'Start line date',
                  hint: 'Optional ISO date',
                ),
                _Input(
                  controller: _finishLineController,
                  label: 'Finish line date',
                  hint: 'Optional ISO date',
                ),
              ],
            ),
            _Section(
              title: 'Rules',
              children: [
                _Input(
                  controller: _rulesController,
                  label: 'Race rules',
                  hint:
                      'What counts, what does not, and how the winner is decided.',
                  maxLines: 5,
                ),
              ],
            ),
            _Section(
              title: 'Proof',
              children: [
                _Menu(
                  label: 'Proof requirement',
                  value: _proofRequirement,
                  values: const {
                    'manual': 'manual proof',
                    'photo_video': 'photo/video proof coming soon',
                    'ai_check': 'AI proof check coming soon',
                  },
                  onChanged: (value) =>
                      setState(() => _proofRequirement = value),
                ),
                _Menu(
                  label: 'Proof review mode',
                  value: _proofReviewMode,
                  values: const {
                    'auto_accept': 'auto accept',
                    'owner_review': 'owner review',
                    'ai_review': 'AI review coming soon',
                  },
                  onChanged: (value) =>
                      setState(() => _proofReviewMode = value),
                ),
              ],
            ),
            _Section(
              title: 'Visibility',
              children: [
                _Menu(
                  label: 'Who can join',
                  value: _visibility,
                  values: const {
                    'private': 'private',
                    'crew_only': 'crew only',
                    'invite_code': 'invite code',
                  },
                  onChanged: (value) => setState(() => _visibility = value),
                ),
              ],
            ),
            if (_error != null) ...[
              Text(
                _error!,
                style: AppTextStyles.bodySmall.copyWith(color: Colors.red),
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
              title: 'Lifecycle',
              children: [
                NuvoGhostButton(
                  label: 'Archive race',
                  icon: Icons.archive_rounded,
                  expand: true,
                  onPressed: _saving
                      ? null
                      : () => _runLifecycleAction(
                          title: 'Archive race?',
                          message:
                              'Archived races leave active competition but remain in your race history.',
                          confirmLabel: 'Archive',
                          action: () => ref
                              .read(raceControllerProvider.notifier)
                              .archiveRace(widget.raceId),
                        ),
                ),
                NuvoGhostButton(
                  label: 'Cancel race',
                  icon: Icons.cancel_rounded,
                  expand: true,
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
              ],
            ),
            _Section(
              title: 'Danger zone',
              children: [
                NuvoDangerButton(
                  label: 'Delete race',
                  icon: Icons.delete_outline_rounded,
                  expand: true,
                  loading: _saving,
                  onPressed: _saving
                      ? null
                      : () => _runLifecycleAction(
                          title: 'Delete race?',
                          message:
                              'This hides the race from your arena. Proof history is preserved in the backend.',
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
        ).animate().fadeIn(duration: 220.ms, curve: Curves.easeOut).slideY(begin: 0.03, end: 0, duration: 260.ms),
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
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: NuvoColors.white,
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Map<String, String> values;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: values.containsKey(value) ? value : values.keys.first,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: NuvoColors.white,
      ),
      items: [
        for (final entry in values.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}
