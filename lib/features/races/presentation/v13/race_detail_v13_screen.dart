import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/navigation/nuvo_navigation.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/v13/v13.dart';
import '../../../auth/data/auth_api.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../crew/application/crew_controller.dart';
import '../../../race_detail/domain/race_poll_backoff.dart';
import '../../data/race_models.dart';
import '../../domain/chase_context.dart';
import '../../domain/motion_activity.dart';
import '../../domain/race_display.dart';
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
  bool _proofsOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resumed =
        (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) ==
        AppLifecycleState.resumed;
    _load();
    _scheduleNext();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
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
      if (mounted) setState(() => _race = race);
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
      RaceFormat.timedAttempt =>
        'Most in ${formatDurationShort(race.attemptDurationSeconds ?? 0)} wins',
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
      body: SafeArea(bottom: false, child: content),
    );
  }

  Widget _body(Race race) {
    final user = ref.watch(authControllerProvider).user;
    final uid = user?.id;
    final isOwner = uid != null && race.isCreator(uid);
    final isParticipant = uid != null && race.isParticipant(uid);
    final completed = raceIsCompleted(race);
    final canVerify = raceIsActive(race) && (isOwner || isParticipant);
    final canJoin = raceIsActive(race) && !isOwner && !isParticipant;
    final chase = uid == null ? null : ChaseContext.compute(race, uid);
    final sorted = serverRankedParticipants(race);
    final me = isParticipant ? race.participantFor(uid) : null;
    final canOpenProofs = raceCanInspectProofs(race, uid);

    final (primaryLabel, onPrimary) = canJoin
        ? ('Join race', _join)
        : completed
        ? (
            isOwner || isParticipant ? 'Race again' : 'Start another race',
            isOwner || isParticipant
                ? _rematch
                : () => context.push('/races/new'),
          )
        : canVerify
        ? (
            'Submit proof',
            () async {
              await openSubmitProof(context, ref, race);
              _load();
            },
          )
        : ('', null);

    return Column(
      children: [
        V13BackBar(
          title: race.displayTitle,
          onBack: () => safePopOrGo(context, '/compete'),
          trailing: [
            V13IconButton(
              icon: Icons.more_horiz_rounded,
              onTap: _openMenu,
              semanticLabel: 'Race actions',
            ),
          ],
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            color: V13.blue,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                V13.pagePad,
                V13.gapMd,
                V13.pagePad,
                96,
              ),
              children: [
                Row(
                  children: [
                    Expanded(child: Text(_ruleLine(race), style: V13.body)),
                    if (chase?.timeLeft != null && !completed)
                      V13Pill(
                        label: '${chase!.timeLeft} left',
                        color: V13.sun,
                        textColor: V13.navy,
                      ),
                  ],
                ),
                const SizedBox(height: V13.gapLg),
                if (completed && race.finalStandings.isNotEmpty)
                  _finalStandings(race, uid)
                else ...[
                  _podium(sorted, uid),
                  if (sorted.length > 3) ...[
                    const SizedBox(height: V13.gapMd),
                    for (var i = 3; i < sorted.length; i++) ...[
                      const V13Divider(),
                      _boardRow(race, sorted[i], i + 1, uid),
                    ],
                  ],
                  if (sorted.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: V13.gapXl),
                      child: Text(
                        'No one on the board yet — invite your friends.',
                        style: V13.body,
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
                if (isParticipant && !completed && me != null) ...[
                  const SizedBox(height: V13.gapLg),
                  V13Card(
                    padding: const EdgeInsets.all(V13.gapMd),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            V13NumberPop(
                              value: me.progressValue,
                              style: V13.number,
                            ),
                            const SizedBox(width: V13.gapSm),
                            Expanded(
                              child: Text(
                                raceDisplayUnit(race),
                                style: V13.caption,
                              ),
                            ),
                            Text(
                              raceRankLabel(race, uid),
                              style: V13.bodyStrong.copyWith(color: V13.blue),
                            ),
                          ],
                        ),
                        const SizedBox(height: V13.gapSm),
                        V13ProgressBar(
                          value: raceProgressPercent(race, me) / 100,
                        ),
                        if (chase?.chaseCopy != null) ...[
                          const SizedBox(height: V13.gapSm),
                          Text(chase!.chaseCopy!, style: V13.caption),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: V13.gapLg),
                _proofsSection(race, canOpenProofs),
              ],
            ),
          ),
        ),
        if (onPrimary != null && primaryLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              V13.pagePad,
              0,
              V13.pagePad,
              V13.gapLg,
            ),
            child: V13Button.primary(
              label: primaryLabel,
              icon: canJoin
                  ? Icons.flag_rounded
                  : completed
                  ? Icons.replay_rounded
                  : Icons.check_rounded,
              loading: _busy,
              fullWidth: true,
              onPressed: onPrimary,
            ),
          ),
      ],
    );
  }

  Widget _podium(List<RaceParticipant> sorted, String? uid) {
    if (sorted.isEmpty) return const SizedBox.shrink();
    final top = sorted.take(3).toList();
    // Podium order: 2nd, 1st, 3rd — the leader stands taller in the middle.
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
      mainAxisAlignment: MainAxisAlignment.center,
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
    final size = place == 1 ? 76.0 : 56.0;
    return SizedBox(
      width: 92,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (place == 1) ...[
            const Icon(Icons.emoji_events_rounded, color: V13.gold, size: 26),
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
          V13MedalCircle(place: place, size: 26),
          const SizedBox(height: 2),
          Text(
            p.userId == uid ? 'You' : p.displayName.split(' ').first,
            style: V13.label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            raceProgressLabel(_race!, p),
            style: V13.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _boardRow(Race race, RaceParticipant p, int rank, String? uid) =>
      V13ListRow(
        title: p.userId == uid ? 'You' : p.displayName,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 30, child: Text('#$rank', style: V13.numberSm)),
            V13Face(
              photoUrl: p.profilePhotoUrl,
              size: 34,
              isMe: p.userId == uid,
              name: p.displayName,
            ),
          ],
        ),
        trailing: Text(raceProgressLabel(race, p), style: V13.bodyStrong),
        onTap: () => openPerson(context, ref, p.userId),
        showDivider: false,
      );

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

  Widget _proofsSection(Race race, bool canOpen) {
    final proofs = race.recentProofs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        V13Pressable(
          onTap: () => setState(() => _proofsOpen = !_proofsOpen),
          pressDepth: 1.5,
          semanticLabel: _proofsOpen ? 'Hide proofs' : 'Show proofs',
          child: Row(
            children: [
              Text('PROOFS', style: V13.label),
              const SizedBox(width: V13.gapSm),
              Text('${proofs.length}', style: V13.caption),
              const Spacer(),
              Icon(
                _proofsOpen
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: V13.muted,
              ),
            ],
          ),
        ),
        if (_proofsOpen) ...[
          const SizedBox(height: V13.gapSm),
          if (proofs.isEmpty)
            Text('No moves logged yet.', style: V13.body)
          else
            for (var i = 0; i < proofs.length && i < 8; i++) ...[
              if (i > 0) const V13Divider(),
              V13ListRow(
                title: proofs[i].displayName,
                subtitle: _proofLine(race, proofs[i]),
                leading: V13Face(
                  photoUrl: proofs[i].profilePhotoUrl,
                  size: 32,
                  name: proofs[i].displayName,
                ),
                trailing: proofs[i].value != null
                    ? Text(
                        raceIsAccumulating(race)
                            ? '+${raceScoreLabel(race, proofs[i].value!)}'
                            : raceScoreLabel(race, proofs[i].value!),
                        style: V13.bodyStrong,
                      )
                    : null,
                onTap: canOpen
                    ? () => context.push(
                        '/race/${race.id}/proofs/${proofs[i].id}',
                      )
                    : null,
                showDivider: false,
              ),
            ],
        ],
      ],
    );
  }

  String _proofLine(Race race, RaceProof proof) {
    final when = proof.createdAt;
    final time = DateTime.tryParse(when)?.toLocal();
    final clock = time == null
        ? ''
        : ' · ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final status = proof.verificationStatus == 'pending_review'
        ? ' · pending'
        : '';
    return '${proof.proofType == 'ai_motion' ? 'Camera proof' : 'Manual proof'}$clock$status';
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
