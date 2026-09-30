import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/demo/presentation_demo.dart';
import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_back_header.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../profile/data/progression_models.dart' show NuvoBadge;
import '../../profile/presentation/widgets/nuvo_badges.dart';
import '../application/crew_controller.dart';
import '../data/crew_api.dart';

/// `/u/:id/badges` — another member's earned collection. The public contract
/// only ever carries earned achievements, so there is nothing locked to
/// reveal and no feature action — this is a read-only collection.
class PublicBadgesScreen extends ConsumerStatefulWidget {
  const PublicBadgesScreen({super.key, required this.userId, this.card});

  final String userId;

  /// Card pushed from the person profile — avoids a second fetch when the
  /// earned list already arrived with it.
  final PublicProfileCard? card;

  @override
  ConsumerState<PublicBadgesScreen> createState() => _State();
}

class _State extends ConsumerState<PublicBadgesScreen> {
  PublicProfileCard? _card;
  Object? _error;
  String _tab = 'All';

  @override
  void initState() {
    super.initState();
    _card = widget.card;
    if (_card == null || _card!.earned.isEmpty) _load();
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
      final card = await ref.read(crewRepositoryProvider).getUser(widget.userId);
      if (mounted) setState(() => _card = card);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  bool _inTab(NuvoBadge b) {
    final cat = nuvoAchievementTabs[_tab];
    if (cat == null || cat.isEmpty) return true;
    if (cat == 'special') return nuvoSpecialCategories.contains(b.category);
    return b.category == cat;
  }

  Future<void> _openDetail(NuvoBadge badge) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => NuvoAchievementDetailSheet(badge: badge),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final card = _card;
    final earned = (card?.earned ?? const <NuvoBadge>[])
        .where(_inTab)
        .toList();
    final usedTabs = nuvoAchievementTabs.keys.where((tab) {
      final cat = nuvoAchievementTabs[tab];
      if (cat == null || cat.isEmpty) return true;
      return (card?.earned ?? const <NuvoBadge>[]).any((b) =>
          cat == 'special'
              ? nuvoSpecialCategories.contains(b.category)
              : b.category == cat);
    }).toList();

    return Scaffold(
      backgroundColor: c.page,
      body: SafeArea(
        child: ListView(
          // Same pushed-page clearance as the self collection — the last
          // row rests visibly above the edge even without a bottom inset.
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 56),
          children: [
            NuvoBackHeader(
              title: 'Achievements',
              onBack: () => safePopOrGo(context, '/u/${widget.userId}'),
            ),
            const SizedBox(height: 6),
            Text(
              card != null
                  ? '${card.displayName.split(' ').first} earned these racing.'
                  : 'Earned by racing.',
              style: AppTextStyles.bodyMedium.copyWith(color: c.inkMuted),
            ),
            const SizedBox(height: 8),
            Text(
              '${card?.earned.length ?? 0} / ${card?.achievementsTotal ?? '?'} earned',
              style: AppTextStyles.labelSmall.copyWith(
                color: NuvoColors.blue,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: NuvoSpacing.lg),
            if (usedTabs.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: NuvoSpacing.lg),
                child: SizedBox(
                  height:
                      34 * MediaQuery.textScalerOf(context).scale(1),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final tab in usedTabs) ...[
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
              ),
            if (card == null && _error == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: NuvoColors.blue,
                  ),
                ),
              )
            else if (card == null)
              NuvoErrorState(
                message: "Couldn't load their achievements.",
                onRetry: _load,
              )
            else if (earned.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  _tab == 'All'
                      ? 'No achievements earned yet.'
                      : 'Nothing earned here yet.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(color: c.inkMuted),
                ),
              )
            else
              NuvoBadgeGrid(badges: earned, onTap: _openDetail),
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
