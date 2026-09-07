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
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/data/auth_api.dart';
import '../ai/custom_pose/custom_pose_verifier_spec.dart';
import '../data/race_models.dart';
import '../domain/motion_activity.dart';
import '../domain/motion_activity_catalog.dart';
import '../domain/race_draft.dart';
import 'create_race_screen.dart';
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
        final parsed = draftFromIdea(prefill.idea);
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
      debugPrint('RACE COMPOSER: ${from.name} -> ${to.name}  '
          'reason: $reason  (${custom ? 'custom' : 'preset'})');
    }
  }

  /// The ONLY place `_step` changes. Every call passes an explicit [reason];
  /// nothing navigates from a provider value, a listener, or a post-frame peek.
  void _goToStep(_Step target, {required String reason}) {
    _dismissKeyboard();
    _logTransition(_step, target, reason);
    final idx = _steps.indexOf(target); // PageView keeps all pages; index by enum
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
    final r = reason ??
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
      ref.read(_composerDraftProvider.notifier).state =
          ref.read(_composerDraftProvider).copyWith(verifierSpec: spec);
      _goToStep(_Step.goal, reason: 'teach nuvo returned verifier spec');
    }
    // spec == null → user backed out; stay on `train` (retry button visible).
  }

  void _retreat() {
    final v = _visibleSteps;
    final i = v.indexOf(_step);
    if (i > 0) {
      _goToStep(v[i - 1], reason: 'back button');
    } else {
      _dismissKeyboard();
      safePopOrGo(context, '/compete');
    }
  }

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
          debugPrint('COMPOSER GUARD: custom race with no verifierSpec — '
              'returning to train step');
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
      backgroundColor: NuvoColors.page,
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
                  ),
                  _ActivityPage(
                    draft: draft,
                    onDraftChanged: (d) =>
                        ref.read(_composerDraftProvider.notifier).state = d,
                    onNext: _advance,
                  ),
                  _TrainPage(
                    draft: draft,
                    onTrain: () => _openTraining(reason: 'train page retry'),
                    onContinue: () =>
                        _advance(reason: 'train page continue (already trained)'),
                  ),
                  _GoalPage(
                    draft: draft,
                    onDraftChanged: (d) =>
                        ref.read(_composerDraftProvider.notifier).state = d,
                    onNext: _advance,
                  ),
                  _RacersPage(
                    draft: draft,
                    onDraftChanged: (d) =>
                        ref.read(_composerDraftProvider.notifier).state = d,
                    onNext: _advance,
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
    final coach = switch (guide) {
      FirstRaceGuideStep.composerName => FirstRaceGuideCoach(
        step: guide,
        targetKey: FirstRaceGuideKeys.composerName,
        eyebrow: 'NAME THE RACE',
        title: 'Give the board a finish line.',
        body: 'Type a short name your crew will understand, then continue.',
      ),
      FirstRaceGuideStep.composerActivity => FirstRaceGuideCoach(
        step: guide,
        targetKey: FirstRaceGuideKeys.composerActivity,
        eyebrow: 'CHOOSE PROOF',
        title: 'Pick what moves the board.',
        body:
            'Choose a supported movement. Nuvo will use it to verify progress.',
      ),
      FirstRaceGuideStep.composerGoal => FirstRaceGuideCoach(
        step: guide,
        targetKey: FirstRaceGuideKeys.composerGoal,
        eyebrow: 'SET THE FINISH LINE',
        title: 'Choose the number to beat.',
        body: 'This is the target everyone races toward.',
      ),
      FirstRaceGuideStep.composerReview => FirstRaceGuideCoach(
        step: guide,
        targetKey: FirstRaceGuideKeys.composerReview,
        eyebrow: 'PUT IT ON THE BOARD',
        title: 'Review it, then start the race.',
        body: 'Tap Start race to create the real leaderboard.',
      ),
      FirstRaceGuideStep.composerRacers => FirstRaceGuideCoach(
        step: guide,
        targetKey: FirstRaceGuideKeys.composerRacers,
        eyebrow: 'BRING YOUR CREW',
        title: 'Choose who starts with you.',
        body:
            'Pick Start solo for now. You can invite your crew from the race room.',
      ),
      _ => null,
    };
    return coach == null ? screen : Stack(children: [screen, coach]);
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
                  color: NuvoColors.muted,
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
                  color: NuvoColors.border,
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
  });

  final String question;
  final String support;
  final Widget body;
  final String ctaLabel;
  final VoidCallback onCta;
  final bool ctaEnabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  question,
                  style: AppTextStyles.headlineLarge.copyWith(
                    color: NuvoColors.navy,
                    height: 1.1,
                  ),
                ).animate().fadeIn(duration: 220.ms),
                const SizedBox(height: 8),
                Text(
                  support,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: NuvoColors.muted,
                  ),
                ),
                const SizedBox(height: 24),
                body.animate(delay: 60.ms).fadeIn(duration: 220.ms),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: NuvoPrimaryButton(
            label: ctaLabel,
            expand: true,
            onPressed: ctaEnabled ? onCta : null,
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
  });
  final RaceDraft draft;
  final ValueChanged<RaceDraft> onDraftChanged;
  final VoidCallback onNext;

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
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(_NamePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When draft is changed externally (e.g. activity/goal change updates the
    // generated title), sync the text field only if the name is not custom.
    if (!widget.draft.hasCustomName) {
      final newTitle = widget.draft.resolvedTitle;
      if (_ctrl.text != newTitle) {
        _ctrl.text = newTitle;
        _hasCustomName = false;
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
      widget.draft.copyWith(title: value, hasCustomName: _hasCustomName),
    );
  }

  void _commit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _focusNode.unfocus();
    widget.onDraftChanged(
      widget.draft.copyWith(title: text, hasCustomName: _hasCustomName),
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
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.md),
        border: Border.all(
          color: _focused ? NuvoColors.actionBlue : NuvoColors.navy,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: NuvoColors.navy.withValues(alpha: _focused ? 0.12 : 0.18),
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
          color: NuvoColors.navy,
          fontSize: 20,
          height: 1.4,
        ),
        maxLines: 2,
        minLines: 1,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: AppTextStyles.titleLarge.copyWith(
            color: NuvoColors.muted.withValues(alpha: 0.45),
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
  });
  final RaceDraft draft;
  final ValueChanged<RaceDraft> onDraftChanged;
  final VoidCallback onNext;

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
    widget.onDraftChanged(widget.draft.copyWith(goalKind: kind));
    setState(() {});
  }

  void _syncCustomMovement() {
    widget.onDraftChanged(
      widget.draft.copyWith(
        goalKind: RaceGoalKind.movement,
        customActivityName: _moveNameController.text.trim(),
        customUnit: _moveUnitController.text.trim().isEmpty
            ? 'reps'
            : _moveUnitController.text.trim(),
      ),
    );
  }

  void _syncManual() {
    widget.onDraftChanged(
      widget.draft.copyWith(
        goalKind: RaceGoalKind.manual,
        manualGoalName: _manualNameController.text.trim(),
        manualUnit: _manualUnitController.text.trim(),
      ),
    );
  }

  void _select(MotionActivityDefinition activity) {
    final currentTarget = widget.draft.targetValue;
    final keepTarget =
        activity.suggestedTargets.contains(currentTarget) ||
        (currentTarget >= 1 && currentTarget <= 99999);
    widget.onDraftChanged(
      widget.draft.asPreset(
        activity: activity,
        targetValue: keepTarget ? currentTarget : activity.defaultTarget,
      ),
    );
    setState(() => _teachMode = false);
    // Record selection in recent movements
    ref
        .read(recentMovementIdsProvider.notifier)
        .record(activity.type.backendValue);
  }

  @override
  Widget build(BuildContext context) {
    final isManual = widget.draft.goalKind == RaceGoalKind.manual;

    if (_teachMode && !isManual) {
      final canContinue = _moveNameController.text.trim().isNotEmpty;
      return _PageShell(
        question: 'Your custom movement',
        support: 'Name it and pick how it is counted. Next you\'ll teach it to '
            'Nuvo.',
        ctaLabel: 'Continue to training',
        ctaEnabled: canContinue,
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
              style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() => _teachMode = false),
              child: Text('Pick a preset movement instead',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: NuvoColors.navy)),
            ),
          ],
        ),
      );
    }

    return _PageShell(
      question: 'What are you competing in?',
      support: isManual
          ? 'Name the goal and how it is measured.'
          : 'Pick a movement for your crew.',
      ctaLabel: 'Set the finish line',
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
                  color: NuvoColors.muted,
                ),
              ),
            ] else ...[
              _TeachNuvoCard(onTap: () => setState(() => _teachMode = true)),
              const SizedBox(height: 18),
              Text(
                'Or pick a movement Nuvo already knows',
                style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
              ),
              const SizedBox(height: 12),
              _SearchBar(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
              const SizedBox(height: 16),
              if (_searchQuery.isNotEmpty)
                _SearchResults(
                  query: _searchQuery,
                  selectedType: widget.draft.activity.type,
                  onSelect: _select,
                )
              else ...[
                _CategoryTabs(
                  categories: activeCategories,
                  selected: _selectedCategory,
                  onSelect: (cat) => setState(() => _selectedCategory = cat),
                ),
                const SizedBox(height: 14),
                _ActivityGrid(
                  activities: _selectedCategory == null
                      ? motionActivityDefinitions
                      : activitiesByCategory(_selectedCategory!),
                  selectedType: widget.draft.activity.type,
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
class _TeachNuvoCard extends StatelessWidget {
  const _TeachNuvoCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      scale: 0.98,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: NuvoColors.blueSurface,
          borderRadius: BorderRadius.circular(NuvoRadii.card),
          border: Border.all(color: NuvoColors.blueBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: NuvoColors.blue,
                borderRadius: BorderRadius.circular(NuvoRadii.badge),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: NuvoColors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Don't see your movement?",
                    style: AppTextStyles.raceRowTitle.copyWith(
                      color: NuvoColors.navy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Teach Nuvo — show it 3 times and race on it.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: NuvoColors.navy,
            ),
          ],
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
                  : NuvoColors.blueSurface,
              borderRadius: BorderRadius.circular(NuvoRadii.card),
              border: Border.all(
                color: trained ? NuvoColors.success : NuvoColors.blueBorder,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  trained
                      ? Icons.check_circle_rounded
                      : Icons.videocam_rounded,
                  color: trained ? NuvoColors.success : NuvoColors.blue,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    trained
                        ? 'Movement trained — Nuvo learned "$name".'
                        : 'Not trained yet. Tap Start training to record your '
                            '3 examples, then test it.',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: NuvoColors.navy),
                  ),
                ),
              ],
            ),
          ),
          if (trained) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: onTrain,
              child: Text(
                'Retrain this movement',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: NuvoColors.navy),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Movement (camera) vs custom manual goal.
