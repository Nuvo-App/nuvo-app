import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/config/nuvo_flags.dart';
import '../../../../../core/navigation/nuvo_navigation.dart';
import '../../../../../core/utils/friendly_error.dart';
import '../../../../../core/v13/v13.dart';
import '../../../../auth/data/auth_api.dart';
import '../../../../squads/application/squad_controller.dart';
import '../../../data/race_models.dart';
import '../../../domain/motion_activity.dart';
import '../../../domain/motion_activity_catalog.dart';
import '../../../domain/race_draft.dart';
import '../../../domain/race_mode_semantics.dart';
import '../../../domain/race_name_interpreter.dart';
import '../../../domain/race_safety.dart';
import '../../custom_pose/learned_custom_movement_provider.dart';
import '../../custom_pose/teach_movement_screen.dart';
import '../../motion_catalog_provider.dart';
import '../../race_controller.dart';

/// v13 race composer — four steps: name (with live autofill), setup
/// (movement + goal + mode), invite friends, review.
class RaceComposerV13Screen extends ConsumerStatefulWidget {
  const RaceComposerV13Screen({super.key, this.prefill});

  final RaceCreatePrefill? prefill;

  @override
  ConsumerState<RaceComposerV13Screen> createState() =>
      _RaceComposerV13ScreenState();
}

class _RaceComposerV13ScreenState extends ConsumerState<RaceComposerV13Screen> {
  late RaceDraft _draft;
  int _step = 0;
  bool _loading = false;
  String? _error;

  List<PublicUser> _friends = const [];
  bool _friendsLoading = false;
  String? _friendsError;
  final Set<String> _invited = {};

  List<MotionActivityDefinition> get _catalog => availableMotionActivities(
    ref.read(motionCatalogProvider).valueOrNull,
    ref.read(motionCapabilitiesProvider),
  );

  @override
  void initState() {
    super.initState();
    final prefill = widget.prefill;
    final idea = prefill?.idea;
    var draft = prefill?.draft ?? (idea != null ? draftFromIdea(idea) : null);
    draft ??= draftForActivity(motionActivityDefinitions.first);
    if (prefill?.withUser != null) {
      draft = draft.copyWith(inviteCrew: true);
      _invited.add(prefill!.withUser!.id);
    }
    _draft = draft;
  }

  void _update(RaceDraft d) => setState(() => _draft = d);

  void _next() {
    if (_step == 2) _loadFriends();
    setState(() {
      _step = (_step + 1).clamp(0, 3);
      _error = null;
    });
  }

  void _back() {
    if (_step == 0) {
      safePopOrGo(context, '/compete');
      return;
    }
    setState(() {
      _step -= 1;
      _error = null;
    });
  }

  Future<void> _loadFriends() async {
    if (_friendsLoading || _friends.isNotEmpty) return;
    setState(() {
      _friendsLoading = true;
      _friendsError = null;
    });
    try {
      final friends = await ref.read(raceControllerProvider.notifier).getCrew();
      if (mounted) {
        setState(() {
          _friends = friends;
          _friendsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _friendsError = 'Could not load your friends.';
          _friendsLoading = false;
        });
      }
    }
  }

