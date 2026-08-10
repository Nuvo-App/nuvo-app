import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_board_components.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_icons.dart';
import '../../../core/widgets/nuvo_move_log_item.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/chase_context.dart';
import '../../races/domain/camera_verification_resolver.dart';
import '../../races/domain/race_display.dart';
import '../../races/presentation/race_controller.dart';

// ── Screen ────────────────────────────────────────────────────────────────────

class RaceDetailScreen extends ConsumerStatefulWidget {
  const RaceDetailScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<RaceDetailScreen> createState() => _RaceDetailScreenState();
}

class _RaceDetailScreenState extends ConsumerState<RaceDetailScreen> {
  Race? _race;
  bool _loading = true;
  bool _busy = false;
  bool _navigating = false;
  String? _error;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _silentRefresh(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _silentRefresh() async {
    if (_loading) return;
    try {
      final race = await ref
          .read(raceControllerProvider.notifier)
          .getRaceDetail(widget.id);
      if (mounted) setState(() => _race = race);
    } catch (e) {
      // Background refresh failed — preserve the already-loaded race on
      // screen and log diagnostics. We intentionally do NOT clear _race or
      // surface a disruptive error here; the periodic timer keeps running.
      debugPrint('RACE_DETAIL_REFRESH_ERROR: ${e.runtimeType}: $e');
    }
  }

  Future<void> _load() async {
    // Use cached race from controller first to prevent stale 0% flash
    final cachedRaces = ref.read(raceControllerProvider).races;
    final cached = cachedRaces.where((r) => r.id == widget.id).firstOrNull;
    if (cached != null && _race == null) {
      setState(() {
        _race = cached;
        _loading = false;
      });
      // Still refresh from network in the background
      _silentRefresh();
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final race = await ref
          .read(raceControllerProvider.notifier)
          .getRaceDetail(widget.id);
      if (mounted) {
        setState(() {
          _race = race;
          _loading = false;
        });
        debugLogCameraVerificationDecision(
          race,
          resolveCameraVerification(race),
          routeAction: 'race_detail_loaded',
        );
      }
    } catch (e, stack) {
      debugPrint('RACE_DETAIL_LOAD_ERROR: ${e.runtimeType}: $e');
      debugPrint('RACE_DETAIL_LOAD_STACK: $stack');
      if (mounted) {
        setState(() {
          _race = null;
          _error = 'Could not load race.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _copyInviteCode() async {
    final race = _race;
    if (race == null) return;
    var code = race.inviteCode;
    if (code == null &&
        race.creatorId == ref.read(authControllerProvider).user?.id) {
      setState(() => _busy = true);
      try {
        code = await ref
            .read(raceControllerProvider.notifier)
            .createInviteCode(race.id);
        final fresh = await ref
            .read(raceControllerProvider.notifier)
            .getRaceDetail(race.id);
        if (mounted) setState(() => _race = fresh);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not create invite code.')),
          );
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    if (code == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ask the race creator for an invite code.'),
        ),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invite code copied.')));
    }
  }

  Future<void> _joinRace() async {
    final race = _race;
    if (race == null) return;
    setState(() => _busy = true);
    try {
      final joined = await ref
          .read(raceControllerProvider.notifier)
          .joinRace(race.id);
      if (mounted) {
        setState(() {
          _race = joined;
          _busy = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyApiError(e, 'join this race'))),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not join this race.')),
        );
      }
    }
  }

  Future<void> _leaveRace() async {
    final race = _race;
    if (race == null) return;
    final confirmed = await _confirm(
      title: 'Leave race?',
      message:
          'You will leave this leaderboard. You can rejoin later with an invite code.',
      confirmLabel: 'Leave',
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      await ref.read(raceControllerProvider.notifier).leaveRace(race.id);
      if (mounted) context.go('/arena');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyApiError(e, 'leave this race'))),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not leave this race.')),
        );
      }
    }
  }

