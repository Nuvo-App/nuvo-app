import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_empty_state.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_page.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/presentation/race_controller.dart';
import '../application/deep_link_controller.dart';
import '../data/invite_models.dart';
import '../domain/nuvo_destination.dart';
import '../social_providers.dart';

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return 'N';
  if (parts.length == 1) return parts.first.characters.take(1).toString().toUpperCase();
  return (parts[0].characters.first + parts[1].characters.first).toUpperCase();
}

/// `/invite/:token` — the one screen every invite link, QR scan and web
/// fallback lands on. Previews before it does anything; accepting is an
/// explicit tap. Works logged-out (previews, then routes through auth).
class InviteScreen extends ConsumerStatefulWidget {
  const InviteScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  InvitePreview? _preview;
  Object? _loadError;
  bool _accepting = false;
  String? _acceptError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _preview = null;
      _loadError = null;
    });
    try {
      final p = await ref.read(inviteRepositoryProvider).preview(widget.token);
      if (mounted) setState(() => _preview = p);
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  bool get _authed =>
      ref.read(authControllerProvider).status == AuthStatus.authenticated;

  Future<void> _accept() async {
    final preview = _preview;
    if (preview == null) return;

    // Not signed in → stash this exact destination and route through sign-in.
    if (!_authed) {
      await ref
          .read(pendingDestinationStoreProvider)
          .put(InviteDestination(widget.token));
      if (mounted) context.go('/welcome');
      return;
    }

    setState(() {
      _accepting = true;
      _acceptError = null;
    });
    try {
      final result = await ref.read(inviteRepositoryProvider).accept(widget.token);
      if (!result.ok) {
        setState(() {
          _acceptError = _messageForStatus(result.status);
          _accepting = false;
        });
        return;
      }
      await _afterAccept(result);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _acceptError = e.message;
          _accepting = false;
        });
      }
    }
  }

  Future<void> _afterAccept(InviteAcceptResult result) async {
    final dest = result.destination;
    // Freshness: fold the new membership into the canonical caches before we
    // navigate, so Arena / Compete / race detail are already current.
    if (result.kind == 'race_join' && dest is RaceDestination) {
      try {
        await ref
            .read(raceControllerProvider.notifier)
            .refreshJoinedRace(dest.raceId);
      } catch (_) {
        /* navigation still proceeds; the detail screen will refetch */
      }
    }
    if (!mounted) return;
    if (result.connectionStatus == 'pending') {
      _showSnack('Request sent — you’ll connect once they accept.');
    }
    context.go(dest?.location ?? '/arena');
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  String _messageForStatus(InviteStatus s) => switch (s) {
        InviteStatus.expired => 'This invite has expired.',
        InviteStatus.revoked => 'This invite was turned off.',
        InviteStatus.used => 'This invite has already been used.',
        InviteStatus.notFound => 'This invite is no longer available.',
        InviteStatus.blocked => 'This invite is no longer available.',
        _ => 'This invite could not be used.',
      };

  @override
  Widget build(BuildContext context) {
    return NuvoPage(
      topBar: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(children: [NuvoBackButton(onPressed: _exit)]),
        ),
      ),
      child: _body(),
    );
  }

  void _exit() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(_authed ? '/arena' : '/welcome');
    }
  }

  Widget _body() {
    if (_loadError != null) {
      return Center(
        child: NuvoErrorState(
          message: "Couldn't load this invite.",
          onRetry: _load,
        ),
      );
    }
    final preview = _preview;
    if (preview == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!preview.isAvailable) {
      return Center(
        child: NuvoEmptyState(
          icon: Icons.link_off_rounded,
          title: 'Invite unavailable',
          body: _messageForStatus(preview.status),
          ctaLabel: 'Done',
          onCta: _exit,
          align: TextAlign.center,
        ),
      );
    }
    return switch (preview.kind) {
      'race_join' => _RacePreview(
          card: preview.race,
          accepting: _accepting,
          error: _acceptError,
          authed: _authed,
          onAccept: _accept,
        ),
      'crew_connect' => _PersonPreview(
          card: preview.person,
          accepting: _accepting,
          error: _acceptError,
          authed: _authed,
          onAccept: _accept,
        ),
      _ => Center(
          child: NuvoEmptyState(
            icon: Icons.help_outline_rounded,
            title: 'Unsupported invite',
            body: 'Update Nuvo to open this link.',
            ctaLabel: 'Done',
            onCta: _exit,
            align: TextAlign.center,
          ),
        ),
    };
  }
}

