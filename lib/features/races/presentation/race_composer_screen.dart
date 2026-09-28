import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_motion.dart';
import '../../../core/widgets/nuvo_fade_scroll.dart';
import '../../../core/widgets/nuvo_number_flow.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/data/auth_api.dart';
import '../ai/custom_pose/custom_pose_verifier_spec.dart';
import '../data/race_models.dart';
import '../domain/motion_activity.dart';
import '../domain/motion_activity_catalog.dart';
import '../domain/race_draft.dart';
import '../domain/race_name_interpreter.dart';
import '../domain/race_safety.dart';
import 'motion_catalog_provider.dart';
import 'custom_pose/recent_movements_provider.dart';
import 'custom_pose/teach_movement_screen.dart';
import 'race_controller.dart';
import '../../onboarding/presentation/first_use_guide.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

const bool kNuvoDiagnosticsEnabled = bool.fromEnvironment('NUVO_DIAGNOSTICS');

void _dismissKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

String _secondsDisplay(int s) {
  if (s < 60) return '$s seconds';
  final m = s ~/ 60;
  final rem = s % 60;
  return rem == 0 ? '$m min' : '$m min $rem sec';
}

typedef ComposerCustomRaceCreator =
    Future<Race> Function({
      required String title,
      required int targetValue,
      required String customActivityName,
      required CustomPoseVerifierSpec verifierSpec,
    });

typedef ComposerPresetRaceCreator =
    Future<Race> Function({
      required String title,
      String? description,
      String? category,
      String goalType,
      int? targetValue,
      String? unit,
      String? proofRequirement,
      String? proofReviewMode,
      String? visibility,
      String? aiActivityType,
      String? activityId,
      String? metric,
      String? format,
      String? recurrence,
      String? targetUnit,
      String? proofMode,
      String? scoreDirection,
    });