  /// Maps an [ApiException] to a concise user-facing message. Technical
  /// details are logged via [debugPrint] but never shown to the user.
  String _friendlyApiError(ApiException e, String action) {
    debugPrint('RACE_DETAIL_API_ERROR: ${e.statusCode} ${e.message}');
    if (e.statusCode >= 500) {
      return 'Nuvo hit a snag. Try again.';
    }
    if (e.statusCode == 401 || e.statusCode == 403) {
      return 'You may need to sign in again.';
    }
    if (e.statusCode == 404) {
      return 'This race could not be found.';
    }
    if (e.statusCode == 409) {
      return 'That action is not available right now.';
    }
    return 'Could not $action. Try again.';
  }

  Future<void> _goToInviteCrew(String raceId) async {
    if (_navigating) return;
    setState(() => _navigating = true);
    try {
      await context.push('/race/$raceId/invite');
    } finally {
      if (mounted) setState(() => _navigating = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    return NuvoConfirmSheet.show(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: NuvoColors.page,
        body: Center(
          child: CircularProgressIndicator(
            color: NuvoColors.blue,
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (_race == null) {
      return Scaffold(
        backgroundColor: NuvoColors.page,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: NuvoBackButton(
                  onPressed: () => safePopOrGo(context, '/arena'),
                ),
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error ?? 'Race not found.',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: NuvoColors.muted,
                        ),
                      ),
                      const SizedBox(height: 16),
                      NuvoGhostButton(
                        label: 'Retry',
                        onPressed: _load,
                        small: true,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final race = _race!;
    final user = ref.watch(authControllerProvider).user;
    final isOwner = user != null && race.isCreator(user.id);
    final isParticipant = user != null && race.isParticipant(user.id);
    final eligibility = resolveCameraVerification(race);
    final canVerify =
        raceIsActive(race) &&
        (isOwner || isParticipant) &&
        eligibility.isCameraVerifiable;
    final canJoin = raceIsActive(race) && !isOwner && !isParticipant;
    final myPart = isParticipant ? race.participantFor(user.id) : null;
    final myProgress = raceProgressPercent(race, myPart);
    final myRaceComplete = raceIsCompleted(race);

    final sorted = serverRankedParticipants(race);
    final chase = user == null ? null : ChaseContext.compute(race, user.id);
    final rank = rankForUser(race, user?.id);
    final heroChaseCopy = myRaceComplete
        ? (rank != null
              ? 'Finish line crossed · you placed #$rank.'
              : 'Finish line crossed.')
        : chase?.chaseCopy;
    final heroAvatars = sorted
        .map(
          (p) =>
              (initials: _initials(p.displayName), photoUrl: p.profilePhotoUrl),
        )
        .toList();
    final movementAvatars = race.recentProofs
        .map(
          (p) =>
              (initials: _initials(p.displayName), photoUrl: p.profilePhotoUrl),
        )
        .toList();
    final recentMoveCount = race.recentProofs.length;
    final primaryLabel = canJoin
        ? 'Join race'
        : myRaceComplete
        ? 'Start another race'
        : eligibility.isCameraVerifiable
        ? 'Verify now'
        : 'Unsupported';
    final onPrimary = _busy
        ? null
        : canJoin
        ? _joinRace
        : myRaceComplete
        ? () => context.push('/races/new')
        : canVerify
        ? () async {
            debugLogCameraVerificationDecision(
              race,
              eligibility,
              routeAction: 'race_detail_to_submit_proof',
            );
            await context.push('/race/${race.id}/proof');
            _load();
          }
        : null;

    return Scaffold(
      backgroundColor: NuvoColors.pageIce,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 56),
            children: [
              _RaceSummaryCard(
                race: race,
                myProgress: myProgress,
                isParticipant: isParticipant,
                userId: user?.id,
                rankLabel: raceRankLabel(race, user?.id),
                chaseCopy: heroChaseCopy,
                subcopy: _heroSubcopy(
                  race: race,
                  userId: user?.id,
                  recentMoveCount: recentMoveCount,
                ),
                badgeLabel: eligibility.movementDefinition?.title,
                daysLeft: myRaceComplete ? null : _daysLeft(race.finishLineAt),
                primaryLabel: primaryLabel,
                loading: _busy,
                onPrimary: onPrimary,
                onBack: () => safePopOrGo(context, '/arena'),
                onSettings: isOwner
                    ? () => context.push('/race/${race.id}/settings')
                    : null,
              ),

              if (raceIsActive(race) && !eligibility.isCameraVerifiable) ...[
                const SizedBox(height: 12),
                _UnsupportedVerificationNotice(
                  message: eligibility.unsupportedMessage,
                ),
              ],

              if (isParticipant && myRaceComplete) ...[
                const SizedBox(height: 12),
                _CompleteCallout(race: race, participant: myPart, rank: rank),
              ],

              // ── Board (leaderboard is the hero — shown first) ───────────
              if (myRaceComplete && race.finalStandings.isNotEmpty) ...[
                const SizedBox(height: 24),
                const _SectionLabel(label: 'Final standings'),
                const SizedBox(height: 12),
                _FinalStandingsGroup(
                  standings: race.finalStandings,
                  race: race,
                  userId: user?.id,
                ),
              ] else ...[
                const SizedBox(height: 20),
                const _SectionLabel(label: 'The board'),
                const SizedBox(height: 12),
                if (sorted.isEmpty)
                  Text(
                    'No one on the board yet. Invite crew to race.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: NuvoColors.muted,
                    ),
                  )
                else
                  _LeaderboardGroup(
                    race: race,
                    participants: sorted,
                    userId: user?.id,
                  ),
              ],

              if (race.participantCount > 1) ...[
                const SizedBox(height: 14),
                _BoardPulseStrip(
                  label: recentMoveCount == 0
                      ? 'Board is waiting for the first move.'
                      : 'Board moved ${recentMoveCount == 1 ? 'once' : '$recentMoveCount times'} recently',
                  movers: movementAvatars.take(3).toList(),
                ),
              ],

              // ── Path to goal (demoted below leaderboard) ────────────────
              if (isParticipant && !myRaceComplete) ...[
                const SizedBox(height: 24),
                const _SectionLabel(label: 'Path to goal'),
                const SizedBox(height: 12),
                _CheckpointPath(
                  progressPercent: myProgress,
                  progressValue: myPart?.progressValue,
                  targetValue: race.targetValue,
                  unit: raceMetricLabel(race),
                ),
              ],

              const SizedBox(height: 20),
              _RacePulseModule(
                rankLabel: raceRankLabel(race, user?.id),
                chaseCopy: heroChaseCopy,
                avatars: heroAvatars,
                racerCount: race.participantCount,
                recentMoveCount: recentMoveCount,
                daysLeft: myRaceComplete ? null : _daysLeft(race.finishLineAt),
              ),

              // ── Invite crew (demoted to text link) ──────────────────────
              if (canVerify && isOwner && !myRaceComplete) ...[
                const SizedBox(height: 16),
                Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: (_busy || _navigating)
                        ? null
                        : () => _goToInviteCrew(race.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'Invite crew',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: NuvoColors.blue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 30),

              // ── Move log ────────────────────────────────────────────────
              const _SectionLabel(label: 'Move log'),
              const SizedBox(height: 12),
              if (race.recentProofs.isEmpty)
                Text(
                  'No moves logged yet.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: NuvoColors.muted,
                  ),
                )
              else
                _MoveLogGroup(
                  proofs: race.recentProofs.take(8).toList(),
                  race: race,
                  isOwner: isOwner,
                  onProofTap: (proof) =>
                      context.push('/race/${race.id}/proofs/${proof.id}'),
                ),

              const SizedBox(height: 28),

              // ── Rules (hidden on completed races) ────────────────────
              if (!myRaceComplete) ...[
                const _SectionLabel(label: 'Rules'),
                const SizedBox(height: 10),
                Text(
                  race.rules?.isNotEmpty == true
                      ? race.rules!
                      : _rulesCopy(race),
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: NuvoColors.muted,
                  ),
                ),
              ],

              // ── Owner manage section ────────────────────────────────────
              if (isOwner) ...[
                const SizedBox(height: 28),
                const _SectionLabel(label: 'Manage'),
                const SizedBox(height: 12),
                _ManageRow(
                  icon: Icons.edit_rounded,
                  label: 'Edit race',
                  onTap: () => context.push('/race/${race.id}/edit'),
                ),
                const SizedBox(height: 8),
                _ManageRow(
                  icon: Icons.tune_rounded,
                  label: 'Race settings',
                  onTap: () => context.push('/race/${race.id}/settings'),
                ),
                const SizedBox(height: 8),
                _ManageRow(
                  icon: Icons.ios_share_rounded,
                  label: 'Share race',
                  onTap: () => Share.share('Racing "${race.title}" on Nuvo.'),
                ),
                const SizedBox(height: 8),
                _ManageRow(
                  icon: Icons.copy_rounded,
                  label: 'Copy invite code',
                  onTap: _copyInviteCode,
                ),
              ],

              // ── Leave (non-owner participant) ───────────────────────────
              if (isParticipant && !isOwner) ...[
                const SizedBox(height: 28),
                NuvoDangerButton(
                  label: 'Leave race',
                  expand: true,
                  onPressed: _busy ? null : _leaveRace,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Race summary ──────────────────────────────────────────────────────────────

class _RaceSummaryCard extends StatelessWidget {
  const _RaceSummaryCard({
    required this.race,
    required this.myProgress,
    required this.isParticipant,
    required this.rankLabel,
    required this.subcopy,
    required this.primaryLabel,
    required this.loading,
    required this.onPrimary,
    required this.onBack,
    this.userId,
    this.chaseCopy,
    this.badgeLabel,
    this.daysLeft,
    this.onSettings,
  });

  final Race race;
  final int myProgress;
  final bool isParticipant;
  final String rankLabel;
  final String subcopy;
  final String primaryLabel;
  final bool loading;
  final VoidCallback? onPrimary;
  final VoidCallback onBack;
  final String? userId;
  final String? chaseCopy;
  final String? badgeLabel;
  final int? daysLeft;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final isActive = race.status == 'active';
    final isComplete = raceIsCompleted(race);
    final me = userId == null ? null : race.participantFor(userId!);
    final score = me == null
        ? '$myProgress% verified'
        : raceProgressLabel(race, me);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
        border: Border.all(color: NuvoColors.navy, width: 2),
        boxShadow: const [
          BoxShadow(
            color: NuvoColors.navy,
            blurRadius: 0,
            offset: Offset(4, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PressableScale(
                onTap: onBack,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: NuvoColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: NuvoColors.navy, width: 1.5),
                  ),
                  child: const NuvoIcon(
                    NuvoIconType.back,
                    color: NuvoColors.navy,
                    size: 18,
                  ),
                ),
              ),
              const Spacer(),
              _StatusPill(
                label: isComplete
                    ? 'Finished'
                    : isActive
                    ? 'Live'
                    : _raceStatusLabel(race.status),
                color: isComplete
                    ? NuvoColors.success
                    : isActive
                    ? NuvoColors.actionBlue
                    : NuvoColors.navy,
              ),
              if (onSettings != null) ...[
                const SizedBox(width: 8),
                PressableScale(
                  onTap: onSettings,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: NuvoColors.panel,
                      shape: BoxShape.circle,
                      border: Border.all(color: NuvoColors.border, width: 1.25),
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      color: NuvoColors.navy,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Hero(
            tag: 'race-title-${race.id}',
            child: Material(
              color: Colors.transparent,
              child: Text(
                race.displayTitle,
                style: AppTextStyles.headlineLarge.copyWith(
                  color: NuvoColors.navy,
                  height: 1.06,
                  letterSpacing: 0,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (badgeLabel != null) _StatusPill(label: badgeLabel!),
              if (race.targetValue != null)
                _StatusPill(label: 'First to ${raceTargetLabel(race)}'),
              if (daysLeft != null) _StatusPill(label: '${daysLeft}d left'),
            ],
          ),
          if (isParticipant) ...[
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    score,
                    style: AppTextStyles.headlineMedium.copyWith(
                      color: isComplete
                          ? NuvoColors.success
                          : NuvoColors.actionBlue,
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  rankLabel,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: NuvoColors.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            NuvoRaceLane(
              progressPercent: myProgress,
              trackHeight: 6,
              dotDiameter: 16,
            ),
            const SizedBox(height: 10),
            Text(
              chaseCopy ?? subcopy,
              style: AppTextStyles.bodySmall.copyWith(
                color: NuvoColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 18),
          NuvoPrimaryButton(
            label: primaryLabel,
            expand: true,
            loading: loading,
            onPressed: onPrimary,
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, this.color = NuvoColors.actionBlue});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(NuvoRadii.pill),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _RacePulseModule extends StatelessWidget {
  const _RacePulseModule({
    required this.rankLabel,
    required this.chaseCopy,
    required this.avatars,
    required this.racerCount,
    required this.recentMoveCount,
    this.daysLeft,
  });

  final String rankLabel;
  final String? chaseCopy;
  final List<({String initials, String? photoUrl})> avatars;
  final int racerCount;
  final int recentMoveCount;
  final int? daysLeft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: NuvoColors.icyBlue,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: NuvoColors.actionBlue.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: NuvoColors.navy,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              rankLabel,
              style: AppTextStyles.labelMedium.copyWith(
                color: NuvoColors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chaseCopy ??
                      (recentMoveCount == 0
                          ? 'Waiting for the next move.'
                          : '$recentMoveCount recent ${recentMoveCount == 1 ? 'move' : 'moves'}.'),
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: NuvoColors.navy,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  daysLeft == null
                      ? '$racerCount ${racerCount == 1 ? 'racer' : 'racers'} on the board'
                      : '$racerCount ${racerCount == 1 ? 'racer' : 'racers'} · ${daysLeft}d left',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (avatars.isNotEmpty) ...[
            const SizedBox(width: 10),
            NuvoAvatarStack(
              avatars: avatars,
              total: racerCount,
              size: 28,
              max: 3,
              borderColor: NuvoColors.icyBlue,
            ),
          ],
        ],
      ),
    );
  }
}

class _LeaderboardGroup extends StatelessWidget {
  const _LeaderboardGroup({
    required this.race,
    required this.participants,
    this.userId,
  });

  final Race race;
  final List<RaceParticipant> participants;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NuvoColors.border, width: 1.25),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < participants.length; i++) ...[
            _LeaderboardCompactRow(
              race: race,
              participant: participants[i],
              rank: participants[i].rank ?? i + 1,
              isCurrentUser: userId != null && participants[i].userId == userId,
              isNearestOpponent: i == 1 && participants.first.userId == userId,
            ),
            if (i < participants.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 72,
                color: NuvoColors.divider,
              ),
          ],
        ],
      ),
    );
  }
}

class _LeaderboardCompactRow extends StatelessWidget {
  const _LeaderboardCompactRow({
    required this.race,
    required this.participant,
    required this.rank,
    required this.isCurrentUser,
    required this.isNearestOpponent,
  });

  final Race race;
  final RaceParticipant participant;
  final int rank;
  final bool isCurrentUser;
  final bool isNearestOpponent;

  @override
  Widget build(BuildContext context) {
    final progress = raceProgressPercent(race, participant);
    final accent = isCurrentUser
        ? NuvoColors.actionBlue
        : rank == 1
        ? NuvoColors.gold
        : NuvoColors.navy;

    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      color: isCurrentUser
          ? NuvoColors.icyBlue
          : isNearestOpponent
          ? NuvoColors.panel
          : NuvoColors.surface,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '#$rank',
              style: AppTextStyles.labelLarge.copyWith(
                color: accent,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          NuvoAvatar(
            initials: _initials(participant.displayName),
            photoUrl: participant.profilePhotoUrl,
            size: 38,
            bgColor: isCurrentUser
                ? NuvoColors.navy
                : nuvoAvatarColorFor(participant.userId),
            textColor: NuvoColors.white,
            borderColor: rank == 1 ? NuvoColors.gold : null,
            borderWidth: rank == 1 ? 2 : 1.5,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isCurrentUser ? 'You' : participant.displayName,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: NuvoColors.navy,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      raceProgressLabel(race, participant),
                      style: AppTextStyles.labelSmall.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(NuvoRadii.pill),
                  child: LinearProgressIndicator(
                    value: (progress / 100).clamp(0.0, 1.0),
                    minHeight: 4,
                    color: accent,
                    backgroundColor: NuvoColors.trackBg,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FinalStandingsGroup extends StatelessWidget {
  const _FinalStandingsGroup({
    required this.standings,
    required this.race,
    this.userId,
  });

  final List<RaceFinalStanding> standings;
  final Race race;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NuvoColors.border, width: 1.25),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < standings.length; i++) ...[
            _FinalStandingRow(
              standing: standings[i],
              isCurrentUser: standings[i].userId == userId,
              race: race,
            ),
            if (i < standings.length - 1)
              const Divider(height: 1, color: NuvoColors.divider),
          ],
        ],
      ),
    );
  }
}

class _MoveLogGroup extends StatelessWidget {
  const _MoveLogGroup({
    required this.proofs,
    required this.race,
    required this.isOwner,
    required this.onProofTap,
  });

  final List<RaceProof> proofs;
  final Race race;
  final bool isOwner;
  final ValueChanged<RaceProof> onProofTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NuvoColors.border, width: 1.25),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < proofs.length; i++) ...[
            NuvoMoveLogItem(
              displayName: proofs[i].displayName,
              profilePhotoUrl: proofs[i].profilePhotoUrl,
              actionLine: _moveActionLine(proofs[i], race),
              createdAt: proofs[i].createdAt,
              valueLabel: proofs[i].value != null
                  ? '+${raceScoreLabel(race, proofs[i].value!)}'
                  : null,
              isPositive:
                  proofs[i].verificationStatus == 'accepted' ||
                  proofs[i].verificationStatus == 'ai_verified',
              onTap: isOwner ? () => onProofTap(proofs[i]) : null,
            ),
            if (i < proofs.length - 1)
              const Divider(height: 1, color: NuvoColors.divider, indent: 58),
          ],
        ],
      ),
    );
  }
}

