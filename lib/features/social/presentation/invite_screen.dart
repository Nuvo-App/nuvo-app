import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nuvo/core/v13/v13.dart';
import '../../../core/analytics/analytics.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../crew/application/crew_controller.dart';
import '../../notifications/application/notification_controller.dart';
import '../../notifications/application/push_service.dart';
import '../../races/presentation/race_controller.dart';
import '../application/deep_link_controller.dart';
import '../data/invite_models.dart';
import '../domain/nuvo_destination.dart';
import '../social_providers.dart';

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
    String? error;
    try {
      final result = await ref
          .read(inviteRepositoryProvider)
          .accept(widget.token);
      if (!result.ok) {
        error = _messageForStatus(result.status);
      } else {
        // Navigates away; the screen is gone once this completes.
        await _afterAccept(result);
      }
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      // Non-JSON bodies (429 / HTML error pages) surface as FormatException
      // or TypeError — never leave the button spinning.
      error = "Couldn't accept this invite. Try again.";
    } finally {
      if (mounted) {
        setState(() {
          _accepting = false;
          if (error != null) _acceptError = error;
        });
      }
    }
  }

  Future<void> _afterAccept(InviteAcceptResult result) async {
    final dest = result.destination;
    // Freshness: fold the new membership into the canonical caches before we
    // navigate, so Arena / Compete / race detail are already current.
    final analytics = ref.read(analyticsProvider);
    if (result.kind == 'race_join') {
      if (dest is RaceDestination) {
        try {
          await ref
              .read(raceControllerProvider.notifier)
              .refreshJoinedRace(dest.raceId);
        } catch (_) {
          // Navigation still proceeds; mark the list stale so the next
          // revalidate refetches instead of trusting a pre-join cache.
          if (mounted) ref.read(raceControllerProvider.notifier).markStale();
        }
      }
      analytics.raceJoined(via: 'invite');
    } else if (result.kind == 'crew_connect') {
      // The connection is canonical in CrewController — mark both it and the
      // inbox stale so the new member/request shows without a restart.
      ref.read(crewControllerProvider.notifier).markStale();
      ref.read(notificationControllerProvider.notifier).markStale();
      // 'pending' means a request was sent, not a friend link — the accept
      // fires friend_added through CrewController when it lands.
      if (result.connectionStatus != 'pending') analytics.friendAdded();
    } else if (result.kind == 'squad_join') {
      analytics.crewJoined();
    }
    // First race join / first crew connect is the contextual moment to ask
    // for push permission (no-op until Firebase is configured).
    unawaited(ref.read(pushServiceProvider).requestPermissionInContext());
    if (!mounted) return;
    if (result.connectionStatus == 'pending') {
      showV13Toast(context, 'Request sent — you’ll connect once they accept.');
    }
    context.go(dest?.location ?? '/arena');
  }

  String _messageForStatus(InviteStatus s) => switch (s) {
    InviteStatus.expired => 'This invite has expired.',
    InviteStatus.revoked => 'This invite was turned off.',
    InviteStatus.used => 'This invite has already been used.',
    InviteStatus.notFound => 'This invite is no longer available.',
    InviteStatus.blocked => 'This invite is no longer available.',
    InviteStatus.closed => 'This race has ended.',
    _ => 'This invite could not be used.',
  };

  @override
  Widget build(BuildContext context) {
    // Watch, not read: the session restore can land after first paint, and
    // the CTA label ("Join race" vs "Sign in to join") must follow it.
    final authed = ref.watch(
      authControllerProvider.select(
        (s) => s.status == AuthStatus.authenticated,
      ),
    );
    return Scaffold(
      backgroundColor: V13.bg,
      body: SafeArea(
        child: Column(
          children: [
            V13BackBar(title: 'Invite', onBack: _exit),
            Expanded(child: _body(authed)),
          ],
        ),
      ),
    );
  }

  void _exit() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(_authed ? '/arena' : '/welcome');
    }
  }

  Widget _body(bool authed) {
    if (_loadError != null) {
      return V13AsyncView<Never>.state(
        status: V13AsyncStatus.error,
        errorTitle: "Couldn't load this invite.",
        errorBody: 'Check your connection and try again.',
        onRetry: _load,
        builder: (_) => const SizedBox.shrink(),
      );
    }
    final preview = _preview;
    if (preview == null) {
      return const V13Skeleton.screen();
    }
    if (!preview.isAvailable) {
      return V13AsyncView<Never>.state(
        status: V13AsyncStatus.empty,
        emptyIcon: Icons.link_off_rounded,
        emptyTitle: 'Invite unavailable',
        emptyBody: _messageForStatus(preview.status),
        emptyAction: V13Button.secondary(label: 'Done', onPressed: _exit),
        builder: (_) => const SizedBox.shrink(),
      );
    }
    return switch (preview.kind) {
      'race_join' => _RacePreview(
        card: preview.race,
        accepting: _accepting,
        error: _acceptError,
        authed: authed,
        onAccept: _accept,
      ),
      'crew_connect' => _PersonPreview(
        card: preview.person,
        accepting: _accepting,
        error: _acceptError,
        authed: authed,
        onAccept: _accept,
      ),
      _ => V13AsyncView<Never>.state(
        status: V13AsyncStatus.empty,
        emptyIcon: Icons.help_outline_rounded,
        emptyTitle: 'Unsupported invite',
        emptyBody: 'Update Nuvo to open this link.',
        emptyAction: V13Button.secondary(label: 'Done', onPressed: _exit),
        builder: (_) => const SizedBox.shrink(),
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
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          V13.pagePad,
          V13.gapMd,
          V13.pagePad,
          V13.pagePad,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.maxHeight - V13.gapMd - V13.pagePad,
          ),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                V13Card(
                  color: V13.raceColor(c.id),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("You're invited to a race", style: V13.label),
                      const SizedBox(height: V13.gapSm),
                      Text(c.title, style: V13.title),
                      const SizedBox(height: V13.gapMd),
                      Wrap(
                        spacing: V13.gapSm,
                        runSpacing: V13.gapSm,
                        children: [
                          if (target != null)
                            V13Pill(
                              icon: Icons.flag_rounded,
                              label: 'Goal $target',
                            ),
                          if (c.activityId != null)
                            V13Pill(
                              icon: Icons.bolt_rounded,
                              label: _pretty(c.activityId!),
                            ),
                          V13Pill(
                            icon: Icons.group_rounded,
                            label: '${c.participantCount} racing',
                          ),
                        ],
                      ),
                      if (c.creatorName != null) ...[
                        const SizedBox(height: V13.gapLg),
                        Row(
                          children: [
                            V13Face(
                              photoUrl: c.creatorPhotoUrl,
                              size: 32,
                              name: c.creatorName,
                            ),
                            const SizedBox(width: V13.gapMd),
                            Expanded(
                              child: Text(
                                'Created by ${c.creatorName}',
                                style: V13.bodyStrong,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const Spacer(),
                if (error != null) ...[
                  Text(
                    error!,
                    textAlign: TextAlign.center,
                    style: V13.caption.copyWith(color: V13.danger),
                  ),
                  const SizedBox(height: V13.gapMd),
                ],
                V13Button.primary(
                  label: c.alreadyJoined
                      ? 'Go to race'
                      : authed
                      ? 'Join race'
                      : 'Sign in to join',
                  loading: accepting,
                  fullWidth: true,
                  onPressed: accepting ? null : onAccept,
                ),
              ],
            ),
          ),
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
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          V13.pagePad,
          V13.gapMd,
          V13.pagePad,
          V13.pagePad,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.maxHeight - V13.gapMd - V13.pagePad,
          ),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Column(
                  children: [
                    Center(
                      child: V13Face(
                        photoUrl: c.profilePhotoUrl,
                        size: 88,
                        name: c.displayName,
                      ),
                    ),
                    const SizedBox(height: V13.gapLg),
                    Text(
                      c.displayName,
                      textAlign: TextAlign.center,
                      style: V13.title,
                    ),
                    if (c.username != null) ...[
                      const SizedBox(height: V13.gapXs),
                      Text(
                        '@${c.username}',
                        textAlign: TextAlign.center,
                        style: V13.body.copyWith(color: V13.muted),
                      ),
                    ],
                    const SizedBox(height: V13.gapMd),
                    Text(
                      'Add them as a friend to race together.',
                      textAlign: TextAlign.center,
                      style: V13.body.copyWith(color: V13.muted),
                    ),
                  ],
                ),
                const Spacer(),
                if (error != null) ...[
                  Text(
                    error!,
                    textAlign: TextAlign.center,
                    style: V13.caption.copyWith(color: V13.danger),
                  ),
                  const SizedBox(height: V13.gapMd),
                ],
                V13Button.primary(
                  label: !authed ? 'Sign in to connect' : 'Add friend',
                  loading: accepting,
                  fullWidth: true,
                  onPressed: accepting ? null : onAccept,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
