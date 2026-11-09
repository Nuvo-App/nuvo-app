import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_service.dart';
import '../../../core/motion/motion.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/onboarding_v2_store.dart';
import 'onboarding_step.dart';
import 'xp_table.dart';

/// Immutable view of the persisted flow — the store is the source of truth;
/// this is what widgets watch.
class OnboardingFlowState {
  const OnboardingFlowState({
    required this.restored,
    required this.step,
    required this.completed,
    required this.xpAwarded,
    this.answerQ1,
    this.answerQ2,
    this.email,
    required this.cameraFallback,
    required this.tourSkipped,
    this.notifyOutcome,
  });

  /// The store has been read — never route on an unrestored state.
  final bool restored;

  /// The step currently on screen. May point at a completed step while the
  /// user navigates back — completion is durable either way.
  final OnboardingStep step;

  /// Steps finished so far (skips count — a skipped step is resolved).
  final Set<OnboardingStep> completed;

  /// Step → XP actually granted (the idempotency record; entries are never
  /// re-applied, which is what makes a kill + relaunch double-award-free).
  final Map<OnboardingStep, int> xpAwarded;

  final String? answerQ1;
  final String? answerQ2;
  final String? email;
  final bool cameraFallback;
  final bool tourSkipped;

  /// S11 resolution — 'accepted' | 'declined' | null (unresolved).
  final String? notifyOutcome;

  int get totalXp => xpAwarded.values.fold(0, (a, b) => a + b);

  /// The first enum-ordered step not yet completed — the resume target.
  OnboardingStep? get earliestOwed {
    for (final s in OnboardingStep.values) {
      if (!completed.contains(s)) return s;
    }
    return null;
  }

  bool get allStepsComplete => earliestOwed == null;

  /// The flow may graduate the account. The only permitted gap: a skipped
  /// tour leaves the level-up celebration owed to the "Getting started"
  /// missions (Part D surfaces it outside the flow).
  bool get readyToGraduate =>
      allStepsComplete ||
      (tourSkipped && earliestOwed == OnboardingStep.levelUp);
}

/// The onboarding-v2 state machine — S0–S15, one [OnboardingStep] at a time.
///
/// Responsibilities: step advancement, XP awarding (idempotent via
/// [OnboardingV2Store]), resume-at-earliest-owed, the ob_* analytics
/// vocabulary, and the graduation write that mirrors the server
/// `onboardingComplete` flag. It never touches navigation — the host screen
/// listens to [readyToGraduate] and performs the route change.
class OnboardingFlowController extends StateNotifier<OnboardingFlowState> {
  OnboardingFlowController({
    required OnboardingV2Store store,
    required AnalyticsService analytics,
    required Future<void> Function() onGraduate,
    NuvoSounds sounds = const NoopNuvoSounds(),
  }) : _store = store,
       _analytics = analytics,
       _onGraduate = onGraduate,
       _sounds = sounds,
       super(
         const OnboardingFlowState(
           restored: false,
           step: OnboardingStep.splash,
           completed: {},
           xpAwarded: {},
           cameraFallback: false,
           tourSkipped: false,
         ),
       );

  final OnboardingV2Store _store;
  final AnalyticsService _analytics;
  final Future<void> Function() _onGraduate;
  final NuvoSounds _sounds;

  DateTime _enteredAt = DateTime.now();
  bool _restoring = false;

  /// Ids saved by older builds that were folded into another step. The
  /// old leaderboard intro maps onto the merged "how it works" screen;
  /// `introCamera` (and any other unknown id) is simply ignored.
  static const Map<String, OnboardingStep> _legacyStepIds = {
    'introBoard': OnboardingStep.introHow,
  };

  /// The step for a persisted id, or null when the id is unknown (a step
  /// removed in a later build) — never crashes on stale state.
  static OnboardingStep? _stepNamed(String name) =>
      OnboardingStep.values.asNameMap()[name] ?? _legacyStepIds[name];

  static Set<OnboardingStep> _stepSet(Iterable<String> names) => {
    for (final n in names) ?_stepNamed(n),
  };

  // ── Lifecycle ──────────────────────────────────────────────────────────

  /// Reads the store and lands on the earliest owed step. [accountEmail]
  /// binds the record to the signed-in account (adopts anonymous pre-auth
  /// progress, resets when a different person signs in).
  Future<void> restore({String? accountEmail}) async {
    if (state.restored || _restoring) return;
    _restoring = true;
    await _store.ensureLoaded();
    if (accountEmail != null) await _store.attachAccount(accountEmail);
    _emitState(advance: true);
    _restoring = false;
    _trackViewed(state.step);
  }