class _BoardPulseStrip extends StatelessWidget {
  const _BoardPulseStrip({required this.label, required this.movers});

  final String label;
  final List<({String initials, String? photoUrl})> movers;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: NuvoColors.icyBlue,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: NuvoColors.actionBlue.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.trending_up_rounded,
            color: NuvoColors.success,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.labelMedium.copyWith(
                color: NuvoColors.navy,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (movers.isNotEmpty)
            NuvoAvatarStack(
              avatars: movers,
              total: movers.length,
              size: 28,
              max: 3,
              borderColor: NuvoColors.icyBlue,
            ),
        ],
      ),
    );
  }
}

String _rulesCopy(Race race) {
  if (race.format == 'first_to_goal') {
    return 'Every verified session adds to your total. First racer to the finish line wins.';
  }
  return 'Verify moves before the finish line. Nuvo updates the leaderboard.';
}

String _raceStatusLabel(String status) => switch (status) {
  'completed' || 'complete' || 'finished' => 'Finished',
  'archived' => 'Archived',
  'cancelled' => 'Cancelled',
  _ => status.replaceAll('_', ' '),
};

// ── Checkpoint path ────────────────────────────────────────────────────────────

enum _NodeState { done, current, todo }

class _Checkpoint {
  const _Checkpoint({
    required this.label,
    required this.sub,
    required this.state,
    required this.marker,
  });
  final String label;
  final String sub;
  final _NodeState state;
  final String marker;
}

