import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/nuvo_responsive.dart';
import '../../../core/widgets/nuvo_board_components.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_icons.dart';
import '../../../core/widgets/nuvo_empty_state.dart';
import '../../../core/widgets/nuvo_loading_indicator.dart';
import '../../../core/widgets/nuvo_move_log_item.dart';
import '../../../core/widgets/nuvo_podium.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../social/presentation/race_share_sheet.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/chase_context.dart';
import '../../races/domain/camera_verification_resolver.dart';
import '../../races/domain/motion_activity.dart';
import '../../races/domain/race_display.dart';
import '../../races/presentation/race_controller.dart';
import '../../onboarding/presentation/first_use_guide.dart';

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
        body: Center(child: NuvoLoadingIndicator()),
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
            if (ref.read(firstRaceGuideProvider) ==
                FirstRaceGuideStep.raceDetail) {
              ref.read(firstRaceGuideProvider.notifier).state =
                  FirstRaceGuideStep.complete;
            }
            debugLogCameraVerificationDecision(
              race,
              eligibility,
              routeAction: 'race_detail_to_submit_proof',
            );
            await context.push('/race/${race.id}/proof');
            _load();
          }
        : null;

    final showBottomBar =
        !myRaceComplete && onPrimary != null && primaryLabel != 'Unsupported';

    final screen = Scaffold(
      backgroundColor: NuvoColors.pageIce,
      bottomNavigationBar: showBottomBar
          ? _VerifyBar(
              key: FirstRaceGuideKeys.racePrimary,
              label: primaryLabel,
              loading: _busy,
              onPressed: onPrimary,
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: EdgeInsets.fromLTRB(18, 16, 18, showBottomBar ? 24 : 56),
            children: [
              if (myRaceComplete)
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
                  daysLeft: null,
                  primaryLabel: primaryLabel,
                  loading: _busy,
                  onPrimary: onPrimary,
                  onBack: () => safePopOrGo(context, '/arena'),
                  onSettings: isOwner
                      ? () => context.push('/race/${race.id}/settings')
                      : null,
                )
              else
                _LiveRaceHeader(
                  race: race,
                  eligibility: eligibility,
                  onBack: () => safePopOrGo(context, '/arena'),
                  onMenu: isOwner
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
                const SizedBox(height: 26),
                if (sorted.isEmpty)
                  NuvoEmptyState(
                    icon: Icons.group_add_rounded,
                    title: 'No one on the board yet',
                    body: 'Invite your crew — the leaderboard fills in as '
                        'people join and log their first move.',
                    ctaLabel: isOwner ? 'Invite crew' : null,
                    onCta: isOwner
                        ? () => _goToInviteCrew(race.id)
                        : null,
                    compact: true,
                  )
                else if (sorted.length >= 2)
                  NuvoPodium(
                    top: [
                      for (var i = 0; i < sorted.take(3).length; i++)
                        NuvoPodiumEntry(
                          rank: i + 1,
                          name: sorted[i].displayName,
                          statLabel: raceProgressLabel(race, sorted[i]),
                          photoUrl: sorted[i].profilePhotoUrl,
                          avatarSeedId: sorted[i].userId,
                          isCurrentUser: sorted[i].userId == user?.id,
                        ),
                    ],
                    rest: sorted.length > 3
                        ? _LeaderboardGroup(
                            race: race,
                            participants: sorted.sublist(3),
                            userId: user?.id,
                            rankOffset: 3,
                          )
                        : null,
                  )
                else
                  _LeaderboardGroup(
                    race: race,
                    participants: sorted,
                    userId: user?.id,
                  ),
              ],

              // ── Your progress (the focal card) ─────────────────────────────
              if (isParticipant && !myRaceComplete && race.targetValue != null) ...[
                const SizedBox(height: 20),
                _YourProgressCard(
                  measurementType: raceMeasurementType(race),
                  progressValue: myPart?.progressValue ?? 0,
                  targetValue: race.targetValue!,
                  unit: raceDisplayUnit(race),
                  rankLabel: raceRankLabel(race, user.id),
                  chaseCopy: chase?.chaseCopy,
                  leaderGap: chase?.leaderGap,
                  isLeading: (chase?.myRank ?? 99) == 1,
                ),
              ],

              // ── Path to goal (only for goals with no numeric target) ────
              if (isParticipant && !myRaceComplete && race.targetValue == null) ...[
                const SizedBox(height: 24),
                const _SectionLabel(label: 'Path to goal'),
                const SizedBox(height: 12),
                _CheckpointPath(
                  measurementType: raceMeasurementType(race),
                  progressPercent: myProgress,
                  progressValue: myPart?.progressValue,
                  targetValue: race.targetValue,
                  unit: raceDisplayUnit(race),
                ),
              ],

              // ── Invite crew ────────────────────────────────────────────
              if (canVerify && isOwner && !myRaceComplete) ...[
                const SizedBox(height: 20),
                NuvoSecondaryButton(
                  label: 'Invite crew',
                  icon: Icons.person_add_alt_1_rounded,
                  expand: true,
                  onPressed: (_busy || _navigating)
                      ? null
                      : () => _goToInviteCrew(race.id),
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
                  onTap: () => context.push('/race/${race.id}/settings'),
                ),
                const SizedBox(height: 8),
                _ManageRow(
                  icon: Icons.ios_share_rounded,
                  label: 'Share race — link & QR',
                  onTap: () => showRaceShareSheet(
                    context,
                    raceId: race.id,
                    raceTitle: race.title,
                  ),
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

    final guide = ref.watch(firstRaceGuideProvider);
    if (guide != FirstRaceGuideStep.raceDetail) return screen;
    return Stack(
      children: [
        screen,
        FirstRaceGuideCoach(
          step: guide,
          targetKey: FirstRaceGuideKeys.racePrimary,
          eyebrow: 'MAKE THE FIRST MOVE',
          title: 'This button moves your leaderboard.',
          body:
              'Tap Verify now to submit your first proof and see your progress update.',
        ),
      ],
    );
  }
}

// ── Live race header (active races) ──────────────────────────────────────────

class _LiveRaceHeader extends StatelessWidget {
  const _LiveRaceHeader({
    required this.race,
    required this.eligibility,
    required this.onBack,
    this.onMenu,
  });

  final Race race;
  final CameraVerificationEligibility eligibility;
  final VoidCallback onBack;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final target = race.targetValue;
    final subtitle = target != null
        ? 'First to ${raceTargetLabel(race)}'
        : eligibility.movementDefinition?.title ?? 'Keep moving to the finish';

    final count = race.participantCount;
    final racerLine = '$count ${count == 1 ? 'racer' : 'racers'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            NuvoBackButton(onPressed: onBack),
            const Spacer(),
            if (onMenu != null)
              NuvoIconAction(
                icon: Icons.more_horiz_rounded,
                onTap: onMenu!,
                semanticLabel: 'Race settings',
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          race.displayTitle,
          style: AppTextStyles.displaySmall.copyWith(
            color: NuvoColors.navy,
            fontSize: context.rs(32),
            height: 1.06,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '$subtitle  ·  $racerLine',
          style: AppTextStyles.bodyMedium.copyWith(
            color: NuvoColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ── Your progress card (the focal element) ───────────────────────────────────

class _YourProgressCard extends StatelessWidget {
  const _YourProgressCard({
    required this.measurementType,
    required this.progressValue,
    required this.targetValue,
    required this.unit,
    required this.rankLabel,
    this.chaseCopy,
    this.leaderGap,
    this.isLeading = false,
  });

  final MotionMeasurementType measurementType;
  final int progressValue;
  final int targetValue;
  final String unit;
  final String rankLabel;
  final String? chaseCopy;
  final int? leaderGap;
  final bool isLeading;

  @override
  Widget build(BuildContext context) {
    final pct = targetValue <= 0
        ? 0.0
        : (progressValue / targetValue).clamp(0.0, 1.0);
    final remaining = (targetValue - progressValue).clamp(0, targetValue);
    final gap = leaderGap ?? 0;
    final gapText = formatMotionTarget(measurementType, gap, unit);
    final gapLine = isLeading && gap > 0
        ? 'Leading by $gapText'
        : gap > 0
        ? '$gapText behind the leader'
        : chaseCopy;
    final done = remaining <= 0;
    // Green while you hold the lead or have crossed the line, blue otherwise.
    final accent = (isLeading || done) ? NuvoColors.success : NuvoColors.blue;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
        border: Border.all(color: NuvoColors.navy, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR PROGRESS',
            style: AppTextStyles.eyebrow.copyWith(color: accent),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatMotionProgress(
                  measurementType,
                  progressValue,
                  targetValue,
                  unit,
                ),
                style: AppTextStyles.statLarge(
                  context.rs(30),
                  color: accent,
                ),
              ),
              const Spacer(),
              Text(
                rankLabel,
                style: AppTextStyles.statLarge(
                  context.rs(26),
                  color: isLeading ? NuvoColors.gold : NuvoColors.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(NuvoRadii.pill),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              color: accent,
              backgroundColor: NuvoColors.trackBg,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            remaining > 0
                ? '${formatMotionTarget(measurementType, remaining, unit)} '
                      'to the finish'
                : 'Finish line reached',
            style: AppTextStyles.bodyMedium.copyWith(
              color: NuvoColors.navy,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (gapLine != null && gapLine.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              gapLine,
              style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Pinned verify bar ───────────────────────────────────────────────────────

class _VerifyBar extends StatelessWidget {
  const _VerifyBar({
    super.key,
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: NuvoColors.pageIce,
      padding: EdgeInsets.fromLTRB(
        18,
        10,
        18,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      child: NuvoPrimaryButton(
        label: label,
        icon: Icons.arrow_forward_rounded,
        expand: true,
        loading: loading,
        onPressed: onPressed,
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
                child: const SizedBox(
                  width: 36,
                  height: 36,
                  child: Center(
                    child: NuvoIcon(
                      NuvoIconType.back,
                      color: NuvoColors.navy,
                      size: 22,
                    ),
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Hero(
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
              ),
              if (onSettings != null) ...[
                const SizedBox(width: 10),
                PressableScale(
                  onTap: onSettings,
                  child: const Padding(
                    padding: EdgeInsets.only(top: 3, right: 2),
                    child: Icon(
                      Icons.tune_rounded,
                      color: NuvoColors.navy,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isComplete ? 'FINISHED' : 'ON-GOING',
            style: AppTextStyles.labelSmall.copyWith(
              color: isComplete ? NuvoColors.success : NuvoColors.actionBlue,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),
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
            key: FirstRaceGuideKeys.racePrimary,
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
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: NuvoColors.actionBlue.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(NuvoRadii.pill),
        border: Border.all(
          color: NuvoColors.actionBlue.withValues(alpha: 0.22),
        ),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: NuvoColors.actionBlue,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _LeaderboardGroup extends StatelessWidget {
  const _LeaderboardGroup({
    required this.race,
    required this.participants,
    this.userId,
    this.rankOffset = 0,
  });

  final Race race;
  final List<RaceParticipant> participants;
  final String? userId;

  /// Number of higher-ranked participants not in [participants] (e.g. the top 3
  /// shown on the podium), so fallback ranks continue correctly.
  final int rankOffset;

  @override
  Widget build(BuildContext context) {
    return _OutlinedSheet(
      child: Column(
        children: [
          for (var i = 0; i < participants.length; i++) ...[
            _LeaderboardCompactRow(
              race: race,
              participant: participants[i],
              rank: participants[i].rank ?? rankOffset + i + 1,
              isCurrentUser:
                  userId != null && participants[i].userId == userId,
            ),
            if (i < participants.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                color: NuvoColors.divider,
                indent: 16,
                endIndent: 16,
              ),
          ],
        ],
      ),
    );
  }
}

/// Outlined white container whose child is clipped *inside* the 2 px ink edge,
/// so the border corners stay crisp. A plain `Container(border: …,
/// clipBehavior: Clip.antiAlias)` clips the outer half of the border at each
/// corner, which reads as "clipped corners".
class _OutlinedSheet extends StatelessWidget {
  const _OutlinedSheet({required this.child, this.radius = NuvoRadii.lg});
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: NuvoColors.navy, width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 2),
        child: child,
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
  });

  final Race race;
  final RaceParticipant participant;
  final int rank;
  final bool isCurrentUser;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isCurrentUser ? NuvoColors.blueSurface : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$rank',
              style: AppTextStyles.labelMedium.copyWith(
                color: NuvoColors.textMuted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 6),
          NuvoAvatar(
            initials: _initials(participant.displayName),
            photoUrl: participant.profilePhotoUrl,
            size: 34,
            bgColor: nuvoAvatarColorFor(participant.userId),
            textColor: NuvoColors.white,
            borderColor: isCurrentUser ? NuvoColors.blue : NuvoColors.navy,
            borderWidth: isCurrentUser ? 2 : 1.5,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isCurrentUser ? 'You' : participant.displayName,
              style: AppTextStyles.titleMedium.copyWith(
                fontSize: 15,
                color: NuvoColors.navy,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            raceProgressLabel(race, participant),
            style: AppTextStyles.raceRowMeta.copyWith(
              color: isCurrentUser ? NuvoColors.blue : NuvoColors.muted,
              fontWeight: FontWeight.w800,
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
    return _OutlinedSheet(
      child: Column(
        children: [
          for (var i = 0; i < standings.length; i++) ...[
            _FinalStandingRow(
              standing: standings[i],
              isCurrentUser: standings[i].userId == userId,
              race: race,
            ),
            if (i < standings.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                color: NuvoColors.divider,
                indent: 16,
                endIndent: 16,
              ),
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
    return _OutlinedSheet(
      radius: NuvoRadii.card,
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
              const Divider(
                height: 1,
                thickness: 1,
                color: NuvoColors.divider,
                indent: 62,
              ),
          ],
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

/// Vertical checkpoint path toward the race goal. Checkpoints are derived from
/// real progress (25/50/75/100% of the actual target or, for percent-only
/// races, of 100%) — never invented milestone content.
class _CheckpointPath extends StatelessWidget {
  const _CheckpointPath({
    required this.measurementType,
    required this.progressPercent,
    required this.progressValue,
    required this.targetValue,
    required this.unit,
  });

  final MotionMeasurementType measurementType;
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
            ? formatMotionProgress(
                measurementType,
                progressValue ?? 0,
                targetValue!,
                unit ?? measurementType.defaultPluralUnit,
              )
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
        border: Border.all(color: NuvoColors.navy, width: 2),
        boxShadow: AppShadows.hardSmall,
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
        border: Border.all(color: NuvoColors.navy, width: 2),
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
    final rankColor = switch (standing.rank) {
      1 => NuvoColors.gold,
      2 => NuvoColors.silver,
      3 => NuvoColors.bronze,
      _ => NuvoColors.actionBlue,
    };
    final selectedFill = isCurrentUser ? rankColor : null;
    final outlineColor = standing.rank <= 3
        ? rankColor
        : isCurrentUser
        ? NuvoColors.actionBlue
        : null;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: selectedFill,
        borderRadius: BorderRadius.circular(14),
        border: outlineColor != null
            ? Border.all(color: outlineColor, width: 2)
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              rankLabel,
              style: AppTextStyles.labelLarge.copyWith(
                color: selectedFill != null ? NuvoColors.white : rankColor,
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
                color: selectedFill != null
                    ? NuvoColors.white
                    : NuvoColors.navy,
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
                color: selectedFill != null ? NuvoColors.white : rankColor,
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
          border: Border.all(color: NuvoColors.navy, width: 2),
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
