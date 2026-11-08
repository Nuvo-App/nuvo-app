import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/demo/presentation_demo.dart';
import '../../../../core/v13/v13.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../crew/application/crew_controller.dart';
import '../../../pass/application/member_pass_provider.dart';
import '../../../races/data/race_models.dart';
import '../../../races/domain/race_display.dart';
import '../../../races/presentation/race_controller.dart';
import '../../../social/data/invite_models.dart';
import '../../../social/social_providers.dart';
import '../../application/activity_controller.dart';
import '../../application/progression_controller.dart';
import '../../data/profile_v13_api.dart';
import '../../data/progression_models.dart';
import 'v13_profile_shared.dart';

/// `/profile` — the v13 identity tab: photo, level, bio, counts, favorite
/// movement, activity map, featured badges and race history.
class ProfileV13Screen extends ConsumerWidget {
  const ProfileV13Screen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authUser = ref.watch(authControllerProvider).user;
    final user = authUser == null ? null : presentedUser(authUser);
    final progression = ref.watch(progressionControllerProvider).valueOrNull;
    final prefs = ref.watch(profilePrefsProvider).valueOrNull;
    final activity = ref.watch(profileActivityProvider);
    final crew = ref.watch(crewControllerProvider);
    final races = ref.watch(raceControllerProvider).races;

    final record = progression?.record;
    final finished = _finishedHistory(races, user?.id);

    return Scaffold(
      backgroundColor: V13.bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: V13.blue,
          backgroundColor: V13.card,
          onRefresh: () => _refresh(ref),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(bottom: V13TabBar.bottomPadding(context)),
            children: [
              V13TopBar(
                title: user?.username != null && user!.username!.isNotEmpty
                    ? '@${user.username}'
                    : 'Profile',
                trailing: [
                  V13IconButton(
                    icon: Icons.qr_code_2_rounded,
                    onTap: () => context.push('/my-nuvo'),
                    semanticLabel: 'My Nuvo code',
                  ),
                  V13IconButton(
                    icon: Icons.settings_outlined,
                    onTap: () => context.push('/settings'),
                    semanticLabel: 'Settings',
                  ),
                ],
              ),
              const SizedBox(height: V13.gapMd),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _IdentityCard(
                      name: user?.fullName ?? user?.username ?? 'Nuvo member',
                      photoUrl: user?.profilePhotoUrl,
                      level: progression?.level,
                      bio: prefs?.bio,
                      favoriteMovementKey: prefs?.favoriteMovementKey,
                      races: record?.finished ?? finished.length,
                      wins: record?.wins,
                      friends: record?.friends ?? crew.members.length,
                    ),
                    const SizedBox(height: V13.gapLg),
                    Row(
                      children: [
                        Expanded(
                          child: V13Button.secondary(
                            label: 'Edit profile',
                            onPressed: () => context.push('/profile/edit'),
                          ),
                        ),
                        const SizedBox(width: V13.gapMd),
                        Expanded(
                          child: V13Button.primary(
                            label: 'Share profile',
                            onPressed: () => _shareProfile(context, ref),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: V13.gapSection),
                    _activitySection(activity),
                    const SizedBox(height: V13.gapSection),
                    _achievementsSection(context, progression),
                    const SizedBox(height: V13.gapSection),
                    _historySection(context, finished, user?.id),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(profileActivityProvider);
    ref.invalidate(profilePrefsProvider);
    ref.read(crewControllerProvider.notifier).load();
    unawaited(ref.read(raceControllerProvider.notifier).loadRaces(force: true));
    await ref.read(progressionControllerProvider.notifier).load();
  }

  Future<void> _shareProfile(BuildContext context, WidgetRef ref) async {
    String? url = ref.read(memberPassProvider).info?.shareUrl;
    if (url == null || url.isEmpty) {
      try {
        final MintedInvite invite = await ref
            .read(inviteRepositoryProvider)
            .mintMyCrewInvite();
        url = invite.url;
      } catch (_) {
        if (context.mounted) {
          showV13Toast(context, "Couldn't get your profile link. Try again.");
        }
        return;
      }
    }
    await Share.share('Race me on Nuvo — $url');
  }

  List<Race> _finishedHistory(List<Race> races, String? userId) {
    final finished =
        races
            .where(
              (r) =>
                  raceIsCompleted(r) &&
                  (r.isParticipant(userId ?? '') ||
                      (userId != null && r.isCreator(userId))),
            )
            .toList()
          ..sort(
            (a, b) => (b.completedAt ?? b.updatedAt).compareTo(
              a.completedAt ?? a.updatedAt,
            ),
          );
    return finished.take(8).toList();
  }

  Widget _activitySection(AsyncValue<Map<String, int>> activity) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const V13SectionHeader(title: 'ACTIVITY'),
        const SizedBox(height: V13.gapMd),
        switch (activity) {
          AsyncData(:final value) => V13Card(
            padding: const EdgeInsets.all(V13.gapLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                V13HeatMap(
                  counts: {
                    for (final e in value.entries)
                      if (DateTime.tryParse(e.key) != null)
                        DateTime.parse(e.key): e.value,
                  },
                ),
                const SizedBox(height: V13.gapSm),
                Text(_activitySummary(value), style: V13.caption),
              ],
            ),
          ),
          AsyncError() => const SizedBox.shrink(),
          _ => V13Card(
            padding: const EdgeInsets.all(V13.gapLg),
            child: const V13Skeleton(height: 120, radius: V13.radiusTile),
          ),
        },
      ],
    );
  }

