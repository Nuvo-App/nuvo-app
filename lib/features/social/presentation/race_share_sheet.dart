import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/v13/v13.dart';
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
  return showV13Sheet<void>(
    context,
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
      final invite = await ref
          .read(inviteRepositoryProvider)
          .mintRaceInvite(widget.raceId);
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        V13.pagePad,
        V13.gapMd,
        V13.pagePad,
        V13.gapXl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Share this race', style: V13.sectionHead),
          const SizedBox(height: V13.gapXs),
          Text(
            'Anyone with the link can preview and join.',
            style: V13.caption,
          ),
          const SizedBox(height: V13.gapLg),
          _content(),
        ],
      ),
    );
  }

  Widget _content() {
    if (_error) {
      return Column(
        children: [
          Text(
            "Couldn't create a share link.",
            style: V13.body.copyWith(color: V13.danger),
          ),
          const SizedBox(height: V13.gapMd),
          V13Button.secondary(
            label: 'Try again',
            fullWidth: true,
            onPressed: _mint,
          ),
        ],
      );
    }
    final invite = _invite;
    if (invite == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: V13.gapSection),
        child: Center(
          child: SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 3, color: V13.blue),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: V13Card(
            padding: const EdgeInsets.all(V13.gapLg),
            child: QrImageView(
              data: invite.url,
              version: QrVersions.auto,
              size: 200,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: V13.navy,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: V13.navy,
              ),
            ),
          ),
        ),
        const SizedBox(height: V13.gapLg),
        if (invite.code != null) ...[
          Center(
            child: Text('Or enter code  ${invite.code}', style: V13.bodyStrong),
          ),
          const SizedBox(height: V13.gapLg),
        ],
        V13Button.primary(
          label: 'Share link',
          icon: Icons.ios_share_rounded,
          fullWidth: true,
          onPressed: () => Share.share(_shareMessage),
        ),
        const SizedBox(height: V13.gapMd),
        V13Button.secondary(
          label: 'Copy link',
          icon: Icons.link_rounded,
          fullWidth: true,
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: invite.url));
            if (mounted) {
              showV13Toast(context, 'Link copied.');
            }
          },
        ),
      ],
    );
  }
}
