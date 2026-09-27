import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/nuvo_entrance.dart';
import '../../../core/widgets/nuvo_back_header.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_motion.dart';
import '../../../core/widgets/nuvo_progress_bar.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/data/auth_api.dart';
import '../application/progression_controller.dart';
import '../data/progression_models.dart';
import 'widgets/nuvo_badges.dart';

/// Achievement collection — everything earned plus everything still asking.
/// Locked achievements carry live canonical progress, so every tile answers
/// "what do I do next." Tap a tile for the detail sheet; earned tiles can be
/// featured on Profile within the unlocked slot count.
class BadgesScreen extends ConsumerStatefulWidget {
  const BadgesScreen({super.key});

  @override
  ConsumerState<BadgesScreen> createState() => _BadgesScreenState();
}

/// Server categories grouped into the collection's filter tabs.
const _achievementTabs = <String, String>{
  'All': '',
  'Racing': 'racing',
  'Winning': 'winning',
  'Creating': 'creation',
  'Performance': 'performance',
  'Social': 'social',
  'Variety': 'variety',
  'Motion': 'motion',
  'Special': 'special',
};

const _specialCategories = {'proof', 'category', 'level'};

class _BadgesScreenState extends ConsumerState<BadgesScreen> {
  List<NuvoBadge>? _badges;
  Object? _error;
  bool _mutating = false;
  String _tab = 'All';

  int get _slots =>
      ref.read(progressionControllerProvider).valueOrNull?.featuredSlots ?? 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final badges =
          await ref.read(progressionControllerProvider.notifier).getBadges();
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

  bool _inTab(NuvoBadge b) {
    final cat = _achievementTabs[_tab];
    if (cat == null || cat.isEmpty) return true;
    if (cat == 'special') return _specialCategories.contains(b.category);
    return b.category == cat;
  }