@visibleForTesting
Future<Race> createRaceForComposerDraft({
  required RaceDraft draft,
  required ComposerCustomRaceCreator createCustomRace,
  required ComposerPresetRaceCreator createRace,
}) {
  if (draft.isCustom) {
    return createCustomRace(
      title: draft.resolvedTitle,
      targetValue: draft.targetValue,
      customActivityName: draft.customActivityName!,
      verifierSpec: draft.verifierSpec!,
    );
  }
  final payload = draft.toCreatePayload();
  return createRace(
    title: payload['title'] as String,
    description: payload['description'] as String,
    category: payload['category'] as String,
    goalType: payload['goalType'] as String,
    targetValue: payload['targetValue'] as int,
    unit: payload['unit'] as String,
    proofRequirement: payload['proofRequirement'] as String,
    proofReviewMode: payload['proofReviewMode'] as String,
    visibility: payload['visibility'] as String,
    // Absent for manual goals — no camera activity is involved.
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

// ── Step enum ─────────────────────────────────────────────────────────────────

/// Composer stages. `train` is visited ONLY for a custom (Teach Nuvo) movement,
/// and only after the movement name is set. A custom race cannot advance past
/// `train` until `draft.verifierSpec != null`.
enum _Step { name, activity, train, goal, racers, review }

// ── Provider ──────────────────────────────────────────────────────────────────

final _composerDraftProvider = StateProvider.autoDispose<RaceDraft>(
  (ref) => draftForActivity(motionActivityDefinitions.first),
);

// ── Screen ────────────────────────────────────────────────────────────────────

class RaceComposerScreen extends ConsumerStatefulWidget {
  const RaceComposerScreen({super.key, this.prefill});

  final RaceCreatePrefill? prefill;

  @override
  ConsumerState<RaceComposerScreen> createState() => _RaceComposerScreenState();
}

class _RaceComposerScreenState extends ConsumerState<RaceComposerScreen> {
  late final PageController _pageController;
  _Step _step = _Step.name;

  /// Pages whose input action the user has already performed (name typed,
  /// movement picked, goal set, racer mode chosen). The coach uses this —
  /// plus draft state — to retarget from the input control to the page's
  /// real continue CTA.
  final Set<_Step> _inputDone = {};

  bool _loading = false;
  String? _error;
  String? _lastApiError;
  int? _lastApiStatusCode;
  String _lastCreatePathUsed = 'none';

  static const _steps = _Step.values;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    // A learned movement in session state is DATA, not a navigation trigger.
    // Never let it jump the composer to a later step.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prefill = widget.prefill;
      if (prefill != null) {
        // Structured drafts (quick starts, run-it-back) are used verbatim —
        // only a user-written idea is ever interpreted as text.
        var parsed =
            prefill.draft ??
            (prefill.idea != null ? draftFromIdea(prefill.idea!) : null);
        // Race Together ("Race {name}") — the person joins on create, so the
        // race must be crew-joinable from the start.
        if (parsed != null && prefill.withUser != null) {
          parsed = parsed.copyWith(visibility: 'invite_code');
        }
        if (parsed != null) {
          ref.read(_composerDraftProvider.notifier).state = parsed;
        }
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// The stages this race actually visits. `train` only exists once the draft
  /// is a custom (Teach Nuvo) movement.
  List<_Step> get _visibleSteps {
    final custom = ref.read(_composerDraftProvider).isCustom;
    return [
      _Step.name,
      _Step.activity,
      if (custom) _Step.train,
      _Step.goal,
      _Step.racers,
      _Step.review,
    ];
  }

  void _logTransition(_Step from, _Step to, String reason) {
    if (kDebugMode || kNuvoDiagnosticsEnabled) {
      final custom = ref.read(_composerDraftProvider).isCustom;
      debugPrint(
        'RACE COMPOSER: ${from.name} -> ${to.name}  '
        'reason: $reason  (${custom ? 'custom' : 'preset'})',
      );
    }
  }

  /// The ONLY place `_step` changes. Every call passes an explicit [reason];
  /// nothing navigates from a provider value, a listener, or a post-frame peek.
  void _goToStep(_Step target, {required String reason}) {
    _dismissKeyboard();
    _logTransition(_step, target, reason);
    final idx = _steps.indexOf(
      target,
    ); // PageView keeps all pages; index by enum
    setState(() => _step = target);
    _pageController.animateToPage(
      idx,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _syncGuide(_Step step) {
    final next = switch (step) {
      _Step.name => FirstRaceGuideStep.composerActivity,
      _Step.activity => FirstRaceGuideStep.composerGoal,
      _Step.train => FirstRaceGuideStep.composerGoal,
      _Step.goal => FirstRaceGuideStep.composerRacers,
      _Step.racers => FirstRaceGuideStep.composerReview,
      _Step.review => null,
    };
    if (next == null) return;
    final guide = ref.read(firstRaceGuideProvider);
    const order = [
      FirstRaceGuideStep.composerName,
      FirstRaceGuideStep.composerActivity,
      FirstRaceGuideStep.composerGoal,
      FirstRaceGuideStep.composerRacers,
      FirstRaceGuideStep.composerReview,
    ];
    if (order.contains(guide) && order.indexOf(next) > order.indexOf(guide)) {
      ref.read(firstRaceGuideProvider.notifier).state = next;
    }
  }

  /// Advance to the next visible stage in response to a step's CTA.
  ///
  /// Custom movement: `activity` → `train` opens Teach Nuvo immediately and the
  /// composer stays on `train` until Teach Nuvo returns a verifier spec via
  /// `Navigator.pop`. Nothing else moves the composer forward.
  void _advance({String? reason}) {
    _syncGuide(_step);
    final draft = ref.read(_composerDraftProvider);
    final r =
        reason ??
        switch (_step) {
          _Step.name => 'race named',
          _Step.activity =>
            draft.isCustom ? 'custom movement named' : 'preset activity chosen',
          _Step.train => 'movement trained',
          _Step.goal => 'target set',
          _Step.racers => 'participants set',
          _Step.review => 'review',
        };
    final v = _visibleSteps;
    final i = v.indexOf(_step);
    if (i < 0 || i >= v.length - 1) return;
    final next = v[i + 1];
    if (next == _Step.train && draft.verifierSpec == null) {
      _openTraining(reason: r);
      return;
    }
    _goToStep(next, reason: r);
  }

  /// Custom-movement training stage. Explicit: only ever called from
  /// `_advance` (the activity step's "Continue to training" button) or the
  /// train page's retry button.
  Future<void> _openTraining({String reason = 'continue to training'}) async {
    final draft = ref.read(_composerDraftProvider);
    final name = (draft.customActivityName ?? '').trim();
    if (name.isEmpty) return;
    _goToStep(_Step.train, reason: reason);
    final spec = await context.push<CustomPoseVerifierSpec>(
      '/races/teach',
      extra: TeachMovementArgs(movementName: name, unit: draft.customUnit),
    );
    if (!mounted) return;
    if (spec != null) {
      ref.read(_composerDraftProvider.notifier).state = ref
          .read(_composerDraftProvider)
          .copyWith(verifierSpec: spec);
      _goToStep(_Step.goal, reason: 'teach nuvo returned verifier spec');
    }
    // spec == null → user backed out; stay on `train` (retry button visible).
  }

  void _retreat() {
    final v = _visibleSteps;
    final i = v.indexOf(_step);
    if (i > 0) {
      // Back inside the composer: the coach re-derives the right substep from
      // the page + draft — no provider rewind needed.
      _goToStep(v[i - 1], reason: 'back button');
    } else {
      _dismissKeyboard();
      // Backing all the way out to Compete re-arms the guide's first step so
      // the Start button is the next obvious action.
      final guide = ref.read(firstRaceGuideProvider);
      if (guide != FirstRaceGuideStep.idle &&
          guide != FirstRaceGuideStep.complete) {
        ref.read(firstRaceGuideProvider.notifier).state =
            FirstRaceGuideStep.competeStart;
      }
      safePopOrGo(context, '/compete');
    }
  }

  /// Whether the user has already satisfied [step]'s input — drives the
  /// coach's input → continue-CTA retarget. Draft-derived fallbacks keep this
  /// correct across back navigation and prefills.
  bool _inputReady(_Step step, RaceDraft draft) => switch (step) {
    _Step.name =>
      // A valid name isn't "done" while the keyboard is still up — the coach
      // stays on the field until the user dismisses/commits it.
      (_inputDone.contains(step) || draft.hasCustomName) && !_nameFocused,
    _Step.activity =>
      _inputDone.contains(step) ||
          draft.isCustom ||
          (draft.isManual &&
              (draft.manualGoalName ?? '').trim().isNotEmpty),
    _Step.goal ||
    _Step.racers =>
      _inputDone.contains(step),
    _Step.train || _Step.review => false,
  };

  ComposerGuidePage _guidePage(_Step step) => switch (step) {
    _Step.name => ComposerGuidePage.name,
    _Step.activity => ComposerGuidePage.activity,
    _Step.train => ComposerGuidePage.train,
    _Step.goal => ComposerGuidePage.goal,
    _Step.racers => ComposerGuidePage.racers,
    _Step.review => ComposerGuidePage.review,
  };

  void _markInput(_Step step) {
    if (_inputDone.add(step)) setState(() {});
  }

  /// Whether the name field currently has the keyboard — while it does, the
  /// coach must not retarget the continue CTA even if the name is valid.
  bool _nameFocused = false;

  Future<void> _startRace() async {
    if (_loading) return; // guard against double-tap
    _dismissKeyboard();
    final draft = ref.read(_composerDraftProvider);
    _lastCreatePathUsed = draft.isCustom ? 'custom' : 'preset';
    if (draft.isCustom) {
      if (draft.verifierSpec == null || draft.customActivityName == null) {
        // Invariant broken before we ever hit the backend — send the user back
        // to the training stage instead of showing a server "couldn't create".
        assert(() {
          debugPrint(
            'COMPOSER GUARD: custom race with no verifierSpec — '
            'returning to train step',
          );
          return true;
        }());
        setState(() {
          _error = 'Teach Nuvo this movement first — record it 3 times.';
          _lastApiError = null;
        });
        _goToStep(_Step.train, reason: 'create guard: no verifier spec');
        return;
      }
      if (draft.resolvedTitle.trim().isEmpty) {
        setState(() {
          _error = 'Add a race title.';
          _lastApiError = null;
        });
        return;
      }
      if (draft.targetValue <= 0) {
        setState(() {
          _error = 'Enter a target greater than 0.';
          _lastApiError = null;
        });
        return;
      }
    } else if (!draft.isValidToCreate) {
      setState(() {
        _error = draft.isManual
            ? 'Name the goal and how it is measured.'
            : 'Choose a supported activity.';
        _lastApiError = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final controller = ref.read(raceControllerProvider.notifier);
      final race = await createRaceForComposerDraft(
        draft: draft,
        createCustomRace: controller.createCustomRace,
        createRace: controller.createRace,
      );
      if (!mounted) return;
      final wantsInvite = draft.visibility == 'invite_code';
      if (ref.read(firstRaceGuideProvider) ==
          FirstRaceGuideStep.composerReview) {
        ref.read(firstRaceGuideProvider.notifier).state =
            FirstRaceGuideStep.raceDetail;
      }
      final withUser = widget.prefill?.withUser;
      if (withUser != null) {
        // Race Together — pull the person into the race we just created.
        // Best-effort: on failure land on the invite screen where the same
        // action is one tap away rather than losing them silently.
        try {
          await controller.addRaceParticipant(race.id, withUser.id);
          if (!mounted) return;
          context.go('/race/${race.id}');
        } catch (_) {
          if (!mounted) return;
          context.go('/race/${race.id}/invite');
        }
        return;
      }
      // Replace the composer stack — the race now exists, so back should not
      // return to the (stale) draft flow. Matches create_race_screen.
      if (wantsInvite) {
        context.go('/race/${race.id}/invite');
      } else {
        context.go('/race/${race.id}');
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _lastApiError = e.message;
          _lastApiStatusCode = e.statusCode;
          _error = e.statusCode >= 500
              ? "Couldn't create the race. Try again."
              : e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "Couldn't create the race. Try again.";
          _lastApiError = e.toString();
          _lastApiStatusCode = null;
          _loading = false;
        });
      }
    }
  }

  String? _draftValidationError(RaceDraft draft) {
    if (draft.resolvedTitle.trim().isEmpty) return 'missing_title';
    if (draft.targetValue <= 0) return 'invalid_target';
    if (draft.isCustom) {
      if (draft.customActivityName == null ||
          draft.customActivityName!.isEmpty) {
        return 'missing_custom_activity_name';
      }
      if (draft.verifierSpec == null) return 'missing_verifier_spec';
      return null;
    }
    if (!draft.isValidToCreate) return 'unsupported_activity';
    return null;
  }

  Map<String, dynamic> _raceComposerDebugReport(RaceDraft draft) {
    final spec = draft.verifierSpec;
    String? specJson;
    int? specJsonBytes;
    if (spec != null) {
      try {
        specJson = jsonEncode(spec.toJson());
        specJsonBytes = specJson.length;
      } catch (_) {
        specJson = '<encode_failed>';
        specJsonBytes = null;
      }
    }
    return {
      'step': _step.name,
      'visibleSteps': [for (final s in _visibleSteps) s.name],
      'draft': {
        'isCustom': draft.isCustom,
        'customActivityName': draft.customActivityName,
        'verifierSpecPresent': draft.verifierSpec != null,
        'verifierType': spec?.verifierType,
        'verifierVersion': spec?.schemaVersion,
        'verifierSpecJsonBytes': specJsonBytes,
        'isValidToCreate': draft.isValidToCreate,
        'resolvedTitle': draft.resolvedTitle,
        'targetValue': draft.targetValue,
        'metric': draft.metric.name,
        'visibility': draft.visibility,
      },
      'validationError': _draftValidationError(draft),
      'screenError': _error,
      'lastApiError': _lastApiError,
      'lastApiStatusCode': _lastApiStatusCode,
      'createPathUsed': _lastCreatePathUsed,
      'primaryButtonDisabled': _loading,
    };
  }

  Future<void> _copyRaceComposerDebugReport(RaceDraft draft) async {
    if (!(kDebugMode || kNuvoDiagnosticsEnabled)) return;
    final pretty = const JsonEncoder.withIndent(
      '  ',
    ).convert(_raceComposerDebugReport(draft));
    debugPrint(pretty, wrapWidth: 1024);
    await Clipboard.setData(ClipboardData(text: pretty));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Debug report copied.')));
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(_composerDraftProvider);
    final visible = _visibleSteps;
    final stepIndex = visible.indexOf(_step).clamp(0, visible.length - 1);

    final screen = Scaffold(
      backgroundColor: context.themeColors.page,
      // resizeToAvoidBottomInset keeps CTA above keyboard on Name step
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _ComposerTopBar(
              stepIndex: stepIndex,
              totalSteps: visible.length,
              onBack: _loading ? null : _retreat,
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _NamePage(
                    draft: draft,
                    onDraftChanged: (d) =>
                        ref.read(_composerDraftProvider.notifier).state = d,
                    onNext: _advance,
                    onInput: () => _markInput(_Step.name),
                    onFocusChange: (f) {
                      // Focus only suppresses the CTA while editing an
                      // UNSATISFIED name. The field autofocuses when you come
                      // back to a completed Name page — that must not drag
                      // the coach off the continue button.
                      final satisfied =
                          _inputDone.contains(_Step.name) ||
                          ref.read(_composerDraftProvider).hasCustomName;
                      final editing = f && !satisfied;
                      if (editing != _nameFocused) {
                        setState(() => _nameFocused = editing);
                      }
                    },
                  ),
                  _ActivityPage(
                    draft: draft,
                    onDraftChanged: (d) =>
                        ref.read(_composerDraftProvider.notifier).state = d,
                    onNext: _advance,
                    onInput: () => _markInput(_Step.activity),
                  ),
                  _TrainPage(
                    draft: draft,
                    onTrain: () => _openTraining(reason: 'train page retry'),
                    onContinue: () => _advance(
                      reason: 'train page continue (already trained)',
                    ),
                  ),
                  _GoalPage(
                    draft: draft,
                    onDraftChanged: (d) =>
                        ref.read(_composerDraftProvider.notifier).state = d,
                    onNext: _advance,
                    onInput: () => _markInput(_Step.goal),
                  ),
                  _RacersPage(
                    draft: draft,
                    withUser: widget.prefill?.withUser,
                    onDraftChanged: (d) =>
                        ref.read(_composerDraftProvider.notifier).state = d,
                    onNext: _advance,
                    onInput: () => _markInput(_Step.racers),
                  ),
                  _ReviewPage(
                    draft: draft,
                    loading: _loading,
                    error: _error,
                    onStart: _startRace,
                    onEditStep: (s) =>
                        _goToStep(s, reason: 'review: edit step'),
                    showDiagnostics: kDebugMode || kNuvoDiagnosticsEnabled,
                    onCopyDiagnostics: () =>
                        _copyRaceComposerDebugReport(draft),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final guide = ref.watch(firstRaceGuideProvider);
    const guidedSteps = {
      FirstRaceGuideStep.composerName,
      FirstRaceGuideStep.composerActivity,
      FirstRaceGuideStep.composerGoal,
      FirstRaceGuideStep.composerRacers,
      FirstRaceGuideStep.composerReview,
    };
    // The coach follows the page ACTUALLY on screen, not just the furthest
    // guide step — back navigation re-derives the right target from the live
    // draft instead of pointing at a page the user already left.
    final spec = guidedSteps.contains(guide)
        ? composerCoachSpec(
            _guidePage(_step),
            inputReady: _inputReady(_step, draft),
            teachMode: draft.isCustom,
            manualGoal: draft.isManual,
          )
        : null;
    if (spec == null) return screen;
    return Stack(
      children: [
        screen,
        FirstRaceGuideCoach(
          step: guide,
          targetKey: spec.targetKey,
          eyebrow: spec.eyebrow,
          title: spec.title,
          body: spec.body,
        ),
      ],
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

class _ComposerTopBar extends StatelessWidget {
  const _ComposerTopBar({
    required this.stepIndex,
    required this.totalSteps,
    required this.onBack,
  });

  final int stepIndex;
  final int totalSteps;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final progress = (stepIndex + 1) / totalSteps;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              NuvoBackButton(onPressed: onBack ?? () {}),
              const Spacer(),
              Text(
                '${stepIndex + 1} of $totalSteps',
                style: AppTextStyles.labelMedium.copyWith(
                  color: context.themeColors.inkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ProgressLine(progress: progress),
        ],
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = constraints.maxWidth;
        return SizedBox(
          height: 3,
          child: Stack(
            children: [
              Container(
                width: total,
                decoration: BoxDecoration(
                  color: context.themeColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeOutCubic,
                width: total * progress,
                decoration: BoxDecoration(
                  color: NuvoColors.actionBlue,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Shared page chrome ────────────────────────────────────────────────────────

class _PageShell extends StatelessWidget {
  const _PageShell({
    required this.question,
    required this.support,
    required this.body,
    required this.ctaLabel,
    required this.onCta,
    this.ctaEnabled = true,
    this.ctaKey,
    this.aboveCta,
  });

  final String question;
  final String support;
  final Widget body;
  final String ctaLabel;
  final VoidCallback onCta;
  final bool ctaEnabled;

  /// Optional context strip rendered directly above the CTA (e.g. the picked
  /// movement). Animates in — keep it one line.
  final Widget? aboveCta;

  /// Spotlight key for the real continue button — the coach retargets here
  /// once the page's input is satisfied.
  final GlobalKey? ctaKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: NuvoFadeScroll(
            child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  question,
                  style: AppTextStyles.headlineLarge.copyWith(
                    color: context.themeColors.ink,
                    height: 1.1,
                  ),
                ).animate().fadeIn(duration: 220.ms),
                const SizedBox(height: 8),
                Text(
                  support,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: context.themeColors.inkMuted,
                  ),
                ),
                const SizedBox(height: 24),
                body.animate(delay: 60.ms).fadeIn(duration: 220.ms),
              ],
            ),
          ),
          ),
        ),
        Padding(
          key: ctaKey,
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (aboveCta != null) ...[
                aboveCta!,
                const SizedBox(height: 10),
              ],
              NuvoPrimaryButton(
                label: ctaLabel,
                expand: true,
                onPressed: ctaEnabled ? onCta : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Step 1: Name ──────────────────────────────────────────────────────────────

class _NamePage extends StatefulWidget {
  const _NamePage({
    required this.draft,
    required this.onDraftChanged,
    required this.onNext,
    this.onInput,
    this.onFocusChange,
  });
  final RaceDraft draft;
  final ValueChanged<RaceDraft> onDraftChanged;
  final VoidCallback onNext;

  /// Fires once the user has entered a name — lets the coach retarget the
  /// page's continue CTA.
  final VoidCallback? onInput;

  /// Reports the name field's focus so the coach can keep pointing at the
  /// field while the keyboard is up.
  final ValueChanged<bool>? onFocusChange;

  @override
  State<_NamePage> createState() => _NamePageState();
}

class _NamePageState extends State<_NamePage> {
  late final TextEditingController _ctrl;
  late final FocusNode _focusNode;
  // Tracks whether the user has manually deviated from the generated title
  bool _hasCustomName = false;

  @override
  void initState() {
    super.initState();
    _hasCustomName = widget.draft.hasCustomName;
    _ctrl = TextEditingController(text: widget.draft.resolvedTitle);
    _focusNode = FocusNode()
      // The coach only retargets the continue CTA once the user is DONE with
      // the keyboard — a single keystroke or delete must not flip it.
      ..addListener(() {
        widget.onFocusChange?.call(_focusNode.hasFocus);
        if (!_focusNode.hasFocus && _ctrl.text.trim().isNotEmpty) {
          widget.onInput?.call();
        }
      });
  }

  @override
  void didUpdateWidget(_NamePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When draft is changed externally (e.g. activity/goal change updates the
    // generated title, or a prefill applies an interpreted idea), sync the
    // field unless the user has deviated from the previous draft's title.
    final newTitle = widget.draft.resolvedTitle;
    final untouched = _ctrl.text == oldWidget.draft.resolvedTitle;
    if (!widget.draft.hasCustomName || untouched) {
      if (_ctrl.text != newTitle) {
        _ctrl.text = newTitle;
        _hasCustomName = widget.draft.hasCustomName;
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged(String value) {
    setState(() {});
    // Mark as custom only when the user's text differs from the generated title
    final isGenerated = value.trim() == widget.draft.generatedTitleText;
    _hasCustomName = !isGenerated;
    widget.onDraftChanged(
      widget.draft.copyWith(
        title: value,
        hasCustomName: _hasCustomName,
        markEdited: {RaceField.title},
      ),
    );
  }

  void _commit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _focusNode.unfocus();
    // Safety boundary: the interpreter may understand anything, but refused
    // categories never become a draft. The server enforces the same policy.
    final safety = evaluateRaceSafety(text);
    if (!safety.isAllowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(safety.reason ?? 'That race isn\u2019t allowed.')),
      );
      return;
    }
    // THE interpretation event: the committed race name is read ONCE into a
    // structured draft. Fields the user already edited are protected inside
    // mergeRaceNameInterpretation — nothing else in the composer infers.
    widget.onDraftChanged(
      mergeRaceNameInterpretation(
        widget.draft.copyWith(
          title: text,
          hasCustomName: true,
          markEdited: {RaceField.title},
        ),
        interpretRaceName(text),
      ),
    );
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      question: 'Name your race.',
      support: 'Your crew will see this name.',
      ctaLabel: 'Choose activity',
      onCta: _commit,
      ctaEnabled: _ctrl.text.trim().isNotEmpty,
      ctaKey: FirstRaceGuideKeys.composerNameCta,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LargeTextField(
            key: FirstRaceGuideKeys.composerName,
            controller: _ctrl,
            focusNode: _focusNode,
            hint: 'First to 100 Pushups',
            onChanged: _onTextChanged,
            onSubmitted: (_) => _commit(),
          ),
        ],
      ),
    );
  }
}

class _LargeTextField extends StatefulWidget {
  const _LargeTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onChanged,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_LargeTextField> createState() => _LargeTextFieldState();
}

class _LargeTextFieldState extends State<_LargeTextField> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.themeColors.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.md),
        border: Border.all(
          color: _focused ? NuvoColors.actionBlue : context.themeColors.ink,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: context.themeColors.ink.withValues(alpha: _focused ? 0.12 : 0.18),
            blurRadius: 0,
            offset: const Offset(3, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        style: AppTextStyles.titleLarge.copyWith(
          color: context.themeColors.ink,
          fontSize: 20,
          height: 1.4,
        ),
        maxLines: 2,
        minLines: 1,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: AppTextStyles.titleLarge.copyWith(
            color: context.themeColors.inkMuted.withValues(alpha: 0.45),
            fontSize: 20,
            height: 1.4,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
          isCollapsed: true,
        ),
      ),
    );
  }
}

// ── Step 2: Activity ──────────────────────────────────────────────────────────

class _ActivityPage extends ConsumerStatefulWidget {
  const _ActivityPage({
    required this.draft,
    required this.onDraftChanged,
    required this.onNext,
    this.onInput,
  });
  final RaceDraft draft;
  final ValueChanged<RaceDraft> onDraftChanged;
  final VoidCallback onNext;

  /// Fires once the user has picked/named a movement — lets the coach
  /// retarget the page's continue CTA.
  final VoidCallback? onInput;

  @override
  ConsumerState<_ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends ConsumerState<_ActivityPage> {
  final _searchController = TextEditingController();
  final _manualNameController = TextEditingController();
  final _manualUnitController = TextEditingController();
  final _moveNameController = TextEditingController();
  final _moveUnitController = TextEditingController();
  String _searchQuery = '';
  MovementCategory? _selectedCategory; // null = All

  /// The user chose "Teach Nuvo a new movement" — collect its name + unit here,
  /// then Continue advances to the required training stage.
  bool _teachMode = false;

  @override
  void initState() {
    super.initState();
    _manualNameController.text = widget.draft.manualGoalName ?? '';
    _manualUnitController.text = widget.draft.manualUnit ?? '';
    _moveNameController.text = widget.draft.customActivityName ?? '';
    _moveUnitController.text = widget.draft.customUnit ?? 'reps';
    _teachMode = widget.draft.isCustom;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _manualNameController.dispose();
    _manualUnitController.dispose();
    _moveNameController.dispose();
    _moveUnitController.dispose();
    super.dispose();
  }

  void _setKind(RaceGoalKind kind) {
    if (widget.draft.goalKind == kind) return;
    widget.onDraftChanged(
      widget.draft.copyWith(
        goalKind: kind,
        markEdited: {RaceField.goalKind},
      ),
    );
    setState(() {});
  }

  void _syncCustomMovement() {
    if (_moveNameController.text.trim().isNotEmpty) widget.onInput?.call();
    widget.onDraftChanged(
      widget.draft.copyWith(
        goalKind: RaceGoalKind.movement,
        customActivityName: _moveNameController.text.trim(),
        customUnit: _moveUnitController.text.trim().isEmpty
            ? 'reps'
            : _moveUnitController.text.trim(),
        markEdited: {RaceField.goalKind, RaceField.activity},
      ),
    );
  }

  void _syncManual() {
    if (_manualNameController.text.trim().isNotEmpty) widget.onInput?.call();
    widget.onDraftChanged(
      widget.draft.copyWith(
        goalKind: RaceGoalKind.manual,
        manualGoalName: _manualNameController.text.trim(),
        manualUnit: _manualUnitController.text.trim(),
        markEdited: {
          RaceField.goalKind,
          RaceField.manualGoal,
          RaceField.manualUnit,
        },
      ),
    );
  }

  void _select(MotionActivityDefinition activity) {
    final currentTarget = widget.draft.targetValue;
    final keepTarget =
        activity.suggestedTargets.contains(currentTarget) ||
        (currentTarget >= 1 && currentTarget <= 99999);
    widget.onDraftChanged(
      widget.draft
          .asPreset(
            activity: activity,
            targetValue: keepTarget ? currentTarget : activity.defaultTarget,
          )
          .copyWith(markEdited: {RaceField.activity}),
    );
    setState(() => _teachMode = false);
    widget.onInput?.call();
    // Record selection in recent movements
    ref
        .read(recentMovementIdsProvider.notifier)
        .record(activity.activityId);
  }

  @override
  Widget build(BuildContext context) {
    final isManual = widget.draft.goalKind == RaceGoalKind.manual;
    final recentActivities = recentActivitiesFromIds(
      ref.watch(recentMovementIdsProvider),
    );
    final remoteSnapshot = ref.watch(motionCatalogProvider).valueOrNull;
    final capabilities = ref.watch(motionCapabilitiesProvider);
    final availableActivities = availableMotionActivities(
      remoteSnapshot,
      capabilities,
    );
    final categories = availableActivities.map((activity) => activity.category).toSet().toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final sorted = [...availableActivities]
      ..sort((a, b) {
        final category = a.category.index.compareTo(b.category.index);
        return category == 0 ? a.sortPriority.compareTo(b.sortPriority) : category;
      });
    // A draft can arrive pre-filled (initial state or name interpretation) —
    // the picker only treats a movement as SELECTED once the user picks one
    // here. Everything else stays a suggestion: tile unselected, CTA quiet.
    final userPicked =
        widget.draft.userEditedFields.contains(RaceField.activity);
    final selectedActivityId =
        userPicked ? widget.draft.activity.activityId : '';

    if (_teachMode && !isManual) {
      final canContinue = _moveNameController.text.trim().isNotEmpty;
      return _PageShell(
        question: 'Your custom movement',
        support:
            'Name it and pick how it is counted. Next you\'ll teach it to '
            'Nuvo.',
        ctaLabel: 'Continue to training',
        ctaEnabled: canContinue,
        ctaKey: FirstRaceGuideKeys.composerActivityCta,
        onCta: () {
          _syncCustomMovement();
          widget.onNext();
        },
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GoalKindToggle(kind: widget.draft.goalKind, onChanged: _setKind),
            const SizedBox(height: 16),
            _ComposerField(
              controller: _moveNameController,
              label: 'Movement name',
              hint: 'e.g. Side reach, Star jump',
              onChanged: (_) {
                _syncCustomMovement();
                setState(() {});
              },
            ),
            const SizedBox(height: 12),
            _ComposerField(
              controller: _moveUnitController,
              label: 'Counted in',
              hint: 'reps',
              onChanged: (_) => _syncCustomMovement(),
            ),
            const SizedBox(height: 12),
            Text(
              'Nuvo watches you do it 3 times, learns the shape of the motion, '
              'then counts every rep live.',
              style: AppTextStyles.bodySmall.copyWith(color: context.themeColors.inkMuted),
            ),
            const SizedBox(height: 16),
            NuvoTertiaryButton(
              label: 'Pick a preset movement instead',
              small: true,
              onPressed: () => setState(() => _teachMode = false),
            ),
          ],
        ),
      );
    }

    // The CTA stays quiet until the user has actually picked a movement.
    final hasActivity =
        !widget.draft.isCustom && selectedActivityId.isNotEmpty;

    return _PageShell(
      question: 'What are you competing in?',
      // A clarification from the title interpretation is the support copy —
      // answering it IS filling in the fields below.
      support: widget.draft.clarification ??
          (isManual
              ? 'Name the goal and how it is measured.'
              : 'Pick a movement for your crew.'),
      ctaLabel: isManual
          ? 'Set the finish line'
          : hasActivity
              ? 'Continue with ${widget.draft.activity.title}'
              : 'Pick a movement',
      ctaEnabled: isManual || hasActivity,
      ctaKey: FirstRaceGuideKeys.composerActivityCta,
      aboveCta: !isManual && hasActivity
          ? _SelectionContext(activity: widget.draft.activity)
          : null,
      onCta: () {
        if (isManual) _syncManual();
        widget.onNext();
      },
      body: KeyedSubtree(
        key: FirstRaceGuideKeys.composerActivity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GoalKindToggle(kind: widget.draft.goalKind, onChanged: _setKind),
            const SizedBox(height: 16),
            if (isManual) ...[
              _ComposerField(
                controller: _manualNameController,
                label: 'Goal',
                hint: 'e.g. Read, Meditate, Cold plunge',
                onChanged: (_) => _syncManual(),
              ),
              const SizedBox(height: 12),
              _ComposerField(
                controller: _manualUnitController,
                label: 'Measured in',
                hint: 'e.g. pages, minutes, days',
                onChanged: (_) => _syncManual(),
              ),
              const SizedBox(height: 12),
              Text(
                'Racers log their own progress. Nuvo keeps the leaderboard; '
                'your crew keeps each other honest.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: context.themeColors.inkMuted,
                ),
              ),
            ] else ...[
              _TeachNuvoCard(onTap: () => setState(() => _teachMode = true)),
              const SizedBox(height: 12),
              _SearchBar(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
              const SizedBox(height: 14),
              if (_searchQuery.isNotEmpty)
                _SearchResults(
                  query: _searchQuery,
                  activities: availableActivities,
                  selectedActivityId: selectedActivityId,
                  onSelect: _select,
                  onTeachNuvo: () => setState(() => _teachMode = true),
                )
              else ...[
                if (recentActivities.isNotEmpty) ...[
                  _RecentMovements(
                    activities: recentActivities.take(5).toList(),
                    selectedActivityId: selectedActivityId,
                    onSelect: _select,
                  ),
                  const SizedBox(height: 16),
                ],
                _CategoryTabs(
                  categories: categories,
                  selected: _selectedCategory,
                  onSelect: (cat) => setState(() => _selectedCategory = cat),
                ),
                const SizedBox(height: 12),
                _MovementGrid(
                  activities: _selectedCategory == null
                      ? sorted
                      : availableActivities.where((activity) => activity.category == _selectedCategory).toList(),
                  selectedActivityId: selectedActivityId,
                  onSelect: _select,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Entry into the Teach Nuvo flow from the activity step — for movements that
/// aren't in the preset list. Reached at `/races/teach`.
///
/// Compact premium row — a violet accent marks it as the special "make your
/// own" path, not a help box.
class _TeachNuvoCard extends StatelessWidget {
  const _TeachNuvoCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    const accent = NuvoColors.avatarPlum;
    return PressableScale(
      onTap: onTap,
      scale: 0.98,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: accent.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark ? 0.16 : 0.09,
          ),
          borderRadius: BorderRadius.circular(NuvoRadii.lg),
        ),
        child: Row(
          children: [
            const _Sparkle(),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Teach Nuvo',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: accent,
                        fontSize: 13.5,
                      ),
                    ),
                    TextSpan(
                      text: '  ·  Create your own movement',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: c.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: accent.withValues(alpha: 0.8),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small twinkle on mount — Teach Nuvo is the special path, but the icon
/// settles (no perpetual ticker under tests or battery).
class _Sparkle extends StatefulWidget {
  const _Sparkle();

  @override
  State<_Sparkle> createState() => _SparkleState();
}

class _SparkleState extends State<_Sparkle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Transform.scale(
        scale: 1.0 + Curves.easeOutBack.transform(_c.value) * 0.12,
        child: Opacity(
          opacity: 0.55 + _c.value * 0.45,
          child: const Icon(
            Icons.auto_awesome_rounded,
            size: 16,
            color: NuvoColors.avatarPlum,
          ),
        ),
      ),
    );
  }
}

// ── Step: Custom movement training (custom races only) ────────────────────────

/// Required middle stage for a custom movement. The composer (`_openTraining`)
/// owns launching Teach Nuvo and the `train → goal` transition; this page is a
/// pure status + retry view. It never navigates or mutates the draft.
class _TrainPage extends StatelessWidget {
  const _TrainPage({
    required this.draft,
    required this.onTrain,
    required this.onContinue,
  });

  final RaceDraft draft;

  /// Launch / relaunch Teach Nuvo (composer handles the result).
  final VoidCallback onTrain;

  /// Already trained — proceed to the target step.
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final trained = draft.verifierSpec != null;
    final name = (draft.customActivityName ?? 'your movement').trim();
    return _PageShell(
      question: trained ? '"$name" is ready' : 'Teach Nuvo "$name"',
      support: trained
          ? 'Nuvo learned the motion. Continue to set the target.'
          : 'Record it 3 times so Nuvo can recognise every rep. This step '
                'is required before you can race on it.',
      ctaLabel: trained ? 'Continue' : 'Start training',
      onCta: trained ? onContinue : onTrain,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: trained
                  ? NuvoColors.success.withValues(alpha: 0.08)
                  : context.semanticColors.neutral.surface,
              borderRadius: BorderRadius.circular(NuvoRadii.card),
              border: Border.all(
                color: trained ? NuvoColors.success : context.semanticColors.neutral.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  trained ? Icons.check_circle_rounded : Icons.videocam_rounded,
                  color: trained ? NuvoColors.success : NuvoColors.blue,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    trained
                        ? 'Movement trained — Nuvo learned "$name".'
                        : 'Not trained yet. Tap Start training to record your '
                              '3 examples, then test it.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: context.themeColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (trained) ...[
            const SizedBox(height: 12),
            NuvoTertiaryButton(
              label: 'Retrain this movement',
              small: true,
              onPressed: onTrain,
            ),
          ],
        ],
      ),
    );
  }
}

/// Movement (camera) vs custom manual goal.
/// A light two-option switch — text + sliding underline, not a bordered
/// pill tray. The picker below is the visual object; this just filters.
class _GoalKindToggle extends StatelessWidget {
  const _GoalKindToggle({required this.kind, required this.onChanged});
  final RaceGoalKind kind;
  final ValueChanged<RaceGoalKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final selectedIndex = kind == RaceGoalKind.movement ? 0 : 1;

    Widget seg(RaceGoalKind k, String label) {
      final selected = kind == k;
      return Expanded(
        child: NuvoPressable(
          onTap: () => onChanged(k),
          scale: 0.98,
          haptic: false,
          child: SizedBox(
            height: 38,
            child: Center(
              child: Text(
                label,
                style: AppTextStyles.labelMedium.copyWith(
                  fontSize: 13.5,
                  color: selected ? c.ink : c.inkSubtle,
                  fontWeight:
                      selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 38,
      child: Stack(
        children: [
          // Sliding accent indicator — the state moves, not a color swap.
          Positioned.fill(
            child: AnimatedAlign(
              alignment:
                  Alignment(selectedIndex == 0 ? -1.0 : 1.0, 1),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: 2.5,
                    margin:
                        const EdgeInsets.symmetric(horizontal: 28),
                    decoration: BoxDecoration(
                      color: NuvoColors.blue,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              seg(RaceGoalKind.movement, 'Movement'),
              seg(RaceGoalKind.manual, 'Custom goal'),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(height: 1, color: c.divider),
          ),
        ],
      ),
    );
  }
}

class _ComposerField extends StatelessWidget {
  const _ComposerField({
    required this.controller,
    required this.label,
    this.hint,
    this.onChanged,
  });
  final TextEditingController controller;
  final String label;
  final String? hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: AppTextStyles.bodyMedium.copyWith(color: context.themeColors.ink),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: context.themeColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NuvoRadii.md),
          borderSide: BorderSide(color: context.themeColors.border, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NuvoRadii.md),
          borderSide: BorderSide(color: context.themeColors.border, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NuvoRadii.md),
          borderSide: const BorderSide(color: NuvoColors.blue, width: 2),
        ),
      ),
    );
  }
}

// ── Search bar ───────────────────────────────────────────────────────────────

/// Light search — a soft field, not a boxed outline. Focus lifts it with a
/// blue edge; otherwise it recedes.
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final quiet = OutlineInputBorder(
      borderRadius: BorderRadius.circular(NuvoRadii.lg),
      borderSide: BorderSide.none,
    );
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: AppTextStyles.bodyMedium.copyWith(color: c.ink),
      decoration: InputDecoration(
        hintText: 'Search movements',
        hintStyle: AppTextStyles.bodyMedium.copyWith(color: c.inkSubtle),
        prefixIcon: Icon(Icons.search_rounded, color: c.inkSubtle, size: 20),
        filled: true,
        fillColor: c.panel,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: quiet,
        enabledBorder: quiet,
        focusedBorder: quiet.copyWith(
          borderSide: const BorderSide(color: NuvoColors.blue, width: 1.5),
        ),
        errorBorder: quiet,
      ),
    );
  }
}

// ── Category tabs ────────────────────────────────────────────────────────────

class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });
  final List<MovementCategory> categories;
  final MovementCategory? selected;
  final ValueChanged<MovementCategory?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36 * MediaQuery.textScalerOf(context).scale(1),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 24),
        itemCount: categories.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == 0) {
            final isSelected = selected == null;
            return _CategoryTab(
              label: 'All',
              selected: isSelected,
              onTap: () => onSelect(null),
            );
          }
          final cat = categories[i - 1];
          return _CategoryTab(
            label: cat.label,
            selected: selected == cat,
            onTap: () => onSelect(cat),
          );
        },
      ),
    );
  }
}

class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NuvoPressable(
      onTap: onTap,
      scale: 0.96,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: selected ? NuvoColors.actionBlue : Colors.transparent,
              width: selected ? 2 : 0,
            ),
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: selected ? NuvoColors.actionBlue : context.themeColors.inkMuted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ── Movement browse ──────────────────────────────────────────────────────────

/// Subtle identity accent per movement family — icon wells, selected edges,
/// and the check chip. Blue stays the overall brand; these are quiet
/// variations, not a rainbow dashboard.
Color _movementAccent(MovementCategory category) {
  return switch (category) {
    MovementCategory.upperBody => NuvoColors.blue,
    MovementCategory.lowerBody => NuvoColors.avatarDustyBlue,
    MovementCategory.cardio => NuvoColors.avatarTeal,
    MovementCategory.core => NuvoColors.avatarPlum,
    MovementCategory.fullBody => NuvoColors.avatarSage,
  };
}

/// RECENT — only when real recent-movement data exists. Compact chips, not a
/// second browse system.
class _RecentMovements extends StatelessWidget {
  const _RecentMovements({
    required this.activities,
    required this.selectedActivityId,
    required this.onSelect,
  });

  final List<MotionActivityDefinition> activities;
  final String selectedActivityId;
  final ValueChanged<MotionActivityDefinition> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'RECENT',
          style: AppTextStyles.eyebrow.copyWith(color: c.inkDim),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final activity in activities)
              _RecentChip(
                activity: activity,
                selected: activity.activityId == selectedActivityId,
                onTap: () => onSelect(activity),
              ),
          ],
        ),
      ],
    );
  }
}

