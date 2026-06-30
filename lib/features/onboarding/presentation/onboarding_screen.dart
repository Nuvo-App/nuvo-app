import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../auth/presentation/auth_controller.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  bool _privateStats = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authControllerProvider).user;
    _nameController = TextEditingController(text: user?.fullName ?? '');
    _usernameController = TextEditingController(text: user?.username ?? '');
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  String get _initials {
    final raw = _nameController.text.trim();
    if (raw.isEmpty) return '?';
    final parts = raw.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  Future<void> _continue() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .saveProfile(
            fullName: _nameController.text.trim(),
            username: _usernameController.text.trim().toLowerCase(),
            privateProfile: _privateStats,
          );
      if (mounted) context.go('/onboarding/member-pass');
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not save profile. Please try again.';
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
                  padding: const EdgeInsets.fromLTRB(20, 34, 20, 40),
                  children: [
                    // Step progress
                    Row(
                      children: [
                        for (var i = 0; i < 5; i++) ...[
                          Expanded(
                            child: Container(
                              height: 3,
                              decoration: BoxDecoration(
                                color: i <= 2
                                    ? NuvoColors.blue
                                    : NuvoColors.border,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                          if (i < 4) const SizedBox(width: 4),
                        ],
                      ],
                    ),
                    const SizedBox(height: 28),

                    Text(
                      'Build your profile',
                      style: AppTextStyles.headlineLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'This is how your crew will see you in races.',
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: NuvoColors.muted,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Avatar
                    Center(
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Container(
                            width: 96,
                            height: 96,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: NuvoColors.navy,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _initials,
                              style: AppTextStyles.headlineMedium.copyWith(
                                color: NuvoColors.white,
                              ),
                            ),
                          ),
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: NuvoColors.blue,
                              border: Border.all(
                                color: NuvoColors.page,
                                width: 2.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              color: NuvoColors.white,
                              size: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    const _FieldLabel('FULL NAME'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(hintText: 'Your name'),
                    ),
                    const SizedBox(height: 20),

                    const _FieldLabel('USERNAME'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        prefixText: '@ ',
                        hintText: 'handle',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: NuvoColors.success,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Username set',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: NuvoColors.success,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Private stats toggle
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: NuvoColors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: NuvoColors.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Private race stats',
                                  style: AppTextStyles.titleMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Only your crew can see your race stats.',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: NuvoColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Switch.adaptive(
                            value: _privateStats,
                            activeThumbColor: NuvoColors.blue,
                            onChanged: (value) =>
                                setState(() => _privateStats = value),
                          ),
                        ],
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

                    const SizedBox(height: 32),

                    NuvoPrimaryButton(
                      label: 'Continue',
                      icon: Icons.arrow_forward_rounded,
                      expand: true,
                      loading: _loading,
                      onPressed: _loading ? null : _continue,
                    ),
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
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.brandLabel.copyWith(color: NuvoColors.muted),
    );
  }
}
