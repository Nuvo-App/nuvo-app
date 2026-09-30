import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/demo/presentation_demo.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
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
import '../../../core/widgets/nuvo_progress_bar.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart'
    show PublicUser, Race, RaceParticipant, RaceCreatePrefill;
import '../../races/domain/race_display.dart'
    show raceProgressLabel, serverRankedParticipants;
import '../../races/presentation/race_controller.dart';
import '../../profile/data/progression_models.dart' show NuvoBadge;
import '../../profile/presentation/widgets/nuvo_badges.dart';
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
      final demo = presentationDemoProfile(
        widget.userId,
        viewerId: ref.read(authControllerProvider).user?.id,
      );
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
        _card = _withStatus(
          card,
          outcome == ConnectOutcome.active
              ? CrewConnectionStatus.connected
              : CrewConnectionStatus.pendingOutgoing,
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
        level: c.level,
        levelProgress: c.levelProgress,
        achievementsEarned: c.achievementsEarned,
        achievementsTotal: c.achievementsTotal,
        featured: c.featured,
        earned: c.earned,
        racesFinished: c.racesFinished,
        racesWon: c.racesWon,
        racesWithYou: c.racesWithYou,
        lastActiveAt: c.lastActiveAt,
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
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        children: [
          _hero(card).nuvoEnter(),
          // Same progression plane as the self profile — the level climb and
          // the canonical racing record share one ice-blue field.
          if (card.level != null || card.racesFinished != null) ...[
            const SizedBox(height: 20),
            _PublicProgressionPlane(card: card).nuvoEnter(),
          ],
          // Earned collection — featured first; tap opens the earned-only
          // collection (locked progress stays self-only).
          if ((card.achievementsEarned ?? 0) > 0) ...[
            const SizedBox(height: 24),
            _PublicAchievements(card: card),
          ],
          _racesWithYou(card),
          // Racing together — races I'm in that this person races too,
          // derived from RaceController's cache (no extra fetch).
          _sharedRaces(),
          const SizedBox(height: 24),
          _cta(card),
        ],
      ),
    );
  }

  /// Same identity composition as the self profile — avatar with physical
  /// edge, name, @handle, and the Nuvo Level in the block. The climb bar and
  /// record live on the shared progression plane below; the public contract
  /// only carries the 0..1 fraction, never absolute XP.
  Widget _hero(PublicProfileCard card) {
    final c = context.themeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.inkShadow, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: c.inkShadow,
                    offset: const Offset(2.5, 2.5),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: NuvoAvatar(
                photoUrl: card.profilePhotoUrl,
                initials: card.initials,
                size: NuvoAvatarSizes.lg,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.headlineMedium.copyWith(color: c.ink),
                  ),
                  if (card.username != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '@${card.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: c.inkSubtle,
                      ),
                    ),
                  ],
                  if (card.level != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'LEVEL ${card.level}',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: NuvoColors.blue,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                      maxLines: 1,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (card.memberId != null) ...[
          const SizedBox(height: 6),
          Text(
            card.memberId!,
            style: AppTextStyles.bodySmall.copyWith(color: c.inkMuted),
          ),
        ],
        // Real presence, crew only — same rule as the crew list.
        if (card.connectionStatus == CrewConnectionStatus.connected &&
            crewPresenceLabel(card.lastActiveAt) != null) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: crewPresenceFor(card.lastActiveAt) ==
                          CrewPresence.active
                      ? context.semanticColors.success.on
                      : context.themeColors.inkDim,
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
    );
  }

  /// Races we've both finished — canonical head-to-head context. Only shown
  /// when the server says there's a real shared history.
  Widget _racesWithYou(PublicProfileCard card) {
    final shared = card.racesWithYou;
    if (shared == null || shared.total == 0) return const SizedBox.shrink();
    final c = context.themeColors;
    final first = card.displayName.split(' ').first;
    final myId = ref.read(authControllerProvider).user?.id ?? '';
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RACES WITH YOU',
            style: AppTextStyles.labelSmall.copyWith(
              color: c.inkSubtle,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${shared.total} ${shared.total == 1 ? 'race' : 'races'}',
                            style: AppTextStyles.titleMedium.copyWith(
                              color: c.ink,
                            ),
                          ),
                        ),
                        Text(
                          'You ${shared.viewerWins}  ·  $first ${shared.targetWins}',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: NuvoColors.blue,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (var i = 0; i < shared.recent.length; i++)
                    _SharedResultRow(
                      race: shared.recent[i],
                      first: first,
                      myId: myId,
                      showDivider: true,
                      onTap: () =>
                          context.push('/race/${shared.recent[i].raceId}'),
                    ),
                ],
              ),
            ),
          ),
        ],
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

/// The public half of the progression plane — same ice-blue field as the
/// self profile, carrying the level climb and the racing record as one
/// system. The public contract shows level and the 0..1 fraction only;
/// absolute XP never leaves the owner's own profile.
class _PublicProgressionPlane extends StatelessWidget {
  const _PublicProgressionPlane({required this.card});

