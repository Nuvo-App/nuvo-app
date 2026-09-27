import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/demo/presentation_demo.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_confirm_dialog.dart';
import '../../../core/widgets/nuvo_empty_state.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/theme/nuvo_entrance.dart';
import '../../../core/widgets/nuvo_loading_indicator.dart';
import '../../../core/widgets/nuvo_motion.dart';
import '../../../core/widgets/nuvo_page.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart'
    show PublicUser, Race, RaceParticipant, RaceCreatePrefill;
import '../../races/domain/race_display.dart'
    show raceProgressLabel, serverRankedParticipants;
import '../../races/presentation/race_controller.dart';
import '../application/crew_controller.dart';
import '../data/crew_api.dart';
import '../domain/crew_presence.dart';

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
    // Presentation demo people resolve locally — the session is offline-safe
    // and demo ids never exist on the server anyway.
    if (isPresentationDemoUser(ref.read(authControllerProvider).user)) {
      final demo = presentationDemoProfile(widget.userId);
      if (demo != null) {
        if (mounted) setState(() => _card = demo);
        return;
      }
    }
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

  Future<void> _remove() async {
    final card = _card;
    if (card == null) return;
    final confirmed = await showNuvoConfirmDialog(
      context,
      title: 'Remove from crew?',
      message:
          '${card.displayName} will no longer be in your crew. You can add '
          'them again later.',
      confirmLabel: 'Remove',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(crewControllerProvider.notifier).remove(card.id);
      if (mounted) {
        setState(() {
          _busy = false;
          _card = _withStatus(card, CrewConnectionStatus.none);
        });
        _snack('Removed from your crew.');
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

  Future<void> _report() async {
    final reason = await _askReason('Report this person?');
    if (!mounted || reason == null) return;
    try {
      await ref
          .read(crewRepositoryProvider)
          .reportUser(widget.userId, reason: reason);
      _snack('Thanks — our team will take a look.');
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _block() async {
    final card = _card;
    final confirmed = await showNuvoConfirmDialog(
      context,
      title: 'Block ${card?.displayName ?? 'this person'}?',
      message:
          'They won\u2019t be able to connect with you or race with you on Nuvo. '
          'You can unblock them later.',
      confirmLabel: 'Block',
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(crewRepositoryProvider).blockUser(widget.userId);
      _snack('Blocked.');
      _exit();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<String?> _askReason(String title) async {
    final controller = TextEditingController();
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: NuvoColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          20,
          24,
          24 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: AppTextStyles.titleLarge),
            const SizedBox(height: 6),
            Text(
              'What\u2019s wrong? This goes to the Nuvo review team.',
              style: AppTextStyles.bodySmall
                  .copyWith(color: NuvoColors.textMuted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                hintText: 'Optional details',
              ),
            ),
            const SizedBox(height: 8),
            NuvoPrimaryButton(
              label: 'Send report',
              icon: Icons.flag_outlined,
              expand: true,
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            ),
          ],
        ),
      ),
    );
    return value;
  }

  void _overflow() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NuvoColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Report this person'),
              onTap: () {
                Navigator.of(ctx).pop();
                _report();
              },
            ),
            ListTile(
              leading: const Icon(Icons.block_rounded),
              title: const Text('Block this person'),
              onTap: () {
                Navigator.of(ctx).pop();
                _block();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NuvoPage(
      topBar: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              NuvoBackButton(onPressed: _exit),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.more_horiz_rounded),
                onPressed: _overflow,
              ),
            ],
          ),
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
                // Real presence, crew only — same rule as the crew list.
                if (card.connectionStatus == CrewConnectionStatus.connected &&
                    crewPresenceLabel(card.lastActiveAt) != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: crewPresenceFor(card.lastActiveAt) ==
                                  CrewPresence.active
                              ? NuvoColors.success
                              : NuvoColors.textMuted,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        crewPresenceLabel(card.lastActiveAt)!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: crewPresenceFor(card.lastActiveAt) ==
                                  CrewPresence.active
                              ? context.semanticColors.success.on
                              : context.themeColors.inkSubtle,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ).nuvoEnter(),
            // Racing together — races I'm in that this person races too,
            // derived from RaceController's cache (no extra fetch).
            _sharedRaces(),
            const Spacer(),
            _cta(card),
          ],
        ),
      ),
    );
  }

  Widget _sharedRaces() {
    final races = ref
        .watch(raceControllerProvider)
        .races
        .where((r) => r.status == 'active' && r.isParticipant(widget.userId))
        .take(3)
        .toList();
    if (races.isEmpty) return const SizedBox.shrink();
    final myId = ref.read(authControllerProvider).user?.id ?? '';
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Container(
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: NuvoColors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Column(
            children: [
              for (var i = 0; i < races.length; i++)
                _SharedRaceRow(
                  race: races[i],
                  myId: myId,
                  userId: widget.userId,
                  isLast: i == races.length - 1,
                  onTap: () => context.push('/race/${races[i].id}'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cta(PublicProfileCard card) {
    return NuvoStateMorph(
      stateKey: card.connectionStatus,
      child: switch (card.connectionStatus) {
        CrewConnectionStatus.connected => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _Badge(
                icon: Icons.check_circle_rounded,
                label: 'In your crew',
                color: NuvoColors.success,
              ),
              const SizedBox(height: 14),
              NuvoPrimaryButton(
                label: 'Race ${card.displayName.split(' ').first}',
                icon: Icons.flag_rounded,
                expand: true,
                onPressed: () => context.push(
                  '/races/new',
                  extra: RaceCreatePrefill.pushups.copyWith(
                    withUser: _asUser(card),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              NuvoTertiaryButton(
                label: 'Remove from crew',
                expand: true,
                onPressed: _busy ? null : _remove,
              ),
            ],
          ),
        CrewConnectionStatus.pendingOutgoing => const _Badge(
            icon: Icons.schedule_rounded,
            label: 'Request sent',
            color: NuvoColors.warning,
          ),
        CrewConnectionStatus.pendingIncoming => NuvoPrimaryButton(
            label: 'Accept crew request',
            expand: true,
            loading: _busy,
            onPressed: _busy ? null : _accept,
          ),
        CrewConnectionStatus.none => NuvoPrimaryButton(
            label: card.isPrivate ? 'Send crew request' : 'Add to crew',
            expand: true,
            loading: _busy,
            onPressed: _busy ? null : _connect,
          ),
      },
    );
  }
}

class _SharedRaceRow extends StatelessWidget {
  const _SharedRaceRow({
    required this.race,
    required this.myId,
    required this.userId,
    required this.isLast,
    required this.onTap,
  });

  final Race race;
  final String myId;
  final String userId;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Server-rank order + format-aware progress from race_display — Crew
    // never guesses scoring direction or "/target" semantics.
    final ordered = serverRankedParticipants(race);
    String line(RaceParticipant? p, String fallback) {
      if (p == null) return fallback;
      final rank = ordered.indexWhere((x) => x.userId == p.userId);
      final rankLabel = rank >= 0 ? '#${rank + 1} · ' : '';
      return '$rankLabel${raceProgressLabel(race, p)}';
    }

    return Column(
      children: [
        NuvoPressable(
          onTap: onTap,
          haptic: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        race.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: NuvoColors.navy,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${line(race.participantFor(userId), '—')} · you ${line(race.participantFor(myId), '—')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: NuvoColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: NuvoColors.textMuted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (!isLast)
          const Divider(height: 1, color: NuvoColors.border, indent: 14),
      ],
    );
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