  /// The same create dispatch the old composer runs: custom movements go to
  /// `createCustomRace`, everything else to `createRace` with the draft's
  /// canonical payload — the API contract lives in [RaceDraft.toCreatePayload].
  Future<Race> _createRace(RaceController controller, RaceDraft draft) {
    if (draft.isCustom) {
      final racesToTarget = draft.format.usesScoreTarget;
      return controller.createCustomRace(
        title: draft.resolvedTitle,
        targetValue: racesToTarget ? draft.targetValue : null,
        customActivityName: draft.customActivityName!,
        verifierSpec: draft.verifierSpec,
        motionV2Spec: draft.motionV2Spec,
        format: draft.format.backendValue,
        finishLineAt: racesToTarget ? null : draft.finishLineAt,
        attemptDurationSeconds: racesToTarget
            ? null
            : draft.attemptDurationSeconds,
        attemptLimit: racesToTarget ? null : draft.attemptLimit,
        scoreDirection: draft.scoreDirection,
      );
    }
    final payload = draft.toCreatePayload();
    return controller.createRace(
      title: payload['title'] as String,
      description: payload['description'] as String,
      category: payload['category'] as String,
      goalType: payload['goalType'] as String,
      targetValue: payload['targetValue'] as int?,
      unit: payload['unit'] as String,
      proofRequirement: payload['proofRequirement'] as String,
      proofReviewMode: payload['proofReviewMode'] as String,
      aiActivityType: payload['aiActivityType'] as String?,
      activityId: payload['activityId'] as String?,
      metric: payload['metric'] as String,
      format: payload['format'] as String,
      recurrence: payload['recurrence'] as String,
      targetUnit: payload['targetUnit'] as String,
      proofMode: payload['proofMode'] as String,
      scoreDirection: payload['scoreDirection'] as String?,
    );
  }

  Future<void> _startRace() async {
    if (_loading) return;
    if (!_draft.isValidToCreate) {
      setState(
        () => _error = _draft.isManual
            ? 'Name the goal and how it is measured.'
            : 'Finish setting up your race first.',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final controller = ref.read(raceControllerProvider.notifier);
      final race = await _createRace(controller, _draft);
      if (!mounted) return;

      final crewId = widget.prefill?.crewId;
      var sent = 0;
      if (crewId != null) {
        try {
          await ref
              .read(squadControllerProvider.notifier)
              .addRace(crewId, race.id);
        } catch (_) {}
      } else {
        for (final friend in _friends) {
          if (!_invited.contains(friend.id)) continue;
          try {
            await controller.addRaceParticipant(
              race.id,
              friend.id,
              user: friend,
            );
            sent++;
          } catch (_) {}
        }
      }
      ref.read(raceControllerProvider.notifier).loadRaces(force: true);
      if (!mounted) return;
      showV13Confetti(context);
      showV13Toast(
        context,
        crewId != null
            ? '${race.displayTitle} is live.'
            : '${race.displayTitle} is live. $sent '
                  'invite${sent == 1 ? '' : 's'} sent.',
      );
      context.go('/compete');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.statusCode >= 500
              ? "Couldn't create the race. Try again."
              : friendlyApiError(e);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = "Couldn't create the race. Try again.";
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _NameStep(
        key: const ValueKey('name'),
        draft: _draft,
        catalog: _catalog,
        onUpdate: _update,
        onNext: _next,
      ),
      _SetupStep(
        key: const ValueKey('setup'),
        draft: _draft,
        catalog: _catalog,
        onUpdate: _update,
        onNext: _next,
      ),
      _FriendsStep(
        key: const ValueKey('friends'),
        friends: _friends,
        loading: _friendsLoading,
        error: _friendsError,
        onRetry: () {
          setState(() => _friends = const []);
          _loadFriends();
        },
        invited: _invited,
        onToggle: (id) => setState(
          () => _invited.contains(id) ? _invited.remove(id) : _invited.add(id),
        ),
        crewName: widget.prefill?.crewId == null
            ? null
            : (widget.prefill?.crewName ?? 'your crew'),
        onNext: _next,
      ),
      _ReviewStep(
        key: const ValueKey('review'),
        draft: _draft,
        invitedCount: _invited.length,
        loading: _loading,
        error: _error,
        onJump: (i) => setState(() => _step = i),
        onStart: _startRace,
      ),
    ];
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: V13.bg,
        body: SafeArea(
          child: Column(
            children: [
              _ComposerBar(step: _step, onBack: _loading ? null : _back),
              Expanded(
                child: AnimatedSwitcher(
                  duration: V13Motion.medium,
                  child: pages[_step],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerBar extends StatelessWidget {
  const _ComposerBar({required this.step, required this.onBack});
  final int step;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V13.pagePad,
        V13.gapMd,
        V13.pagePad,
        V13.gapSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              V13IconButton(
                icon: Icons.arrow_back_rounded,
                onTap: onBack,
                semanticLabel: 'Back',
              ),
              const Spacer(),
              Text('${step + 1} of 4', style: V13.label),
            ],
          ),
          const SizedBox(height: V13.gapMd),
          V13ProgressBar(value: (step + 1) / 4),
        ],
      ),
    );
  }
}

class _StepShell extends StatelessWidget {
  const _StepShell({
    required this.question,
    required this.body,
    this.ctaLabel,
    this.onCta,
    this.ctaEnabled = true,
    this.ctaLoading = false,
  });
  final String question;
  final Widget body;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final bool ctaEnabled;
  final bool ctaLoading;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        V13.pagePad,
        V13.gapLg,
        V13.pagePad,
        V13.gapSection,
      ),
      children: [
        Text(question, style: V13.title),
        const SizedBox(height: V13.gapLg),
        body,
        if (ctaLabel != null) ...[
          const SizedBox(height: V13.gapXl),
          V13Button.primary(
            label: ctaLabel!,
            onPressed: ctaEnabled ? onCta : null,
            loading: ctaLoading,
          ),
        ],
      ],
    );
  }
}

