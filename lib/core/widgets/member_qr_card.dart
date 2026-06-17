import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'nuvo_card.dart';

/// Member ID + QR code card shown on the Crew screen.
class MemberQrCard extends StatelessWidget {
  const MemberQrCard({
    super.key,
    required this.memberId,
    required this.username,
    required this.profileUrl,
  });

  final String memberId;
  final String username;
  final String profileUrl;

  @override
  Widget build(BuildContext context) {
    return NuvoCard(
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code_rounded,
                  size: 18, color: NuvoColors.blue),
              const SizedBox(width: 8),
              Text('Your Member ID', style: AppTextStyles.titleMedium),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Share your ID so crew members can find and race you.',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 20),

          // QR code
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: NuvoColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: NuvoColors.border),
            ),
            child: QrImageView(
              data: profileUrl,
              version: QrVersions.auto,
              size: 160,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: NuvoColors.navy,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: NuvoColors.navy,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Member ID chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: NuvoColors.sectionBlue,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NuvoColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  memberId,
                  style: AppTextStyles.brandLabel.copyWith(
                    color: NuvoColors.navy,
                    fontSize: 14,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => _copyId(context),
                  child: const Icon(Icons.copy_rounded,
                      size: 16, color: NuvoColors.blue),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Action row
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.copy_rounded,
                  label: 'Copy link',
                  onPressed: () => _copyLink(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
                  icon: Icons.ios_share_rounded,
                  label: 'Share',
                  primary: true,
                  onPressed: () => _share(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _copyId(BuildContext context) {
    Clipboard.setData(ClipboardData(text: memberId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Member ID copied')),
    );
  }

  void _copyLink(BuildContext context) {
    Clipboard.setData(ClipboardData(text: profileUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile link copied')),
    );
  }

  void _share() {
    Share.share(
      'Join me on Nuvo — $profileUrl',
      subject: 'Race me on Nuvo',
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: primary ? NuvoColors.blue : NuvoColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: primary ? NuvoColors.blue : NuvoColors.border,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: primary ? NuvoColors.white : NuvoColors.blue,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.labelMedium.copyWith(
                color: primary ? NuvoColors.white : NuvoColors.blue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
