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

  static const jumpingJacks = RaceCreatePrefill(idea: '10 Jumping Jacks');
}

const _quickStarts = [
  '10 Jumping Jacks',
  '10 Squats',
  '20 High Knees',
  '10 Arm Raises',
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

  bool get _canStart => _ideaController.text.trim().isNotEmpty && !_loading;

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
      final race = await ref
          .read(raceControllerProvider.notifier)
          .createRace(
            title: idea,
            description: activity == null
                ? null
                : 'AI MoveCheck counts ${activity.targetLabel(parsed.targetValue)} live.',
            category: activity == null ? null : 'fitness',
            goalType: 'manual',
            targetValue: parsed.targetValue,
            unit: parsed.unit,
            proofRequirement: parsed.aiSupported ? 'ai_check' : 'manual',
            proofReviewMode: 'auto_accept',
            aiActivityType: activity?.type.backendValue,
            targetUnit: parsed.unit,
            proofMode: parsed.aiSupported ? 'ai_check' : 'manual',
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
                            parsed.aiSupported ? 'Start AI race' : 'New race',
                            style: AppTextStyles.headlineLarge,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Type a movement race naturally. Nuvo detects MoveCheck support automatically.',
                            style: AppTextStyles.bodyLarge.copyWith(
                              color: NuvoColors.muted,
                            ),
                          ),
                          const SizedBox(height: 22),
                          Text('Race idea', style: AppTextStyles.titleMedium),
                          const SizedBox(height: 8),
                          _InputField(
                            controller: _ideaController,
                            hint: 'e.g. 10 squats',
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 14),
                          _DetectionCard(parsed: parsed),
                          const SizedBox(height: 22),
                          Text(
                            'Quick starts',
                            style: AppTextStyles.titleMedium,
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final quickStart in _quickStarts)
                                _QuickStartPill(
                                  label: quickStart,
                                  selected:
                                      quickStart.toLowerCase() ==
                                      _ideaController.text.trim().toLowerCase(),
                                  onTap: () => _setIdea(quickStart),
                                ),
                            ],
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: Colors.red,
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
                label: parsed.aiSupported ? 'Start AI race' : 'Start race',
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

class _DetectionCard extends StatelessWidget {
  const _DetectionCard({required this.parsed});

  final ParsedRaceIdea parsed;

  @override
  Widget build(BuildContext context) {
    final activity = parsed.activity;
    final isAi = activity != null;
    final bg = isAi ? NuvoColors.navy : NuvoColors.white;
    final titleColor = isAi ? NuvoColors.white : NuvoColors.navy;
    final bodyColor = isAi
        ? NuvoColors.white.withValues(alpha: 0.72)
        : NuvoColors.muted;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isAi ? NuvoColors.navy : NuvoColors.border),
        boxShadow: isAi
            ? const [
                BoxShadow(
                  color: Color(0x3307152B),
                  blurRadius: 0,
                  offset: Offset(3, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isAi ? NuvoColors.blue : NuvoColors.icyBlue,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isAi ? Icons.directions_run_rounded : Icons.edit_note_rounded,
              color: isAi ? NuvoColors.white : NuvoColors.blue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAi ? 'AI MoveCheck available' : 'Manual logging',
                  style: AppTextStyles.titleMedium.copyWith(color: titleColor),
                ),
                const SizedBox(height: 4),
                Text(
                  isAi
                      ? '${activity.title} · ${activity.targetLabel(parsed.targetValue)}. Nuvo can verify this with your iPhone camera.'
                      : 'Manual logging for this race.',
                  style: AppTextStyles.bodySmall.copyWith(color: bodyColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickStartPill extends StatelessWidget {
  const _QuickStartPill({
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? NuvoColors.blue : NuvoColors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? NuvoColors.blue : NuvoColors.border,
          ),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x3307152B),
                    blurRadius: 0,
                    offset: Offset(2, 3),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: AppTextStyles.labelMedium.copyWith(
            color: selected ? NuvoColors.white : NuvoColors.navy,
          ),
        ),
      ),
    );
  }
}
