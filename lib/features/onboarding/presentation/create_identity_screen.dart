import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../auth/presentation/auth_controller.dart';

class CreateIdentityScreen extends ConsumerStatefulWidget {
  const CreateIdentityScreen({super.key});

  @override
  ConsumerState<CreateIdentityScreen> createState() =>
      _CreateIdentityScreenState();
}

class _CreateIdentityScreenState extends ConsumerState<CreateIdentityScreen> {
  late final TextEditingController _nameController;
  final _usernameController = TextEditingController();
  final _nameFocus = FocusNode();
  final _usernameFocus = FocusNode();

  bool _loading = false;
  bool? _usernameAvailable;
  bool _usernameChecking = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authControllerProvider).user;
    _nameController = TextEditingController(text: user?.fullName ?? '');
    _nameController.addListener(() => setState(() {}));
    _usernameController.addListener(_onUsernameChanged);
  }

  void _onUsernameChanged() {
    setState(() {
      _usernameAvailable = null;
      _error = null;
    });
    _debounce?.cancel();
    final raw = _usernameController.text.trim().toLowerCase();
    if (raw.length < 3) return;
    setState(() => _usernameChecking = true);
    _debounce = Timer(const Duration(milliseconds: 650), () async {
      final available = await ref
          .read(authControllerProvider.notifier)
          .checkUsername(raw);
      if (mounted) {
        setState(() {
          _usernameAvailable = available;
          _usernameChecking = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameController.dispose();
    _usernameController.dispose();
    _nameFocus.dispose();
    _usernameFocus.dispose();
    super.dispose();
  }

  String get _initials {
    final raw = _nameController.text.trim();
    if (raw.isEmpty) return '?';
    final parts = raw.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  bool get _canContinue =>
      _nameController.text.trim().isNotEmpty &&
      _usernameController.text.trim().length >= 3 &&
      _usernameAvailable == true &&
      !_loading;

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final username = _usernameController.text.trim().toLowerCase();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .saveProfile(fullName: name, username: username);
      if (mounted) context.go('/onboarding/profile');
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
    final username = _usernameController.text.trim();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child:
            ListView(
                  padding: const EdgeInsets.fromLTRB(22, 34, 22, 44),
                  children: [
                    // Step indicator
                    Row(
                      children: [
                        for (var i = 0; i < 5; i++) ...[
                          Expanded(
                            child: Container(
                              height: 3,
                              decoration: BoxDecoration(
                                color: i == 0
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
                      'Create your\nNuvo identity',
                      style: AppTextStyles.headlineLarge.copyWith(
                        fontSize: 32,
                        letterSpacing: -0.9,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Choose how your crew will find and race you.',
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: NuvoColors.muted,
                      ),
                    ),
                    const SizedBox(height: 32),

                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                      decoration: BoxDecoration(
                        color: NuvoColors.surface,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: NuvoColors.border),
                        boxShadow: AppShadows.surfaceShadow,
                      ),
                      child: Column(
                        children: [
                          // The avatar is the focal point of the identity card.
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            width: 92,
                            height: 92,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _nameController.text.trim().isEmpty
                                  ? NuvoColors.panel
                                  : NuvoColors.blue,
                              border: Border.all(
                                color: NuvoColors.white,
                                width: 4,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: NuvoColors.blue.withValues(
                                    alpha: _nameController.text.trim().isEmpty
                                        ? 0.05
                                        : 0.10,
                                  ),
                                  blurRadius: 18,
                                  spreadRadius: -7,
                                  offset: const Offset(0, 8),
                                ),
                                BoxShadow(
                                  color: NuvoColors.navy.withValues(
                                    alpha: 0.10,
                                  ),
                                  blurRadius: 8,
                                  spreadRadius: -4,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _initials,
                              style: AppTextStyles.headlineMedium.copyWith(
                                color: NuvoColors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),

                          NuvoTextInput(
                            controller: _nameController,
                            label: 'FULL NAME',
                            hint: 'Your name',
                            textCapitalization: TextCapitalization.words,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 20),

                          NuvoTextInput(
                            controller: _usernameController,
                            label: 'USERNAME',
                            hint: 'pick a handle',
                            prefixIcon: Padding(
                              padding: const EdgeInsets.only(left: 14),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                widthFactor: 1,
                                child: Text(
                                  '@',
                                  style: AppTextStyles.bodyMedium,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          if (_usernameChecking)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Checking availability…',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: NuvoColors.muted,
                                ),
                              ),
                            )
                          else if (username.length >= 3)
                            Row(
                              children: [
                                Icon(
                                  _usernameAvailable == true
                                      ? Icons.check_circle_rounded
                                      : Icons.cancel_rounded,
                                  color: _usernameAvailable == true
                                      ? NuvoColors.success
                                      : NuvoColors.danger,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _usernameAvailable == true
                                      ? '@$username is available'
                                      : '@$username is taken',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: _usernameAvailable == true
                                        ? NuvoColors.success
                                        : NuvoColors.danger,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),

                          if (_error != null) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _error!,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: NuvoColors.danger,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    NuvoPrimaryButton(
                      label: 'Continue',
                      icon: Icons.arrow_forward_rounded,
                      expand: true,
                      loading: _loading,
                      onPressed: _canContinue ? _submit : null,
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
