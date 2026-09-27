import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/demo/presentation_demo.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_back_header.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_loading_indicator.dart';
import '../../../core/widgets/nuvo_motion.dart';
import '../../../core/widgets/nuvo_page.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/invite_models.dart';
import '../social_providers.dart';

/// `/my-nuvo` — the member's social identity, built to be physically shown to
/// another person: who I am, my code, my QR, and the three ways to connect
/// (show, share, scan). Not a settings screen — an object you hand over.
///
/// Hierarchy: identity hero (ice) → member code chip → QR on a clean white
/// card → one blue share action + a compact secondary grid.
class MyNuvoScreen extends ConsumerStatefulWidget {
  const MyNuvoScreen({super.key});

  @override
  ConsumerState<MyNuvoScreen> createState() => _MyNuvoScreenState();
}

class _MyNuvoScreenState extends ConsumerState<MyNuvoScreen> {
  MintedInvite? _invite;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _mint();
  }

  Future<void> _mint() async {
    setState(() => _error = false);
    // Presentation/offline demo sessions can't mint a real invite — the
    // sentinel token would 401. Render the same deterministic fixture the
    // QR sheet uses.
    if (isPresentationDemoUser(ref.read(authControllerProvider).user)) {
      if (mounted) {
        setState(
          () => _invite = const MintedInvite(
            token: 'demo-crew-invite',
            url: 'https://getnuvo.net/invite/demo-crew-invite',
            code: 'NUVO-DEMO',
            kind: 'crew_connect',
          ),
        );
      }
      return;
    }
    try {
      final invite = await ref.read(inviteRepositoryProvider).mintMyCrewInvite();
      if (mounted) setState(() => _invite = invite);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authControllerProvider).user;
    final user = authUser == null ? null : presentedUser(authUser);
    final name = user?.fullName ?? user?.email ?? 'Nuvo member';
    final username = user?.username;
    final t = context.themeColors;
    final code = _invite?.code ??
        (username != null && username.isNotEmpty ? '@$username' : null);
    return NuvoPage(
      topBar: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: NuvoBackHeader(
            title: 'My Nuvo',
            onBack: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/pass');
              }
            },
          ),
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              _identityHero(name, username, code, user?.profilePhotoUrl, t),
              const SizedBox(height: 16),
              _qrCard(t),
              const SizedBox(height: 16),
              NuvoPrimaryButton(
                label: 'Share my Nuvo',
                icon: Icons.ios_share_rounded,
                expand: true,
                height: 52,
                onPressed: _invite == null
                    ? null
                    : () => Share.share(
                        'Connect with me on Nuvo — ${_invite!.url}'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: NuvoCopyButton(
                      text: _invite?.url ?? '',
                      height: 46,
                      enabled: _invite != null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NuvoSecondaryButton(
                      label: 'Scan a code',
                      icon: Icons.qr_code_scanner_rounded,
                      height: 46,
                      onPressed: () => context.push('/scan'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Colored identity block — the person's name carries the screen. The
  /// avatar overlaps the hero's top edge; the member code sits inside it as
  /// a real, copyable chip instead of a decorative label.
  Widget _identityHero(
    String name,
    String? username,
    String? code,
    String? photoUrl,
    NuvoThemeColors t,
  ) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 32),
          padding: const EdgeInsets.fromLTRB(18, 44, 18, 14),
          decoration: BoxDecoration(
            color: t.panelLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: t.border, width: 1.5),
          ),
          child: Column(
            children: [
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.headlineMedium.copyWith(color: t.ink),
              ),
              if (username != null && username.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  '@$username',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: t.inkSubtle),
                ),
              ],
              if (code != null) ...[
                const SizedBox(height: 10),
                _CodeChip(code: code),
              ],
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: t.border, width: 1.5),
            color: t.surface,
          ),
          child: NuvoAvatar(
            photoUrl: photoUrl,
            initials: _initials(name),
            size: 64,
            borderWidth: 0,
          ),
        ),
      ],
    );
  }

  Widget _qrCard(NuvoThemeColors t) {
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
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          // The QR face stays pure white in both themes — scanners need the
          // quiet zone, so this card is one place theme colors do NOT apply.
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: NuvoColors.navy, width: 2.5),
          boxShadow: const [
            BoxShadow(
              color: NuvoColors.neutralShadow,
              blurRadius: 0,
              offset: Offset(5, 5),
            ),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          QrImageView(
            data: invite.url,
            version: QrVersions.auto,
            size: 168,
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
          Text('Scan to add me',
              style: AppTextStyles.bodySmall
                  .copyWith(color: NuvoColors.textMuted)),
        ]),
      ),
    );
  }

  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return 'N';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

/// The member's Nuvo code as a tappable identity chip — shows the actual
/// code (not a label), taps copy it.
class _CodeChip extends StatefulWidget {
  const _CodeChip({required this.code});

  final String code;

  @override
  State<_CodeChip> createState() => _CodeChipState();
}

class _CodeChipState extends State<_CodeChip> {
  bool _copied = false;
  Timer? _reset;

  Future<void> _copy() async {
    if (_copied) return;
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    NuvoHaptics.confirm();
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.themeColors;
    return Semantics(
      button: true,
      label: 'Copy member code ${widget.code}',
      child: NuvoPressable(
        onTap: _copy,
        scale: 0.94,
        haptic: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _copied ? NuvoColors.success : t.border,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.badge_rounded, size: 15, color: t.inkMuted),
              const SizedBox(width: 7),
              Text(
                widget.code,
                style: AppTextStyles.labelMedium.copyWith(
                  color: t.ink,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 7),
              AnimatedSwitcher(
                duration: NuvoMotion.select,
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(
                  _copied ? Icons.check_rounded : Icons.copy_rounded,
                  key: ValueKey(_copied),
                  size: 13,
                  color: _copied ? NuvoColors.successOn : t.inkSubtle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
