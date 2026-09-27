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

/// Badge collection — everything earned plus everything still asking. Tap an
/// unlocked badge to feature it on Profile (up to 3 slots); locked badges
/// show the level they unlock at, so there's always something to race for.
class BadgesScreen extends ConsumerStatefulWidget {
  const BadgesScreen({super.key});

  @override
  ConsumerState<BadgesScreen> createState() => _BadgesScreenState();
}

class _BadgesScreenState extends ConsumerState<BadgesScreen> {
  List<NuvoBadge>? _badges;
  Object? _error;
  bool _mutating = false;

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
        _badges = badges;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _toggleFeature(NuvoBadge badge) async {
    if (_mutating || !badge.unlocked) return;
    final current = _badges ?? const <NuvoBadge>[];
    final featuredIds =
        current.where((b) => b.featured).map((b) => b.unlockId).toList();
    final next = badge.featured
        ? (featuredIds..remove(badge.unlockId))
        : [...featuredIds, badge.unlockId];
    if (!badge.featured &&
        next.length > featuredSlots) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can feature up to 3 badges.'),
        ),
      );
      return;
    }
    setState(() => _mutating = true);
    try {
      final badges = await ref
          .read(progressionControllerProvider.notifier)
          .setFeatured(next);
      if (!mounted) return;
      setState(() => _badges = badges);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final badges = _badges;
    final featuredCount = badges?.where((b) => b.featured).length ?? 0;

    return Scaffold(
      backgroundColor: c.page,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                children: [
                  NuvoBackHeader(
                    title: 'Badges',
                    onBack: () => safePopOrGo(context, '/profile'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Earned by racing. Feature up to $featuredSlots on your profile.',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: c.inkMuted),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$featuredCount of $featuredSlots featured',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: NuvoColors.blue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: NuvoSpacing.xl),
                  if (badges == null && _error == null)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: NuvoColors.blue,
                        ),
                      ),
                    )
                  else if (badges == null)
                    NuvoErrorState(
                      message: "Couldn't load your badges.",
                      onRetry: _load,
                    )
                  else
                    _BadgeGrid(
                      badges: badges,
                      onTap: _mutating ? null : _toggleFeature,
                    ),
                ],
              ),
            ),
          ],
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
        childAspectRatio: 0.78,
      ),
      itemCount: badges.length,
      itemBuilder: (context, i) {
        final badge = badges[i];
        return PressableScale(
          onTap: badge.unlocked && onTap != null
              ? () => onTap!(badge)
              : null,
          scale: 0.95,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: badge.unlocked ? 1 : 0.55,
                    child: NuvoBadgeDisc(badge: badge, size: 60),
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
              const SizedBox(height: 2),
              Text(
                badge.unlocked ? 'Level ${badge.requiredLevel}' : 'Lv ${badge.requiredLevel}',
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
