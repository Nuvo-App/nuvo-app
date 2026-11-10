import '../../../../core/offline/online_gate.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/navigation/nuvo_navigation.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/v13/v13.dart';
import '../../../auth/data/auth_api.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../crew/application/crew_controller.dart';
import '../../../race_detail/domain/race_poll_backoff.dart';
import '../../../notifications/domain/notification_display.dart';
import '../../data/race_models.dart';
import '../../domain/chase_context.dart';
import '../../domain/motion_activity.dart';
import '../../domain/race_display.dart';
import '../../domain/race_mode_semantics.dart';
import '../race_controller.dart';
import 'submit_proof_entry.dart';

/// v13 Race detail — the leaderboard room for one race. Podium top 3 +
/// open rows first; one blue action: Submit proof / Join / Race again.
class RaceDetailV13Screen extends ConsumerStatefulWidget {
  const RaceDetailV13Screen({
    super.key,
    required this.raceId,
    this.openProofOnLoad = false,
  });

  /// Path param from `/race/:id` — the orchestrator wires it through.
  final String raceId;

  /// `/race/:id/proof` (push deep links, "Take it back", legacy links) lands
  /// here and opens the Submit proof sheet once the race has loaded — only
  /// when the viewer is racing in it and it is still live.
  final bool openProofOnLoad;

  @override
  ConsumerState<RaceDetailV13Screen> createState() =>
      _RaceDetailV13ScreenState();
}

