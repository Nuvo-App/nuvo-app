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

class _Template {
  const _Template(this.label, this.category, this.unit, this.targetValue);
  final String label;
  final String category;
  final String unit;
  final int? targetValue;
}

const _templates = [
  _Template('Read more', 'reading', 'books', 10),
  _Template('Work out', 'fitness', 'sessions', 20),
  _Template('Run distance', 'running', 'km', 50),
  _Template('Ship a project', 'work', 'projects', 1),
  _Template('Study more', 'learning', 'hours', 40),
  _Template('Custom', '', '', null),
];

class CreateRaceScreen extends ConsumerStatefulWidget {
  const CreateRaceScreen({super.key});

  @override
  ConsumerState<CreateRaceScreen> createState() => _CreateRaceScreenState();
}

class _CreateRaceScreenState extends ConsumerState<CreateRaceScreen> {
  final _titleController = TextEditingController();
  final _targetController = TextEditingController();
  final _unitController = TextEditingController();
  int _templateIndex = 0;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _applyTemplate(0);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _targetController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  void _applyTemplate(int index) {
    final t = _templates[index];
    setState(() {
      _templateIndex = index;
      if (t.label != 'Custom') {
        _titleController.text = t.label;
        _unitController.text = t.unit;
        _targetController.text = t.targetValue != null ? '${t.targetValue}' : '';
      }
    });
  }

  bool get _canStart => _titleController.text.trim().isNotEmpty && !_loading;

  Future<void> _start() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final t = _templates[_templateIndex];
      final targetValue = int.tryParse(_targetController.text.trim());
      final unit = _unitController.text.trim().isEmpty ? null : _unitController.text.trim();
      final category = (t.label == 'Custom' || t.category.isEmpty) ? null : t.category;

      final race = await ref.read(raceControllerProvider.notifier).createRace(
            title: title,
            category: category,
            goalType: 'manual',
            targetValue: targetValue,
            unit: unit,
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
    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton.filledTonal(
                      onPressed: () => safePopOrGo(context, '/compete'),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('New race', style: AppTextStyles.headlineLarge),
                  const SizedBox(height: 6),
                  Text(
                    'Pick a template or write your own goal.',
                    style: AppTextStyles.bodyLarge.copyWith(color: NuvoColors.muted),
                  ),
                  const SizedBox(height: 22),
                  Text('Quick templates', style: AppTextStyles.titleMedium),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < _templates.length; i++)
                        ChoiceChip(
                          label: Text(_templates[i].label),
                          selected: i == _templateIndex,
                          onSelected: (_) => _applyTemplate(i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text('Race title', style: AppTextStyles.titleMedium),
                  const SizedBox(height: 8),
                  _InputField(
                    controller: _titleController,
                    hint: 'e.g. Read 10 books this month',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Goal amount', style: AppTextStyles.titleMedium),
                            const SizedBox(height: 8),
                            _InputField(
                              controller: _targetController,
                              hint: 'e.g. 10',
                              keyboardType: TextInputType.number,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Unit', style: AppTextStyles.titleMedium),
                            const SizedBox(height: 8),
                            _InputField(
                              controller: _unitController,
                              hint: 'e.g. books',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: AppTextStyles.bodySmall.copyWith(color: Colors.red),
                    ),
                  ],
                ],
              )
                  .animate()
                  .fadeIn(duration: 280.ms, curve: Curves.easeOut)
                  .slideY(begin: 0.04, end: 0, duration: 320.ms, curve: Curves.easeOutCubic),
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
    this.keyboardType,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: onChanged,
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
