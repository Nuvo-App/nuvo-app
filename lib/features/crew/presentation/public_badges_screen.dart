import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/demo/presentation_demo.dart';
import '../../../core/v13/v13.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../profile/data/progression_models.dart' show NuvoBadge;
import '../../profile/presentation/v13/v13_profile_shared.dart';
import '../../profile/presentation/widgets/nuvo_badges.dart'
    show nuvoBadgeIconFor;
import '../application/crew_controller.dart';
import '../data/crew_api.dart';

/// `/u/:id/badges` — another member's badge collection, read-only.
///
/// Earned tiles render filled like the self collection; locked tiles stay
/// dashed and carry catalog metadata only (name + icon — a friend's progress
/// is never exposed). Tapping a tile opens a detail sheet with no
/// "Show on profile" action: you can't feature someone else's badges.
class PublicBadgesScreen extends ConsumerStatefulWidget {
  const PublicBadgesScreen({super.key, required this.userId, this.card});

  final String userId;

  /// Card pushed from the person profile — avoids a second fetch when the
  /// collection already arrived with it.
  final PublicProfileCard? card;

  @override
  ConsumerState<PublicBadgesScreen> createState() => _State();
}

class _BadgeItem {
  const _BadgeItem.earned(this.badge) : locked = null;
  const _BadgeItem.locked(this.locked) : badge = null;

  final NuvoBadge? badge;
  final PublicLockedAchievement? locked;

  String get name => badge?.name ?? locked?.name ?? '';
  String? get category => badge?.category ?? locked?.category;
  bool get isEarned => badge != null;
}

class _Filter {
  const _Filter(this.label, {this.category, this.earnedOnly});

  final String label;

  /// Category key for category filters; null for All/Earned/Locked.
  final String? category;

  /// true = earned only, false = locked only, null = not a state filter.
  final bool? earnedOnly;
}

class _State extends ConsumerState<PublicBadgesScreen> {
  PublicProfileCard? _card;
  Object? _error;
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _card = widget.card;
    if (_card == null ||
        (_card!.earned.isEmpty && _card!.lockedAchievements.isEmpty)) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
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
      final card = await ref
          .read(crewRepositoryProvider)
          .getUser(widget.userId);
      if (mounted) setState(() => _card = card);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String get _firstName {
    final name = _card?.displayName.trim() ?? '';
    if (name.isEmpty) return 'They';
    return name.split(RegExp(r'\s+')).first;
  }

  List<_BadgeItem> get _items => [
    for (final b in _card?.earned ?? const <NuvoBadge>[]) _BadgeItem.earned(b),
    for (final l
        in _card?.lockedAchievements ?? const <PublicLockedAchievement>[])
      _BadgeItem.locked(l),
  ];

  /// Preferred chip order for known category keys; anything else the server
  /// sends follows prettified, so a new category never lands silently.
  static const _categoryOrder = [
    'racing',
    'winning',
    'streak',
    'performance',
    'social',
    'motion',
    'creation',
    'variety',
    'consistency',
    'proof',
    'category',
    'level',
  ];

  static String _categoryLabel(String key) =>
      key.isEmpty ? key : key[0].toUpperCase() + key.substring(1);

  List<_Filter> get _filters {
    final items = _items;
    final cats = <String>{
      for (final i in items)
        if (i.category != null && i.category!.isNotEmpty) i.category!,
    };
    return [
      const _Filter('All'),
      const _Filter('Earned', earnedOnly: true),
      if (items.any((i) => !i.isEarned))
        const _Filter('Locked', earnedOnly: false),
      for (final c in _categoryOrder)
        if (cats.remove(c)) _Filter(_categoryLabel(c), category: c),
      for (final c in cats) _Filter(_categoryLabel(c), category: c),
    ];
  }

