import 'dart:async';

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
import '../../../core/widgets/nuvo_icons.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../../data/models/user_profile.dart';
import '../../auth/data/auth_models.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/presentation/race_controller.dart';
import '../../crew/application/crew_controller.dart';
import '../../crew/data/crew_api.dart' show ConnectOutcome;
import '../../notifications/presentation/notification_bell.dart';
import '../../social/presentation/my_qr_sheet.dart';
import 'package:go_router/go_router.dart';

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
  List<PublicUser> get _crew => ref.read(crewControllerProvider).members;
  List<PublicUser> _results = const [];
  Set<String> _adding = {};
  bool _loading = true;
  bool _searching = false;
  String? _error;
  String? _searchError;

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
      final pass =
          await ref.read(authControllerProvider.notifier).getMemberPass();
      // Crew + requests are owned by CrewController (docs/agents/18) — it
      // auto-loads on auth and revalidates on tab focus (MainShell); this
      // screen only reads it via ref.watch in build().
      if (mounted) {
        setState(() {
          _passInfo = pass;
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
        _searchError = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
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
        if (mounted) {
          setState(() {
            _searching = false;
            _searchError = 'Search failed. Try again.';
          });
        }
      }
    });
  }

  Future<void> _addCrew(PublicUser user) async {
    setState(() => _adding = {..._adding, user.id});
    try {
      final outcome =
          await ref.read(crewControllerProvider.notifier).add(user);
      if (mounted) {
        setState(() => _adding = _adding.where((id) => id != user.id).toSet());
        if (outcome == ConnectOutcome.pending) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Request sent.')),
          );
        }
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

  Future<void> _acceptRequest(PublicUser user) async {
    try {
      await ref.read(crewControllerProvider.notifier).acceptRequest(user);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't accept the request.")),
        );
      }
    }
  }

  Future<void> _declineRequest(PublicUser user) async {
    try {
      await ref.read(crewControllerProvider.notifier).declineRequest(user);
    } catch (_) {/* best-effort */}
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
    final crewState = ref.watch(crewControllerProvider);
    final crew = crewState.members;
    final requests = crewState.requests;
    final closest = user == null ? null : _closestCrewRace(races, user.id);

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _fetch,
          child: ListView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(
              20,
              32,
              20,
              NuvoBottomNav.bottomPadding(context),
            ),
            children: [
              // ── Header ───────────────────────────────────────────────────
              _CrewHeader(
                crewCount: _crew.length,
                onShare: _sharePass,
                onCopy: _copyId,
              ),
              const SizedBox(height: 24),

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
                // ── Member pass (hero) ───────────────────────────────────
                MemberPassCard(profile: profile, compact: true, dark: true),
                const SizedBox(height: 20),

                // ── Find people ──────────────────────────────────────────
                const _SectionLabel(
                  label: 'Find people',
                  accent: NuvoColors.blue,
                ),
                const SizedBox(height: 10),
                NuvoSearchField(
                  controller: _searchController,
                  hint: 'Username or member ID',
                  searching: _searching,
                  onChanged: _onSearchChanged,
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: NuvoOutlineButton(
                      label: 'Scan a code',
                      icon: Icons.qr_code_scanner_rounded,
                      onPressed: () => context.push('/scan'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NuvoOutlineButton(
                      label: 'My code',
                      icon: Icons.qr_code_rounded,
                      onPressed: () => showMyQrSheet(
                        context,
                        displayName: profile.name.isEmpty
                            ? 'Your code'
                            : profile.name,
                        memberId: profile.memberId == '-'
                            ? null
                            : profile.memberId,
                      ),
                    ),
                  ),
                ]),
                if (_results.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _SearchResultList(
                    results: _results,
                    isCrew: _isCrew,
                    isAdding: (user) => _adding.contains(user.id),
                    onAdd: _addCrew,
                  ),
                ] else if (_searchError != null && !_searching) ...[
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => _onSearchChanged(_searchController.text),
                    child: _EmptyNote(text: _searchError!),
                  ),
                ] else if (_searchController.text.trim().length >= 2 &&
                    !_searching) ...[
                  const SizedBox(height: 16),
                  const _EmptyNote(text: 'No matching Nuvo members found.'),
                ],
                const SizedBox(height: 20),

                // ── Your crew ────────────────────────────────────────────
                if (closest != null) ...[
                  const _SectionLabel(
                    label: 'Closest race',
                    accent: NuvoColors.warning,
                  ),
                  const SizedBox(height: 10),
                  _ClosestRaceCard(closest: closest),
                  const SizedBox(height: 20),
                ],

                if (requests.isNotEmpty) ...[
                  const _SectionLabel(
                    label: 'Crew requests',
                    accent: NuvoColors.warning,
                  ),
                  const SizedBox(height: 10),
                  for (final r in requests)
                    _CrewRequestRow(
                      user: r,
                      onAccept: () => _acceptRequest(r),
                      onDecline: () => _declineRequest(r),
                    ),
                  const SizedBox(height: 20),
                ],

                _SectionLabel(
                  label: 'Your crew',
                  accent: crew.isEmpty ? NuvoColors.blue : NuvoColors.success,
                ),
                const SizedBox(height: 10),
                if (crewState.error != null && crew.isEmpty)
                  NuvoErrorState(
                    message: crewState.error!,
                    onRetry: () =>
                        ref.read(crewControllerProvider.notifier).load(force: true),
                  )
                else if (crew.isEmpty)
                  const _EmptyNote(
                    text: 'Search a username or member ID to add crew.',
                  )
                else
                  _CrewList(members: crew),
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
  const _SectionLabel({required this.label, this.accent = NuvoColors.blue});
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(NuvoRadii.pill),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTextStyles.titleMedium.copyWith(
            color: NuvoColors.navy,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ],
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
    final tied = closest.gap == 0;
    final statusColor = tied
        ? NuvoColors.warning
        : ahead
            ? NuvoColors.success
            : NuvoColors.danger;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
        border: NuvoBorders.hero,
        boxShadow: AppShadows.hardSmall,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${closest.race.displayTitle} · vs ${crewMember.displayName.split(' ').first}',
            style: AppTextStyles.labelSmall.copyWith(
              color: NuvoColors.textMuted,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                tied
                    ? "You're tied"
                    : '${closest.gap} ${closest.gap == 1 ? 'point' : 'points'} apart',
                style: AppTextStyles.titleLarge,
              ),
            ],
          ),
          const SizedBox(height: 18),
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
            style: AppTextStyles.bodySmall.copyWith(
              color: statusColor,
              fontWeight: FontWeight.w600,
            ),
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
                child: ColoredBox(
                  color: NuvoColors.trackBg,
                  child: SizedBox(height: 3),
                ),
              ),
              const Positioned(
                top: 21,
                right: -2,
                child: NuvoIcon(
                  NuvoIconType.flag,
                  size: 16,
                  color: NuvoColors.paleSlate,
                ),
              ),
              Positioned(
                left: markerLeft(themPercent),
                top: 6,
                child: _TrackAvatar(
                  initials: themInitials,
                  color: NuvoColors.avatarDustyBlue,
                ),
              ),
              Positioned(
                left: markerLeft(youPercent),
                top: 34,
                child: _TrackAvatar(
                  initials: youInitials,
                  color: NuvoColors.blue,
                ),
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
        style: AppTextStyles.labelSmall.copyWith(
          color: Colors.white,
          fontSize: 9,
        ),
      ),
    );
  }
}