  Future<void> _toggleFeature(NuvoBadge badge) async {
    if (_mutating || !badge.unlocked) return;
    final current = _badges ?? const <NuvoBadge>[];
    final featuredIds =
        current.where((b) => b.featured).map((b) => b.unlockId).toList();
    final next = badge.featured
        ? (featuredIds..remove(badge.unlockId))
        : [...featuredIds, badge.unlockId];
    if (!badge.featured && next.length > _slots) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You can feature up to $_slots.')),
      );
      return;
    }
    setState(() => _mutating = true);
    try {
      final badges = await ref
          .read(progressionControllerProvider.notifier)
          .setFeatured(next);
      if (!mounted) return;
      setState(() =>
          _badges = badges.where((b) => b.isAchievement).toList());
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _openDetail(NuvoBadge badge) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _AchievementDetailSheet(
        badge: badge,
        onFeature: badge.unlocked
            ? () {
                Navigator.of(context).pop();
                _toggleFeature(badge);
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final all = _badges ?? const <NuvoBadge>[];
    final badges = all.where(_inTab).toList()
      ..sort((a, b) {
        // Earned first, then nearest to done — the grid reads as momentum.
        if (a.unlocked != b.unlocked) return a.unlocked ? -1 : 1;
        if (!a.unlocked) {
          final cmp = b.goalProgress.compareTo(a.goalProgress);
          if (cmp != 0) return cmp;
        }
        return (a.threshold ?? 0).compareTo(b.threshold ?? 0);
      });
    final earned = all.where((b) => b.unlocked).length;
    final featuredCount = all.where((b) => b.featured).length;

    return Scaffold(
      backgroundColor: c.page,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          children: [
            NuvoBackHeader(
              title: 'Achievements',
              onBack: () => safePopOrGo(context, '/profile'),
            ),
            const SizedBox(height: 6),
            Text(
              'Earned by racing. Feature up to $_slots on your profile.',
              style: AppTextStyles.bodyMedium.copyWith(color: c.inkMuted),
            ),
            const SizedBox(height: 8),
            Text(
              '$earned / ${all.length} earned · $featuredCount / $_slots featured',
              style: AppTextStyles.labelSmall.copyWith(
                color: NuvoColors.blue,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: NuvoSpacing.lg),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final tab in _achievementTabs.keys) ...[
                    _TabChip(
                      label: tab,
                      selected: _tab == tab,
                      onTap: () => setState(() => _tab = tab),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: NuvoSpacing.lg),
            if (_badges == null && _error == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: NuvoColors.blue,
                  ),
                ),
              )
            else if (_badges == null)
              NuvoErrorState(
                message: "Couldn't load your achievements.",
                onRetry: _load,
              )
            else
              _BadgeGrid(badges: badges, onTap: _openDetail),
          ],
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return PressableScale(
      onTap: onTap,
      scale: 0.95,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? NuvoColors.blue : c.panelLight,
          borderRadius: BorderRadius.circular(NuvoRadii.pill),
          border: Border.all(
            color: selected ? c.inkShadow : c.border,
            width: 1.5,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: c.inkShadow,
                    offset: const Offset(2, 2),
                    blurRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: selected ? NuvoColors.white : c.inkSubtle,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _BadgeGrid extends StatelessWidget {
  const _BadgeGrid({required this.badges, this.onTap});

  final List<NuvoBadge> badges;
  final void Function(NuvoBadge badge)? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: NuvoSpacing.lg,
        crossAxisSpacing: NuvoSpacing.sm,
        childAspectRatio: 0.72,
      ),
      itemCount: badges.length,
      itemBuilder: (context, i) {
        final badge = badges[i];
        return PressableScale(
          onTap: onTap == null ? null : () => onTap!(badge),
          scale: 0.95,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: badge.unlocked ? 1 : 0.6,
                    child: NuvoAchievementBadge(badge: badge, size: 60),
                  ),
                  if (badge.featured)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: NuvoColors.blue,
                          border: Border.all(color: c.page, width: 2),
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 12,
                          color: NuvoColors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                badge.name,
                style: AppTextStyles.labelSmall.copyWith(
                  color: badge.unlocked ? c.ink : c.inkDim,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 3),
              if (!badge.unlocked && badge.goalProgress > 0)
                SizedBox(
                  width: 52,
                  child: NuvoProgressBar(
                    value: badge.goalProgress,
                    height: 4,
                    color: NuvoColors.blue,
                    trackColor: c.track,
                  ),
                )
              else
                Text(
                  badge.unlocked ? 'Earned' : 'Locked',
                  style: AppTextStyles.labelUppercase(
                    9,
                    color: badge.unlocked ? c.inkSubtle : c.inkDim,
                  ).copyWith(
                    color: badge.unlocked ? c.inkSubtle : c.inkDim,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One achievement, large — what it is, what it asked for, where you stand.
class _AchievementDetailSheet extends StatelessWidget {
  const _AchievementDetailSheet({required this.badge, this.onFeature});

  final NuvoBadge badge;
  final VoidCallback? onFeature;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
        border: Border.all(color: c.inkShadow, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: c.inkShadow,
            offset: const Offset(4, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: c.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: NuvoSpacing.lg),
          NuvoAchievementBadge(badge: badge, size: 72),
          const SizedBox(height: NuvoSpacing.md),
          Text(
            badge.name,
            style: AppTextStyles.headlineMedium.copyWith(color: c.ink),
            textAlign: TextAlign.center,
          ),
          if (badge.description != null) ...[
            const SizedBox(height: 6),
            Text(
              badge.description!,
              style: AppTextStyles.bodyMedium.copyWith(color: c.inkMuted),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: NuvoSpacing.lg),
          if (badge.unlocked)
            Text(
              badge.unlockedAt != null && badge.unlockedAt != 'demo'
                  ? 'Earned ${badge.unlockedAt!.split('T').first}'
                  : 'Earned',
              style: AppTextStyles.labelSmall.copyWith(
                color: NuvoColors.blue,
                fontWeight: FontWeight.w800,
              ),
            )
          else if (badge.threshold != null && badge.threshold! > 0)
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: NuvoProgressBar(
                        value: badge.goalProgress,
                        height: 8,
                        color: NuvoColors.blue,
                        trackColor: c.track,
                      ),
                    ),
                    const SizedBox(width: NuvoSpacing.sm),
                    Text(
                      '${badge.progressValue} / ${badge.threshold}',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: c.inkSubtle,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                if (badge.threshold! - badge.progressValue == 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'One to go.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: NuvoColors.blue,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          if (onFeature != null) ...[
            const SizedBox(height: NuvoSpacing.lg),
            NuvoPressable(
              onTap: onFeature,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: badge.featured ? c.panelLight : NuvoColors.blue,
                  borderRadius: BorderRadius.circular(NuvoRadii.md),
                  border: Border.all(color: c.inkShadow, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: c.inkShadow,
                      offset: const Offset(3, 3),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Text(
                  badge.featured ? 'Unfeature' : 'Feature on Profile',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: badge.featured ? c.ink : NuvoColors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    ).nuvoEnter();
  }
}
