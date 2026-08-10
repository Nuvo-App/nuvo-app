import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../auth/presentation/auth_controller.dart';

const _kPrivacyUrl = 'https://getnuvo.net/privacy';
const _kTermsUrl = 'https://getnuvo.net/terms';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  bool _privateStats = true;
  bool _termsAccepted = false;
  bool _loading = false;
  String? _error;

  Future<void> _openLegalUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

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
    if (!_termsAccepted) {
      setState(
        () => _error = 'Please accept the Terms of Service to continue.',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final controller = ref.read(authControllerProvider.notifier);
      await controller.acceptTerms();
      await controller.saveProfile(
        fullName: _nameController.text.trim(),
        username: _usernameController.text.trim().toLowerCase(),
        privateProfile: _privateStats,
      );
      if (mounted) context.go('/onboarding/member-pass');
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is Exception
              ? e.toString()
              : 'Could not save profile. Please try again.';
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Scrollable content ───────────────────────────────────────────
            Expanded(
              child:
                  SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                            const SizedBox(height: 24),

                            Text(
                              'Build your profile',
                              style: AppTextStyles.headlineLarge.copyWith(
                                fontSize: 32,
                                letterSpacing: -0.9,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'This is how your crew will see you in races.',
                              style: AppTextStyles.bodyLarge.copyWith(
                                color: NuvoColors.muted,
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Avatar
                            Center(
                              child: Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  Container(
                                    width: 80,
                                    height: 80,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: NuvoColors.navy,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      _initials,
                                      style: AppTextStyles.headlineMedium
                                          .copyWith(color: NuvoColors.white),
                                    ),
                                  ),
                                  Container(
                                    width: 28,
                                    height: 28,
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
                                      size: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            NuvoTextInput(
                              controller: _nameController,
                              label: 'Full name',
                              hint: 'Your name',
                              textCapitalization: TextCapitalization.words,
                            ),
                            const SizedBox(height: 16),

                            NuvoTextInput(
                              controller: _usernameController,
                              label: 'Username',
                              hint: 'handle',
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
                            const SizedBox(height: 20),

                            // Private stats toggle
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: NuvoColors.panel.withValues(alpha: 0.58),
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Private race stats',
                                          style: AppTextStyles.titleMedium,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Only your crew can see your race stats.',
                                          style: AppTextStyles.bodySmall
                                              .copyWith(
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

                            const SizedBox(height: 20),

                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Checkbox.adaptive(
                                  value: _termsAccepted,
                                  activeColor: NuvoColors.blue,
                                  onChanged: (value) => setState(
                                    () => _termsAccepted = value ?? false,
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      top: 8,
                                      right: 8,
                                    ),
                                    child: RichText(
                                      text: TextSpan(
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: NuvoColors.muted,
                                        ),
                                        children: [
                                          const TextSpan(
                                            text: 'I agree to the ',
                                          ),
                                          TextSpan(
                                            text: 'Terms of Service',
                                            style: AppTextStyles.bodySmall
                                                .copyWith(
                                                  color: NuvoColors.blue,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                            recognizer: TapGestureRecognizer()
                                              ..onTap = () =>
                                                  _openLegalUrl(_kTermsUrl),
                                          ),
                                          const TextSpan(text: ' and '),
                                          TextSpan(
                                            text: 'Privacy Policy',
                                            style: AppTextStyles.bodySmall
                                                .copyWith(
                                                  color: NuvoColors.blue,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                            recognizer: TapGestureRecognizer()
                                              ..onTap = () =>
                                                  _openLegalUrl(_kPrivacyUrl),
                                          ),
                                          const TextSpan(text: '.'),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
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

            // ── Pinned CTA ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: NuvoPrimaryButton(
                label: 'Continue',
                icon: Icons.arrow_forward_rounded,
                expand: true,
                loading: _loading,
                onPressed: _loading ? null : _continue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