  List<_BadgeItem> _filtered(List<_Filter> filters) {
    final items = _items;
    final filter = filters.firstWhere(
      (f) => f.label == _filter,
      orElse: () => filters.first,
    );
    if (filter.earnedOnly != null) {
      return items.where((i) => i.isEarned == filter.earnedOnly).toList();
    }
    if (filter.category != null) {
      return items.where((i) => i.category == filter.category).toList();
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V13.bg,
      body: SafeArea(
        child: Column(
          children: [
            V13BackBar(
              title: 'Badges',
              fallback: '/u/${Uri.encodeComponent(widget.userId)}',
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final card = _card;
    if (card == null) {
      if (_error == null) return _loading();
      return V13AsyncView<PublicProfileCard>.state(
        status: V13AsyncStatus.error,
        errorTitle: "Couldn't load their badges",
        errorBody: 'Check your connection and try again.',
        onRetry: _load,
        builder: (_) => const SizedBox.shrink(),
      );
    }
    if (_items.isEmpty) {
      return V13AsyncView<PublicProfileCard>.state(
        status: V13AsyncStatus.empty,
        emptyIcon: Icons.emoji_events_outlined,
        emptyTitle: 'No badges yet',
        emptyBody:
            '$_firstName hasn\'t earned any yet — badges come from racing.',
        emptyAction: V13Button.secondary(
          label: 'Back to profile',
          onPressed: () => _backToProfile(context),
        ),
        builder: (_) => const SizedBox.shrink(),
      );
    }
    return RefreshIndicator(
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
          _progressRing(card),
          const SizedBox(height: V13.gapMd),
          Text(
            '$_firstName earned these racing.',
            style: V13.caption,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: V13.gapSection),
          _filterChips(),
          const SizedBox(height: V13.gapLg),
          _grid(),
        ],
      ),
    );
  }

  void _backToProfile(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/u/${Uri.encodeComponent(widget.userId)}');
    }
  }

  Widget _loading() => ListView(
    padding: const EdgeInsets.all(V13.pagePad),
    children: const [
      SizedBox(height: V13.gapXl),
      Center(child: V13Skeleton(height: 140, width: 140, radius: 70)),
      SizedBox(height: V13.gapXl),
      V13Skeleton(height: 300, radius: V13.radiusCard),
    ],
  );

  Widget _progressRing(PublicProfileCard card) {
    final earned = card.achievementsEarned ?? card.earned.length;
    final total =
        card.achievementsTotal ??
        card.earned.length + card.lockedAchievements.length;
    final fraction = total == 0 ? 0.0 : (earned / total).clamp(0.0, 1.0);
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

  Widget _filterChips() {
    final filters = _filters;
    if (filters.length < 2) return const SizedBox.shrink();
    return V13ChipRow(
      children: [
        for (final f in filters)
          V13Chip(
            label: f.label,
            selected: _filter == f.label,
            onTap: () => setState(() => _filter = f.label),
          ),
      ],
    );
  }

  Widget _grid() {
    final list = _filtered(_filters);
    if (list.isEmpty) {
      return V13Card.dashed(
        padding: const EdgeInsets.all(V13.gapXl),
        child: Row(
          children: [
            const V13IconTile(icon: Icons.emoji_events_outlined),
            const SizedBox(width: V13.gapMd),
            Expanded(
              child: Text('Nothing in this filter yet.', style: V13.body),
            ),
          ],
        ),
      );
    }
    return Wrap(
      spacing: V13.gapMd,
      runSpacing: V13.gapLg,
      children: [
        for (final item in list)
          SizedBox(
            width:
                (MediaQuery.sizeOf(context).width -
                    V13.pagePad * 2 -
                    V13.gapMd * 2) /
                3,
            child: Column(
              children: [
                _tileFor(item),
                const SizedBox(height: V13.gapXs),
                Text(
                  item.name,
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

  Widget _tileFor(_BadgeItem item) {
    final badge = item.badge;
    if (badge != null) {
      return V13BadgeTile.badge(
        badge,
        size: 72,
        onTap: () => _earnedSheet(badge),
        semanticLabel: badge.name,
      );
    }
    final locked = item.locked!;
    return V13BadgeTile(
      icon: nuvoBadgeIconFor(locked.iconKey),
      accent: V13.sky,
      earned: false,
      size: 72,
      onTap: () => _lockedSheet(locked),
      semanticLabel: locked.name,
    );
  }

  /// Read-only earned detail: big tile, description, status, rarity — the
  /// "Show on profile" slot exists only on your own collection.
  void _earnedSheet(NuvoBadge badge) {
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
                const V13Pill(
                  label: 'Earned',
                  color: V13.mint,
                  icon: Icons.check_rounded,
                ),
                const SizedBox(width: V13.gapSm),
                V13Pill(
                  label: _rarityLabel(badge),
                  color: badge.isMilestone ? V13.gold : V13.sky,
                ),
              ],
            ),
            if (badge.unlockedAt != null && badge.unlockedAt!.isNotEmpty) ...[
              const SizedBox(height: V13.gapMd),
              Text(
                'Earned ${badge.unlockedAt!.split('T').first}',
                style: V13.caption,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _lockedSheet(PublicLockedAchievement badge) {
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
              size: 96,
            ),
            const SizedBox(height: V13.gapLg),
            Text(
              badge.name,
              style: V13.sectionHead,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: V13.gapSm),
            Text(
              '$_firstName hasn\'t earned this one yet.',
              style: V13.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: V13.gapMd),
            const V13Pill(
              label: 'Locked',
              color: V13.divider,
              icon: Icons.lock_outline_rounded,
            ),
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
}
