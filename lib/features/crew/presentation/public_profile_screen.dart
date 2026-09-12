import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_empty_state.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/theme/nuvo_entrance.dart';
import '../../../core/widgets/nuvo_loading_indicator.dart';
import '../../../core/widgets/nuvo_page.dart';
import '../../auth/data/auth_api.dart';
import '../../races/data/race_models.dart' show PublicUser;
import '../application/crew_controller.dart';
import '../data/crew_api.dart';

/// `/u/:id` — a public person card. Where `ProfileDestination` (a scanned
/// profile QR, a crew_request notification tap) lands. Connect / Accept follows
/// the same crew lifecycle + privacy rules as everywhere else.
class PublicProfileScreen extends ConsumerStatefulWidget {
  const PublicProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<PublicProfileScreen> createState() => _State();
}

class _State extends ConsumerState<PublicProfileScreen> {
  PublicProfileCard? _card;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _card = null;
      _error = null;
    });
    try {
      final card = await ref.read(crewRepositoryProvider).getUser(widget.userId);
      if (mounted) setState(() => _card = card);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  PublicUser _asUser(PublicProfileCard c) => PublicUser(
        id: c.id,
        displayName: c.displayName,
        username: c.username,
        memberId: c.memberId,
        initials: c.initials,
        profilePhotoUrl: c.profilePhotoUrl,
      );

  Future<void> _connect() async {
    final card = _card;
    if (card == null) return;
    setState(() => _busy = true);
    try {
      final outcome = await ref.read(crewControllerProvider.notifier).add(_asUser(card));
      if (!mounted) return;
      setState(() {
        _busy = false;
        _card = PublicProfileCard(
          id: card.id,
          displayName: card.displayName,
          initials: card.initials,
          connectionStatus: outcome == ConnectOutcome.active
              ? CrewConnectionStatus.connected
              : CrewConnectionStatus.pendingOutgoing,
          username: card.username,
          memberId: card.memberId,
          profilePhotoUrl: card.profilePhotoUrl,
          isPrivate: card.isPrivate,
        );
      });
      _snack(outcome == ConnectOutcome.active
          ? 'Added to your crew.'
          : 'Request sent.');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack(e.message);
      }
    }
  }

  Future<void> _accept() async {
    final card = _card;
    if (card == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(crewControllerProvider.notifier).acceptRequest(_asUser(card));
      if (mounted) {
        setState(() {
          _busy = false;
          _card = _withStatus(card, CrewConnectionStatus.connected);
        });
        _snack('Added to your crew.');
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack(e.message);
      }
    }
  }

  PublicProfileCard _withStatus(PublicProfileCard c, CrewConnectionStatus s) =>
      PublicProfileCard(
        id: c.id,
        displayName: c.displayName,
        initials: c.initials,
        connectionStatus: s,
        username: c.username,
        memberId: c.memberId,
        profilePhotoUrl: c.profilePhotoUrl,
        isPrivate: c.isPrivate,
      );

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  void _exit() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/pass');
    }
  }

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

  Widget _body() {
    if (_error != null) {
      final e = _error;
      final forbidden = e is ApiException && e.statusCode == 403;
      if (forbidden) {
        return Center(
          child: NuvoEmptyState(
            icon: Icons.person_off_rounded,
            title: 'Not available',
            body: 'This person can’t be viewed right now.',
            ctaLabel: 'Done',
            onCta: _exit,
            align: TextAlign.center,
          ),
        );
      }
      return Center(
        child: NuvoErrorState(message: "Couldn't load this profile.", onRetry: _load),
      );
    }
    final card = _card;
    if (card == null) {
      return const Center(child: NuvoLoadingIndicator());
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            Column(
              children: [
                Center(
                  child: NuvoAvatar(
                    photoUrl: card.profilePhotoUrl,
                    initials: card.initials,
                    size: 96,
                  ),
                ),
                const SizedBox(height: 16),
                Text(card.displayName,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.displaySmall),
                if (card.username != null) ...[
                  const SizedBox(height: 4),
                  Text('@${card.username}',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: NuvoColors.textMuted)),
                ],
                if (card.memberId != null) ...[
                  const SizedBox(height: 2),
                  Text(card.memberId!,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: NuvoColors.textMuted)),
                ],
              ],
            ).nuvoEnter(),
            const Spacer(),
            _cta(card),
          ],
        ),
      ),
    );
  }

  Widget _cta(PublicProfileCard card) {
    switch (card.connectionStatus) {
      case CrewConnectionStatus.connected:
        return const _Badge(
          icon: Icons.check_circle_rounded,
          label: 'In your crew',
          color: NuvoColors.success,
        );
      case CrewConnectionStatus.pendingOutgoing:
        return const _Badge(
          icon: Icons.schedule_rounded,
          label: 'Request sent',
          color: NuvoColors.warning,
        );
      case CrewConnectionStatus.pendingIncoming:
        return NuvoPrimaryButton(
          label: 'Accept crew request',
          expand: true,
          loading: _busy,
          onPressed: _busy ? null : _accept,
        );
      case CrewConnectionStatus.none:
        return NuvoPrimaryButton(
          label: card.isPrivate ? 'Send crew request' : 'Add to crew',
          expand: true,
          loading: _busy,
          onPressed: _busy ? null : _connect,
        );
    }
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(label,
            style: AppTextStyles.labelLarge.copyWith(color: color)),
      ]),
    );
  }
}