  /// Re-key progress to the account that just authenticated inside the
  /// flow (safe to call on every auth change — it's a no-op for the same
  /// email). When the store wiped a different account's record the flow
  /// restarts at splash.
  Future<void> attachAccount(String email) async {
    await _store.ensureLoaded();
    final wiped = await _store.attachAccount(email);
    if (wiped && state.restored) {
      _emitState(advance: true);
      _trackViewed(state.step);
    }
  }

  /// Demo replay / hard restart: wipes the record and starts at splash.
  Future<void> reset() async {
    await _store.reset();
    _emitState(advance: true);
    _trackViewed(state.step);
  }

  // ── Answers & flags (persisted; survive kill) ─────────────────────────

  Future<void> setAnswer(int question, String? value) =>
      _mutate(() => _store.setAnswer(question, value));

  Future<void> setEmail(String? email) => _mutate(() => _store.setEmail(email));

  Future<void> setCameraFallback(bool fallback) =>
      _mutate(() => _store.setCameraFallback(fallback));

  /// S11 outcome — 'accepted' | 'declined'.
  Future<void> setNotifyOutcome(String outcome) =>
      _mutate(() => _store.setNotifyOutcome(outcome));

  Future<void> _mutate(Future<void> Function() fn) async {
    await fn();
    _emitState();
  }

  // ── Advancement ────────────────────────────────────────────────────────

  /// Marks [step] complete, grants its XP (once — the store dedupes), and
  /// moves to the earliest still-owed step. Fires `ob_step_completed` for
  /// [step] and `ob_step_viewed` for whatever comes next.
  Future<int> completeStep(OnboardingStep step) async {
    await _store.ensureLoaded();
    final ms = _msOnStep();
    await _store.markStepCompleted(step.name);
    final awarded = await _awardFor(step);
    _analytics.obStepCompleted(
      stepIndex: step.index,
      stepName: step.analyticsName,
      msOnStep: ms,
    );
    if (awarded > 0) _sounds.xpChime();
    NuvoHaptics.medium();
    final prev = state.step;
    _emitState(advance: state.step == step);
    if (state.step != prev) _trackViewed(state.step);
    return awarded;
  }

  /// Jumps to [target] without completing anything (e.g. "Change" email on
  /// the code screen). The target becomes the viewed step.
  void goTo(OnboardingStep target) {
    _setStep(target);
  }

  /// Back square: the previous step in flow order, if any.
  void goBack() {
    final prev = state.step.previous;
    if (prev == null) return;
    _setStep(prev);
  }

  /// S1–S2 Skip — compresses the intros; lands on the sign-in step.
  Future<void> skipIntros() async {
    await _skip(
      from: state.step,
      skipped: const [OnboardingStep.introRace, OnboardingStep.introHow],
    );
  }

  /// S8 Skip — the questions resolve unanswered but still pay out
  /// (spec: "+10 XP after Q2 or skip").
  Future<void> skipQuestions() async {
    await _skip(
      from: state.step,
      skipped: const [OnboardingStep.questions1, OnboardingStep.questions2],
      award: OnboardingStep.questions2,
    );
  }

  /// "Skip tour" — the three stops resolve without XP (the missions stay
  /// earnable on Arena's "Getting started" row), and the level-up
  /// celebration is deferred until they're done.
  Future<void> skipTour() async {
    await _store.setTourSkipped();
    await _skip(
      from: state.step,
      skipped: const [
        OnboardingStep.tourCompete,
        OnboardingStep.tourCrew,
        OnboardingStep.tourProfile,
      ],
    );
  }

  Future<void> _skip({
    required OnboardingStep from,
    required List<OnboardingStep> skipped,
    OnboardingStep? award,
  }) async {
    await _store.ensureLoaded();
    for (final s in skipped) {
      await _store.markStepCompleted(s.name);
    }
    if (award != null) {
      final granted = await _awardFor(award);
      if (granted > 0) _sounds.xpChime();
    }
    _analytics.obSkipped(
      stepIndex: from.index,
      stepName: from.analyticsName,
      msOnStep: _msOnStep(),
    );
    final prev = state.step;
    _emitState(advance: true);
    if (state.step != prev) _trackViewed(state.step);
  }

  // ── S10 practice proof ─────────────────────────────────────────────────

  /// The real Submit proof sheet opened on the practice race.
  void proofStarted() {
    _analytics.obProofStarted(stepName: state.step.analyticsName);
  }

  /// The proof session resolved. [cameraFallback] is the D3 reduced-XP
  /// path (30 → 10); it persists so a kill mid-result can't renegotiate it.
  Future<int> proofCompleted({required bool cameraFallback}) async {
    await setCameraFallback(cameraFallback);
    _analytics.obProofCompleted(
      stepName: state.step.analyticsName,
      outcome: cameraFallback ? 'fallback_practice' : 'verified',
      msOnStep: _msOnStep(),
    );
    return completeStep(OnboardingStep.arenaTour);
  }