class _RecentChip extends StatelessWidget {
  const _RecentChip({
    required this.activity,
    required this.selected,
    required this.onTap,
  });

  final MotionActivityDefinition activity;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final accent = _movementAccent(activity.category);
    return NuvoPressable(
      onTap: onTap,
      scale: 0.94,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.14)
              : c.panelLight,
          borderRadius: BorderRadius.circular(NuvoRadii.pill),
          border: Border.all(
            color: selected ? accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              activity.icon,
              size: 14,
              color: selected ? accent : c.inkMuted,
            ),
            const SizedBox(width: 6),
            Text(
              activity.title,
              style: AppTextStyles.labelMedium.copyWith(
                fontSize: 12.5,
                color: selected ? accent : c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one browse system — a compact two-column activity grid.
class _MovementGrid extends StatelessWidget {
  const _MovementGrid({
    required this.activities,
    required this.selectedActivityId,
    required this.onSelect,
  });

  final List<MotionActivityDefinition> activities;
  final String selectedActivityId;
  final ValueChanged<MotionActivityDefinition> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final tileWidth = (constraints.maxWidth - gap) / 2;
        // Enough room for icon well + 2-line name + unit, compact at 320.
        final ratio = tileWidth / 108;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: activities.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            childAspectRatio: ratio,
          ),
          itemBuilder: (context, index) {
            final activity = activities[index];
            return _MovementTile(
              activity: activity,
              selected: activity.activityId == selectedActivityId,
              onTap: () => onSelect(activity),
            );
          },
        );
      },
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({
    required this.activity,
    required this.selected,
    required this.onTap,
  });

