import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/member_pass_card.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_icons.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../data/models/user_profile.dart';
import '../../auth/data/auth_models.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/presentation/race_controller.dart';

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

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _fetch,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
            children: [
              // ── Header ───────────────────────────────────────────────────
              _CrewHero(
                crewCount: _crew.length,
                onShare: _sharePass,
                onCopy: _copyId,
              ),
              const SizedBox(height: 26),

              // ── Loading ──────────────────────────────────────────────────
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              // ── Error ────────────────────────────────────────────────────
              else if (_error != null)
                NuvoErrorState(message: _error!, onRetry: _fetch)
              // ── Content ──────────────────────────────────────────────────
              else ...[
                // ── Member pass ──────────────────────────────────────────
                const _SectionLabel(label: 'Member pass'),
                const SizedBox(height: 12),
                MemberPassCard(profile: profile, compact: true, dark: true),
                const SizedBox(height: 28),

                if (closest != null) ...[
                  const _SectionLabel(label: 'Closest race'),
                  const SizedBox(height: 12),
                  _ClosestRaceCard(closest: closest),
                  const SizedBox(height: 28),
                ],

                // ── Find people ──────────────────────────────────────────
                const _SectionLabel(label: 'Find people'),
                const SizedBox(height: 12),
                _SearchField(
                  controller: _searchController,
                  searching: _searching,
                  onChanged: _onSearchChanged,
                ),
                if (_results.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final result in _results)
                    _UserRow(
                      user: result,
                      added: _isCrew(result),
                      loading: _adding.contains(result.id),
                      actionLabel: _isCrew(result) ? 'In crew' : 'Add',
                      onPressed: _isCrew(result) || _adding.contains(result.id)
                          ? null
                          : () => _addCrew(result),
                    ),
                ] else if (_searchController.text.trim().length >= 2 &&
                    !_searching) ...[
                  const SizedBox(height: 12),
                  const _EmptyNote(text: 'No matching Nuvo members found.'),
                ],
                const SizedBox(height: 28),

                // ── Your crew ────────────────────────────────────────────
                const _SectionLabel(label: 'Your crew'),
                const SizedBox(height: 12),
                if (_crew.isEmpty)
                  const _EmptyNote(
                    text: 'Search a username or member ID to add crew.',
                  )
                else
                  for (final member in _crew)
                    _UserRow(user: member, added: true, actionLabel: 'In crew'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: AppTextStyles.labelMedium.copyWith(
        color: NuvoColors.textMuted,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
    );
  }
}

// ── Closest race card ─────────────────────────────────────────────────────────

class _ClosestRaceCard extends StatelessWidget {
  const _ClosestRaceCard({required this.closest});
  final _ClosestRace closest;

  @override
  Widget build(BuildContext context) {
    final me = closest.me;
    final crewMember = closest.crewMember;
    final ahead = me.progressPercent >= crewMember.progressPercent;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A2C6D).withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${closest.race.displayTitle} · vs ${crewMember.displayName.split(' ').first}',
            style: AppTextStyles.labelSmall.copyWith(color: NuvoColors.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            closest.gap == 0
                ? "You're tied"
                : '${closest.gap} ${closest.gap == 1 ? 'point' : 'points'} apart',
            style: AppTextStyles.titleLarge,
          ),
          const SizedBox(height: 26),
          _ComparisonTrack(
            youPercent: me.progressPercent,
            themPercent: crewMember.progressPercent,
            youInitials: _initials2('You'),
            themInitials: _initials2(crewMember.displayName),
          ),
          const SizedBox(height: 10),
          Text(
            ahead
                ? "You're ahead in this race."
                : '${crewMember.displayName.split(' ').first} is ahead in this race.',
            style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
          ),
        ],
      ),
    );
  }
}

String _initials2(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  final s = name.trim();
  return s.isEmpty ? '?' : s[0].toUpperCase();
}

