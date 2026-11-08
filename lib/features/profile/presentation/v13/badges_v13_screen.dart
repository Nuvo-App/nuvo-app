import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/v13/v13.dart';
import '../../../auth/data/auth_api.dart';
import '../../application/progression_controller.dart';
import '../../data/progression_models.dart';
import 'v13_profile_shared.dart';

/// `/profile/badges` — the v13 badge collection: progress ring, up-next
/// card, server-granted featured slots, filter chips, and the tile grid.
class BadgesV13Screen extends ConsumerStatefulWidget {
  const BadgesV13Screen({super.key});

  @override
  ConsumerState<BadgesV13Screen> createState() => _BadgesV13ScreenState();
}

class _BadgesV13ScreenState extends ConsumerState<BadgesV13Screen> {
  List<NuvoBadge>? _badges;
  Object? _error;
  String _filter = 'All';
  bool _mutating = false;

  int get _slots =>
      ref.read(progressionControllerProvider).valueOrNull?.featuredSlots ?? 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final badges = await ref
          .read(progressionControllerProvider.notifier)
          .getBadges();
      if (!mounted) return;
      setState(() {
        _badges = badges.where((b) => b.isAchievement).toList();
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  List<NuvoBadge> get _filtered {
    final all = _badges ?? const <NuvoBadge>[];
    return switch (_filter) {
      'Earned' => all.where((b) => b.unlocked).toList(),
      'Locked' => all.where((b) => !b.unlocked).toList(),
      'Racing' => all.where((b) => b.category == 'racing').toList(),
      'Winning' => all.where((b) => b.category == 'winning').toList(),
      'Streaks' => all.where((b) => b.category == 'streak').toList(),
      _ => all,
    };
  }

  int _countFor(String filter) {
    final all = _badges ?? const <NuvoBadge>[];
    return switch (filter) {
      'All' => all.length,
      'Earned' => all.where((b) => b.unlocked).length,
      'Locked' => all.where((b) => !b.unlocked).length,
      'Racing' => all.where((b) => b.category == 'racing').length,
      'Winning' => all.where((b) => b.category == 'winning').length,
      'Streaks' => all.where((b) => b.category == 'streak').length,
      _ => 0,
    };
  }

  @override
  Widget build(BuildContext context) {
    final badges = _badges;
    return Scaffold(
      backgroundColor: V13.bg,
      body: SafeArea(
        child: Column(
          children: [
            const V13BackBar(title: 'Badges'),
            Expanded(
              child: badges == null
                  ? (_error == null ? _loading() : _errorView())
                  : RefreshIndicator(
                      color: V13.blue,
                      backgroundColor: V13.card,
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                          V13.pagePad,
                          V13.gapMd,
                          V13.pagePad,
                          V13.gapXxl,
                        ),
                        children: [
                          _progressRing(badges),
                          const SizedBox(height: V13.gapSection),
                          _nextUp(),
                          const SizedBox(height: V13.gapSection),
                          _featuredSlots(badges),
                          const SizedBox(height: V13.gapSection),
                          _filterChips(),
                          const SizedBox(height: V13.gapLg),
                          _grid(),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loading() => ListView(
    padding: const EdgeInsets.all(V13.pagePad),
    children: const [
      SizedBox(height: V13.gapXl),
      Center(child: V13Skeleton(height: 140, width: 140, radius: 70)),
      SizedBox(height: V13.gapXl),
      V13Skeleton(height: 96, radius: V13.radiusCard),
      SizedBox(height: V13.gapLg),
      V13Skeleton(height: 300, radius: V13.radiusCard),
    ],
  );

  Widget _errorView() => V13AsyncView<List<NuvoBadge>>.state(
    status: V13AsyncStatus.error,
    errorTitle: "Couldn't load your badges",
    errorBody: 'Check your connection and try again.',
    onRetry: _load,
    builder: (_) => const SizedBox.shrink(),
  );

  Widget _progressRing(List<NuvoBadge> badges) {
    final earned = badges.where((b) => b.unlocked).length;
    final total = badges.length;
    final fraction = total == 0 ? 0.0 : earned / total;
    return Center(
      child: SizedBox(
        width: 140,
        height: 140,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 140,
              height: 140,
              child: CircularProgressIndicator(
                value: fraction,
                strokeWidth: 10,
                color: V13.blue,
                backgroundColor: V13.divider,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$earned/$total', style: V13.number),
                Text('earned', style: V13.caption),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _nextUp() {
    final next = ref
        .watch(progressionControllerProvider)
        .valueOrNull
        ?.nextAchievement;
    if (next == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const V13SectionHeader(title: 'UP NEXT'),
        const SizedBox(height: V13.gapMd),
        V13Card(
          padding: const EdgeInsets.all(V13.gapLg),
          child: Row(
            children: [
              V13BadgeTile.badge(next, size: 56),
              const SizedBox(width: V13.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(next.name, style: V13.bodyStrong),
                    if (next.description != null)
                      Text(next.description!, style: V13.caption, maxLines: 2),
                    if (next.threshold != null) ...[
                      const SizedBox(height: V13.gapXs),
                      Text(
                        '${next.progressValue} of ${next.threshold}',
                        style: V13.caption,
                      ),
                    ],
                  ],
                ),
              ),
              V13Button.secondary(
                label: 'Find a race',
                size: V13ButtonSize.small,
                onPressed: () => context.go('/compete'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _featuredSlots(List<NuvoBadge> badges) {
    final featured = badges.where((b) => b.featured).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        V13SectionHeader(title: 'ON YOUR PROFILE · ${featured.length}/$_slots'),
        const SizedBox(height: V13.gapMd),
        Row(
          children: [
            for (var i = 0; i < _slots; i++) ...[
              if (i > 0) const SizedBox(width: V13.gapMd),
              if (i < featured.length)
                SizedBox(
                  width: 84,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      V13BadgeTile.badge(
                        featured[i],
                        size: 72,
                        onTap: () => _badgeSheet(featured[i]),
                        semanticLabel: featured[i].name,
                      ),
                      const SizedBox(height: V13.gapXs),
                      Text(
                        featured[i].name,
                        style: V13.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                )
              else
                V13DashedBox(
                  size: 72,
                  radius: 20,
                  child: const Icon(
                    Icons.add_rounded,
                    color: V13.muted,
                    size: 28,
                  ),
                ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _filterChips() {
    const filters = ['All', 'Earned', 'Locked', 'Racing', 'Winning', 'Streaks'];
    final visible = filters.where((f) => _countFor(f) > 0).toList();
    return V13ChipRow(
      children: [
        for (final f in visible)
          V13Chip(
            label: f,
            selected: _filter == f,
            onTap: () => setState(() => _filter = f),
          ),
      ],
    );
  }

  Widget _grid() {
    final list = _filtered;
    if (list.isEmpty) {
      return V13Card.dashed(
        onTap: () => context.go('/compete'),
        padding: const EdgeInsets.all(V13.gapXl),
        child: Row(
          children: [
            const V13IconTile(icon: Icons.emoji_events_outlined),
            const SizedBox(width: V13.gapMd),
            Expanded(
              child: Text(
                'Nothing in this filter yet. Races are how badges get earned.',
                style: V13.body,
              ),
            ),
          ],
        ),
      );
    }
    return Wrap(
      spacing: V13.gapMd,
      runSpacing: V13.gapLg,
      children: [
        for (final badge in list)
          SizedBox(
            width:
                (MediaQuery.sizeOf(context).width -
                    V13.pagePad * 2 -
                    V13.gapMd * 2) /
                3,
            child: Column(
              children: [
                V13BadgeTile.badge(
                  badge,
                  size: 72,
                  onTap: () => _badgeSheet(badge),
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
    );
  }

  void _badgeSheet(NuvoBadge badge) {
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
            V13BadgeTile.badge(badge, size: 96),
            const SizedBox(height: V13.gapLg),
            Text(
              badge.name,
              style: V13.sectionHead,
              textAlign: TextAlign.center,
            ),
            if (badge.description != null &&
                badge.description!.trim().isNotEmpty) ...[
              const SizedBox(height: V13.gapSm),
              Text(
                badge.description!,
                style: V13.body,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: V13.gapMd),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                V13Pill(
                  label: badge.unlocked ? 'Earned' : 'Locked',
                  color: badge.unlocked ? V13.mint : V13.divider,
                  icon: badge.unlocked
                      ? Icons.check_rounded
                      : Icons.lock_outline_rounded,
                ),
                const SizedBox(width: V13.gapSm),
                V13Pill(
                  label: _rarityLabel(badge),
                  color: badge.isMilestone ? V13.gold : V13.sky,
                ),
              ],
            ),
            if (!badge.unlocked && badge.threshold != null) ...[
              const SizedBox(height: V13.gapMd),
              Text(
                '${badge.progressValue} of ${badge.threshold}',
                style: V13.caption,
              ),
              const SizedBox(height: V13.gapXs),
              V13ProgressBar(value: badge.goalProgress),
            ],
            if (badge.unlocked) ...[
              const SizedBox(height: V13.gapLg),
              V13Button.secondary(
                label: badge.featured
                    ? 'Remove from profile'
                    : 'Show on profile',
                loading: _mutating,
                onPressed: _mutating
                    ? null
                    : () {
                        Navigator.of(ctx).pop();
                        _toggleFeature(badge);
                      },
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _rarityLabel(NuvoBadge badge) {
    final rarity = badge.metadata?['rarity'];
    if (rarity is String && rarity.isNotEmpty) {
      return rarity[0].toUpperCase() + rarity.substring(1);
    }
    return 'Common';
  }

  Future<void> _toggleFeature(NuvoBadge badge) async {
    if (_mutating || !badge.unlocked) return;
    final current = _badges ?? const <NuvoBadge>[];
    final featuredIds = current
        .where((b) => b.featured)
        .map((b) => b.unlockId)
        .toList();
    final next = badge.featured
        ? (featuredIds..remove(badge.unlockId))
        : [...featuredIds, badge.unlockId];
    if (!badge.featured && next.length > _slots) {
      showV13Toast(context, 'You can feature up to $_slots.');
      return;
    }
    setState(() => _mutating = true);
    try {
      final badges = await ref
          .read(progressionControllerProvider.notifier)
          .setFeatured(next);
      if (!mounted) return;
      setState(() => _badges = badges.where((b) => b.isAchievement).toList());
      showV13Toast(
        context,
        badge.featured ? 'Removed from profile.' : 'On your profile.',
      );
    } on ApiException catch (e) {
      if (mounted) showV13Toast(context, e.message);
    } catch (_) {
      if (mounted) {
        showV13Toast(context, "Couldn't update your profile. Try again.");
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }
}