class _GoalKindToggle extends StatelessWidget {
  const _GoalKindToggle({required this.kind, required this.onChanged});
  final RaceGoalKind kind;
  final ValueChanged<RaceGoalKind> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(RaceGoalKind k, IconData icon, String label) {
      final selected = kind == k;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(k),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? NuvoColors.actionBlue : Colors.transparent,
              borderRadius: BorderRadius.circular(NuvoRadii.sm),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? NuvoColors.white : NuvoColors.muted,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: selected ? NuvoColors.white : NuvoColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.md),
        border: Border.all(color: NuvoColors.navy, width: 2),
      ),
      child: Row(
        children: [
          seg(RaceGoalKind.movement, Icons.directions_run_rounded, 'Movement'),
          seg(RaceGoalKind.manual, Icons.flag_rounded, 'Custom goal'),
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
      style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.navy),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: NuvoColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NuvoRadii.md),
          borderSide: const BorderSide(color: NuvoColors.navy, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NuvoRadii.md),
          borderSide: const BorderSide(color: NuvoColors.navy, width: 2),
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

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(NuvoRadii.lg),
      borderSide: const BorderSide(color: NuvoColors.navy, width: 2),
    );
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.navy),
      decoration: InputDecoration(
        hintText: 'Search movements',
        hintStyle: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: NuvoColors.muted,
          size: 20,
        ),
        filled: true,
        fillColor: NuvoColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border,
        errorBorder: border,
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
      height: 36,
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
    return GestureDetector(
      onTap: onTap,
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
            color: selected ? NuvoColors.actionBlue : NuvoColors.muted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ActivityGrid extends StatelessWidget {
  const _ActivityGrid({
    required this.activities,
    required this.selectedType,
    required this.onSelect,
  });

  final List<MotionActivityDefinition> activities;
  final MotionActivityType selectedType;
  final ValueChanged<MotionActivityDefinition> onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.45,
      ),
      itemCount: activities.length,
      itemBuilder: (context, index) {
        final activity = activities[index];
        return _CompactActivityCard(
          activity: activity,
          selected: activity.type == selectedType,
          onTap: () => onSelect(activity),
        );
      },
    );
  }
}