  final PublicProfileCard card;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      decoration: BoxDecoration(
        color: c.panelLight,
        borderRadius: BorderRadius.circular(NuvoRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (card.level != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'LEVEL ',
                          style: AppTextStyles.titleMedium.copyWith(
                            color: c.ink,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                        TextSpan(
                          text: '${card.level}',
                          style: AppTextStyles.statLarge(
                            30,
                            color: NuvoColors.blue,
                            weight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${((card.levelProgress ?? 0) * 100).round()}%',
                  maxLines: 1,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: c.inkSubtle,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: NuvoSpacing.sm),
            NuvoProgressBar(
              value: card.levelProgress ?? 0,
              height: 12,
              color: NuvoColors.blue,
              trackColor: c.track,
            ),
          ],
          if (card.racesFinished != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Divider(
                height: 1,
                thickness: 1,
                color: c.ink.withValues(alpha: 0.10),
              ),
            ),
            _PubStatsStrip(card: card),
          ],
        ],
      ),
    );
  }
}

/// Canonical racing stats — how much they race and how often they win.
/// Page-level like the self profile: color carries meaning (blue = live,
/// gold = wins, navy = record), hairlines separate, no card.
class _PubStatsStrip extends StatelessWidget {
  const _PubStatsStrip({required this.card});

  final PublicProfileCard card;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final races = card.racesFinished ?? 0;
    final wins = card.racesWon ?? 0;
    final rate = races > 0 ? ((wins / races) * 100).round() : 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          _PubStat(value: '$races', label: 'RACING', color: NuvoColors.blue),
          _divider(c),
          _PubStat(value: '$wins', label: 'WINS', color: NuvoColors.gold),
          _divider(c),
          _PubStat(value: '$rate%', label: 'WIN RATE', color: c.ink),
        ],
      ),
    );
  }

  Widget _divider(NuvoThemeColors c) => Container(
        width: 1,
        height: 32,
        color: c.ink.withValues(alpha: 0.12),
        margin: const EdgeInsets.symmetric(horizontal: 4),
      );
}

class _PubStat extends StatelessWidget {
  const _PubStat({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: AppTextStyles.number(
              24,
              color: color,
              weight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: AppTextStyles.labelUppercase(10).copyWith(
              color: c.inkSubtle,
            ),
          ),
        ],
      ),
    );
  }
}

/// Featured + earned achievements on someone else's profile. Tapping opens
/// their earned-only collection — locked progress is never exposed.
class _PublicAchievements extends ConsumerWidget {
  const _PublicAchievements({required this.card});

  final PublicProfileCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.themeColors;
    // Featured achievements resolve to full badges from the earned list so
    // they render with the same silhouette as the collection.
    final shown = <NuvoBadge>[];
    for (final f in card.featured) {
      final hit = card.earned.where((b) => b.unlockId == f.unlockId);
      if (hit.isNotEmpty) shown.add(hit.first);
    }
    if (shown.isEmpty) shown.addAll(card.earned.take(3));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NuvoPressable(
          onTap: () => context.push('/u/${card.id}/badges', extra: card),
          haptic: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'Achievements',
                  style: AppTextStyles.sectionTitle.copyWith(
                    color: c.ink,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${card.achievementsEarned} / ${card.achievementsTotal ?? '?'}',
                style: AppTextStyles.labelSmall.copyWith(
                  color: c.inkSubtle,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: NuvoColors.blue,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (shown.isNotEmpty)
          Row(
            children: [
              for (var i = 0; i < shown.length; i++) ...[
                Expanded(
                  child: Column(
                    children: [
                      Center(
                        child: NuvoAchievementBadge(
                          badge: shown[i],
                          size: 48,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        shown[i].name,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: nuvoBadgeAccent(shown[i]),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (i < shown.length - 1) const SizedBox(width: 8),
              ],
              // Keep cells evenly sized when fewer than 3 are earned.
              for (var i = shown.length; i < 3; i++) ...[
                const SizedBox(width: 8),
                const Expanded(child: SizedBox()),
              ],
            ],
          ),
      ],
    );
  }
}

/// One shared finished race — title plus who took it.
class _SharedResultRow extends StatelessWidget {
  const _SharedResultRow({
    required this.race,
    required this.first,
    required this.myId,
    required this.showDivider,
    required this.onTap,
  });

  final PublicSharedRace race;
  final String first;
  final String myId;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final won = race.winnerUserId != null && race.winnerUserId == myId;
    final theirs = race.winnerUserId != null && race.winnerUserId != myId;
    final result = won
        ? 'You won'
        : theirs
            ? '$first won'
            : 'Finished';
    return Column(
      children: [
        if (showDivider) Divider(height: 1, color: c.divider, indent: 14),
        NuvoPressable(
          onTap: onTap,
          haptic: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    race.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: c.ink,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  result,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: won
                        ? NuvoColors.blue
                        : c.inkSubtle,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: c.inkDim,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
