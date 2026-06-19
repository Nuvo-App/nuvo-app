import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';

class AddCrewScreen extends StatelessWidget {
  const AddCrewScreen({super.key});

  void _showComingSoonSheet(BuildContext context, String title, String body) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NuvoColors.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: NuvoColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              const Icon(
                Icons.group_add_rounded,
                color: NuvoColors.blue,
                size: 44,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: AppTextStyles.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: NuvoColors.muted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: NuvoColors.page,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPad + 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NuvoPrimaryButton(
                label: 'Continue',
                icon: Icons.arrow_forward_rounded,
                expand: true,
                onPressed: () => context.go('/onboarding/first-race'),
              ),
              const SizedBox(height: 10),
              NuvoOutlineButton(
                label: 'Skip for now',
                expand: true,
                onPressed: () => context.go('/onboarding/first-race'),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child:
            ListView(
                  padding: const EdgeInsets.fromLTRB(20, 30, 20, 24),
                  children: [
                    Row(
                      children: [
                        for (var i = 0; i < 5; i++) ...[
                          Expanded(
                            child: Container(
                              height: 3,
                              decoration: BoxDecoration(
                                color: i <= 3
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
                      'Pull in your crew',
                      style: AppTextStyles.headlineLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Your crew is waiting at the start line.',
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: NuvoColors.muted,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      readOnly: true,
                      onTap: () => _showComingSoonSheet(
                        context,
                        'Crew search is coming soon.',
                        'For now, share your member pass link with friends after onboarding.',
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search by username or member ID',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: IconButton(
                          onPressed: () => _showComingSoonSheet(
                            context,
                            'QR scanning coming soon.',
                            'For now, share your member pass link with friends after onboarding.',
                          ),
                          icon: const Icon(Icons.qr_code_scanner_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _CrewAction(
                            icon: Icons.qr_code_scanner_rounded,
                            label: 'Scan QR',
                            onTap: () => _showComingSoonSheet(
                              context,
                              'QR scanning coming soon.',
                              'For now, share your member pass link with friends after onboarding.',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _CrewAction(
                            icon: Icons.link_rounded,
                            label: 'Invite link',
                            onTap: () => _showComingSoonSheet(
                              context,
                              'Direct race links are coming soon.',
                              'For now, share this invite code with your crew.',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _CrewAction(
                            icon: Icons.contacts_rounded,
                            label: 'Contacts',
                            onTap: () => _showComingSoonSheet(
                              context,
                              'Contact invites are coming soon.',
                              'For now, share your member pass link with friends after onboarding.',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: NuvoColors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: NuvoColors.border),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.group_add_rounded,
                            color: NuvoColors.blue,
                            size: 34,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Your crew is waiting at the start line.',
                            style: AppTextStyles.titleLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Invite friends to turn this into a race.',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: NuvoColors.muted,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
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

class _CrewAction extends StatelessWidget {
  const _CrewAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: NuvoColors.icyBlue,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: NuvoColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: NuvoColors.blue),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppTextStyles.labelSmall.copyWith(color: NuvoColors.navy),
            ),
          ],
        ),
      ),
    );
  }
}
