import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/member_pass_card.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../../data/models/user_profile.dart';
import '../../auth/data/auth_models.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/presentation/race_controller.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CREW — Light-Mode "Living Network"
// Bright, energetic social movement experience with connection visuals.
// ═══════════════════════════════════════════════════════════════════════════════

class _ClosestRace {
  const _ClosestRace({
    required this.race,
    required this.me,
    required this.crewMember,
    required this.gap,
  });
  final Race race;
  final RaceParticipant me;
  final RaceParticipant crewMember;
  final int gap;
}

class PassScreen extends ConsumerStatefulWidget {
  const PassScreen({super.key});

  @override
  ConsumerState<PassScreen> createState() => _PassScreenState();
}

class _PassScreenState extends ConsumerState<PassScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  PassInfo? _passInfo;
  List<PublicUser> _crew = const [];
  List<PublicUser> _results = const [];
  Set<String> _adding = {};
  bool _loading = true;
  bool _searching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final passFuture = ref
          .read(authControllerProvider.notifier)
          .getMemberPass();
      final crewFuture = ref.read(raceControllerProvider.notifier).getCrew();
      final pass = await passFuture;
      final crew = await crewFuture;
      if (mounted) {
        setState(() {
          _passInfo = pass;
          _crew = crew;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load your crew.';
          _loading = false;
        });
      }
    }
  }

  UserProfile _buildProfile(AuthUser? user) {
    return UserProfile(
      name: user?.fullName ?? user?.email ?? '',
      username: user?.username ?? '',
      memberId: _passInfo?.memberId ?? '-',
      passSlug: _passInfo?.passSlug,
    );
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      try {
        final results = await ref
            .read(raceControllerProvider.notifier)
            .searchUsers(query);
        if (mounted) {
          setState(() {
            _results = results;
            _searching = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _addCrew(PublicUser user) async {
    setState(() => _adding = {..._adding, user.id});
    try {
      await ref.read(raceControllerProvider.notifier).addCrewUser(user.id);
      final crew = await ref.read(raceControllerProvider.notifier).getCrew();
      if (mounted) {
        setState(() {
          _crew = crew;
          _adding = _adding.where((id) => id != user.id).toSet();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _adding = _adding.where((id) => id != user.id).toSet());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not add this crew member.')),
        );
      }
    }
  }

  bool _isCrew(PublicUser user) => _crew.any((m) => m.id == user.id);

  void _sharePass() {
    final passInfo = _passInfo;
    if (passInfo == null) return;
    Share.share(passInfo.shareUrl);
  }

  Future<void> _copyId() async {
    final passInfo = _passInfo;
    if (passInfo == null) return;
    await Clipboard.setData(ClipboardData(text: passInfo.memberId));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Member ID copied.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  _ClosestRace? _closestCrewRace(List<Race> races, String userId) {
    final crewIds = _crew.map((c) => c.id).toSet();
    _ClosestRace? best;
    for (final race in races) {
      if (race.status != 'active') continue;
      final me = race.participantFor(userId);
      if (me == null) continue;
      for (final p in race.participants) {
        if (p.userId == userId || !crewIds.contains(p.userId)) continue;
        final gap = (me.progressPercent - p.progressPercent).abs();
        if (best == null || gap < best.gap) {
          best = _ClosestRace(race: race, me: me, crewMember: p, gap: gap);
        }
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final profile = _buildProfile(user);
    final races = ref.watch(raceControllerProvider).races;
    final closest = user == null ? null : _closestCrewRace(races, user.id);
    final safeTop = MediaQuery.viewPaddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: NuvoColors.page,
        body: RefreshIndicator(
          onRefresh: _fetch,
          color: NuvoColors.blue,
          backgroundColor: NuvoColors.surface,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: NuvoBottomNav.bottomPadding(context),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Header ──────────────────────────────────
                      _CrewHeader(
                        safeTop: safeTop,
                        crewCount: _crew.length,
                        onShare: _sharePass,
                        onCopy: _copyId,
                      ),

                      // ── Constellation ─────────────────────────────
                      if (!_loading && _crew.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          child: _MovementConstellation(
                            crewCount: _crew.length,
                            memberInitials: _crew
                                .take(6)
                                .map((u) => u.initials)
                                .toList(),
                          ),
                        ),

                      // ── Content ─────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _loading
                            ? const _LoadingState()
                            : _error != null
                                ? NuvoErrorState(
                                    message: _error!,
                                    onRetry: _fetch,
                                  )
                                : _crewContent(profile, closest),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _crewContent(UserProfile profile, _ClosestRace? closest) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Member pass
        MemberPassCard(profile: profile, compact: true, dark: false),
        const SizedBox(height: 24),

        // Find people
        _SectionLabel(title: 'Find people'),
        const SizedBox(height: 12),
        NuvoSearchField(
          controller: _searchController,
          hint: 'Username or member ID',
          searching: _searching,
          onChanged: _onSearchChanged,
        ),
        if (_results.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SearchResultList(
            results: _results,
            isCrew: _isCrew,
            isAdding: (user) => _adding.contains(user.id),
            onAdd: _addCrew,
          ),
        ] else if (_searchController.text.trim().length >= 2 &&
            !_searching) ...[
          const SizedBox(height: 16),
          Text(
            'No matching Nuvo members found.',
            style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.textMuted),
          ),
        ],
        const SizedBox(height: 24),

        // Closest race
        if (closest != null) ...[
          _SectionLabel(title: 'Closest race'),
          const SizedBox(height: 12),
          _ClosestRaceCard(closest: closest),
          const SizedBox(height: 24),
        ],

        // Your crew
        _SectionLabel(title: 'Your crew'),
        const SizedBox(height: 12),
        if (_crew.isEmpty)
          _EmptyCrewState()
        else
          _CrewGrid(members: _crew),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HEADER
// ═══════════════════════════════════════════════════════════════════════════════

class _CrewHeader extends StatelessWidget {
  const _CrewHeader({
    required this.safeTop,
    required this.crewCount,
    required this.onShare,
    required this.onCopy,
  });
  final double safeTop;
  final int crewCount;
  final VoidCallback onShare;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(22, safeTop + 14, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'NUVO',
                style: AppTextStyles.labelSmall.copyWith(
                  color: NuvoColors.blue,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  fontSize: 10,
                ),
              ),
              const Spacer(),
              if (crewCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: NuvoColors.blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(NuvoRadii.pill),
                    border: Border.all(
                      color: NuvoColors.blue.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Text(
                    '$crewCount in crew',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: NuvoColors.blue,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Crew',
            style: AppTextStyles.screenTitle.copyWith(
              color: NuvoColors.navy,
              fontSize: 34,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'The people you race with.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: NuvoColors.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          // Actions
          Row(
            children: [
              Expanded(
                child: NuvoPrimaryButton(
                  label: 'Share pass',
                  icon: Icons.ios_share_rounded,
                  expand: true,
                  small: true,
                  onPressed: onShare,
                ),
              ),
              const SizedBox(width: 10),
              NuvoOutlineButton(
                label: 'Copy ID',
                icon: Icons.copy_rounded,
                small: true,
                onPressed: onCopy,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION LABEL
// ═══════════════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: NuvoColors.blue,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title.toUpperCase(),
          style: AppTextStyles.labelSmall.copyWith(
            color: NuvoColors.textMuted,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CLOSEST RACE CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _ClosestRaceCard extends StatelessWidget {
  const _ClosestRaceCard({required this.closest});
  final _ClosestRace closest;

  @override
  Widget build(BuildContext context) {
    final me = closest.me;
    final crewMember = closest.crewMember;
    final ahead = me.progressPercent >= crewMember.progressPercent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NuvoColors.border, width: 1),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: NuvoColors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.leaderboard_rounded,
                  color: NuvoColors.amber,
                  size: 14,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${closest.race.displayTitle} · vs ${crewMember.displayName.split(' ').first}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            closest.gap == 0
                ? "You're tied"
                : '${closest.gap} ${closest.gap == 1 ? 'point' : 'points'} apart',
            style: AppTextStyles.titleLarge.copyWith(color: NuvoColors.navy),
          ),
          const SizedBox(height: 14),
          // Progress comparison
          _ComparisonBar(
            youPercent: me.progressPercent,
            themPercent: crewMember.progressPercent,
            themName: crewMember.displayName.split(' ').first,
          ),
          const SizedBox(height: 8),
          Text(
            ahead
                ? "You're ahead in this race."
                : '${crewMember.displayName.split(' ').first} is ahead.',
            style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _ComparisonBar extends StatelessWidget {
  const _ComparisonBar({
    required this.youPercent,
    required this.themPercent,
    required this.themName,
  });
  final int youPercent;
  final int themPercent;
  final String themName;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Text('You', style: AppTextStyles.labelSmall.copyWith(
              color: NuvoColors.blue,
              fontWeight: FontWeight.w800,
            )),
            const Spacer(),
            Text('$youPercent%', style: AppTextStyles.labelSmall.copyWith(
              color: NuvoColors.navy,
              fontWeight: FontWeight.w800,
            )),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: (youPercent / 100).clamp(0.0, 1.0),
            minHeight: 5,
            backgroundColor: NuvoColors.trackBg,
            valueColor: const AlwaysStoppedAnimation(NuvoColors.blue),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(themName, style: AppTextStyles.labelSmall.copyWith(
              color: NuvoColors.avatarDustyBlue,
              fontWeight: FontWeight.w800,
            )),
            const Spacer(),
            Text('$themPercent%', style: AppTextStyles.labelSmall.copyWith(
              color: NuvoColors.navy,
              fontWeight: FontWeight.w800,
            )),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: (themPercent / 100).clamp(0.0, 1.0),
            minHeight: 5,
            backgroundColor: NuvoColors.trackBg,
            valueColor: const AlwaysStoppedAnimation(NuvoColors.avatarDustyBlue),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CREW GRID — Signature component (constellation layout)
// ═══════════════════════════════════════════════════════════════════════════════

class _CrewGrid extends StatelessWidget {
  const _CrewGrid({required this.members});
  final List<PublicUser> members;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NuvoColors.border, width: 1),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < members.length; i++) ...[
            _CrewMemberRow(user: members[i], isLast: i == members.length - 1),
            if (i < members.length - 1)
              Divider(
                height: 1,
                color: NuvoColors.divider,
                indent: NuvoAvatarSizes.md + 26,
              ),
          ],
        ],
      ),
    );
  }
}

class _CrewMemberRow extends StatelessWidget {
  const _CrewMemberRow({required this.user, this.isLast = false});
  final PublicUser user;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          NuvoAvatar(
            initials: user.initials,
            photoUrl: user.profilePhotoUrl,
            size: NuvoAvatarSizes.md,
            bgColor: nuvoAvatarColorFor(user.id),
            textColor: NuvoColors.white,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: NuvoColors.navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user.handleLine,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: NuvoColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(NuvoRadii.pill),
            ),
            child: Text(
              'In crew',
              style: AppTextStyles.labelSmall.copyWith(
                color: NuvoColors.success,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SEARCH RESULTS
// ═══════════════════════════════════════════════════════════════════════════════

class _SearchResultList extends StatelessWidget {
  const _SearchResultList({
    required this.results,
    required this.isCrew,
    required this.isAdding,
    required this.onAdd,
  });
  final List<PublicUser> results;
  final bool Function(PublicUser user) isCrew;
  final bool Function(PublicUser user) isAdding;
  final ValueChanged<PublicUser> onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NuvoColors.border, width: 1),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < results.length; i++) ...[
            _SearchRow(
              user: results[i],
              added: isCrew(results[i]),
              loading: isAdding(results[i]),
              onAdd: isCrew(results[i]) || isAdding(results[i])
                  ? null
                  : () => onAdd(results[i]),
            ),
            if (i < results.length - 1)
              Divider(
                height: 1,
                color: NuvoColors.divider,
                indent: NuvoAvatarSizes.md + 26,
              ),
          ],
        ],
      ),
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({
    required this.user,
    required this.added,
    required this.loading,
    this.onAdd,
  });
  final PublicUser user;
  final bool added;
  final bool loading;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          NuvoAvatar(
            initials: user.initials,
            photoUrl: user.profilePhotoUrl,
            size: NuvoAvatarSizes.md,
            bgColor: nuvoAvatarColorFor(user.id),
            textColor: NuvoColors.white,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: NuvoColors.navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user.handleLine,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (added)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: NuvoColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(NuvoRadii.pill),
              ),
              child: Text(
                'In crew',
                style: AppTextStyles.labelSmall.copyWith(
                  color: NuvoColors.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            SizedBox(
              width: 72,
              child: NuvoOutlineButton(
                label: loading ? '...' : 'Add',
                small: true,
                onPressed: loading ? null : onAdd,
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STATES
// ═══════════════════════════════════════════════════════════════════════════════

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: NuvoColors.blue,
        ),
      ),
    );
  }
}

class _EmptyCrewState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NuvoColors.border, width: 1),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: NuvoColors.blue.withValues(alpha: 0.06),
              shape: BoxShape.circle,
              border: Border.all(
                color: NuvoColors.blue.withValues(alpha: 0.15),
                width: 1.5,
              ),
            ),
            child: const Icon(
              Icons.group_add_rounded,
              color: NuvoColors.blue,
              size: 24,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No crew members yet',
            style: AppTextStyles.titleMedium.copyWith(
              color: NuvoColors.navy,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Search by username or member ID\nto add people to your crew.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: NuvoColors.textMuted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MOVEMENT CONSTELLATION — Signature component
// Connected portraits with blue path lines radiating from center.
// ═══════════════════════════════════════════════════════════════════════════════

class _MovementConstellation extends StatelessWidget {
  const _MovementConstellation({
    required this.crewCount,
    required this.memberInitials,
  });
  final int crewCount;
  final List<String> memberInitials;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NuvoColors.border, width: 1),
        boxShadow: AppShadows.card,
      ),
      child: CustomPaint(
        painter: _ConstellationPainter(
          nodeCount: memberInitials.length.clamp(0, 6),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: NuvoColors.blue,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: NuvoColors.blue.withValues(alpha: 0.3),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$crewCount connected',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: NuvoColors.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Your movement network',
                style: AppTextStyles.bodySmall.copyWith(
                  color: NuvoColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints the constellation: a central node with radial connection paths
/// to outer nodes, mimicking Arena's orbital geometry on a light surface.
class _ConstellationPainter extends CustomPainter {
  _ConstellationPainter({required this.nodeCount});
  final int nodeCount;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const orbitRadius = 44.0;

    // Draw orbital ring (faint)
    canvas.drawCircle(
      center,
      orbitRadius,
      Paint()
        ..color = NuvoColors.blue.withValues(alpha: 0.05)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Second orbit ring
    canvas.drawCircle(
      center,
      orbitRadius + 14,
      Paint()
        ..color = const Color(0xFFE8ECF2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );

    // Central node
    canvas.drawCircle(
      center, 5,
      Paint()..color = NuvoColors.blue.withValues(alpha: 0.12),
    );
    canvas.drawCircle(center, 3, Paint()..color = NuvoColors.blue);

    // Draw connection paths and outer nodes
    for (var i = 0; i < nodeCount; i++) {
      final angle = (i / nodeCount) * 2 * math.pi - math.pi / 2;
      final nodeX = center.dx + orbitRadius * math.cos(angle);
      final nodeY = center.dy + orbitRadius * math.sin(angle);
      final node = Offset(nodeX, nodeY);

      // Connection line (trajectory path)
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(nodeX, nodeY);
      canvas.drawPath(
        path,
        Paint()
          ..color = NuvoColors.blue.withValues(alpha: 0.08)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
      );

      // Outer node glow
      canvas.drawCircle(
        node, 9,
        Paint()..color = NuvoColors.blue.withValues(alpha: 0.04),
      );
      // Outer node
      canvas.drawCircle(node, 5, Paint()..color = const Color(0xFFDDE3EB));
      canvas.drawCircle(node, 3, Paint()..color = const Color(0xFFA8B5C5));
    }

    // Trajectory arcs between adjacent nodes (subtle)
    if (nodeCount >= 3) {
      for (var i = 0; i < nodeCount; i++) {
        final angle1 = (i / nodeCount) * 2 * math.pi - math.pi / 2;
        final angle2 = ((i + 1) % nodeCount / nodeCount) * 2 * math.pi - math.pi / 2;
        final p1 = Offset(
          center.dx + orbitRadius * math.cos(angle1),
          center.dy + orbitRadius * math.sin(angle1),
        );
        final p2 = Offset(
          center.dx + orbitRadius * math.cos(angle2),
          center.dy + orbitRadius * math.sin(angle2),
        );
        canvas.drawLine(
          p1, p2,
          Paint()
            ..color = const Color(0xFFE2E7EE)
            ..strokeWidth = 0.5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ConstellationPainter old) => old.nodeCount != nodeCount;
}
