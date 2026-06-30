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

class JoinRaceScreen extends ConsumerStatefulWidget {
  const JoinRaceScreen({super.key});

  @override
  ConsumerState<JoinRaceScreen> createState() => _JoinRaceScreenState();
}

class _JoinRaceScreenState extends ConsumerState<JoinRaceScreen> {
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = 'Enter an invite code.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final race = await ref
          .read(raceControllerProvider.notifier)
          .joinRaceByCode(code);
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
          _error = 'Could not join this race.';
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
        child:
            ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                  children: [
                    NuvoBackButton(
                      onPressed: () => safePopOrGo(context, '/compete'),
                    ),
                    const SizedBox(height: 18),
                    Text('Join a race', style: AppTextStyles.headlineLarge),
                    const SizedBox(height: 8),
                    Text(
                      'Have a crew invite code? Enter it below to join the race.',
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: NuvoColors.muted,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _codeController,
                      textCapitalization: TextCapitalization.characters,
                      style: AppTextStyles.bodyMedium,
                      decoration: InputDecoration(
                        hintText: 'NUV-XXXXXX',
                        hintStyle: AppTextStyles.bodyMedium.copyWith(
                          color: NuvoColors.muted,
                        ),
                        filled: true,
                        fillColor: NuvoColors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: NuvoColors.border,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: NuvoColors.border,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: NuvoColors.blue,
                            width: 1.6,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: NuvoColors.danger,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    NuvoPrimaryButton(
                      label: 'Join race',
                      icon: Icons.group_add_rounded,
                      expand: true,
                      loading: _loading,
                      onPressed: _loading ? null : _join,
                    ),
                  ],
                )
                .animate()
                .fadeIn(duration: 220.ms, curve: Curves.easeOut)
                .slideY(begin: 0.03, end: 0, duration: 260.ms),
      ),
    );
  }
}
