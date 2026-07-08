import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../auth/data/auth_api.dart';
import '../domain/motion_activity.dart';
import '../domain/motion_activity_catalog.dart';
import 'race_controller.dart';

class RaceCreatePrefill {
  const RaceCreatePrefill({required this.idea});

  final String idea;

  static const pushups = RaceCreatePrefill(idea: '10 Pushups');
  static const squats = RaceCreatePrefill(idea: '10 Squats');
  static const jumpingJacks = RaceCreatePrefill(idea: '10 Jumping Jacks');
  static const lunges = RaceCreatePrefill(idea: '10 Lunges');
  static const plank = RaceCreatePrefill(idea: '20 Second Plank');
}

const _quickStarts = [
  '10 Pushups',
  '10 Jumping Jacks',
  '10 Squats',
  '10 Lunges',
  '20 Second Plank',
];

class CreateRaceScreen extends ConsumerStatefulWidget {
  const CreateRaceScreen({super.key, this.prefill});

  final RaceCreatePrefill? prefill;

  @override
  ConsumerState<CreateRaceScreen> createState() => _CreateRaceScreenState();
}

class _CreateRaceScreenState extends ConsumerState<CreateRaceScreen> {
  final _ideaController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ideaController.text = widget.prefill?.idea ?? _quickStarts.first;
  }

  @override
  void dispose() {
    _ideaController.dispose();
    super.dispose();
  }

  ParsedRaceIdea get _parsed => parseRaceIdea(_ideaController.text);

  bool get _canStart =>
      _ideaController.text.trim().isNotEmpty &&
      _parsed.aiSupported &&
      !_loading;

  void _setIdea(String idea) {
    setState(() {
      _ideaController.text = idea;
      _ideaController.selection = TextSelection.collapsed(offset: idea.length);
    });
  }

  Future<void> _start() async {
    final parsed = _parsed;
    final idea = _ideaController.text.trim();
    if (idea.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final activity = parsed.activity;
      final unit = _unitForActivity(activity);
      final targetLabel = _targetLabel(parsed);
      final race = await ref
          .read(raceControllerProvider.notifier)
          .createRace(
            title: idea,
            description: activity == null
                ? null
                : 'Camera counts $targetLabel automatically.',
            category: activity == null ? null : 'fitness',
            goalType: 'manual',
            targetValue: parsed.targetValue,
            unit: unit,
            proofRequirement: 'ai_check',
            proofReviewMode: 'auto_accept',
            aiActivityType: activity?.type.backendValue,
            targetUnit: unit,
            proofMode: 'ai_check',
          );

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
          _error = 'Something went wrong. Try again.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parsed;

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child:
                  ListView(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: NuvoBackButton(
                              onPressed: () => safePopOrGo(context, '/compete'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Start race',
                            style: AppTextStyles.headlineLarge,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'What are you racing?',
                            style: AppTextStyles.bodyLarge.copyWith(
                              color: NuvoColors.muted,
                            ),
                          ),
                          const SizedBox(height: 22),
                          _InputField(
                            controller: _ideaController,
                            hint: 'e.g. 10 squats',
                            onChanged: (_) => setState(() {}),
                          ),

                          // Inline verification status — not a card, just text
                          if (parsed.aiSupported) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: NuvoColors.blue,
                                  size: 15,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Camera verified \u00b7 ${_targetLabel(parsed)}',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: NuvoColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ] else if (_ideaController.text.trim().isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Icon(
                                  Icons.info_outline_rounded,
                                  color: NuvoColors.muted,
                                  size: 15,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Not supported for camera verification yet.',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: NuvoColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          const SizedBox(height: 28),

                          // Quick starts — clean list, not floating pills
                          for (final quickStart in _quickStarts) ...[
                            _QuickStartRow(
                              label: quickStart,
                              selected:
                                  quickStart.toLowerCase() ==
                                  _ideaController.text.trim().toLowerCase(),
                              onTap: () => _setIdea(quickStart),
                            ),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: NuvoPrimaryButton(
                label: 'Start race',
                icon: Icons.flag_rounded,
                expand: true,
                loading: _loading,
                onPressed: _canStart ? _start : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.hint,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}

String _unitForActivity(MotionActivityDefinition? activity) {
  if (activity == null) return 'reps';
  return activity.isHold ? 'seconds' : 'reps';
}

String _targetLabel(ParsedRaceIdea parsed) {
  final activity = parsed.activity;
  final unit = _unitForActivity(activity);
  return '${parsed.targetValue} $unit';
}

class _QuickStartRow extends StatelessWidget {
  const _QuickStartRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? NuvoColors.blue : Colors.transparent,
                border: Border.all(
                  color: selected ? NuvoColors.blue : NuvoColors.border,
                  width: selected ? 6 : 1.5,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: selected ? NuvoColors.navy : NuvoColors.muted,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
