import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_back_header.dart';
import '../../../core/widgets/nuvo_error_state.dart';
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
    final cat = nuvoAchievementTabs[_tab];
    if (cat == null || cat.isEmpty) return true;
    if (cat == 'special') return nuvoSpecialCategories.contains(b.category);
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
      isScrollControlled: true,
      builder: (context) => NuvoAchievementDetailSheet(
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
          // Pushed pages reserve real breathing room below the last tile —
          // the same clearance Race Detail uses (56). On inset-less devices
          // (viewPadding.bottom == 0) this padding is the only thing
          // keeping the final row off the physical screen edge.
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 56),
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
              height: 34 * MediaQuery.textScalerOf(context).scale(1),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final tab in nuvoAchievementTabs.keys) ...[
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
              NuvoBadgeGrid(badges: badges, onTap: _openDetail),
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

