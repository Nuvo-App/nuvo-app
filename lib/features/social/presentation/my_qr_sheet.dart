import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_loading_indicator.dart';
import '../data/invite_models.dart';
import '../social_providers.dart';

/// "My QR" — a personal, reusable `crew_connect` invite for the current user.
/// Scanning it lands on `/invite/:token` → profile preview → Connect, exactly
/// the same NuvoDestination flow as any other entry source. Screenshot-friendly;
/// encodes only the opaque token, no profile data.
Future<void> showMyQrSheet(
  BuildContext context, {
  required String displayName,
  String? memberId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: NuvoColors.page,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _MyQrSheet(displayName: displayName, memberId: memberId),
  );
}

class _MyQrSheet extends ConsumerStatefulWidget {
  const _MyQrSheet({required this.displayName, this.memberId});

  final String displayName;
  final String? memberId;

  @override
  ConsumerState<_MyQrSheet> createState() => _MyQrSheetState();
}

class _MyQrSheetState extends ConsumerState<_MyQrSheet> {
  MintedInvite? _invite;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _mint();
  }

  Future<void> _mint() async {
    setState(() => _error = false);
    try {
      final invite = await ref.read(inviteRepositoryProvider).mintMyCrewInvite();
      if (mounted) setState(() => _invite = invite);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: NuvoColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text('My code', style: AppTextStyles.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Let someone scan this to add you to their crew.',
              style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.textMuted),
            ),
            const SizedBox(height: 20),
            _content(),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    if (_error) {
      return Column(children: [
        Text("Couldn't create your code.",
            style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.danger)),
        const SizedBox(height: 12),
        NuvoSecondaryButton(label: 'Try again', expand: true, onPressed: _mint),
      ]);
    }
    final invite = _invite;
    if (invite == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: NuvoLoadingIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: NuvoColors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: NuvoColors.navy, width: 2),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              QrImageView(
                data: invite.url,
                version: QrVersions.auto,
                size: 208,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: NuvoColors.navy,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: NuvoColors.navy,
                ),
              ),
              const SizedBox(height: 10),
              Text(widget.displayName,
                  style: AppTextStyles.titleMedium.copyWith(color: NuvoColors.navy)),
              if (widget.memberId != null)
                Text(widget.memberId!,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: NuvoColors.textMuted)),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        NuvoPrimaryButton(
          label: 'Share link',
          icon: Icons.ios_share_rounded,
          expand: true,
          onPressed: () =>
              Share.share('Connect with me on Nuvo — ${invite.url}'),
        ),
        const SizedBox(height: 10),
        NuvoSecondaryButton(
          label: 'Copy link',
          icon: Icons.link_rounded,
          expand: true,
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: invite.url));
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Link copied.')),
              );
            }
          },
        ),
      ],
    );
  }
}