// ── Step 1: name + live autofill ─────────────────────────────────────────────

class _NameStep extends StatefulWidget {
  const _NameStep({
    super.key,
    required this.draft,
    required this.catalog,
    required this.onUpdate,
    required this.onNext,
  });
  final RaceDraft draft;
  final List<MotionActivityDefinition> catalog;
  final ValueChanged<RaceDraft> onUpdate;
  final VoidCallback onNext;

  @override
  State<_NameStep> createState() => _NameStepState();
}

class _NameStepState extends State<_NameStep> {
  late final TextEditingController _ctrl;
  Timer? _debounce;
  FlexiRaceInterpretation? _guess;

  @override
  void initState() {
    super.initState();
    // Start empty for a fresh race (the hint shows an example); only a name
    // the person (or a prefill) actually chose is carried in.
    _ctrl = TextEditingController(
      text: widget.draft.hasCustomName ? widget.draft.resolvedTitle : '',
    );
    _ctrl.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 350), _interpret);
    });
    _interpret();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _interpret() {
    final text = _ctrl.text.trim();
    if (!mounted) return;
    setState(
      () => _guess = text.isEmpty
          ? null
          : interpretRaceName(text, catalog: widget.catalog),
    );
  }

  void _commit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final safety = evaluateRaceSafety(text);
    if (!safety.isAllowed) {
      showV13Toast(context, safety.reason ?? 'That race isn\u2019t allowed.');
      return;
    }
    widget.onUpdate(
      mergeRaceNameInterpretation(
        widget.draft.copyWith(
          title: text,
          hasCustomName: true,
          markEdited: {RaceField.title},
        ),
        interpretRaceName(text, catalog: widget.catalog),
      ),
    );
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final guess = _guess;
    final chips = <Widget>[
      if (guess?.activity != null)
        V13Chip(label: guess!.activity!.title, auto: true, onTap: _commit),
      if (guess != null && guess.inferredFields.contains(RaceField.target))
        V13Chip(label: '${guess.targetValue}', auto: true, onTap: _commit),
      if (guess != null && guess.inferredFields.contains(RaceField.format))
        V13Chip(
          label: switch (guess.format) {
            RaceFormat.mostInWindow => 'Most total',
            RaceFormat.bestAttempt => 'Best single',
            RaceFormat.timedAttempt => 'Timed battle',
            _ => 'First to',
          },
          auto: true,
          onTap: _commit,
        ),
      if (guess?.deadline != null)
        V13Chip(label: guess!.deadline!, auto: true, onTap: _commit),
    ];
    return _StepShell(
      question: 'What are you racing?',
      ctaLabel: 'Set it up',
      onCta: _commit,
      ctaEnabled: _ctrl.text.trim().isNotEmpty,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          V13Card(
            padding: const EdgeInsets.symmetric(
              horizontal: V13.gapMd,
              vertical: 4,
            ),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              style: V13.bodyStrong,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _commit(),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'First to 100 Pushups',
                hintStyle: TextStyle(color: V13.muted),
              ),
            ),
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: V13.gapMd),
            Wrap(spacing: V13.gapSm, runSpacing: V13.gapSm, children: chips),
          ],
          const SizedBox(height: V13.gapMd),
          Text(
            'Name it like you\u2019d say it — we\u2019ll fill in the rest. '
            'Everything marked auto can be changed next.',
            style: V13.caption,
          ),
        ],
      ),
    );
  }
}