class _CrewHeader extends StatelessWidget {
  const _CrewHeader({
    required this.crewCount,
    required this.onShare,
    required this.onCopy,
  });

  final int crewCount;
  final VoidCallback onShare;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          crewCount == 0
              ? 'Your start line is open'
              : '$crewCount ${crewCount == 1 ? 'person' : 'people'} in your crew',
          style: AppTextStyles.labelMedium.copyWith(
            color: crewCount == 0 ? NuvoColors.muted : NuvoColors.successOn,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text('Crew', style: AppTextStyles.screenTitle),
            const Spacer(),
            const NotificationBell(),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Your crew for races.',
          style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
        ),
        const SizedBox(height: NuvoSpacing.md),
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
            NuvoGhostButton(
              label: 'Copy ID',
              icon: Icons.copy_rounded,
              small: true,
              onPressed: onCopy,
            ),
          ],
        ),
      ],
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
    this.onTap,
    this.isLast = false,
  });

  final PublicUser user;
  final bool added;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onPressed;
  final VoidCallback? onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: NuvoColors.navy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.handleLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                            color: NuvoColors.textMuted,
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
        ),
        if (!isLast)
          Divider(
            height: 1,
            color: NuvoColors.border.withValues(alpha: 0.7),
            indent: NuvoAvatarSizes.md + 12,
          ),
      ],
    );
  }
}

// ── Crew list ─────────────────────────────────────────────────────────────────

class _CrewList extends StatelessWidget {
  const _CrewList({required this.members});

  final List<PublicUser> members;

  @override
  Widget build(BuildContext context) {
    return _PeopleSurface(
      children: [
        for (var i = 0; i < members.length; i++)
          _UserRow(
            user: members[i],
            isLast: i == members.length - 1,
            onTap: () => context.push('/u/${members[i].id}'),
          ),
      ],
    );
  }
}

class _CrewRequestRow extends StatelessWidget {
  const _CrewRequestRow({
    required this.user,
    required this.onAccept,
    required this.onDecline,
  });

  final PublicUser user;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Row(children: [
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
              Text(user.displayName,
                  style: AppTextStyles.bodyMedium.copyWith(
                      color: NuvoColors.navy, fontWeight: FontWeight.w700)),
              Text('wants to connect',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: NuvoColors.textMuted)),
            ],
          ),
        ),
        IconButton(
          onPressed: onDecline,
          icon: const Icon(Icons.close_rounded),
          color: NuvoColors.textMuted,
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 4),
        NuvoPrimaryButton(label: 'Accept', small: true, onPressed: onAccept),
      ]),
    );
  }
}

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
    return _PeopleSurface(
      children: [
        for (var i = 0; i < results.length; i++)
          _UserRow(
            user: results[i],
            added: isCrew(results[i]),
            loading: isAdding(results[i]),
            actionLabel: isCrew(results[i]) ? 'In crew' : 'Add',
            onPressed: isCrew(results[i]) || isAdding(results[i])
                ? null
                : () => onAdd(results[i]),
            isLast: i == results.length - 1,
          ),
      ],
    );
  }
}

class _PeopleSurface extends StatelessWidget {
  const _PeopleSurface({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // Directories stay on the page surface. Grouping comes from section
    // spacing and inset rules, not another rounded card around every row.
    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
        border: NuvoBorders.hero,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(NuvoRadii.lg - 2),
        child: Column(children: children),
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
    return Text(
      text,
      style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
    );
  }
}