/// Duolingo-style vertical checkpoint path toward the race goal. Checkpoints
/// are derived from real progress (25/50/75/100% of the actual target or,
/// for percent-only races, of 100%) — never invented milestone content.
class _CheckpointPath extends StatelessWidget {
  const _CheckpointPath({
    required this.progressPercent,
    required this.progressValue,
    required this.targetValue,
    required this.unit,
  });

  final int progressPercent;
  final int? progressValue;
  final int? targetValue;
  final String? unit;

  static const _fractions = [0.25, 0.5, 0.75, 1.0];
  static const _labels = [
    'Quarter way',
    'Halfway',
    'Three quarters',
    'Finish line',
  ];

  @override
  Widget build(BuildContext context) {
    var currentAssigned = false;
    final checkpoints = <_Checkpoint>[];
    for (var i = 0; i < _fractions.length; i++) {
      final fraction = _fractions[i];
      final reached = progressPercent >= (fraction * 100).round();
      final marker = targetValue != null
          ? '${(targetValue! * fraction).round()}'
          : '${(fraction * 100).round()}%';

      _NodeState state;
      String sub;
      if (reached) {
        state = _NodeState.done;
        sub = 'Verified';
      } else if (!currentAssigned) {
        state = _NodeState.current;
        currentAssigned = true;
        sub = targetValue != null
            ? '$progressValue / $targetValue ${unit ?? ''}'.trim()
            : '$progressPercent% verified';
      } else {
        state = _NodeState.todo;
        sub = 'Not reached yet';
      }
      checkpoints.add(
        _Checkpoint(label: _labels[i], sub: sub, state: state, marker: marker),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < checkpoints.length; i++)
            _CheckpointRow(
              checkpoint: checkpoints[i],
              isFirst: i == 0,
              isLast: i == checkpoints.length - 1,
            ),
        ],
      ),
    );
  }
}