  final MotionActivityDefinition activity;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final accent = _movementAccent(activity.category);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      selected: selected,
      label: '${activity.title}, ${activity.unit}',
      child: PressableScale(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: dark ? 0.20 : 0.10)
                : c.surface,
            borderRadius: BorderRadius.circular(NuvoRadii.lg),
            border: Border.all(
              color: selected ? accent : c.divider,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: accent.withValues(
                        alpha: selected ? (dark ? 0.30 : 0.18) : 0.10,
                      ),
                      borderRadius: BorderRadius.circular(NuvoRadii.sm),
                    ),
                    child: Icon(activity.icon, size: 16, color: accent),
                  ),
                  const Spacer(),
                  if (selected)
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 12,
                        color: NuvoColors.white,
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                activity.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelMedium.copyWith(
                  color: c.ink,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                activity.unit,
                style: AppTextStyles.labelSmall.copyWith(
                  color: c.inkSubtle,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The animated line above the CTA once a movement is picked — "Pushups ·
/// reps" context that morphs as the selection changes.
class _SelectionContext extends StatelessWidget {
  const _SelectionContext({required this.activity});
  final MotionActivityDefinition activity;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final accent = _movementAccent(activity.category);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.25),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: Row(
        key: ValueKey(activity.activityId),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(activity.icon, size: 15, color: accent),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              '${activity.title} · ${activity.unit}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelMedium.copyWith(
                color: c.ink,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Search results ───────────────────────────────────────────────────────────

/// Search swaps the grid for a compact result list — the only list mode.
/// Empty state routes straight into Teach Nuvo, a key product moment.
class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.query,
    required this.activities,
    required this.selectedActivityId,
    required this.onSelect,
    required this.onTeachNuvo,
  });
  final String query;
  final List<MotionActivityDefinition> activities;
  final String selectedActivityId;
  final ValueChanged<MotionActivityDefinition> onSelect;
  final VoidCallback onTeachNuvo;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final normalized = query.toLowerCase().trim();
    final results = activities.where((activity) {
      if (normalized.isEmpty) return true;
      return activity.title.toLowerCase().contains(normalized) ||
          activity.aliases.any((alias) => alias.toLowerCase().contains(normalized));
    }).toList();
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: Column(
            children: [
              Text(
                'No movement found.',
                style: AppTextStyles.bodyMedium.copyWith(color: c.inkMuted),
              ),
              const SizedBox(height: 8),
              NuvoPressable(
                onTap: onTeachNuvo,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Text(
                    'Create it with Teach Nuvo →',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: NuvoColors.avatarPlum,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < results.length; i++) ...[
          _SearchResultRow(
            activity: results[i],
            selected: results[i].activityId == selectedActivityId,
            onTap: () => onSelect(results[i]),
          ),
          if (i < results.length - 1)
            Divider(height: 1, thickness: 1, color: c.divider),
        ],
      ],
    );
  }
}

