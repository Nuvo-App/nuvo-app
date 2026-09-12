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

/// One reusable "share this race" surface — QR, copy link, native share, and
/// the typable code. Backed by the unified invite model: it mints (or reuses)
/// a `race_join` token and renders its universal URL.
///
/// Open with [showRaceShareSheet].
Future<void> showRaceShareSheet(
  BuildContext context, {
  required String raceId,
  required String raceTitle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: NuvoColors.page,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _RaceShareSheet(raceId: raceId, raceTitle: raceTitle),
  );
}

class _RaceShareSheet extends ConsumerStatefulWidget {
  const _RaceShareSheet({required this.raceId, required this.raceTitle});

  final String raceId;
  final String raceTitle;

  @override
  ConsumerState<_RaceShareSheet> createState() => _RaceShareSheetState();
}

class _RaceShareSheetState extends ConsumerState<_RaceShareSheet> {
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
      final invite =
          await ref.read(inviteRepositoryProvider).mintRaceInvite(widget.raceId);
      if (mounted) setState(() => _invite = invite);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  String get _shareMessage {
    final url = _invite?.url ?? '';
    return 'Join my Nuvo race "${widget.raceTitle}" — $url';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          14,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
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
            Text('Share this race', style: AppTextStyles.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Anyone with the link can preview and join.',
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
        Text("Couldn't create a share link.",
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
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: NuvoColors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: NuvoColors.navy, width: 2),
            ),
            child: QrImageView(
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
          ),
        ),
        const SizedBox(height: 16),
        if (invite.code != null) ...[
          Center(
            child: Text(
              'Or enter code  ${invite.code}',
              style: AppTextStyles.bodyMedium.copyWith(
                color: NuvoColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        NuvoPrimaryButton(
          label: 'Share link',
          icon: Icons.ios_share_rounded,
          expand: true,
          onPressed: () => Share.share(_shareMessage),
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