// ── Step 2: movement + goal + mode ───────────────────────────────────────────

class _SetupStep extends ConsumerWidget {
  const _SetupStep({
    super.key,
    required this.draft,
    required this.catalog,
    required this.onUpdate,
    required this.onNext,
  });
  final RaceDraft draft;
  final List<MotionActivityDefinition> catalog;
  final ValueChanged<RaceDraft> onUpdate;
  final VoidCallback onNext;

  static const _modeLabels = {
    RaceFormat.firstToGoal: 'First to',
    RaceFormat.mostInWindow: 'Most total',
    RaceFormat.bestAttempt: 'Best single',
    RaceFormat.timedAttempt: 'Timed battle',
  };

  Future<void> _teach(BuildContext context) async {
    final name = await showV13Sheet<String>(
      context,
      builder: (ctx) => const _MovementNameSheet(),
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final learned = await context.push<LearnedCustomMovement>(
      '/races/teach',
      extra: TeachMovementArgs(movementName: name.trim()),
    );
    if (learned != null) {
      onUpdate(
        draft.copyWith(
          customActivityName: name.trim(),
          customUnit: 'reps',
          verifierSpec: learned.verifierSpec,
          motionV2Spec: learned.motionV2Spec,
          goalKind: RaceGoalKind.movement,
          clearTiming: false,
          markEdited: {RaceField.goalKind, RaceField.activity},
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customOn = NuvoFlags.customMotionOn;
    final modes = draft.isManual
        ? const [RaceFormat.firstToGoal, RaceFormat.mostInWindow]
        : draft.activity.supportedFormats
              .where(_modeLabels.containsKey)
              .toList();
    final finishOptions = draft.isDeadlineMode
        ? const ['today', '3 days', '1 week', '2 weeks']
        : const <String>[];

    return _StepShell(
      question: 'Set it up.',
      ctaLabel: 'Invite friends',
      onCta: onNext,
      ctaEnabled: !draft.isCustom || draft.hasVerifierSpec,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MOVEMENT', style: V13.label),
          const SizedBox(height: V13.gapMd),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: V13.gapSm,
            crossAxisSpacing: V13.gapSm,
            childAspectRatio: 1,
            children: [
              for (final a in catalog.take(11))
                _MovementTile(
                  icon: a.icon,
                  label: a.title,
                  selected:
                      !draft.isCustom &&
                      !draft.isManual &&
                      draft.activity.activityId == a.activityId,
                  onTap: () => onUpdate(
                    draft
                        .asPreset(activity: a, targetValue: a.defaultTarget)
                        .copyWith(
                          clearCustom: true,
                          goalKind: RaceGoalKind.movement,
                          markEdited: {RaceField.activity, RaceField.goalKind},
                        ),
                  ),
                ),
              if (customOn)
                _MovementTile(
                  icon: Icons.auto_awesome_rounded,
                  label: 'Custom',
                  selected: draft.isCustom,
                  onTap: () => _teach(context),
                ),
              _MovementTile(
                icon: Icons.edit_note_rounded,
                label: 'Custom goal',
                selected: draft.isManual,
                onTap: () => onUpdate(
                  draft.copyWith(
                    goalKind: RaceGoalKind.manual,
                    metric: RaceMetric.reps,
                    clearCustom: true,
                    markEdited: {RaceField.goalKind},
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: V13.gapLg),
          if (draft.isCustom && !draft.hasVerifierSpec) ...[
            V13Card.dashed(
              padding: const EdgeInsets.all(V13.gapMd),
              onTap: () => _teach(context),
              child: Row(
                children: [
                  const V13IconTile(
                    icon: Icons.videocam_rounded,
                    color: V13.lilac,
                  ),
                  const SizedBox(width: V13.gapMd),
                  Expanded(
                    child: Text(
                      'Teach Nuvo ${draft.customActivityName ?? 'this movement'} — record it 3 times.',
                      style: V13.bodyStrong,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: V13.muted),
                ],
              ),
            ),
            const SizedBox(height: V13.gapLg),
          ],
          if (draft.isManual) ...[
            _ManualFields(draft: draft, onUpdate: onUpdate),
            const SizedBox(height: V13.gapLg),
          ],
          Text('MODE', style: V13.label),
          const SizedBox(height: V13.gapMd),
          Wrap(
            spacing: V13.gapSm,
            runSpacing: V13.gapSm,
            children: [
              for (final f in modes)
                V13Chip(
                  label: _modeLabels[f]!,
                  selected: draft.format == f,
                  onTap: () => onUpdate(
                    draft.copyWith(format: f, markEdited: {RaceField.format}),
                  ),
                ),
            ],
          ),
          const SizedBox(height: V13.gapLg),
          if (draft.format.usesScoreTarget) ...[
            Text('GOAL', style: V13.label),
            const SizedBox(height: V13.gapMd),
            Center(
              child: V13Stepper(
                value: draft.targetValue,
                min: 1,
                max: 9999,
                onChanged: (v) => onUpdate(
                  draft.copyWith(
                    targetValue: v,
                    markEdited: {RaceField.target},
                  ),
                ),
                semanticLabel: 'Goal',
              ),
            ),
            const SizedBox(height: V13.gapSm),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: V13.gapSm,
              children: [
                for (final t in draft.activity.suggestedTargets)
                  V13Chip(
                    label: '$t',
                    selected: draft.targetValue == t,
                    onTap: () => onUpdate(
                      draft.copyWith(
                        targetValue: t,
                        markEdited: {RaceField.target},
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: V13.gapLg),
          ],
          if (finishOptions.isNotEmpty) ...[
            Text('FINISH LINE', style: V13.label),
            const SizedBox(height: V13.gapMd),
            Wrap(
              spacing: V13.gapSm,
              runSpacing: V13.gapSm,
              children: [
                for (final phrase in finishOptions)
                  V13Chip(
                    label: phrase == 'today' ? 'Today' : 'In $phrase',
                    selected: _finishMatches(phrase),
                    onTap: () => onUpdate(
                      draft.copyWith(
                        finishLineAt: deadlineUtcFromPhrase(
                          phrase,
                        )?.toIso8601String(),
                        markEdited: {RaceField.timing},
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  bool _finishMatches(String phrase) {
    final iso = draft.finishLineAt;
    final target = deadlineUtcFromPhrase(phrase);
    if (iso == null || target == null) return false;
    final actual = DateTime.tryParse(iso);
    return actual != null && actual.difference(target).inMinutes.abs() < 2;
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return V13Pressable(
      onTap: onTap,
      pressDepth: 2,
      semanticLabel: label,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? V13.navy : V13.card,
          borderRadius: BorderRadius.circular(V13.radiusCard),
          border: Border.all(color: V13.navy, width: V13.outline),
          boxShadow: selected ? null : V13.shadow3,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 26, color: selected ? V13.card : V13.navy),
            const SizedBox(height: 4),
            Text(
              label,
              style: V13.label.copyWith(color: selected ? V13.card : V13.navy),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualFields extends StatefulWidget {
  const _ManualFields({required this.draft, required this.onUpdate});
  final RaceDraft draft;
  final ValueChanged<RaceDraft> onUpdate;

  @override
  State<_ManualFields> createState() => _ManualFieldsState();
}

class _ManualFieldsState extends State<_ManualFields> {
  late final TextEditingController _name = TextEditingController(
    text: widget.draft.manualGoalName ?? '',
  );
  late final TextEditingController _unit = TextEditingController(
    text: widget.draft.manualUnit ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _field(
          _name,
          'What\u2019s the goal? (Reading, Math test grade…)',
          (v) => widget.onUpdate(
            widget.draft.copyWith(
              manualGoalName: v,
              markEdited: {RaceField.manualGoal},
            ),
          ),
        ),
        const SizedBox(height: V13.gapSm),
        _field(
          _unit,
          'Measured in… (pages, percent, minutes)',
          (v) => widget.onUpdate(
            widget.draft.copyWith(
              manualUnit: v,
              markEdited: {RaceField.manualUnit},
            ),
          ),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController c,
    String hint,
    ValueChanged<String> onChanged,
  ) => V13Card(
    padding: const EdgeInsets.symmetric(horizontal: V13.gapMd, vertical: 2),
    child: TextField(
      controller: c,
      style: V13.body,
      onChanged: onChanged,
      decoration: InputDecoration(
        border: InputBorder.none,
        hintText: hint,
        hintStyle: const TextStyle(color: V13.muted),
      ),
    ),
  );
}

class _MovementNameSheet extends StatefulWidget {
  const _MovementNameSheet();

  @override
  State<_MovementNameSheet> createState() => _MovementNameSheetState();
}

class _MovementNameSheetState extends State<_MovementNameSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(V13.pagePad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Name your movement', style: V13.sectionHead),
          const SizedBox(height: V13.gapMd),
          V13Card(
            padding: const EdgeInsets.symmetric(
              horizontal: V13.gapMd,
              vertical: 2,
            ),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              style: V13.body,
              onSubmitted: (_) => Navigator.of(context).pop(_ctrl.text),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Burpee backflip',
                hintStyle: TextStyle(color: V13.muted),
              ),
            ),
          ),
          const SizedBox(height: V13.gapLg),
          V13Button.primary(
            label: 'Teach Nuvo',
            onPressed: () => Navigator.of(context).pop(_ctrl.text),
          ),
        ],
      ),
    );
  }
}

// ── Step 3: invite friends ───────────────────────────────────────────────────

class _FriendsStep extends StatelessWidget {
  const _FriendsStep({
    super.key,
    required this.friends,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.invited,
    required this.onToggle,
    required this.crewName,
    required this.onNext,
  });
  final List<PublicUser> friends;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final Set<String> invited;
  final ValueChanged<String> onToggle;
  final String? crewName;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      question: 'Invite your friends.',
      ctaLabel: 'Review race',
      onCta: onNext,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (crewName != null) ...[
            V13Card(
              padding: const EdgeInsets.all(V13.gapMd),
              color: V13.mint,
              child: Row(
                children: [
                  const Icon(Icons.groups_rounded, color: V13.navy),
                  const SizedBox(width: V13.gapMd),
                  Expanded(
                    child: Text(
                      'Everyone in $crewName joins when this goes live.',
                      style: V13.bodyStrong,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: V13.gapMd),
          ],
          if (loading)
            const Padding(
              padding: EdgeInsets.all(V13.gapXl),
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    color: V13.blue,
                    strokeWidth: 3,
                  ),
                ),
              ),
            )
          else if (error != null)
            Column(
              children: [
                Text(error!, style: V13.body),
                const SizedBox(height: V13.gapSm),
                V13Button.secondary(label: 'Retry', onPressed: onRetry),
              ],
            )
          else if (friends.isEmpty)
            Text(
              'No friends yet — you can invite them after the race is live.',
              style: V13.body,
            )
          else
            for (var i = 0; i < friends.length; i++) ...[
              if (i > 0) const V13Divider(),
              V13ListRow(
                title: friends[i].displayName,
                subtitle:
                    friends[i].racesTogether != null &&
                        friends[i].racesTogether! > 0
                    ? 'Raced you ${friends[i].racesTogether} '
                          'time${friends[i].racesTogether == 1 ? '' : 's'}'
                    : null,
                leading: V13Face(
                  photoUrl: friends[i].profilePhotoUrl,
                  size: 36,
                  name: friends[i].displayName,
                ),
                trailing: _CheckDot(selected: invited.contains(friends[i].id)),
                onTap: () => onToggle(friends[i].id),
                showDivider: false,
              ),
            ],
        ],
      ),
    );
  }
}

class _CheckDot extends StatelessWidget {
  const _CheckDot({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: V13Motion.fast,
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? V13.blue : V13.card,
        border: Border.all(color: V13.navy, width: V13.outline),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 16, color: V13.card)
          : null,
    );
  }
}

// ── Step 4: review + create ──────────────────────────────────────────────────

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    super.key,
    required this.draft,
    required this.invitedCount,
    required this.loading,
    required this.error,
    required this.onJump,
    required this.onStart,
  });
  final RaceDraft draft;
  final int invitedCount;
  final bool loading;
  final String? error;
  final ValueChanged<int> onJump;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final mode = switch (draft.format) {
      RaceFormat.mostInWindow => 'Most total',
      RaceFormat.bestAttempt => 'Best single',
      RaceFormat.timedAttempt => 'Timed battle',
      _ => 'First to ${draft.targetValue}',
    };
    return _StepShell(
      question: 'Start the race?',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          V13Card(
            padding: const EdgeInsets.all(V13.gapMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(draft.resolvedTitle, style: V13.bodyStrong),
                const SizedBox(height: 4),
                Text(draft.winStatement, style: V13.caption),
              ],
            ),
          ),
          const SizedBox(height: V13.gapLg),
          _reviewRow('Movement', draft.displayActivityName, () => onJump(1)),
          const V13Divider(),
          _reviewRow('Mode', mode, () => onJump(1)),
          const V13Divider(),
          _reviewRow(
            'Finish line',
            _finishLine() ?? 'First to the goal wins it',
            () => onJump(1),
          ),
          const V13Divider(),
          _reviewRow(
            'Friends',
            invitedCount == 0
                ? 'Invite after it\u2019s live'
                : '$invitedCount invited',
            () => onJump(2),
          ),
          if (error != null) ...[
            const SizedBox(height: V13.gapLg),
            V13Card(
              padding: const EdgeInsets.all(V13.gapMd),
              color: V13.coral.withValues(alpha: 0.15),
              child: Text(
                error!,
                style: V13.bodyStrong.copyWith(color: V13.danger),
              ),
            ),
          ],
        ],
      ),
      ctaLabel: error == null ? 'Start race' : 'Try again',
      onCta: onStart,
      ctaLoading: loading,
    );
  }

  String? _finishLine() {
    final iso = draft.finishLineAt;
    if (iso == null) return null;
    final d = DateTime.tryParse(iso);
    if (d == null) return null;
    final local = d.toLocal();
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[local.month - 1]} ${local.day}';
  }

  Widget _reviewRow(String label, String value, VoidCallback onTap) =>
      V13ListRow(
        title: label,
        subtitle: value,
        trailing: const Icon(Icons.chevron_right_rounded, color: V13.muted),
        onTap: onTap,
        showDivider: false,
      );
}