  // ── Tour stops (S12–14) ───────────────────────────────────────────────

  /// A tour stop rendered — `ob_tour_stop` with the stop's step identity.
  void tourStopViewed(OnboardingStep stop) {
    _analytics.obTourStop(stepIndex: stop.index, stepName: stop.analyticsName);
  }

  // ── S15 ────────────────────────────────────────────────────────────────

  /// The level-up moment actually played.
  void levelUpSeen() {
    _analytics.obLevelUpSeen(
      stepIndex: OnboardingStep.levelUp.index,
      stepName: OnboardingStep.levelUp.analyticsName,
      msOnStep: _msOnStep(),
    );
    NuvoHaptics.heavy();
    _sounds.fanfare();
  }

  /// The graduation write — the same `completeOnboarding()` old builds
  /// make; on success the last step closes and [readyToGraduate] reports
  /// true so the host routes out. Returns false when the write fails so the
  /// screen can retry inline (no dialog, spec §S15).
  Future<bool> graduate() async {
    try {
      await _onGraduate();
    } catch (_) {
      return false;
    }
    await _store.ensureLoaded();
    await _store.markStepCompleted(OnboardingStep.levelUp.name);
    _analytics.obStepCompleted(
      stepIndex: OnboardingStep.levelUp.index,
      stepName: OnboardingStep.levelUp.analyticsName,
      msOnStep: _msOnStep(),
    );
    _emitState();
    return true;
  }

  // ── Internals ──────────────────────────────────────────────────────────

  /// Grants [step]'s award honoring the fallback/outcome flags. Returns the
  /// amount actually written (0 when the step carries none or it was
  /// already granted).
  Future<int> _awardFor(OnboardingStep step) {
    final amount = OnboardingXp.xpFor(
      step,
      cameraFallback: _store.cameraFallback,
      notifyAccepted: _store.notifyOutcome == 'accepted',
    );
    return _store.awardXp(step.name, amount);
  }

  int _msOnStep() => DateTime.now().difference(_enteredAt).inMilliseconds;

  void _setStep(OnboardingStep step) {
    if (state.step == step) return;
    state = _copy(step: step);
    _trackViewed(step);
  }

  void _trackViewed(OnboardingStep step) {
    _enteredAt = DateTime.now();
    _analytics.obStepViewed(
      stepIndex: step.index,
      stepName: step.analyticsName,
    );
  }

  /// Republishes state from the store. [advance] moves the pointer to the
  /// earliest owed step — fired only by actions that resolve the current
  /// step (complete/skip/restore); flag mutations and back-navigation never
  /// move the pointer on their own.
  void _emitState({bool advance = false}) {
    final completed = _stepSet(_store.completedSteps);
    final awarded = <OnboardingStep, int>{};
    for (final e in _store.xpAwarded.entries) {
      final step = _stepNamed(e.key);
      if (step != null) awarded[step] = e.value;
    }
    final owed = advance
        ? _earliestOwed(completed) ?? OnboardingStep.levelUp
        : state.step;
    state = OnboardingFlowState(
      restored: true,
      step: owed,
      completed: completed,
      xpAwarded: awarded,
      answerQ1: _store.answerQ1,
      answerQ2: _store.answerQ2,
      email: _store.email,
      cameraFallback: _store.cameraFallback,
      tourSkipped: _store.tourSkipped,
      notifyOutcome: _store.notifyOutcome,
    );
  }

  static OnboardingStep? _earliestOwed(Set<OnboardingStep> completed) {
    for (final s in OnboardingStep.values) {
      if (!completed.contains(s)) return s;
    }
    return null;
  }

  OnboardingFlowState _copy({OnboardingStep? step}) => OnboardingFlowState(
    restored: state.restored,
    step: step ?? state.step,
    completed: state.completed,
    xpAwarded: state.xpAwarded,
    answerQ1: state.answerQ1,
    answerQ2: state.answerQ2,
    email: state.email,
    cameraFallback: state.cameraFallback,
    tourSkipped: state.tourSkipped,
    notifyOutcome: state.notifyOutcome,
  );
}

final onboardingFlowProvider =
    StateNotifierProvider<OnboardingFlowController, OnboardingFlowState>((ref) {
      return OnboardingFlowController(
        store: ref.watch(onboardingV2StoreProvider),
        analytics: ref.watch(analyticsProvider),
        sounds: ref.watch(nuvoSoundsProvider),
        // The same server write the v1 story makes — the flag's meaning for
        // old builds is untouched (build plan: additive grant is Part E's).
        onGraduate: () =>
            ref.read(authControllerProvider.notifier).completeOnboarding(),
      );
    });