class _ComparisonTrack extends StatelessWidget {
  const _ComparisonTrack({
    required this.youPercent,
    required this.themPercent,
    required this.youInitials,
    required this.themInitials,
  });

  final int youPercent;
  final int themPercent;
  final String youInitials;
  final String themInitials;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackWidth = constraints.maxWidth - 28;
          double markerLeft(int percent) =>
              (trackWidth * (percent / 100).clamp(0.0, 1.0));

          return Stack(
            clipBehavior: Clip.none,
            children: [
              const Positioned(
                top: 28,
                left: 0,
                right: 28,
                child: ColoredBox(color: NuvoColors.trackBg, child: SizedBox(height: 3)),
              ),
              const Positioned(
                top: 21,
                right: -2,
                child: NuvoIcon(NuvoIconType.flag, size: 16, color: NuvoColors.paleSlate),
              ),
              Positioned(
                left: markerLeft(themPercent),
                top: 6,
                child: _TrackAvatar(initials: themInitials, color: NuvoColors.avatarDustyBlue),
              ),
              Positioned(
                left: markerLeft(youPercent),
                top: 34,
                child: _TrackAvatar(initials: youInitials, color: NuvoColors.blue),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TrackAvatar extends StatelessWidget {
  const _TrackAvatar({required this.initials, required this.color});
  final String initials;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: NuvoColors.surface, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: AppTextStyles.labelSmall.copyWith(color: Colors.white, fontSize: 9),
      ),
    );
  }
}

class _CrewHero extends StatelessWidget {
  const _CrewHero({
    required this.crewCount,
    required this.onShare,
    required this.onCopy,
  });

  final int crewCount;
  final VoidCallback onShare;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A2C6D),
            Color(0xFF2A4C9B),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Crew hub',
                      style: AppTextStyles.headlineLarge.copyWith(
                        color: NuvoColors.white,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Share your pass, copy your ID, pull people into your next race.',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: NuvoColors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: NuvoColors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$crewCount in crew',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _QuickActionButton(
                  icon: Icons.ios_share_rounded,
                  label: 'Share pass',
                  onTap: onShare,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickActionButton(
                  icon: Icons.copy_rounded,
                  label: 'Copy ID',
                  onTap: onCopy,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Quick action button ───────────────────────────────────────────────────────

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: NuvoColors.navy, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTextStyles.labelMedium.copyWith(
                color: NuvoColors.navy,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Search field ──────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.searching,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool searching;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.navy),
      decoration: InputDecoration(
        hintText: 'Username or member ID',
        hintStyle: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
        filled: true,
        fillColor: NuvoColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: NuvoColors.muted,
          size: 20,
        ),
        suffixIcon: searching
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
        suffixIconConstraints: const BoxConstraints(),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: NuvoColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: NuvoColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: NuvoColors.blue, width: 1.6),
        ),
      ),
    );
  }
}

// ── User row ──────────────────────────────────────────────────────────────────

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    this.added = false,
    this.loading = false,
    this.actionLabel,
    this.onPressed,
  });

  final PublicUser user;
  final bool added;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1A2C6D).withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: NuvoColors.blue,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                user.initials,
                style: AppTextStyles.labelMedium.copyWith(
                  color: NuvoColors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.displayName, style: AppTextStyles.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    user.handleLine,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (actionLabel != null)
              added
                  ? Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        actionLabel!,
                        style: AppTextStyles.labelMedium.copyWith(
                          color: NuvoColors.muted,
                        ),
                      ),
                    )
                  : SizedBox(
                      width: 72,
                      child: NuvoOutlineButton(
                        label: loading ? '...' : actionLabel!,
                        small: true,
                        onPressed: loading ? null : onPressed,
                      ),
                    ),
          ],
        ),
      ),
    );
  }
}

// ── Empty note ────────────────────────────────────────────────────────────────

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: NuvoColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NuvoColors.divider),
      ),
      child: Text(
        text,
        style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
      ),
    );
  }
}