// ── Compact activity card ────────────────────────────────────────────────────

class _CompactActivityCard extends StatelessWidget {
  const _CompactActivityCard({
    required this.activity,
    required this.selected,
    required this.onTap,
  });
  final MotionActivityDefinition activity;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? NuvoColors.actionBlue.withValues(alpha: 0.08)
              : NuvoColors.surface,
          borderRadius: BorderRadius.circular(NuvoRadii.md),
          border: Border.all(
            color: selected ? NuvoColors.actionBlue : NuvoColors.navy,
            width: selected ? 2 : 1.5,
          ),
          boxShadow: null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(
                  activity.icon,
                  color: selected ? NuvoColors.actionBlue : NuvoColors.navy,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    activity.title,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: NuvoColors.navy,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Search results ───────────────────────────────────────────────────────────

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.query,
    required this.selectedType,
    required this.onSelect,
  });
  final String query;
  final MotionActivityType selectedType;
  final ValueChanged<MotionActivityDefinition> onSelect;

  @override
  Widget build(BuildContext context) {
    final results = searchActivities(query);
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            'No movements found for "$query"',
            style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
          ),
        ),
      );
    }
    return Column(
      children: [
        _ActivityGrid(
          activities: results,
          selectedType: selectedType,
          onSelect: onSelect,
        ),
      ],
    );
  }
}