  String _activitySummary(Map<String, int> counts) {
    final proofs = counts.values.fold<int>(0, (a, b) => a + b);
    return '$proofs proofs · ${counts.length} active days';
  }

  Widget _achievementsSection(
    BuildContext context,
    NuvoProgression? progression,
  ) {
    final featured = progression?.featuredBadges ?? const <NuvoBadge>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        V13SectionHeader(
          title: progression == null
              ? 'ACHIEVEMENTS'
              : 'ACHIEVEMENTS · ${progression.achievementsEarned}/${progression.achievementsTotal}',
          trailing: V13Pressable(
            onTap: () => context.push('/profile/badges'),
            pressDepth: 2,
            borderRadius: BorderRadius.circular(V13.radiusPill),
            semanticLabel: 'See all badges',
            child: Text(
              'See all',
              style: V13.bodyStrong.copyWith(color: V13.blue),
            ),
          ),
        ),
        const SizedBox(height: V13.gapMd),
        if (featured.isEmpty)
          V13Card.dashed(
            onTap: () => context.push('/profile/badges'),
            padding: const EdgeInsets.all(V13.gapLg),
            child: Row(
              children: [
                const V13IconTile(icon: Icons.emoji_events_outlined),
                const SizedBox(width: V13.gapMd),
                Expanded(
                  child: Text(
                    'Earn badges in races, then pin your favorites here.',
                    style: V13.body,
                  ),
                ),
              ],
            ),
          )
        else
          Row(
            children: [
              for (final badge in featured.take(3)) ...[
                Expanded(
                  child: Column(
                    children: [
                      V13BadgeTile.badge(
                        badge,
                        onTap: () => context.push('/profile/badges'),
                        semanticLabel: badge.name,
                      ),
                      const SizedBox(height: V13.gapXs),
                      Text(
                        badge.name,
                        style: V13.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }

  Widget _historySection(
    BuildContext context,
    List<Race> finished,
    String? userId,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const V13SectionHeader(title: 'RACE HISTORY'),
        if (finished.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: V13.gapMd),
            child: V13Card.dashed(
              onTap: () => context.go('/compete'),
              padding: const EdgeInsets.all(V13.gapLg),
              child: Row(
                children: [
                  const V13IconTile(icon: Icons.flag_outlined),
                  const SizedBox(width: V13.gapMd),
                  Expanded(
                    child: Text(
                      'No finished races yet. Start one and your medals land here.',
                      style: V13.body,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: V13.gapMd),
            child: V13Card(
              padding: const EdgeInsets.symmetric(horizontal: V13.gapLg),
              child: Column(
                children: [
                  for (var i = 0; i < finished.length; i++)
                    V13ListRow(
                      title: finished[i].displayTitle,
                      subtitle: _historySubtitle(finished[i], userId),
                      leading: _medalFor(finished[i], userId),
                      showDivider: i < finished.length - 1,
                      onTap: () => context.push('/race/${finished[i].id}'),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _medalFor(Race race, String? userId) {
    final rank = _myRank(race, userId);
    if (rank != null && rank >= 1 && rank <= 3) {
      return V13MedalCircle(place: rank);
    }
    return V13IconTile(
      icon: rank != null ? Icons.tag_rounded : Icons.flag_outlined,
      size: 40,
    );
  }

  int? _myRank(Race race, String? userId) {
    if (userId == null) return null;
    for (final s in race.finalStandings) {
      if (s.userId == userId) return s.rank;
    }
    if (race.winnerUserId == userId) return 1;
    return null;
  }

  String _historySubtitle(Race race, String? userId) {
    final rank = _myRank(race, userId);
    if (rank == 1) return 'You took it';
    if (rank != null) return 'You finished #$rank';
    return 'Finished';
  }
}

/// Photo, name, plain "Level N", bio, the counts strip and the favorite
/// movement chip — the shared IG-like header block.
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.name,
    this.photoUrl,
    this.level,
    this.bio,
    this.favoriteMovementKey,
    this.races,
    this.wins,
    this.friends,
  });

  final String name;
  final String? photoUrl;
  final int? level;
  final String? bio;
  final String? favoriteMovementKey;
  final int? races;
  final int? wins;
  final int? friends;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        V13Face(photoUrl: photoUrl, size: 96, isMe: true, name: name),
        const SizedBox(height: V13.gapMd),
        Text(name, style: V13.sectionHead, textAlign: TextAlign.center),
        if (level != null)
          Text(
            'Level $level',
            style: V13.bodyStrong.copyWith(color: V13.muted),
          ),
        if (bio != null && bio!.trim().isNotEmpty) ...[
          const SizedBox(height: V13.gapSm),
          Text(bio!.trim(), style: V13.body, textAlign: TextAlign.center),
        ],
        const SizedBox(height: V13.gapLg),
        V13ProfileCounts(races: races, wins: wins, friends: friends),
        if (favoriteMovementKey != null &&
            favoriteMovementKey!.trim().isNotEmpty) ...[
          const SizedBox(height: V13.gapLg),
          V13Chip(
            label: v13MovementLabel(favoriteMovementKey!),
            icon: Icons.bolt_rounded,
            selected: true,
          ),
        ],
      ],
    );
  }
}