class _CheckpointRow extends StatelessWidget {
  const _CheckpointRow({
    required this.checkpoint,
    required this.isFirst,
    required this.isLast,
  });
  final _Checkpoint checkpoint;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final c = checkpoint;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                if (!isFirst)
                  Positioned(
                    top: -10,
                    child: Container(
                      width: 2,
                      height: 10,
                      color: NuvoColors.divider,
                    ),
                  ),
                if (!isLast)
                  Positioned(
                    bottom: -10,
                    child: Container(
                      width: 2,
                      height: 10,
                      color: NuvoColors.divider,
                    ),
                  ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: switch (c.state) {
                      _NodeState.done => NuvoColors.blue,
                      _NodeState.current => NuvoColors.navy,
                      _NodeState.todo => NuvoColors.surface,
                    },
                    border: c.state == _NodeState.todo
                        ? Border.all(color: NuvoColors.divider, width: 2)
                        : null,
                    boxShadow: c.state == _NodeState.current
                        ? const [
                            BoxShadow(
                              color: NuvoColors.panel,
                              blurRadius: 0,
                              spreadRadius: 5,
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    c.marker,
                    style: AppTextStyles.number(
                      12,
                      color: c.state == _NodeState.todo
                          ? NuvoColors.paleSlate
                          : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.state == _NodeState.current ? 'You are here' : c.label,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: NuvoColors.navy,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  c.sub,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Complete callout ──────────────────────────────────────────────────────────

class _UnsupportedVerificationNotice extends StatelessWidget {
  const _UnsupportedVerificationNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: NuvoColors.icyBlue,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.videocam_off_rounded,
            color: NuvoColors.navy,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.navy),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompleteCallout extends StatelessWidget {
  const _CompleteCallout({
    required this.race,
    required this.participant,
    this.rank,
  });
  final Race race;
  final RaceParticipant? participant;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final scoreText = raceProgressLabel(race, participant);
    final rankText = rank != null ? ' · #$rank' : '';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: NuvoColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NuvoColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const NuvoIcon(
            NuvoIconType.checkCircle,
            color: NuvoColors.success,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$scoreText$rankText', style: AppTextStyles.titleMedium),
                const SizedBox(height: 2),
                Text(
                  'Start another race with your crew.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Move action line helper ───────────────────────────────────────────────────

String _moveActionLine(RaceProof proof, Race race) {
  final verb = proof.value != null
      ? 'logged ${raceScoreLabel(race, proof.value!)}'
      : 'logged a move';
  return switch (proof.verificationStatus) {
    'accepted' || 'ai_verified' => '$verb · Camera verified',
    'ai_failed' || 'rejected' => "$verb · Move didn't count",
    'needs_review' => '$verb · Under review',
    _ => verb,
  };
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  final s = name.trim();
  return s.isEmpty ? '?' : s[0].toUpperCase();
}

String _heroSubcopy({
  required Race race,
  required String? userId,
  required int recentMoveCount,
}) {
  final sorted = serverRankedParticipants(race);
  final leader = sorted.isEmpty ? null : sorted.first;
  final me = userId == null ? null : race.participantFor(userId);
  if (me != null && raceIsCompleted(race)) {
    return 'You hit the finish line. Pull in your crew and move the board again.';
  }
  final parts = <String>[];

  if (leader != null && me != null && leader.userId != me.userId) {
    final gap = race.targetValue != null
        ? leader.progressValue - me.progressValue
        : leader.progressPercent - me.progressPercent;
    if (gap > 0) {
      parts.add(
        '${leader.displayName.split(' ').first} leads by ${raceScoreLabel(race, gap)}.',
      );
    }
  } else if (leader != null) {
    parts.add('${leader.displayName.split(' ').first} leads the board.');
  }

  if (recentMoveCount > 0) {
    parts.add(
      '$recentMoveCount ${recentMoveCount == 1 ? 'move' : 'moves'} logged recently.',
    );
  } else {
    parts.add('No moves logged yet.');
  }

  return parts.join(' ');
}

int? _daysLeft(String? finishLineAt) {
  if (finishLineAt == null || finishLineAt.isEmpty) return null;
  final finish = DateTime.tryParse(finishLineAt);
  if (finish == null) return null;
  final now = DateTime.now();
  final diff = finish.difference(now).inDays;
  return diff < 0 ? 0 : diff + 1;
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTextStyles.titleMedium.copyWith(
        color: NuvoColors.navy,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    );
  }
}

// ── Final standing row ────────────────────────────────────────────────────────

class _FinalStandingRow extends StatelessWidget {
  const _FinalStandingRow({
    required this.standing,
    required this.isCurrentUser,
    required this.race,
  });

  final RaceFinalStanding standing;
  final bool isCurrentUser;
  final Race race;

  @override
  Widget build(BuildContext context) {
    final rankLabel = '#${standing.rank}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? NuvoColors.success.withValues(alpha: 0.08)
            : NuvoColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrentUser
              ? NuvoColors.success.withValues(alpha: 0.4)
              : NuvoColors.border,
          width: isCurrentUser ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              rankLabel,
              style: AppTextStyles.labelLarge.copyWith(
                color: standing.rank == 1
                    ? NuvoColors.success
                    : NuvoColors.muted,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              standing.displayName,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: isCurrentUser ? FontWeight.w700 : FontWeight.w500,
                color: NuvoColors.navy,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          if (standing.scoreValue > 0)
            Text(
              raceScoreLabel(race, standing.scoreValue),
              style: AppTextStyles.labelMedium.copyWith(
                color: NuvoColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Manage row ────────────────────────────────────────────────────────────────

class _ManageRow extends StatelessWidget {
  const _ManageRow({
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: NuvoColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: NuvoColors.navy, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const NuvoIcon(
              NuvoIconType.arrow,
              color: NuvoColors.muted,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}