// ── Step 3: Goal ──────────────────────────────────────────────────────────────

class _GoalPage extends StatefulWidget {
  const _GoalPage({
    required this.draft,
    required this.onDraftChanged,
    required this.onNext,
  });
  final RaceDraft draft;
  final ValueChanged<RaceDraft> onDraftChanged;
  final VoidCallback onNext;

  @override
  State<_GoalPage> createState() => _GoalPageState();
}

class _GoalPageState extends State<_GoalPage> {
  late int _target;
  bool _editing = false;
  late final TextEditingController _editCtrl;
  late final FocusNode _editFocus;

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
    _editCtrl.dispose();
    _editFocus.dispose();
    super.dispose();
  }

  void _setTarget(int value) {
    final clamped = value.clamp(1, 99999);
    setState(() => _target = clamped);
    widget.onDraftChanged(widget.draft.copyWith(targetValue: clamped));
  }

  void _startEdit() {
    setState(() {
      _editing = true;
      _editCtrl.text = _isDistance ? formatMiles(_target) : '$_target';
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
      final miles = double.tryParse(text.replaceAll(RegExp(r'[^0-9.]'), ''));
      if (miles != null && miles > 0) {
        _setTarget((miles * 1609.344).round());
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
  void _decrement() => _setTarget((_target - _stepSize).clamp(1, 99999));

  /// Measurement model for the selected preset (reps unless it's a distance /
  /// duration activity like Treadmill Running / Plank).
  MotionMeasurementType get _measure => widget.draft.isCustom ||
          widget.draft.isManual
      ? MotionMeasurementType.repetitions
      : widget.draft.activity.resolvedMeasurementType;

  bool get _isDistance => _measure == MotionMeasurementType.distance;

  int get _stepSize {
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
    return 'First to $valueLabel of verified $activityName wins.';
  }

  String get _displayTarget {
    if (_isDistance) return formatMiles(_target);
    if (widget.draft.metric == RaceMetric.seconds) {
      return _secondsDisplay(_target);
    }
    return '$_target';
  }

  List<int> get _suggestedTargets => widget.draft.isCustom || widget.draft.isManual
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
      body: KeyedSubtree(
        key: FirstRaceGuideKeys.composerGoal,
        child: Column(
          children: [
            // ── Big tappable number ──────────────────────────────────────────
            _GoalDisplay(
              displayValue: _displayTarget,
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
            ),
            const SizedBox(height: 24),

            // ── Suggested values ─────────────────────────────────────────────
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final t in _suggestedTargets.take(5))
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
            const SizedBox(height: 24),

            // ── Win statement ────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: NuvoColors.panel,
                borderRadius: BorderRadius.circular(NuvoRadii.md),
              ),
              child: Text(
                _winStatement,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: NuvoColors.navy,
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
    required this.displayValue,
    required this.unitLabel,
    required this.editing,
    required this.editCtrl,
    required this.editFocus,
    required this.onTapNumber,
    required this.onCommitEdit,
    required this.onIncrement,
    required this.onDecrement,
    this.allowDecimal = false,
  });
  final String displayValue;
  final String unitLabel;
  final bool allowDecimal;
  final bool editing;
  final TextEditingController editCtrl;
  final FocusNode editFocus;
  final VoidCallback onTapNumber;
  final VoidCallback onCommitEdit;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(NuvoRadii.hero),
        border: Border.all(color: NuvoColors.inkNavy, width: 2),
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
          _StepButton(icon: Icons.remove_rounded, onTap: onDecrement),
          GestureDetector(
            onTap: onTapNumber,
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
                  Text(
                    displayValue,
                    style: AppTextStyles.displaySmall.copyWith(
                      color: NuvoColors.navy,
                      letterSpacing: -2,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  editing ? 'tap done to confirm' : unitLabel,
                  style: AppTextStyles.labelUppercase(
                    12,
                    color: editing ? NuvoColors.actionBlue : NuvoColors.muted,
                  ),
                ),
              ],
            ),
          ),
          _StepButton(icon: Icons.add_rounded, onTap: onIncrement),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: NuvoColors.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NuvoColors.navy, width: 2),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: NuvoColors.navy, size: 22),
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
          color: selected ? NuvoColors.actionBlue : NuvoColors.white,
          borderRadius: BorderRadius.circular(NuvoRadii.pill),
          border: Border.all(
            color: selected ? NuvoColors.actionBlue : NuvoColors.navy,
            width: 1.5,
          ),
        ),
        child: Text(
          value,
          style: AppTextStyles.labelLarge.copyWith(
            color: selected ? NuvoColors.white : NuvoColors.navy,
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
  });
  final RaceDraft draft;
  final ValueChanged<RaceDraft> onDraftChanged;
  final VoidCallback onNext;

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
    widget.onDraftChanged(
      widget.draft.copyWith(visibility: value ? 'invite_code' : 'private'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      question: 'Who are you racing with?',
      support: 'Race solo or with crew.',
      ctaLabel: 'Review race',
      onCta: widget.onNext,
      body: KeyedSubtree(
        key: FirstRaceGuideKeys.composerRacers,
        child: Column(
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
            color: selected ? NuvoColors.actionBlue : NuvoColors.navy,
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
                    : NuvoColors.panel,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                color: selected ? NuvoColors.actionBlue : NuvoColors.navy,
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
                      color: selected ? NuvoColors.actionBlue : NuvoColors.navy,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.muted,
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
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.vertical -
                    160,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Eyebrow
                  Text(
                    'Review your race',
                    style: AppTextStyles.labelUppercase(
                      12,
                    ).copyWith(color: NuvoColors.blue),
                  ).animate().fadeIn(duration: 180.ms),
                  const SizedBox(height: 8),

                  // Race title — tappable to edit name
                  GestureDetector(
                    onTap: () => onEditStep(_Step.name),
                    child: Text(
                      draft.resolvedTitle,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.headlineLarge.copyWith(
                        color: NuvoColors.navy,
                        height: 1.1,
                      ),
                    ),
                  ).animate().fadeIn(duration: 220.ms),
                  const SizedBox(height: 6),
                  Text(
                    _winSubtitle,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: NuvoColors.muted,
                    ),
                  ).animate(delay: 40.ms).fadeIn(duration: 200.ms),
                  const SizedBox(height: 36),

                  // Central hero: the race path card
                  _RacePathVisual(
                    targetLabel: _finishLineLabel,
                  ).animate(delay: 80.ms).fadeIn(duration: 260.ms),

                  const SizedBox(height: 24),

                  // Compact editable detail chips — centered row
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ReviewDetailChip(
                        icon: Icons.verified_rounded,
                        label: 'Camera verified',
                        sub: '${draft.displayActivityName} · ${draft.metric.label}',
                        onTap: draft.isCustom
                            ? null
                            : () => onEditStep(_Step.activity),
                      ),
                      _ReviewDetailChip(
                        icon: Icons.flag_rounded,
                        label: _finishLineLabel,
                        sub: 'Finish line',
                        onTap: () => onEditStep(_Step.goal),
                      ),
                      _ReviewDetailChip(
                        icon: isInvite ? Icons.group_rounded : Icons.person_rounded,
                        label: isInvite ? 'Invite crew' : 'Start solo',
                        sub: isInvite
                            ? 'Invite link opens after race starts'
                            : 'Race yourself first',
                        onTap: () => onEditStep(_Step.racers),
                      ),
                    ],
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
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: NuvoPrimaryButton(
            key: FirstRaceGuideKeys.composerReview,
            label: 'Start race',
            icon: Icons.flag_rounded,
            expand: true,
            loading: loading,
            onPressed: loading ? null : onStart,
          ),
        ),
      ],
    );
  }
}

class _RacePathVisual extends StatelessWidget {
  const _RacePathVisual({required this.targetLabel});
  final String targetLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        color: NuvoColors.navy,
        borderRadius: BorderRadius.circular(NuvoRadii.hero),
        boxShadow: const [
          BoxShadow(
            color: NuvoColors.inkNavy,
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
              const Text(
                'START',
                style: TextStyle(
                  color: NuvoColors.actionBlue,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CustomPaint(
                  size: const Size(double.infinity, 16),
                  painter: _RaceLinePainter(),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.flag_rounded,
                color: NuvoColors.success,
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            targetLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Finish line',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RaceLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
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

class _ReviewDetailChip extends StatelessWidget {
  const _ReviewDetailChip({
    required this.icon,
    required this.label,
    required this.sub,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: NuvoColors.border, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: NuvoColors.actionBlue, size: 16),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTextStyles.labelLarge.copyWith(
                  color: NuvoColors.navy,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                sub,
                style: AppTextStyles.bodySmall.copyWith(
                  color: NuvoColors.muted,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return chip;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: chip,
    );
  }
}