class _RacePreview extends StatelessWidget {
  const _RacePreview({
    required this.card,
    required this.accepting,
    required this.error,
    required this.authed,
    required this.onAccept,
  });

  final RaceInviteCard? card;
  final bool accepting;
  final String? error;
  final bool authed;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final c = card;
    if (c == null) {
      return const Center(child: Text('Race not found'));
    }
    final target = (c.targetValue != null)
        ? '${c.targetValue}${c.targetUnit != null ? ' ${c.targetUnit}' : ''}'
        : null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Text('You’re invited to a race',
                style: AppTextStyles.labelSmall.copyWith(color: NuvoColors.blue)),
            const SizedBox(height: 8),
            Text(c.title, style: AppTextStyles.displaySmall),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (target != null) _Pill(icon: Icons.flag_rounded, text: 'Goal $target'),
              if (c.activityId != null)
                _Pill(icon: Icons.bolt_rounded, text: _pretty(c.activityId!)),
              _Pill(
                icon: Icons.group_rounded,
                text: '${c.participantCount} racing',
              ),
            ]),
            const SizedBox(height: 20),
            if (c.creatorName != null)
              Row(children: [
                NuvoAvatar(
                  photoUrl: c.creatorPhotoUrl,
                  initials: _initials(c.creatorName!),
                  size: 32,
                ),
                const SizedBox(width: 10),
                Text('Created by ${c.creatorName}',
                    style: AppTextStyles.bodyMedium),
              ]),
            const Spacer(),
            if (error != null) ...[
              Text(error!, style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.danger)),
              const SizedBox(height: 12),
            ],
            NuvoPrimaryButton(
              label: c.alreadyJoined
                  ? 'Go to race'
                  : authed
                      ? 'Join race'
                      : 'Sign in to join',
              loading: accepting,
              expand: true,
              onPressed: accepting ? null : onAccept,
            ),
          ],
        ),
      ),
    );
  }

  static String _pretty(String id) =>
      id.replaceAll('_', ' ').replaceAll('-', ' ').trim();
}

class _PersonPreview extends StatelessWidget {
  const _PersonPreview({
    required this.card,
    required this.accepting,
    required this.error,
    required this.authed,
    required this.onAccept,
  });

  final PersonInviteCard? card;
  final bool accepting;
  final String? error;
  final bool authed;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final c = card;
    if (c == null) return const Center(child: Text('Profile not found'));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            Center(
              child: NuvoAvatar(
                photoUrl: c.profilePhotoUrl,
                initials: _initials(c.displayName),
                size: 88,
              ),
            ),
            const SizedBox(height: 16),
            Text(c.displayName,
                textAlign: TextAlign.center, style: AppTextStyles.displaySmall),
            if (c.username != null) ...[
              const SizedBox(height: 4),
              Text('@${c.username}',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: NuvoColors.textMuted)),
            ],
            const SizedBox(height: 10),
            Text(
              c.isPrivate
                  ? 'Send a connect request to add them to your crew.'
                  : 'Add them to your crew to race together.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium,
            ),
            const Spacer(),
            if (error != null) ...[
              Text(error!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.danger)),
              const SizedBox(height: 12),
            ],
            NuvoPrimaryButton(
              label: !authed
                  ? 'Sign in to connect'
                  : c.isPrivate
                      ? 'Send request'
                      : 'Add to crew',
              loading: accepting,
              expand: true,
              onPressed: accepting ? null : onAccept,
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: NuvoColors.panel,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: NuvoColors.textMuted),
        const SizedBox(width: 6),
        Text(text, style: AppTextStyles.labelSmall),
      ]),
    );
  }
}