class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({
    required this.activity,
    required this.selected,
    required this.onTap,
  });

  final MotionActivityDefinition activity;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final accent = _movementAccent(activity.category);
    return Semantics(
      button: true,
      selected: selected,
      label: '${activity.title}, ${activity.unit}',
      child: NuvoPressable(
        onTap: onTap,
        haptic: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(NuvoRadii.sm),
                ),
                child: Icon(activity.icon, size: 15, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: c.ink,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${activity.category.label} · ${activity.unit}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: c.inkSubtle,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                color: selected ? accent : c.inkSubtle,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Step 3: Goal ──────────────────────────────────────────────────────────────

class _GoalPage extends StatefulWidget {
  const _GoalPage({
    required this.draft,
    required this.onDraftChanged,
    required this.onNext,
    this.onInput,
  });
  final RaceDraft draft;
  final ValueChanged<RaceDraft> onDraftChanged;
  final VoidCallback onNext;

  /// Fires once the user has set a goal — lets the coach retarget the page's
  /// continue CTA.
  final VoidCallback? onInput;

  @override
  State<_GoalPage> createState() => _GoalPageState();
}

class _GoalPageState extends State<_GoalPage> {
  late int _target;
  bool _editing = false;
  int _floorHits = 0;
  late final TextEditingController _editCtrl;
  late final FocusNode _editFocus;
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    _target = widget.draft.targetValue;
    _editCtrl = TextEditingController();
    _editFocus = FocusNode();
    _editFocus.addListener(() {
      if (!_editFocus.hasFocus) {
        _commitEdit();
      }
    });
  }

  @override
  void didUpdateWidget(_GoalPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync local target when draft changes from outside (e.g. activity reset)
    if (widget.draft.targetValue != _target && !_editing) {
      setState(() => _target = widget.draft.targetValue);
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _editCtrl.dispose();
    _editFocus.dispose();
    super.dispose();
  }

  void _setTarget(int value) {
    final clamped = value.clamp(1, 99999);
    if (clamped == _target) return;
    HapticFeedback.selectionClick();
    setState(() => _target = clamped);
    widget.onDraftChanged(
      widget.draft.copyWith(
        targetValue: clamped,
        markEdited: {RaceField.target},
      ),
    );
    widget.onInput?.call();
  }

  /// Press-and-hold repeat: the first step fires when the hold lands, then
  /// repeats until release. [_setTarget] clamps, so bounds hold themselves.
  void _startHold(VoidCallback step) {
    _stopHold();
    step();
    _holdTimer = Timer.periodic(
      const Duration(milliseconds: 90),
      (_) => step(),
    );
  }

  void _stopHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  void _startEdit() {
    setState(() {
      _editing = true;
      _editCtrl.text = (_isDistance && !_isShortDistance)
          ? formatMiles(_target)
          : '$_target';
      _editCtrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _editCtrl.text.length,
      );
    });
    _editFocus.requestFocus();
  }

  void _commitEdit() {
    final text = _editCtrl.text.trim();
    if (_isDistance) {
      // A decimal reads as miles ("0.5" → 805 m); a whole number reads as
      // metres ("150" → 150 m). Either way the canonical value is metres.
      final cleaned = text.replaceAll(RegExp(r'[^0-9.]'), '');
      final n = double.tryParse(cleaned);
      if (n != null && n > 0) {
        _setTarget(cleaned.contains('.') ? (n * 1609.344).round() : n.round());
      }
    } else {
      final parsed = int.tryParse(text);
      if (parsed != null && parsed > 0) {
        _setTarget(parsed);
      }
    }
    if (mounted) {
      setState(() => _editing = false);
    }
  }

  void _increment() => _setTarget(_target + _stepSize);
  void _decrement() {
    // At the floor the stepper refuses — the button nudges "nope" instead
    // of silently doing nothing (NuvoShake, not a state change).
    if (_target <= 1) {
      setState(() => _floorHits++);
      return;
    }
    _setTarget((_target - _stepSize).clamp(1, 99999));
  }

  /// Measurement model for the selected preset (reps unless it's a distance /
  /// duration activity like Treadmill Running / Plank).
  MotionMeasurementType get _measure =>
      widget.draft.isCustom || widget.draft.isManual
      ? MotionMeasurementType.repetitions
      : widget.draft.activity.resolvedMeasurementType;

  bool get _isDistance => _measure == MotionMeasurementType.distance;

  /// A short distance goal shows / edits in whole metres; a longer one in
  /// miles (matches [formatDistance]'s crossover).
  bool get _isShortDistance => _isDistance && _target < kMetresMilesCrossover;

  int get _stepSize {
    if (_isShortDistance) return 10; // 10 m steps for a sprint goal
    if (_isDistance) return 161; // ~0.1 mi in metres
    if (_target < 10) return 1;
    if (_target < 100) return 5;
    if (_target < 1000) return 25;
    return 100;
  }

  String get _winStatement {
    final activityName = widget.draft.displayActivityName.toLowerCase();
    final valueLabel = widget.draft.isCustom || widget.draft.isManual
        ? (widget.draft.metric == RaceMetric.seconds
              ? _secondsDisplay(_target)
              : '$_target $_unitWord')
        : widget.draft.activity.targetLabel(_target);
    return switch (widget.draft.format) {
      RaceFormat.mostInWindow =>
        'Most verified $activityName before the finish line wins.',
      // Attempt races don't chase a target — the number is a scale hint, not
      // a finish line, so it stays out of the win statement.
      RaceFormat.bestAttempt => widget.draft.lowerWins
          ? 'Lowest score wins — every verified attempt counts.'
          : 'Best single attempt wins — every verified score counts.',
      RaceFormat.timedAttempt =>
        'Most $activityName in '
            '${formatDurationShort(widget.draft.attemptDurationSeconds ?? 60)} '
            'wins.',
      _ => 'First to $valueLabel of verified $activityName wins.',
    };
  }

  // ── Race mode ───────────────────────────────────────────────────────────

  /// Modes this draft can express — preset activities declare their formats
  /// in the catalog; custom/manual goals support the full set.
  List<RaceFormat> get _availableFormats =>
      widget.draft.isCustom || widget.draft.isManual
      ? const [
          RaceFormat.firstToGoal,
          RaceFormat.mostInWindow,
          RaceFormat.bestAttempt,
          RaceFormat.timedAttempt,
        ]
      : widget.draft.activity.supportedFormats;

  String _modeLabel(RaceFormat f) => switch (f) {
    RaceFormat.firstToGoal => 'First to the goal',
    RaceFormat.mostInWindow => 'Most before time runs out',
    RaceFormat.bestAttempt => 'Best attempt',
    RaceFormat.timedAttempt => 'Timed battle',
  };

  void _setFormat(RaceFormat f) {
    if (widget.draft.format == f) return;
    HapticFeedback.selectionClick();
    final now = DateTime.now().toUtc();
    widget.onDraftChanged(
      widget.draft.copyWith(
        format: f,
        // Deadline modes need a finish line; timed battles need a duration.
        // Sensible defaults are set here and editable via the chips below.
        finishLineAt: switch (f) {
          RaceFormat.mostInWindow || RaceFormat.bestAttempt =>
            widget.draft.finishLineAt ??
                now.add(const Duration(days: 7)).toIso8601String(),
          RaceFormat.timedAttempt =>
            widget.draft.finishLineAt ??
                now.add(const Duration(hours: 24)).toIso8601String(),
          _ => widget.draft.finishLineAt,
        },
        attemptDurationSeconds: f == RaceFormat.timedAttempt
            ? widget.draft.attemptDurationSeconds ?? 60
            : widget.draft.attemptDurationSeconds,
        markEdited: {RaceField.format, RaceField.timing},
      ),
    );
    widget.onInput?.call();
  }

  static const _deadlineOptions = <(String, Duration)>[
    ('1 hour', Duration(hours: 1)),
    ('24 hours', Duration(hours: 24)),
    ('3 days', Duration(days: 3)),
    ('1 week', Duration(days: 7)),
  ];

  static const _attemptDurations = <(String, int)>[
    ('30s', 30),
    ('60s', 60),
    ('2 min', 120),
    ('5 min', 300),
  ];

  void _setDeadline(Duration d) {
    HapticFeedback.selectionClick();
    widget.onDraftChanged(
      widget.draft.copyWith(
        finishLineAt: DateTime.now().toUtc().add(d).toIso8601String(),
        markEdited: {RaceField.timing},
      ),
    );
    widget.onInput?.call();
  }

  bool _deadlineSelected(Duration d) {
    final raw = widget.draft.finishLineAt;
    if (raw == null) return false;
    final at = DateTime.tryParse(raw);
    if (at == null) return false;
    return (at.difference(DateTime.now().toUtc()).inSeconds - d.inSeconds)
            .abs() <=
        300;
  }

  void _setAttemptDuration(int seconds) {
    HapticFeedback.selectionClick();
    widget.onDraftChanged(
      widget.draft.copyWith(
        attemptDurationSeconds: seconds,
        markEdited: {RaceField.timing},
      ),
    );
    widget.onInput?.call();
  }

  /// Display string for an arbitrary target — passed to [NuvoNumberFlow] so
  /// the wheel animates whatever text each value formats to ("25", "0.25",
  /// "1 min 20 sec").
  String _displayFor(int v) {
    if (_isDistance && v < kMetresMilesCrossover) return '$v';
    if (_isDistance) return formatMiles(v);
    if (widget.draft.metric == RaceMetric.seconds) return _secondsDisplay(v);
    return '$v';
  }

  List<int> get _suggestedTargets =>
      widget.draft.isCustom || widget.draft.isManual
      ? const [5, 10, 25, 50]
      : widget.draft.activity.suggestedTargets;

  String get _unitWord => widget.draft.isManual
      ? (widget.draft.manualUnit?.trim().isNotEmpty == true
            ? widget.draft.manualUnit!.trim()
            : 'done')
      : widget.draft.isCustom
      ? (widget.draft.customUnit?.trim().isNotEmpty == true
            ? widget.draft.customUnit!.trim()
            : 'reps')
      : _isShortDistance
      ? 'm'
      : _isDistance
      ? 'mi'
      : widget.draft.activity.unit;

  /// Contextual question: "How many push-ups?", "How long?", "How many steps?".
  String get _goalPrompt {
    if (widget.draft.isManual) return 'What is the goal?';
    if (widget.draft.isCustom) return 'How many reps to win?';
    return widget.draft.activity.goalPrompt;
  }

  @override
  Widget build(BuildContext context) {
    final isSeconds = widget.draft.metric == RaceMetric.seconds;

    return _PageShell(
      question: _goalPrompt,
      support: 'First racer to reach it wins.',
      ctaLabel: 'Invite racers',
      onCta: widget.onNext,
      ctaKey: FirstRaceGuideKeys.composerGoalCta,
      body: KeyedSubtree(
        key: FirstRaceGuideKeys.composerGoal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Race mode ─────────────────────────────────────────────────
            if (_availableFormats.length > 1) ...[
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final f in _availableFormats)
                    _SuggestedTarget(
                      value: _modeLabel(f),
                      selected: widget.draft.format == f,
                      onTap: () {
                        _dismissKeyboard();
                        setState(() => _editing = false);
                        _setFormat(f);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 20),
            ],

            // ── Big tappable number ──────────────────────────────────────────
            _GoalDisplay(
              value: _target,
              format: _displayFor,
              allowDecimal: _isDistance,
              unitLabel: isSeconds
                  ? widget.draft.displayActivityName.toUpperCase()
                  : _unitWord.toUpperCase(),
              editing: _editing,
              editCtrl: _editCtrl,
              editFocus: _editFocus,
              onTapNumber: _startEdit,
              onCommitEdit: _commitEdit,
              onIncrement: _increment,
              onDecrement: _decrement,
              onHoldStart: _startHold,
              onHoldEnd: _stopHold,
              decrementNudges: _floorHits,
            ),
            const SizedBox(height: 24),

            // ── Suggested values (Wrap flows to a second row; not a scroller)
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final t in _suggestedTargets.take(_isDistance ? 7 : 5))
                  _SuggestedTarget(
                    value: _isDistance
                        ? formatMotionGoalOption(_measure, t)
                        : isSeconds
                        ? formatDurationShort(t)
                        : '$t',
                    selected: _target == t,
                    onTap: () {
                      _dismissKeyboard();
                      setState(() => _editing = false);
                      _setTarget(t);
                    },
                  ),
              ],
            ),

            // ── Finish line (deadline modes) ────────────────────────────────
            if (widget.draft.format != RaceFormat.firstToGoal) ...[
              const SizedBox(height: 24),
              Text(
                'FINISH LINE',
                style: AppTextStyles.labelUppercase(
                  12,
                  color: context.themeColors.inkMuted,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final (label, duration) in _deadlineOptions)
                    _SuggestedTarget(
                      value: label,
                      selected: _deadlineSelected(duration),
                      onTap: () => _setDeadline(duration),
                    ),
                ],
              ),
            ],

            // ── Attempt length (timed battles) ──────────────────────────────
            if (widget.draft.format == RaceFormat.timedAttempt) ...[
              const SizedBox(height: 24),
              Text(
                'ATTEMPT LENGTH',
                style: AppTextStyles.labelUppercase(
                  12,
                  color: context.themeColors.inkMuted,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final (label, seconds) in _attemptDurations)
                    _SuggestedTarget(
                      value: label,
                      selected:
                          widget.draft.attemptDurationSeconds == seconds,
                      onTap: () => _setAttemptDuration(seconds),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 24),

            // ── Win statement ────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: context.themeColors.panel,
                borderRadius: BorderRadius.circular(NuvoRadii.md),
              ),
              child: Text(
                _winStatement,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: context.themeColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalDisplay extends StatelessWidget {
  const _GoalDisplay({
    required this.value,
    required this.format,
    required this.unitLabel,
    required this.editing,
    required this.editCtrl,
    required this.editFocus,
    required this.onTapNumber,
    required this.onCommitEdit,
    required this.onIncrement,
    required this.onDecrement,
    this.onHoldStart,
    this.onHoldEnd,
    this.allowDecimal = false,
    this.decrementNudges = 0,
  });
  final int value;
  final String Function(int) format;
  final String unitLabel;
  final bool allowDecimal;
  final bool editing;
  final TextEditingController editCtrl;
  final FocusNode editFocus;
  final VoidCallback onTapNumber;
  final VoidCallback onCommitEdit;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  /// Press-and-hold repeat on the steppers: [onHoldStart] receives the step
  /// to repeat, [onHoldEnd] stops it.
  final void Function(VoidCallback step)? onHoldStart;
  final VoidCallback? onHoldEnd;

  /// Bump counter for decrement refusals — each increment shakes the
  /// minus button ("can't go lower").
  final int decrementNudges;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: context.themeColors.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.hero),
        border: Border.all(color: context.themeColors.border, width: 2),
        boxShadow: const [
          BoxShadow(
            color: NuvoColors.inkNavy,
            blurRadius: 0,
            offset: Offset(4, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          NuvoShake(
            trigger: decrementNudges,
            child: _StepButton(
              icon: Icons.remove_rounded,
              onTap: onDecrement,
              onHoldStart: () => onHoldStart?.call(onDecrement),
              onHoldEnd: onHoldEnd,
            ),
          ),
          NuvoPressable(
            onTap: onTapNumber,
            haptic: false,
            child: Column(
              children: [
                if (editing)
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: editCtrl,
                      focusNode: editFocus,
                      keyboardType: TextInputType.numberWithOptions(
                        decimal: allowDecimal,
                      ),
                      textInputAction: TextInputAction.done,
                      textAlign: TextAlign.center,
                      onSubmitted: (_) => onCommitEdit(),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(5),
                      ],
                      style: AppTextStyles.displaySmall.copyWith(
                        color: NuvoColors.actionBlue,
                        letterSpacing: -2,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  )
                else
                  NuvoNumberFlow(
                    value: value,
                    format: format,
                    style: AppTextStyles.displaySmall.copyWith(
                      color: context.themeColors.ink,
                      letterSpacing: -2,
                    ),
                    semanticsLabel:
                        '${format(value)} ${unitLabel.toLowerCase()}',
                  ),
                const SizedBox(height: 4),
                Text(
                  editing ? 'tap done to confirm' : unitLabel,
                  style: AppTextStyles.labelUppercase(
                    12,
                    color: editing ? NuvoColors.actionBlue : context.themeColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          _StepButton(
            icon: Icons.add_rounded,
            onTap: onIncrement,
            onHoldStart: () => onHoldStart?.call(onIncrement),
            onHoldEnd: onHoldEnd,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.onTap,
    this.onHoldStart,
    this.onHoldEnd,
  });
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onHoldStart;
  final VoidCallback? onHoldEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart:
          onHoldStart == null ? null : (_) => onHoldStart!(),
      onLongPressEnd: onHoldEnd == null ? null : (_) => onHoldEnd!(),
      onLongPressCancel: onHoldEnd,
      child: PressableScale(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: context.themeColors.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.themeColors.border, width: 2),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: context.themeColors.ink, size: 22),
        ),
      ),
    );
  }
}

class _SuggestedTarget extends StatelessWidget {
  const _SuggestedTarget({
    required this.value,
    required this.selected,
    required this.onTap,
  });
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? NuvoColors.actionBlue : context.themeColors.surface,
          borderRadius: BorderRadius.circular(NuvoRadii.pill),
          border: Border.all(
            color: selected ? NuvoColors.actionBlue : context.themeColors.ink,
            width: 1.5,
          ),
        ),
        child: Text(
          value,
          style: AppTextStyles.labelLarge.copyWith(
            color: selected ? NuvoColors.white : context.themeColors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

// ── Step 4: Racers ────────────────────────────────────────────────────────────

class _RacersPage extends StatefulWidget {
  const _RacersPage({
    required this.draft,
    required this.onDraftChanged,
    required this.onNext,
    this.onInput,
    this.withUser,
  });
  final RaceDraft draft;

  /// Race Together person context — the crew member this race was started
  /// for. They join when the race is created; the racers step explains that
  /// instead of offering a solo/crew toggle.
  final PublicUser? withUser;
  final ValueChanged<RaceDraft> onDraftChanged;
  final VoidCallback onNext;

  /// Fires once the user has chosen solo/crew — lets the coach retarget the
  /// page's continue CTA.
  final VoidCallback? onInput;

  @override
  State<_RacersPage> createState() => _RacersPageState();
}

class _RacersPageState extends State<_RacersPage> {
  // Initialise from draft visibility so back/forward preserves the choice
  late bool _inviteCrew;

  @override
  void initState() {
    super.initState();
    _inviteCrew = widget.draft.visibility == 'invite_code';
  }

  @override
  void didUpdateWidget(_RacersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _inviteCrew = widget.draft.visibility == 'invite_code';
  }

  void _setInvite(bool value) {
    setState(() => _inviteCrew = value);
    widget.onInput?.call();
    widget.onDraftChanged(
      widget.draft.copyWith(
        visibility: value ? 'invite_code' : 'private',
        markEdited: {RaceField.visibility},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      question: 'Who are you racing with?',
      support: 'Race solo or with crew.',
      ctaLabel: 'Review race',
      onCta: widget.onNext,
      ctaKey: FirstRaceGuideKeys.composerRacersCta,
      body: KeyedSubtree(
        key: FirstRaceGuideKeys.composerRacers,
        child: widget.withUser != null
            ? _RacerOption(
                title: 'Racing ${widget.withUser!.displayName}',
                subtitle: 'They join when the race starts.',
                icon: Icons.flag_rounded,
                selected: true,
                onTap: () {},
              )
            : Column(
                children: [
                  _RacerOption(
                    title: 'Pull in your crew',
                    subtitle: 'Invite link opens right after race starts.',
                    icon: Icons.group_add_rounded,
                    selected: _inviteCrew,
                    onTap: () => _setInvite(true),
                  ),
                  const SizedBox(height: 12),
                  _RacerOption(
                    title: 'Start solo',
                    subtitle: 'Race yourself first. Invite anytime.',
                    icon: Icons.person_rounded,
                    selected: !_inviteCrew,
                    onTap: () => _setInvite(false),
                  ),
                ],
              ),
      ),
    );
  }
}

class _RacerOption extends StatelessWidget {
  const _RacerOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: selected
              ? NuvoColors.actionBlue.withValues(alpha: 0.07)
              : NuvoColors.white,
          borderRadius: BorderRadius.circular(NuvoRadii.lg),
          border: Border.all(
            color: selected ? NuvoColors.actionBlue : context.themeColors.ink,
            width: selected ? 2 : 1.5,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected
                    ? NuvoColors.actionBlue.withValues(alpha: 0.12)
                    : context.themeColors.panel,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                color: selected ? NuvoColors.actionBlue : context.themeColors.ink,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: selected ? NuvoColors.actionBlue : context.themeColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: context.themeColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                color: NuvoColors.actionBlue,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Step 5: Review ────────────────────────────────────────────────────────────

class _ReviewPage extends StatelessWidget {
  const _ReviewPage({
    required this.draft,
    required this.loading,
    required this.error,
    required this.onStart,
    required this.onEditStep,
    required this.showDiagnostics,
    required this.onCopyDiagnostics,
  });
  final RaceDraft draft;
  final bool loading;
  final String? error;
  final VoidCallback onStart;
  final ValueChanged<_Step> onEditStep;
  final bool showDiagnostics;
  final VoidCallback onCopyDiagnostics;

  String get _finishLineLabel {
    if (!draft.isCustom && !draft.isManual) {
      return draft.activity.targetLabel(draft.targetValue);
    }
    final isSeconds = draft.metric == RaceMetric.seconds;
    return isSeconds
        ? _secondsDisplay(draft.targetValue)
        : '${draft.targetValue} ${draft.metric.label}';
  }

  String get _winSubtitle {
    final isSeconds = draft.metric == RaceMetric.seconds;
    final valueLabel = isSeconds
        ? _secondsDisplay(draft.targetValue)
        : '${draft.targetValue}';
    return 'First to $valueLabel verified ${draft.displayActivityName.toLowerCase()} wins.';
  }

  @override
  Widget build(BuildContext context) {
    final isInvite = draft.visibility == 'invite_code';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Review your race',
                  style: AppTextStyles.labelUppercase(
                    12,
                  ).copyWith(color: NuvoColors.blue),
                ).animate().fadeIn(duration: 180.ms),
                const SizedBox(height: 8),
                NuvoPressable(
                  onTap: () => onEditStep(_Step.name),
                  haptic: false,
                  child: Text(
                    draft.resolvedTitle,
                    style: AppTextStyles.headlineLarge.copyWith(
                      color: context.themeColors.ink,
                      height: 1.08,
                    ),
                  ),
                ).animate().fadeIn(duration: 220.ms),
                const SizedBox(height: 6),
                Text(
                  _winSubtitle,
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: context.themeColors.inkMuted,
                  ),
                ).animate(delay: 40.ms).fadeIn(duration: 200.ms),
                const SizedBox(height: 22),
                _RacePathVisual(
                  targetLabel: _finishLineLabel,
                  activityIcon: draft.activity.icon,
                  activityLabel: draft.displayActivityName,
                ).animate(delay: 80.ms).fadeIn(duration: 260.ms),
                const SizedBox(height: 16),
                _ReviewDetails(
                  activityLabel: draft.displayActivityName,
                  activitySub: draft.isCustom
                      ? 'Custom movement'
                      : 'Camera verified',
                  finishLineLabel: _finishLineLabel,
                  raceModeLabel: isInvite ? 'Invite crew' : 'Start solo',
                  raceModeSub: isInvite
                      ? 'Invite link opens after race starts'
                      : 'Race yourself first',
                  onEditActivity: draft.isCustom
                      ? null
                      : () => onEditStep(_Step.activity),
                  onEditGoal: () => onEditStep(_Step.goal),
                  onEditRacers: () => onEditStep(_Step.racers),
                ).animate(delay: 120.ms).fadeIn(duration: 220.ms),
                if (error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: NuvoColors.danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(NuvoRadii.md),
                      border: Border.all(
                        color: NuvoColors.danger.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Text(
                      error!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: NuvoColors.danger,
                      ),
                    ),
                  ),
                ],
                if (showDiagnostics) ...[
                  const SizedBox(height: 16),
                  NuvoOutlineButton(
                    label: 'Copy race debug',
                    expand: true,
                    onPressed: onCopyDiagnostics,
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: NuvoSuccessButton(
            key: FirstRaceGuideKeys.composerReview,
            label: 'Start race',
            icon: Icons.flag_rounded,
            expand: true,
            loading: loading,
            solid: true,
            onPressed: loading ? null : onStart,
          ),
        ),
      ],
    );
  }
}

class _RacePathVisual extends StatelessWidget {
  const _RacePathVisual({
    required this.targetLabel,
    required this.activityIcon,
    required this.activityLabel,
  });
  final String targetLabel;
  final IconData activityIcon;
  final String activityLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: context.semanticColors.neutral.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.hero),
        border: Border.all(color: context.themeColors.border, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: NuvoColors.blue,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(activityIcon, color: NuvoColors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activityLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: context.themeColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your proof moves the leaderboard',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: context.themeColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const _RacePoint(label: 'Start line', color: NuvoColors.blue),
              const SizedBox(width: 10),
              Expanded(
                child: CustomPaint(
                  size: const Size(double.infinity, 16),
                  painter: _RaceLinePainter(
                    color: context.themeColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const _RacePoint(label: 'Finish line', color: NuvoColors.success),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              targetLabel,
              style: AppTextStyles.titleMedium.copyWith(
                color: context.themeColors.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RacePoint extends StatelessWidget {
  const _RacePoint({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: context.themeColors.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ReviewDetails extends StatelessWidget {
  const _ReviewDetails({
    required this.activityLabel,
    required this.activitySub,
    required this.finishLineLabel,
    required this.raceModeLabel,
    required this.raceModeSub,
    required this.onEditActivity,
    required this.onEditGoal,
    required this.onEditRacers,
  });

  final String activityLabel;
  final String activitySub;
  final String finishLineLabel;
  final String raceModeLabel;
  final String raceModeSub;
  final VoidCallback? onEditActivity;
  final VoidCallback onEditGoal;
  final VoidCallback onEditRacers;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.themeColors.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
        border: Border.all(color: context.themeColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _ReviewDetailRow(
            icon: Icons.verified_rounded,
            label: 'Proof',
            value: activityLabel,
            sub: activitySub,
            onTap: onEditActivity,
            isLast: false,
          ),
          _ReviewDetailRow(
            icon: Icons.flag_rounded,
            label: 'Finish line',
            value: finishLineLabel,
            sub: 'Target everyone races toward',
            onTap: onEditGoal,
            isLast: false,
          ),
          _ReviewDetailRow(
            icon: Icons.group_rounded,
            label: 'Race mode',
            value: raceModeLabel,
            sub: raceModeSub,
            onTap: onEditRacers,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _ReviewDetailRow extends StatelessWidget {
  const _ReviewDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    required this.onTap,
    required this.isLast,
  });

  final IconData icon;
  final String label;
  final String value;
  final String sub;
  final VoidCallback? onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: context.semanticColors.neutral.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: NuvoColors.blue, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: context.themeColors.inkMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: context.themeColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.themeColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.edit_outlined, color: context.themeColors.inkMuted, size: 16),
        ],
      ),
    );

    return Column(
      children: [
        if (onTap == null)
          row
        else
          NuvoPressable(onTap: onTap, haptic: false, child: row),
        if (!isLast)
          Divider(
            height: 1,
            thickness: 1,
            indent: 60,
            color: context.themeColors.divider,
          ),
      ],
    );
  }
}

class _RaceLinePainter extends CustomPainter {
  const _RaceLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const dashWidth = 8.0;
    const dashGap = 6.0;
    var x = 0.0;
    final y = size.height / 2;

    while (x < size.width) {
      canvas.drawLine(
        Offset(x, y),
        Offset((x + dashWidth).clamp(0, size.width), y),
        paint,
      );
      x += dashWidth + dashGap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
