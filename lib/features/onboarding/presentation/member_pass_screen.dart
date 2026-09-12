import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/member_pass_card.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_loading_indicator.dart';
import '../../../data/models/user_profile.dart';
import '../../auth/data/auth_models.dart';
import '../../auth/presentation/auth_controller.dart';

class OnboardingMemberPassScreen extends ConsumerStatefulWidget {
  const OnboardingMemberPassScreen({super.key});

  @override
  ConsumerState<OnboardingMemberPassScreen> createState() =>
      _OnboardingMemberPassScreenState();
}

class _OnboardingMemberPassScreenState
    extends ConsumerState<OnboardingMemberPassScreen> {
  PassInfo? _passInfo;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchPass();
  }

  Future<void> _fetchPass() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pass = await ref
          .read(authControllerProvider.notifier)
          .getMemberPass();
      if (mounted) {
        setState(() {
          _passInfo = pass;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load your member pass.';
          _loading = false;
        });
      }
    }
  }

  UserProfile _buildProfile(AuthUser? user) {
    return UserProfile(
      name: user?.fullName ?? user?.email ?? '',
      username: user?.username ?? '',
      memberId: _passInfo?.memberId ?? '—',
      passSlug: _passInfo?.passSlug,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final profile = _buildProfile(user);
    final shareUrl = _passInfo?.shareUrl ?? profile.memberId;

    if (_loading) {
      return const Scaffold(body: Center(child: NuvoLoadingIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: NuvoColors.page,
        body: SafeArea(
          child: NuvoErrorState(message: _error!, onRetry: _fetchPass),
        ),
      );
    }

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child:
            ListView(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
                  children: [
                    // Step progress (3 steps: race, profile, pass)
                    Row(
                      children: [
                        for (var i = 0; i < 3; i++) ...[
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
                          if (i < 2) const SizedBox(width: 4),
                        ],
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Your pass into the crew.',
                      style: AppTextStyles.displaySmall,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Keep it close. This is how people find you and race you.',
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: NuvoColors.muted,
                      ),
                    ),
                    const SizedBox(height: 20),
                    MemberPassCard(profile: profile),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: NuvoPrimaryButton(
                            label: 'Share pass',
                            icon: Icons.ios_share_rounded,
                            onPressed: () =>
                                Share.share('Race me on Nuvo: $shareUrl'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: NuvoOutlineButton(
                            label: 'Copy link',
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: shareUrl),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Link copied to clipboard.'),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: NuvoColors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: NuvoColors.navy, width: 2),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.verified_rounded,
                            color: NuvoColors.blue,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Verified Nuvo Member',
                                  style: AppTextStyles.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Access to races, crew invites, and move logging.',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: NuvoColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    NuvoPrimaryButton(
                      label: 'Continue',
                      icon: Icons.arrow_forward_rounded,
                      expand: true,
                      onPressed: () => context.go('/arena'),
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