class _RaceDetailV13ScreenState extends ConsumerState<RaceDetailV13Screen>
    with WidgetsBindingObserver {
  Race? _race;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Timer? _timer;
  final _backoff = RacePollBackoff();
  bool _inFlight = false;
  bool _resumed = true;
  bool _gated = false;
  bool _showAllRacers = false;

  /// Scroll + hero key: the sticky Submit proof only appears once the YOU
  /// hero (which carries its own Submit) has scrolled off — never both.
  final ScrollController _scroll = ScrollController();
  final GlobalKey _heroKey = GlobalKey();
  final ValueNotifier<bool> _heroVisible = ValueNotifier(true);

  void _onScroll() {
    final ctx = _heroKey.currentContext;
    if (ctx == null) {
      _heroVisible.value = false;
      return;
    }
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
    // Off once the hero's bottom edge passes under the header (~120pt).
    _heroVisible.value = bottom > 120;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    _resumed =
        (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) ==
        AppLifecycleState.resumed;
    _load();
    _scheduleNext();
    final openedAt = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(analyticsProvider)
          .screen(
            'race_detail',
            ms: DateTime.now().difference(openedAt).inMilliseconds,
          );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _scroll.dispose();
    _heroVisible.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_resumed) return;
      _resumed = true;
      _gated = false;
      _backoff.reset();
      _silentRefresh();
      _scheduleNext();
    } else {
      _resumed = false;
      _timer?.cancel();
    }
  }

  bool get _shouldPoll {
    if (!_resumed || !mounted || _loading) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    final race = _race;
    return race != null && !raceIsCompleted(race);
  }

  void _scheduleNext() {
    _timer?.cancel();
    if (!_resumed || !mounted) return;
    _timer = Timer(_backoff.current, _pollTick);
  }

  Future<void> _pollTick() async {
    if (!mounted || !_resumed) return;
    if (!_shouldPoll) {
      _gated = true;
      _scheduleNext();
      return;
    }
    if (_gated) {
      _gated = false;
      _backoff.reset();
    }
    await _silentRefresh();
    _scheduleNext();
  }

  Future<void> _silentRefresh() async {
    if (_loading || _inFlight) return;
    _inFlight = true;
    try {
      final before = _race == null ? null : raceSignature(_race!);
      final race = await ref
          .read(raceControllerProvider.notifier)
          .getRaceDetail(widget.raceId);
      _backoff.recordResult(
        changed: before == null || before != raceSignature(race),
      );
      if (mounted) {
        setState(() => _race = race);
      }
    } catch (_) {
      _backoff.recordResult(changed: false);
    } finally {
      _inFlight = false;
    }
  }

  bool _proofOpened = false;

  void _maybeOpenProof() {
    if (!widget.openProofOnLoad || _proofOpened) return;
    final race = _race;
    final uid = ref.read(authControllerProvider).user?.id;
    if (race == null || uid == null) return;
    if (!raceIsActive(race) || !race.isParticipant(uid)) return;
    _proofOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) openSubmitProof(context, ref, race);
    });
  }

  Future<void> _load() async {
    final cached = ref
        .read(raceControllerProvider)
        .races
        .where((r) => r.id == widget.raceId)
        .firstOrNull;
    if (cached != null && _race == null) {
      setState(() {
        _race = cached;
        _loading = false;
      });
      _maybeOpenProof();
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
          .getRaceDetail(widget.raceId);
      if (mounted) {
        setState(() {
          _race = race;
          _loading = false;
        });
        _maybeOpenProof();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load race.';
          _loading = false;
        });
      }
    }
  }

  void _toastError(Object e, String action) {
    showV13Toast(
      context,
      e is ApiException ? friendlyApiError(e) : 'Could not $action.',
    );
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    try {
      final joined = await ref
          .read(raceControllerProvider.notifier)
          .joinRace(_race!.id);
      if (!mounted) return;
      setState(() {
        _race = joined;
        _busy = false;
      });
      showV13Confetti(context);
      showV13Toast(context, 'You\'re in. Good luck.');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _toastError(e, 'join this race');
      }
    }
  }

  Future<void> _rematch() async {
    setState(() => _busy = true);
    try {
      final next = await ref
          .read(raceControllerProvider.notifier)
          .rematchRace(_race!.id);
      if (mounted) {
        setState(() => _busy = false);
        context.pushReplacement('/race/${next.id}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _toastError(e, 'start a rematch');
      }
    }
  }

  Future<void> _leave() async {
    final race = _race!;
    final ok = await showV13ConfirmSheet(
      context,
      title: 'Leave race?',
      body:
          'You will leave this leaderboard. You can rejoin later with an invite code.',
      confirmLabel: 'Leave',
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(raceControllerProvider.notifier).leaveRace(race.id);
      if (mounted) context.go('/compete');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _toastError(e, 'leave this race');
      }
    }
  }

  Future<void> _cancel() async {
    final race = _race!;
    final ok = await showV13ConfirmSheet(
      context,
      title: 'Cancel this race?',
      body: 'The leaderboard closes for everyone. This can\u2019t be undone.',
      confirmLabel: 'Cancel race',
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final cancelled = await ref
          .read(raceControllerProvider.notifier)
          .cancelRace(race.id);
      if (mounted) {
        setState(() {
          _race = cancelled;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _toastError(e, 'cancel this race');
      }
    }
  }

  Future<void> _report() async {
    final race = _race!;
    final ctrl = TextEditingController();
    final reason = await showV13Sheet<String>(
      context,
      builder: (ctx) => _ReportSheet(controller: ctrl),
    );
    if (reason == null || !mounted) return;
    try {
      await ref
          .read(crewRepositoryProvider)
          .reportRace(race.id, reason: reason);
      if (mounted) {
        showV13Toast(context, 'Thanks — our team will take a look.');
      }
    } on ApiException catch (e) {
      if (mounted) _toastError(e, 'send that');
    } catch (_) {
      if (mounted) showV13Toast(context, "Couldn't send that. Try again.");
    }
  }

  Future<void> _openMenu() async {
    final race = _race;
    final user = ref.read(authControllerProvider).user;
    if (race == null || user == null) return;
    final isOwner = race.isCreator(user.id);
    final isParticipant = race.isParticipant(user.id);
    final active = raceIsActive(race);
    final action = await showV13ActionSheet<String>(
      context,
      actions: [
        if (active)
          const V13SheetAction(
            label: 'Invite friends',
            value: 'invite',
            icon: Icons.person_add_alt_1_rounded,
          ),
        if (isOwner)
          const V13SheetAction(
            label: 'Race settings',
            value: 'settings',
            icon: Icons.tune_rounded,
          ),
        if (isParticipant && !isOwner && active)
          const V13SheetAction(
            label: 'Leave race',
            value: 'leave',
            icon: Icons.logout_rounded,
            destructive: true,
          ),
        if (!isOwner)
          const V13SheetAction(
            label: 'Report this race',
            value: 'report',
            icon: Icons.flag_outlined,
            destructive: true,
          ),
        if (isOwner && active)
          const V13SheetAction(
            label: 'Cancel race',
            value: 'cancel',
            icon: Icons.cancel_outlined,
            destructive: true,
          ),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'invite':
        await context.push('/race/${race.id}/invite');
      case 'settings':
        await context.push('/race/${race.id}/settings');
      case 'leave':
        await _leave();
      case 'report':
        await _report();
      case 'cancel':
        await _cancel();
    }
  }

  String _ruleLine(Race race) {
    final format =
        RaceFormat.fromBackendValue(race.format) ?? RaceFormat.firstToGoal;
    final unit = raceDisplayUnit(race);
    return switch (format) {
      RaceFormat.firstToGoal => 'First to ${raceTargetLabel(race)}',
      RaceFormat.mostInWindow => 'Most $unit before the finish line',
      RaceFormat.bestAttempt =>
        race.scoreDirection == 'lower'
            ? 'Lowest single score wins'
            : 'Best single attempt wins',
      RaceFormat.timedAttempt => timedAttemptRuleLine(
        race.scoreDirection,
        race.attemptDurationSeconds,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final race = _race;
    Widget content;
    if (_loading && race == null) {
      content = const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(color: V13.blue, strokeWidth: 3),
        ),
      );
    } else if (race == null) {
      content = Column(
        children: [
          V13BackBar(
            title: 'Race',
            onBack: () => safePopOrGo(context, '/compete'),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _error ?? 'Race not found.',
                    style: V13.body.copyWith(color: V13.muted),
                  ),
                  const SizedBox(height: V13.gapLg),
                  V13Button.secondary(label: 'Retry', onPressed: _load),
                ],
              ),
            ),
          ),
        ],
      );
    } else {
      content = _body(race);
    }
    return Scaffold(
      backgroundColor: V13.bg,
      // The race body draws its own full-bleed hero under the status bar;
      // loading / error states keep the safe area.
      body: race != null ? content : SafeArea(bottom: false, child: content),
    );
  }

  Widget _body(Race race) {
    final user = ref.watch(authControllerProvider).user;
    final uid = user?.id;
    final isOwner = uid != null && race.isCreator(uid);
    final isParticipant = uid != null && race.isParticipant(uid);
    final completed = raceIsCompleted(race);
    final active = raceIsActive(race);
    final canVerify = active && (isOwner || isParticipant);
    final canJoin = active && !isOwner && !isParticipant;
    final chase = uid == null ? null : ChaseContext.compute(race, uid);
    final sorted = serverRankedParticipants(race);
    final me = isParticipant ? race.participantFor(uid) : null;
    final canOpenProofs = raceCanInspectProofs(race, uid);
    final showHero = me != null && !completed;

    Future<void> submit() async {
      await openSubmitProof(context, ref, race);
      _load();
    }

    // The one blue action. Submit lives inside the hero; the sticky copy
    // only shows once the hero is scrolled away.
    final (primaryLabel, onPrimary, primaryIcon) = canJoin
        ? ('Join race', _join, Icons.flag_rounded)
        : completed
        ? (
            isOwner || isParticipant ? 'Race again' : 'Start another race',
            isOwner || isParticipant
                ? _rematch
                : () => context.push('/races/new'),
            Icons.replay_rounded,
          )
        : canVerify
        ? ('Submit proof', submit, Icons.check_rounded)
        : ('', null, Icons.check_rounded);
    final stickyOnlyWhenHeroHidden = showHero && canVerify;

    var stagger = 0;
    Widget enter(Widget child, String key) =>
        V13StaggerIn(key: ValueKey(key), index: stagger++, child: child);

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            color: V13.blue,
            edgeOffset: MediaQuery.paddingOf(context).top,
            child: ListView(
              controller: _scroll,
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + 120,
              ),
              children: [
                KeyedSubtree(
                  key: _heroKey,
                  child: _topHero(
                    race,
                    me,
                    chase,
                    sorted,
                    completed: completed,
                    onSubmit: showHero && canVerify ? submit : null,
                  ),
                ),
                const SizedBox(height: V13.gapXl),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      enter(
                        completed && race.finalStandings.isNotEmpty
                            ? _finalStandings(race, uid)
                            : _standings(race, sorted, uid),
                        'standings',
                      ),
                      const SizedBox(height: V13.gapSection),
                      enter(_activity(race, canOpenProofs), 'activity'),
                      const SizedBox(height: V13.gapSection),
                      enter(_about(race, active), 'about'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (onPrimary != null && primaryLabel.isNotEmpty)
          ValueListenableBuilder<bool>(
            valueListenable: _heroVisible,
            builder: (context, heroVisible, _) {
              final show = !stickyOnlyWhenHeroHidden || !heroVisible;
              return AnimatedSize(
                duration: V13Motion.fast,
                curve: Curves.easeOutCubic,
                child: show
                    ? Padding(
                        padding: EdgeInsets.fromLTRB(
                          V13.pagePad,
                          V13.gapSm,
                          V13.pagePad,
                          MediaQuery.paddingOf(context).bottom + V13.gapSm,
                        ),
                        child: V13Button.primary(
                          label: primaryLabel,
                          icon: primaryIcon,
                          loading: _busy,
                          fullWidth: true,
                          onPressed: onPrimary,
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              );
            },
          ),
      ],
    );
  }

  // ── Meta chips ──────────────────────────────────────────────────────────

  Widget _metaChips(Race race, ChaseContext? chase, bool completed) {
    final icon = raceActivityDefinition(race)?.icon ?? Icons.flag_rounded;
    final n = race.participants.length;
    Widget chip(IconData? i, String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: V13.card,
        borderRadius: BorderRadius.circular(V13.radiusPill),
        border: Border.all(color: V13.divider, width: V13.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (i != null) ...[
            Icon(i, size: 15, color: V13.navy),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              style: V13.caption.copyWith(
                color: V13.navy,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    return Wrap(
      spacing: V13.gapSm,
      runSpacing: V13.gapSm,
      children: [
        chip(icon, _ruleLine(race)),
        if (completed)
          chip(Icons.flag_circle_rounded, 'Finished')
        else if (chase?.timeLeft != null)
          chip(Icons.schedule_rounded, '${chase!.timeLeft} left'),
        chip(Icons.group_rounded, '$n ${n == 1 ? 'racer' : 'racers'}'),
      ],
    );
  }

  // ── Top hero ────────────────────────────────────────────────────────────

  /// Full-bleed hero in the race's colour: back + menu, big title, meta
  /// chips, and (for racers) the big number, place, chase line and Submit —
  /// one surface with a rounded bottom that flows into the standings.
  Widget _topHero(
    Race race,
    RaceParticipant? me,
    ChaseContext? chase,
    List<RaceParticipant> sorted, {
    required bool completed,
    VoidCallback? onSubmit,
  }) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      decoration: BoxDecoration(
        color: V13.raceColor(race.id),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(V13.radiusCardLg + 8),
        ),
        border: const Border(
          bottom: BorderSide(color: V13.navy, width: V13.outline),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        V13.pagePad,
        top + V13.gapSm,
        V13.pagePad,
        V13.gapXl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              V13IconButton(
                icon: Icons.arrow_back_rounded,
                onTap: () => safePopOrGo(context, '/compete'),
                semanticLabel: 'Back',
              ),
              const Spacer(),
              V13IconButton(
                icon: Icons.more_horiz_rounded,
                onTap: _openMenu,
                semanticLabel: 'Race actions',
              ),
            ],
          ),
          const SizedBox(height: V13.gapLg),
          Text(
            race.displayTitle,
            style: V13.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: V13.gapMd),
          _metaChips(race, chase, completed),
          if (me != null && !completed) ...[
            const SizedBox(height: V13.gapXl),
            _youHero(race, me, chase, sorted, onSubmit: onSubmit),
          ],
        ],
      ),
    );
  }

  // ── YOU hero ────────────────────────────────────────────────────────────

  String _chaseLine(Race race, ChaseContext? chase, List<RaceParticipant> all) {
    if (all.every((p) => p.progressValue <= 0)) {
      return 'No one’s moved yet. First proof takes the lead.';
    }
    return chase?.chaseCopy ?? 'Keep going.';
  }

  Widget _youHero(
    Race race,
    RaceParticipant me,
    ChaseContext? chase,
    List<RaceParticipant> sorted, {
    VoidCallback? onSubmit,
  }) {
    final hasGoal = raceHasFinishLine(race);
    final rank = rankForUser(race, me.userId);
    final type = raceMeasurementType(race);
    final reps = type == MotionMeasurementType.repetitions;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('YOU', style: V13.label.copyWith(color: V13.navy)),
            const Spacer(),
            if (rank != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: V13.card,
                  borderRadius: BorderRadius.circular(V13.radiusPill),
                  border: Border.all(color: V13.navy, width: V13.outline),
                ),
                child: Text(
                  '${raceOrdinal(rank)} of ${sorted.length}',
                  style: V13.bodyStrong.copyWith(fontSize: 14),
                ),
              ),
          ],
        ),
        const SizedBox(height: V13.gapSm),
        // Count up to the current value. Reps get a big number + unit;
        // time / distance use the shared formatter so units never drift.
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: me.progressValue.toDouble()),
          duration: reduce ? Duration.zero : const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) {
            final n = v.round();
            if (!reps) {
              return Text(
                raceScoreLabel(race, n),
                style: V13.hugeNumber.copyWith(fontSize: 48),
                maxLines: 1,
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('$n', style: V13.hugeNumber.copyWith(fontSize: 64)),
                const SizedBox(width: V13.gapSm),
                Flexible(
                  child: Text(
                    hasGoal
                        ? '/ ${race.targetValue} ${raceDisplayUnit(race)}'
                        : raceDisplayUnit(race),
                    style: V13.numberSm.copyWith(color: V13.navy),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            );
          },
        ),
        if (hasGoal) ...[
          const SizedBox(height: V13.gapSm),
          V13ProgressBar(
            value: raceProgressPercent(race, me) / 100,
            trackColor: V13.card,
          ),
        ],
        const SizedBox(height: V13.gapMd),
        Text(_chaseLine(race, chase, sorted), style: V13.bodyStrong),
        if (race.attemptLimit != null) ...[
          const SizedBox(height: 4),
          Text(
            '${race.viewerContext?.attemptsUsed ?? 0} of ${race.attemptLimit} attempts used',
            style: V13.caption.copyWith(color: V13.navy),
          ),
        ],
        // Stage S5 slot: the timed-battle countdown / "start attempt"
        // entry point mounts here, right above Submit proof.
        raceDetailAttemptSlot(context, race),
        if (onSubmit != null) ...[
          const SizedBox(height: V13.gapLg),
          V13Button.primary(
            label: 'Submit proof',
            icon: Icons.check_rounded,
            fullWidth: true,
            onPressed: appOnline(ref) ? onSubmit : null,
          ),
          if (!appOnline(ref)) const NeedsInternetLine(),
        ],
      ],
    );
  }

  // ── Standings ───────────────────────────────────────────────────────────

  Widget _standings(Race race, List<RaceParticipant> sorted, String? uid) {
    if (sorted.isEmpty) {
      return Text(
        'No one on the board yet — invite your friends.',
        style: V13.body.copyWith(color: V13.muted),
      );
    }
    final moved = sorted.where((p) => p.progressValue > 0).toList();
    if (moved.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('STANDINGS', style: V13.label),
          const SizedBox(height: V13.gapMd),
          Row(
            children: [
              V13FaceStack(
                faces: [
                  for (final p in sorted)
                    V13FaceInfo(
                      photoUrl: p.profilePhotoUrl,
                      name: p.displayName,
                      isMe: p.userId == uid,
                    ),
                ],
                total: sorted.length,
                max: 6,
                size: 36,
              ),
              const SizedBox(width: V13.gapMd),
              Expanded(
                child: Text(
                  'Everyone’s at 0',
                  style: V13.body.copyWith(color: V13.muted),
                ),
              ),
            ],
          ),
        ],
      );
    }
    final podium = moved.length >= 3;
    final listFrom = podium ? 3 : 0;
    final rest = sorted.skip(listFrom).toList();
    final visible = _showAllRacers ? rest : rest.take(8).toList();
    final rankCounts = <int, int>{};
    for (final p in sorted) {
      final r = p.rank ?? 0;
      rankCounts[r] = (rankCounts[r] ?? 0) + 1;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('STANDINGS', style: V13.label),
        const SizedBox(height: V13.gapMd),
        if (podium) ...[
          Center(child: _podium(moved.take(3).toList(), uid)),
          const SizedBox(height: V13.gapLg),
        ],
        for (var i = 0; i < visible.length; i++)
          _boardRow(
            race,
            visible[i],
            visible[i].rank ?? (listFrom + i + 1),
            uid,
            tied: (rankCounts[visible[i].rank ?? -1] ?? 0) > 1,
          ),
        if (rest.length > 8 && !_showAllRacers)
          Padding(
            padding: const EdgeInsets.only(top: V13.gapSm),
            child: V13Button.ghost(
              label: 'Show all ${sorted.length} racers',
              onPressed: () => setState(() => _showAllRacers = true),
            ),
          ),
      ],
    );
  }

  Widget _podium(List<RaceParticipant> top, String? uid) {
    final order = [
      for (final i in [1, 0, 2])
        if (i < top.length) top[i],
    ];
    final places = [
      for (final i in [1, 0, 2])
        if (i < top.length) i + 1,
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < order.length; i++) ...[
          if (i > 0) const SizedBox(width: V13.gapMd),
          _podiumPerson(order[i], places[i], uid),
        ],
      ],
    );
  }

  Widget _podiumPerson(RaceParticipant p, int place, String? uid) {
    final size = place == 1 ? 72.0 : 54.0;
    return SizedBox(
      width: 96,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (place == 1) ...[
            const Icon(Icons.emoji_events_rounded, color: V13.gold, size: 24),
            const SizedBox(height: 2),
          ],
          V13Face(
            photoUrl: p.profilePhotoUrl,
            size: size,
            isMe: p.userId == uid,
            name: p.displayName,
            onTap: () => openPerson(context, ref, p.userId),
          ),
          const SizedBox(height: V13.gapSm),
          V13MedalCircle(place: place, size: 24),
          const SizedBox(height: 2),
          Text(
            p.userId == uid ? 'You' : p.displayName.split(' ').first,
            style: V13.bodyStrong.copyWith(fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            raceScoreLabel(_race!, p.progressValue),
            style: V13.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _boardRow(
    Race race,
    RaceParticipant p,
    int rank,
    String? uid, {
    bool tied = false,
  }) {
    final mine = p.userId == uid;
    final hasGoal = raceHasFinishLine(race);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: V13.gapSm, vertical: 10),
      child: Row(
        children: [
          // Fixed rank column: #1–#99 always fit on one line.
          SizedBox(
            width: 40,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '${tied ? '=' : '#'}$rank',
                style: V13.numberSm,
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
          V13Face(
            photoUrl: p.profilePhotoUrl,
            size: 36,
            isMe: mine,
            name: p.displayName,
            onTap: () => openPerson(context, ref, p.userId),
          ),
          const SizedBox(width: V13.gapMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mine ? 'You' : p.displayName,
                  style: V13.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (hasGoal) ...[
                  const SizedBox(height: 4),
                  V13ProgressBar(
                    value: raceProgressPercent(race, p) / 100,
                    height: 6,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: V13.gapMd),
          Text(raceScoreLabel(race, p.progressValue), style: V13.bodyStrong),
        ],
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openPerson(context, ref, p.userId),
      child: mine
          ? Container(
              decoration: BoxDecoration(
                color: V13.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(V13.radiusTileLg),
              ),
              child: row,
            )
          : row,
    );
  }

  // ── Activity ────────────────────────────────────────────────────────────

  Widget _activity(Race race, bool canOpen) {
    final proofs = race.recentProofs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ACTIVITY', style: V13.label),
        const SizedBox(height: V13.gapSm),
        if (proofs.isEmpty)
          Text(
            raceIsActive(race)
                ? 'No proofs yet — the first one sets the pace.'
                : 'Nobody logged a move in this race.',
            style: V13.body.copyWith(color: V13.muted),
          )
        else
          for (var i = 0; i < proofs.length && i < 12; i++) ...[
            if (i > 0) const V13Divider(),
            _proofRow(race, proofs[i], canOpen),
          ],
      ],
    );
  }

  Widget _proofRow(Race race, RaceProof proof, bool canOpen) {
    final name = proof.displayName.trim().split(RegExp(r'\s+')).first;
    final value = proof.value;
    final amount = value == null
        ? 'logged a proof'
        : raceIsAccumulating(race)
        ? '+${raceScoreLabel(race, value)}'
        : raceScoreLabel(race, value);
    final when = DateTime.tryParse(proof.createdAt);
    final meta = [
      if (when != null) notificationRelativeTime(when.toUtc()),
      proof.proofType == 'ai_motion' ? 'Camera' : 'Manual',
      if (proof.verificationStatus == 'pending_review') 'pending',
    ].join(' · ');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canOpen
          ? () => context.push('/race/${race.id}/proofs/${proof.id}')
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: V13.gapMd),
        child: Row(
          children: [
            V13Face(
              photoUrl: proof.profilePhotoUrl,
              size: 36,
              name: proof.displayName,
            ),
            const SizedBox(width: V13.gapMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: name, style: V13.bodyStrong),
                        TextSpan(text: ' $amount', style: V13.body),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(meta, style: V13.caption),
                ],
              ),
            ),
            if (canOpen)
              const Icon(Icons.chevron_right_rounded, color: V13.muted),
          ],
        ),
      ),
    );
  }

  // ── About ───────────────────────────────────────────────────────────────

  Widget _about(Race race, bool active) {
    final finish = DateTime.tryParse(race.finishLineAt ?? '')?.toLocal();
    final creator = race.participantFor(race.creatorId)?.displayName;
    final facts = [
      '${raceModeLabel(race.format)} — ${_ruleLine(race)}.',
      if (finish != null)
        'Finish line: ${MaterialLocalizations.of(context).formatMediumDate(finish)}.',
      if (creator != null) 'Started by $creator.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ABOUT THIS RACE', style: V13.label),
        const SizedBox(height: V13.gapSm),
        for (final f in facts) ...[
          Text(f, style: V13.body),
          const SizedBox(height: 4),
        ],
        if (active) ...[
          const SizedBox(height: V13.gapMd),
          V13Button.secondary(
            label: 'Invite friends',
            icon: Icons.person_add_alt_1_rounded,
            onPressed: appOnline(ref)
                ? () => context.push('/race/${race.id}/invite')
                : null,
          ),
        ],
      ],
    );
  }

  Widget _finalStandings(Race race, String? uid) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('FINAL STANDINGS', style: V13.label),
        const SizedBox(height: V13.gapMd),
        for (var i = 0; i < race.finalStandings.length; i++) ...[
          if (i > 0) const V13Divider(),
          Builder(
            builder: (_) {
              final s = race.finalStandings[i];
              return V13ListRow(
                title: s.userId == uid ? 'You' : s.displayName,
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    V13MedalCircle(place: s.rank, size: 30),
                    const SizedBox(width: V13.gapSm),
                    V13Face(
                      photoUrl: s.profilePhotoUrl,
                      size: 34,
                      isMe: s.userId == uid,
                      name: s.displayName,
                    ),
                  ],
                ),
                trailing: Text(
                  raceScoreLabel(race, s.scoreValue),
                  style: V13.bodyStrong,
                ),
                onTap: () => openPerson(context, ref, s.userId),
                showDivider: false,
              );
            },
          ),
        ],
      ],
    );
  }
}

class _ReportSheet extends StatelessWidget {
  const _ReportSheet({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(V13.pagePad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Report this race?', style: V13.sectionHead),
          const SizedBox(height: V13.gapSm),
          Text(
            'What\u2019s wrong? This goes to the Nuvo review team.',
            style: V13.body,
          ),
          const SizedBox(height: V13.gapMd),
          V13Card(
            padding: const EdgeInsets.symmetric(
              horizontal: V13.gapMd,
              vertical: 2,
            ),
            child: TextField(
              controller: controller,
              maxLines: 3,
              maxLength: 500,
              style: V13.body,
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: 'Optional details',
                hintStyle: TextStyle(color: V13.muted),
                counterStyle: TextStyle(color: V13.muted),
              ),
            ),
          ),
          const SizedBox(height: V13.gapMd),
          V13Button.primary(
            label: 'Send report',
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          ),
        ],
      ),
    );
  }
}

/// Stage S5 slot (race thread): the timed-battle countdown and "start
/// attempt" entry point mount inside the YOU hero, directly above Submit
/// proof. Renders nothing until S5 lands.
Widget raceDetailAttemptSlot(BuildContext context, Race race) =>
    const SizedBox.shrink();
