import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
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
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: NuvoColors.white,
              borderRadius: BorderRadius.circular(NuvoRadii.lg),
              border: Border.all(color: NuvoColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: NuvoPrimaryButton(
                label: _loading ? 'Joining race' : 'Join race',
                icon: Icons.group_add_rounded,
                expand: true,
                loading: _loading,
                onPressed: _loading ? null : _join,
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child:
            ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                  children: [
                    NuvoBackButton(
                      onPressed: () => safePopOrGo(context, '/compete'),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                      decoration: BoxDecoration(
                        color: NuvoColors.navy,
                        borderRadius: BorderRadius.circular(NuvoRadii.lg),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Join a race',
                            style: AppTextStyles.headlineLarge.copyWith(
                              color: NuvoColors.white,
                              letterSpacing: 0,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Paste the invite code from your crew. Nuvo takes you straight to the leaderboard.',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: NuvoColors.white.withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: NuvoColors.white,
                        borderRadius: BorderRadius.circular(NuvoRadii.lg),
                        border: Border.all(color: NuvoColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          NuvoTextInput(
                            controller: _codeController,
                            label: 'Invite code',
                            hint: 'NUV-XXXXXX',
                            textCapitalization: TextCapitalization.characters,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(
                                Icons.lock_open_rounded,
                                color: NuvoColors.success,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'One code, one tap, then you are on the board.',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: NuvoColors.textMuted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: NuvoColors.danger.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(NuvoRadii.md),
                          border: Border.all(
                            color: NuvoColors.danger.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Text(
                          _error!,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: NuvoColors.danger,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                )
                .animate()
                .fadeIn(duration: 220.ms, curve: Curves.easeOut)
                .slideY(begin: 0.03, end: 0, duration: 260.ms),
      ),
    );
  }
}
