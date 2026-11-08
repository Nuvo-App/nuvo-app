import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/demo/presentation_demo.dart';
import '../../../../core/v13/v13.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../crew/application/crew_controller.dart';
import '../../../crew/data/crew_api.dart';
import '../../../crew/domain/crew_presence.dart';
import '../../../notifications/application/notification_controller.dart';
import '../../../races/data/race_models.dart';
import '../../../races/presentation/race_controller.dart';
import '../widgets/nuvo_badges.dart';
import 'v13_profile_shared.dart';

/// `/u/:id` — the v13 public profile. Friend: Race + Friends sheet + menu.
/// Non-friend: Add friend → Requested, incoming → Accept. vs-you scoreboard,
/// friendship badges, their activity map, achievements, shared races.
class PublicProfileV13Screen extends ConsumerStatefulWidget {
  const PublicProfileV13Screen({super.key, required this.userId});

  /// Route path parameter — `/u/:id`.
  final String userId;

  @override
  ConsumerState<PublicProfileV13Screen> createState() =>
      _PublicProfileV13ScreenState();
}

class _PublicProfileV13ScreenState
    extends ConsumerState<PublicProfileV13Screen> {
  PublicProfileCard? _card;
  bool _loading = true;
  Object? _error;
  bool _busy = false;
  bool? _mutedOverride;

  /// null = still loading or not attempted; loaded even when `shared` is
  /// false so the section decides from one source.
  PublicUserActivity? _activity;

  bool get _isDemo =>
      isPresentationDemoUser(ref.read(authControllerProvider).user);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final me = ref.read(authControllerProvider).user;
      final card = _isDemo
          ? presentationDemoProfile(widget.userId, viewerId: me?.id)
          : await ref.read(crewRepositoryProvider).getUser(widget.userId);
      if (!mounted) return;
      if (card == null) {
        setState(() {
          _loading = false;
          _error = 'not-found';
        });
        return;
      }
      setState(() {
        _card = card;
        _loading = false;
        _mutedOverride = null;
      });
      unawaited(_loadActivity());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _loadActivity() async {
    if (_isDemo) return;
    try {
      final a = await ref
          .read(crewRepositoryProvider)
          .getUserActivity(widget.userId);
      if (mounted) setState(() => _activity = a);
    } catch (_) {
      // 404 / not-shared / offline — the section simply hides.
    }
  }

  String get _firstName {
    final name = _card?.displayName.trim() ?? '';
    if (name.isEmpty) return 'them';
    return name.split(RegExp(r'\s+')).first;
  }

  PublicUser get _asPublicUser {
    final c = _card!;
    return PublicUser(
      id: c.id,
      displayName: c.displayName,
      username: c.username,
      memberId: c.memberId,
      initials: c.initials,
      profilePhotoUrl: c.profilePhotoUrl,
      lastActiveAt: c.lastActiveAt,
      level: c.level,
    );
  }

  bool get _muted => _mutedOverride ?? _card?.muted ?? false;

  @override
  Widget build(BuildContext context) {
    final card = _card;
    return Scaffold(
      backgroundColor: V13.bg,
      body: SafeArea(
        child: Column(
          children: [
            V13BackBar(
              title: card?.username != null && card!.username!.isNotEmpty
                  ? '@${card.username}'
                  : 'Profile',
              trailing: [
                if (card != null)
                  V13IconButton(
                    icon: Icons.more_horiz_rounded,
                    onTap: _openMenu,
                    semanticLabel: 'More',
                  ),
              ],
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
        children: const [
          SizedBox(height: V13.gapXl),
          V13Skeleton(height: 220, radius: V13.radiusCard),
          SizedBox(height: V13.gapLg),
          V13Skeleton(height: 120, radius: V13.radiusCard),
          SizedBox(height: V13.gapLg),
          V13Skeleton(height: 160, radius: V13.radiusCard),
        ],
      );
    }
    if (_error != null || _card == null) {
      return V13AsyncView<PublicProfileCard>.state(
        status: V13AsyncStatus.error,
        errorTitle: "Couldn't load this profile",
        errorBody: 'They may be unavailable, or your connection dropped.',
        onRetry: _load,
        builder: (_) => const SizedBox.shrink(),
      );
    }
    final card = _card!;
    final connected = card.connectionStatus == CrewConnectionStatus.connected;
    return RefreshIndicator(
      color: V13.blue,
      backgroundColor: V13.card,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          left: V13.pagePad,
          right: V13.pagePad,
          bottom: V13TabBar.bottomPadding(context),
        ),
        children: [
          const SizedBox(height: V13.gapMd),
          _header(card, connected),
          const SizedBox(height: V13.gapLg),
          _actions(card, connected),
          if (card.versus != null) ...[
            const SizedBox(height: V13.gapSection),
            _versus(card.versus!),
          ],
          if (connected &&
              card.friendship != null &&
              card.friendship!.badges.isNotEmpty) ...[
            const SizedBox(height: V13.gapSection),
            _friendshipBadges(card.friendship!),
          ],
          if (_activity != null && _activity!.shared) ...[
            const SizedBox(height: V13.gapSection),
            _theirActivity(_activity!),
          ],
          if (card.earned.isNotEmpty || card.lockedAchievements.isNotEmpty) ...[
            const SizedBox(height: V13.gapSection),
            _achievements(card),
          ],
          if (card.racesWithYou != null && card.racesWithYou!.total > 0) ...[
            const SizedBox(height: V13.gapSection),
            _racesWithYou(card),
          ],
        ],
      ),
    );
  }

  Widget _header(PublicProfileCard card, bool connected) {
    final presence = connected ? crewPresenceLabel(card.lastActiveAt) : null;
    return Column(
      children: [
        V13Face(
          photoUrl: card.profilePhotoUrl,
          size: 96,
          name: card.displayName,
        ),
        const SizedBox(height: V13.gapMd),
        Text(
          card.displayName,
          style: V13.sectionHead,
          textAlign: TextAlign.center,
        ),
        if (presence != null)
          Text(presence, style: V13.caption.copyWith(color: V13.blue))
        else if (card.level != null)
          Text(
            'Level ${card.level}',
            style: V13.bodyStrong.copyWith(color: V13.muted),
          ),
        if (card.bio != null && card.bio!.trim().isNotEmpty) ...[
          const SizedBox(height: V13.gapSm),
          Text(card.bio!.trim(), style: V13.body, textAlign: TextAlign.center),
        ],
        const SizedBox(height: V13.gapLg),
        V13ProfileCounts(
          races: card.racesFinished,
          wins: card.racesWon,
          friends: card.friendsCount,
        ),
        if (card.favoriteMovementKey != null &&
            card.favoriteMovementKey!.trim().isNotEmpty) ...[
          const SizedBox(height: V13.gapLg),
          V13Chip(
            label: v13MovementLabel(card.favoriteMovementKey!),
            icon: Icons.bolt_rounded,
            selected: true,
          ),
        ],
        if (card.mutual != null && card.mutual!.count > 0) ...[
          const SizedBox(height: V13.gapLg),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              V13FaceStack(
                faces: [
                  for (final p in card.mutual!.preview)
                    V13FaceInfo(
                      id: p.id,
                      photoUrl: p.profilePhotoUrl,
                      name: p.displayName,
                    ),
                ],
                total: card.mutual!.count,
                onFaceTap: (f) {
                  if (f.id != null) context.push('/u/${f.id}');
                },
              ),
              const SizedBox(width: V13.gapSm),
              Text('${card.mutual!.count} mutual', style: V13.caption),
            ],
          ),
        ],
      ],
    );
  }

  Widget _actions(PublicProfileCard card, bool connected) {
    final pendingOut =
        card.connectionStatus == CrewConnectionStatus.pendingOutgoing;
    final pendingIn =
        card.connectionStatus == CrewConnectionStatus.pendingIncoming;
    return Row(
      children: [
        Expanded(
          child: pendingIn
              ? V13Button.primary(
                  label: 'Accept',
                  icon: Icons.check_rounded,
                  loading: _busy,
                  onPressed: _busy ? null : _accept,
                )
              : connected
              ? V13Button.primary(
                  label: 'Race $_firstName',
                  icon: Icons.flag_rounded,
                  onPressed: _race,
                )
              : V13Button.primary(
                  label: pendingOut ? 'Requested' : 'Add friend',
                  icon: pendingOut
                      ? Icons.schedule_rounded
                      : Icons.person_add_alt_1_rounded,
                  loading: _busy,
                  onPressed: (_busy || pendingOut) ? null : _addFriend,
                ),
        ),
        if (connected) ...[
          const SizedBox(width: V13.gapMd),
          V13Button.secondary(
            label: 'Friends',
            icon: Icons.people_alt_rounded,
            onPressed: _friendsSheet,
          ),
        ],
      ],
    );
  }

  Future<void> _race() async {
    context.push(
      '/races/new',
      extra: RaceCreatePrefill(withUser: _asPublicUser),
    );
  }

  Future<void> _addFriend() async {
    setState(() => _busy = true);
    try {
      final outcome = await ref
          .read(crewControllerProvider.notifier)
          .add(_asPublicUser);
      if (!mounted) return;
      showV13Toast(
        context,
        outcome == ConnectOutcome.active
            ? 'Added to your friends.'
            : 'Request sent.',
      );
      _load();
    } catch (e) {
      if (mounted) {
        showV13Toast(context, "Couldn't send that request. Try again.");
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(crewControllerProvider.notifier)
          .acceptRequest(_asPublicUser);
      if (!mounted) return;
      showV13Confetti(context);
      showV13Toast(context, 'You\'re friends now.');
      _load();
    } catch (_) {
      if (mounted) {
        showV13Toast(context, "Couldn't accept right now. Try again.");
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _friendsSheet() async {
    final action = await showV13ActionSheet<String>(
      context,
      actions: [
        V13SheetAction(
          label: _muted ? 'Unmute $_firstName' : 'Mute $_firstName',
          value: 'mute',
          icon: _muted ? Icons.volume_up_outlined : Icons.volume_off_outlined,
        ),
        const V13SheetAction(
          label: 'Remove friend',
          value: 'remove',
          icon: Icons.person_remove_outlined,
          destructive: true,
        ),
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'mute') await _toggleMute();
    if (action == 'remove') await _removeFriend();
  }

  Future<void> _toggleMute() async {
    final next = !_muted;
    try {
      final repo = ref.read(crewRepositoryProvider);
      if (next) {
        await repo.muteUser(widget.userId);
      } else {
        await repo.unmuteUser(widget.userId);
      }
      if (!mounted) return;
      setState(() => _mutedOverride = next);
      showV13Toast(
        context,
        next ? 'Muted $_firstName.' : 'Unmuted $_firstName.',
      );
    } catch (_) {
      if (mounted) {
        showV13Toast(context, "Couldn't update that. Try again.");
      }
    }
  }

  Future<void> _removeFriend() async {
    final ok = await showV13ConfirmSheet(
      context,
      title: 'Remove $_firstName?',
      body: "They won't be told. You can add each other again anytime.",
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(crewControllerProvider.notifier).remove(widget.userId);
      if (!mounted) return;
      showV13Toast(context, 'Removed from your friends.');
      _load();
    } catch (_) {
      if (mounted) {
        showV13Toast(context, "Couldn't remove them. Try again.");
      }
    }
  }

  Future<void> _openMenu() async {
    final action = await showV13ActionSheet<String>(
      context,
      actions: [
        const V13SheetAction(
          label: 'Share profile',
          value: 'share',
          icon: Icons.ios_share_rounded,
        ),
        const V13SheetAction(
          label: 'Copy profile link',
          value: 'copy',
          icon: Icons.link_rounded,
        ),
        V13SheetAction(
          label: _muted ? 'Unmute' : 'Mute',
          value: 'mute',
          icon: _muted ? Icons.volume_up_outlined : Icons.volume_off_outlined,
        ),
        const V13SheetAction(
          label: 'Report',
          value: 'report',
          icon: Icons.flag_outlined,
        ),
        const V13SheetAction(
          label: 'Block',
          value: 'block',
          icon: Icons.block_rounded,
          destructive: true,
        ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'share':
        await Share.share(_profileLink());
      case 'copy':
        await Clipboard.setData(ClipboardData(text: _profileLink()));
        if (mounted) showV13Toast(context, 'Profile link copied.');
      case 'mute':
        await _toggleMute();
      case 'report':
        await _report();
      case 'block':
        await _block();
    }
  }

  /// Their in-app profile link — `/u/:id` resolves through the app's own
  /// destination parser, so the link opens this screen for app users.
  String _profileLink() => 'https://getnuvo.net/u/${widget.userId}';

  Future<void> _report() async {
    final reason = await showV13ActionSheet<String>(
      context,
      title: 'Report $_firstName',
      actions: const [
        V13SheetAction(label: 'Spam', value: 'Spam'),
        V13SheetAction(label: 'Harassment', value: 'Harassment'),
        V13SheetAction(label: 'Inappropriate', value: 'Inappropriate'),
        V13SheetAction(label: 'Something else', value: 'Other'),
      ],
    );
    if (!mounted || reason == null) return;
    try {
      await ref
          .read(crewRepositoryProvider)
          .reportUser(widget.userId, reason: reason);
      if (mounted) {
        showV13Toast(context, 'Report sent. Our team will take a look.');
      }
    } catch (_) {
      if (mounted) {
        showV13Toast(context, "Couldn't send the report. Try again.");
      }
    }
  }

  Future<void> _block() async {
    final ok = await showV13ConfirmSheet(
      context,
      title: 'Block $_firstName?',
      body:
          "They won't be told. You'll disappear from each other's friends, "
          'races and feed.',
      confirmLabel: 'Block',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(crewRepositoryProvider).blockUser(widget.userId);
    } catch (_) {
      if (mounted) {
        showV13Toast(context, "Couldn't block them. Try again.");
      }
      return;
    }
    // Blocked people disappear everywhere — refresh friends, feed and races
    // before leaving this screen.
    ref.read(crewControllerProvider.notifier).load();
    ref.read(raceControllerProvider.notifier).markStale();
    ref.read(notificationControllerProvider.notifier).load();
    if (!mounted) return;
    showV13Toast(context, 'Blocked $_firstName.');
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/pass');
    }
  }

  // ── vs you ────────────────────────────────────────────────────────────────

  Widget _versus(PublicVersus versus) {
    final you = versus.you;
    final them = versus.them;
    final rows =
        <({String label, num you, num them, String Function(num) fmt})>[
          (label: 'Level', you: you.level, them: them.level, fmt: _plain),
          (label: 'Wins', you: you.wins, them: them.wins, fmt: _plain),
          (
            label: 'Win rate',
            you: you.winRatePercent ?? 0,
            them: them.winRatePercent ?? 0,
            fmt: (v) => '$v%',
          ),
          (
            label: 'Best streak',
            you: you.bestStreakDays ?? 0,
            them: them.bestStreakDays ?? 0,
            fmt: (v) => '${v}d',
          ),
          (
            label: 'Proofs this week',
            you: you.proofsThisWeek ?? 0,
            them: them.proofsThisWeek ?? 0,
            fmt: _plain,
          ),
        ];
    var a = 0;
    var b = 0;
    for (final r in rows) {
      if (r.you > r.them) a++;
      if (r.them > r.you) b++;
    }
    final myPhoto = ref.read(authControllerProvider).user?.profilePhotoUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        V13SectionHeader(title: '$_firstName vs you'),
        const SizedBox(height: V13.gapMd),
        V13Card(
          padding: const EdgeInsets.all(V13.gapLg),
          child: Column(
            children: [
              Row(
                children: [
                  V13Face(
                    photoUrl: _card?.profilePhotoUrl,
                    size: 40,
                    name: _card?.displayName,
                  ),
                  const SizedBox(width: V13.gapSm),
                  Expanded(
                    child: Text(
                      'STATS WON $a – $b',
                      style: V13.bodyStrong,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  V13Face(photoUrl: myPhoto, size: 40, isMe: true, name: 'You'),
                ],
              ),
              const SizedBox(height: V13.gapMd),
              const V13Divider(),
              for (final r in rows) _versusRow(r.label, r.you, r.them, r.fmt),
            ],
          ),
        ),
      ],
    );
  }

  String _plain(num v) => '$v';

  Widget _versusRow(String label, num you, num them, String Function(num) fmt) {
    final meWins = you > them;
    final theyWin = them > you;
    final tie = you == them;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: V13.gapSm),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: _versusValue(fmt(them), theyWin, tie, isMe: false),
          ),
          Expanded(
            child: Text(label, style: V13.caption, textAlign: TextAlign.center),
          ),
          SizedBox(
            width: 44,
            child: _versusValue(fmt(you), meWins, tie, isMe: true),
          ),
        ],
      ),
    );
  }

  Widget _versusValue(String text, bool wins, bool tie, {required bool isMe}) {
    if (tie) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: V13.divider,
          borderRadius: BorderRadius.circular(V13.radiusPill),
        ),
        child: Text(text, style: V13.caption, textAlign: TextAlign.center),
      );
    }
    if (!wins) {
      return Text(text, style: V13.caption, textAlign: TextAlign.center);
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isMe ? V13.blue : V13.navy,
        borderRadius: BorderRadius.circular(V13.radiusPill),
        border: Border.all(color: V13.navy, width: V13.outline),
      ),
      child: Text(
        text,
        style: V13.caption.copyWith(
          color: V13.card,
          fontWeight: FontWeight.w800,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ── friendship badges ──────────────────────────────────────────────────────

  Widget _friendshipBadges(PublicFriendship friendship) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const V13SectionHeader(title: 'FRIENDSHIP'),
        const SizedBox(height: V13.gapMd),
        Wrap(
          spacing: V13.gapMd,
          runSpacing: V13.gapLg,
          children: [
            for (final badge in friendship.badges)
              SizedBox(
                width: 76,
                child: Column(
                  children: [
                    V13BadgeTile(
                      icon: _friendshipIcon(badge.key),
                      accent: V13.sun,
                      earned: badge.earned,
                      progress: badge.earned
                          ? 0
                          : (badge.progress / badge.threshold).clamp(0, 1),
                      onTap: () => _explainFriendship(badge),
                      semanticLabel: badge.name,
                    ),
                    const SizedBox(height: V13.gapXs),
                    Text(
                      badge.name,
                      style: V13.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  IconData _friendshipIcon(String key) => switch (key) {
    'first_race' => Icons.flag_rounded,
    'rivals' => Icons.bolt_rounded,
    'cheer_squad' => Icons.favorite_rounded,
    'best_friends' => Icons.handshake_rounded,
    'streak_buddies' => Icons.local_fire_department_rounded,
    _ => Icons.emoji_events_outlined,
  };

  void _explainFriendship(PublicFriendshipBadge badge) {
    showV13Sheet<void>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(
          V13.pagePad,
          0,
          V13.pagePad,
          V13.pagePad,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            V13BadgeTile(
              icon: _friendshipIcon(badge.key),
              accent: V13.sun,
              earned: badge.earned,
              size: 88,
            ),
            const SizedBox(height: V13.gapLg),
            Text(badge.name, style: V13.sectionHead),
            const SizedBox(height: V13.gapSm),
            Text(
              badge.description,
              style: V13.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: V13.gapMd),
            Text(
              badge.earned
                  ? 'Earned together'
                  : '${badge.progress} of ${badge.threshold}',
              style: V13.caption,
            ),
            if (!badge.earned) ...[
              const SizedBox(height: V13.gapSm),
              V13ProgressBar(
                value: (badge.progress / badge.threshold).clamp(0, 1),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── their activity ─────────────────────────────────────────────────────────

  Widget _theirActivity(PublicUserActivity activity) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const V13SectionHeader(title: 'ACTIVITY'),
        const SizedBox(height: V13.gapMd),
        V13Card(
          padding: const EdgeInsets.all(V13.gapLg),
          child: V13HeatMap(
            counts: {
              for (final e in activity.days.entries)
                if (DateTime.tryParse(e.key) != null)
                  DateTime.parse(e.key): e.value,
            },
          ),
        ),
      ],
    );
  }

  // ── achievements ───────────────────────────────────────────────────────────

  Widget _achievements(PublicProfileCard card) {
    final earned = card.earned;
    final locked = card.lockedAchievements;
    final tiles = <Widget>[
      for (final badge in earned.take(6))
        _achievementCell(V13BadgeTile.badge(badge, size: 56), badge.name),
      for (final lockedBadge in locked.take(6))
        _achievementCell(
          V13BadgeTile(
            icon: nuvoBadgeIconFor(lockedBadge.iconKey),
            accent: V13.sky,
            earned: false,
            size: 56,
            onTap: () => _explainLocked(lockedBadge),
            semanticLabel: lockedBadge.name,
          ),
          lockedBadge.name,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        V13SectionHeader(
          title:
              card.achievementsEarned != null && card.achievementsTotal != null
              ? 'ACHIEVEMENTS · ${card.achievementsEarned}/${card.achievementsTotal}'
              : 'ACHIEVEMENTS',
          trailingLabel: 'See all',
          onTrailingTap: () =>
              context.push('/u/${widget.userId}/badges', extra: card),
        ),
        const SizedBox(height: V13.gapMd),
        Wrap(spacing: V13.gapMd, runSpacing: V13.gapLg, children: tiles),
      ],
    );
  }

  Widget _achievementCell(Widget tile, String name) {
    return SizedBox(
      width: 76,
      child: Column(
        children: [
          tile,
          const SizedBox(height: V13.gapXs),
          Text(
            name,
            style: V13.caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _explainLocked(PublicLockedAchievement badge) {
    showV13Sheet<void>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(
          V13.pagePad,
          0,
          V13.pagePad,
          V13.pagePad,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            V13BadgeTile(
              icon: nuvoBadgeIconFor(badge.iconKey),
              accent: V13.sky,
              earned: false,
              size: 88,
            ),
            const SizedBox(height: V13.gapLg),
            Text(badge.name, style: V13.sectionHead),
            const SizedBox(height: V13.gapSm),
            Text(
              '$_firstName hasn\'t earned this one yet.',
              style: V13.body,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ── races with you ─────────────────────────────────────────────────────────

  Widget _racesWithYou(PublicProfileCard card) {
    final shared = card.racesWithYou!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        V13SectionHeader(title: 'RACED TOGETHER · ${shared.total}'),
        const SizedBox(height: V13.gapMd),
        V13Card(
          padding: const EdgeInsets.symmetric(horizontal: V13.gapLg),
          child: Column(
            children: [
              V13ListRow(
                title:
                    'You ${shared.viewerWins} · $_firstName ${shared.targetWins}',
                subtitle: 'Wins across your shared races',
                leading: const V13IconTile(icon: Icons.emoji_events_outlined),
                showDivider: shared.recent.isNotEmpty,
              ),
              for (var i = 0; i < shared.recent.length; i++)
                V13ListRow(
                  title: shared.recent[i].title,
                  subtitle: _sharedRaceSubtitle(shared.recent[i]),
                  leading: _sharedRaceLeading(shared.recent[i]),
                  showDivider: i < shared.recent.length - 1,
                  onTap: () => context.push('/race/${shared.recent[i].raceId}'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _sharedRaceSubtitle(PublicSharedRace race) {
    final winner = race.winnerUserId;
    if (winner == null) return 'Finished';
    if (winner == ref.read(authControllerProvider).user?.id) return 'You won';
    if (winner == widget.userId) return '$_firstName won';
    return 'Finished';
  }

  Widget _sharedRaceLeading(PublicSharedRace race) {
    if (race.winnerUserId == ref.read(authControllerProvider).user?.id) {
      return const V13MedalCircle(place: 1);
    }
    return const V13IconTile(icon: Icons.flag_outlined, size: 36);
  }
}
