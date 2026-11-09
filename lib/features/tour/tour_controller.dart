import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/motion/motion.dart';
import '../onboarding/data/onboarding_v2_store.dart';
import '../onboarding/flow/onboarding_step.dart';
import 'tour_flags.dart';
import 'tour_script.dart';
import 'tour_store.dart';

/// A short-lived message the overlay shows ("+10 XP", "You passed ...").
@immutable
class TourChip {
  const TourChip(this.id, this.text);
  final int id;
  final String text;
}

@immutable
class TourState {
  const TourState({
    this.active = false,
    this.beat,
    this.practiceDone = false,
    this.chip,
    this.skippedBeats = const {},
    this.skipLog = const [],
    this.ready = false,
  });

  /// Store loaded and eligibility decided.
  final bool ready;

  /// The tour is running: fixtures are overlaid and the overlay may render.
  final bool active;

  /// The beat on stage: a [kTourSequence] id, `done`, or null (a gap between
  /// beats).
  final String? beat;

  /// The practice proof landed: the user's practice score is up.
  final bool practiceDone;

  final TourChip? chip;

  /// Beats skipped this run (target never mounted); they stay owed.
  final Set<String> skippedBeats;
  final List<String> skipLog;

  TourState copyWith({
    bool? active,
    bool? ready,
    Object? beat = _keep,
    bool? practiceDone,
    Object? chip = _keep,
    Set<String>? skippedBeats,
    List<String>? skipLog,
  }) => TourState(
    active: active ?? this.active,
    ready: ready ?? this.ready,
    beat: identical(beat, _keep) ? this.beat : beat as String?,
    practiceDone: practiceDone ?? this.practiceDone,
    chip: identical(chip, _keep) ? this.chip : chip as TourChip?,
    skippedBeats: skippedBeats ?? this.skippedBeats,
    skipLog: skipLog ?? this.skipLog,
  );

  static const Object _keep = Object();
}

const String kTourDoneBeat = 'done';

/// Drives the tour: which beat is on stage, what is owed after a kill, and
/// what each completion pays. Pure state + the store; geometry and drawing
/// belong to the overlay.
class TourController extends StateNotifier<TourState> {
  TourController(this._store, {this.gap = NuvoMotion.tourStopGap})
    : super(const TourState());

  final TourStore _store;
  final Duration gap;
  Timer? _timer;
  int _chipId = 0;
  bool _closedThisRun = false;

  TourStore get store => _store;

  /// First beat of the sequence that is neither done nor skipped this run.
  String? firstOwed() {
    for (final id in kTourSequence) {
      if (!_store.isCompleted(id) && !state.skippedBeats.contains(id)) {
        return id;
      }
    }
    return null;
  }

  /// Called when auth / onboarding state resolves. Starts the tour for an
  /// account that just graduated v2 unless it is finished, skipped or closed.
  Future<void> sync({required String? email, required bool graduated}) async {
    if (email == null) {
      _timer?.cancel();
      if (state.active || state.ready) state = const TourState();
      return;
    }
    await _store.ensureLoaded();
    if (!mounted) return;
    final wiped = await _store.attachAccount(email);
    if (!mounted) return;
    if (wiped) state = const TourState();
    state = state.copyWith(
      ready: true,
      practiceDone: _store.isCompleted('arenaProof'),
    );
    if (state.active || _closedThisRun) return;
    if (!graduated || _store.finished || _store.skipped) return;
    start();
  }

  void start() {
    final owed = firstOwed();
    if (owed == null) {
      state = state.copyWith(
        active: true,
        beat: kTourDoneBeat,
        practiceDone: _store.isCompleted('arenaProof'),
      );
      return;
    }
    state = state.copyWith(
      active: true,
      beat: owed,
      practiceDone: _store.isCompleted('arenaProof'),
    );
  }

  /// Getting started row: pick the tour back up at the earliest owed beat.
  Future<void> resume() async {
    await _store.setSkipped(false);
    _closedThisRun = false;
    state = state.copyWith(skippedBeats: const {});
    start();
  }

  /// Settings > Help: walk every stop again. Paid XP is never paid twice.
  Future<void> replay() async {
    await _store.replay();
    _closedThisRun = false;
    state = state.copyWith(skippedBeats: const {}, practiceDone: false);
    start();
  }

  /// Skip tour: fixtures go away, the Arena keeps a Getting started row.
  Future<void> skip() async {
    _timer?.cancel();
    await _store.setSkipped(true);
    if (!mounted) return;
    state = state.copyWith(active: false, beat: null, chip: null);
  }

  /// Close: stops for this run only (nothing recorded); the tour resumes at
  /// the earliest owed stop next launch.
  void close() {
    _timer?.cancel();
    _closedThisRun = true;
    state = state.copyWith(active: false, beat: null, chip: null);
  }

  /// The user finished the closing beat.
  Future<void> finish() async {
    _timer?.cancel();
    await _store.setFinished(true);
    if (!mounted) return;
    state = state.copyWith(active: false, beat: null);
  }

  /// A beat is done. Pays [xp] once (the store is the idempotency record),
  /// shows the chip, and brings the next beat on after a short gap.
  Future<int> completeBeat(
    String id, {
    int? xp,
    String? chipText,
    Duration? next,
  }) async {
    if (!state.active) return 0;
    final stop = tourStopById(id);
    final pay = xp ?? stop?.xp ?? (id == kTourNotifyId ? kTourNotifyXp : 0);
    final awarded = await _store.complete(id, xp: pay);
    if (!mounted) return awarded;
    final text = chipText ?? (awarded > 0 ? '+$awarded XP' : null);
    state = state.copyWith(
      beat: null,
      practiceDone: id == 'arenaProof' ? true : state.practiceDone,
      chip: text == null ? null : TourChip(++_chipId, text),
    );
    _timer?.cancel();
    _timer = Timer(next ?? gap, _advance);
    return awarded;
  }

  void _advance() {
    if (!mounted || !state.active) return;
    final owed = firstOwed();
    state = state.copyWith(beat: owed ?? kTourDoneBeat);
  }

  /// First practice proof landed. [fallback] = the camera was skipped, so it
  /// pays the Practice amount.
  Future<int> practiceProofDone({required bool fallback}) async {
    if (fallback) await _store.setCameraFallback(true);
    final stop = tourStopById('arenaProof')!;
    return completeBeat(
      'arenaProof',
      xp: fallback ? stop.fallbackXp : stop.xp,
      chipText: 'You passed Nuvo Crew',
      next: NuvoMotion.tourNudgeDelay,
    );
  }

  /// Join tapped on the practice race.
  Future<int> practiceJoined() => completeBeat('compete');

  Future<int> notifyResolved({required bool accepted}) async {
    await _store.setNotifyOutcome(accepted ? 'accepted' : 'declined');
    return completeBeat(kTourNotifyId, xp: accepted ? kTourNotifyXp : 0);
  }

  /// The target never mounted in time: skip it, log it, never block. The
  /// beat stays owed for the next launch.
  void targetMissing(String id) {
    if (state.beat != id) return;
    final msg = 'tour: target for "$id" not found, skipped';
    debugPrint(msg);
    state = state.copyWith(
      skippedBeats: {...state.skippedBeats, id},
      skipLog: [...state.skipLog, msg],
      beat: firstOwedExcluding(id) ?? kTourDoneBeat,
    );
  }

  String? firstOwedExcluding(String id) {
    for (final s in kTourSequence) {
      if (s == id) continue;
      if (!_store.isCompleted(s) && !state.skippedBeats.contains(s)) return s;
    }
    return null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final tourControllerProvider = StateNotifierProvider<TourController, TourState>(
  (ref) {
    return TourController(ref.watch(tourStoreProvider));
  },
);

/// True only while the tour is running AND the feature is on. Everything
/// that overlays or decorates a real screen keys off this.
final tourActiveProvider = Provider<bool>((ref) {
  if (!ref.watch(tourFeatureEnabledProvider)) return false;
  return ref.watch(tourControllerProvider.select((s) => s.active));
});

/// "You graduated onboarding v2": the account's onboarding record is bound
/// to this email and carries the flow's last pre-tour step.
bool tourGraduatedV2(OnboardingV2Store v2, String? email) {
  if (email == null) return false;
  final mine = v2.accountEmail == email.trim().toLowerCase();
  return mine && v2.isStepCompleted(OnboardingStep.firstRaceReady.name);
}

/// Getting started: the five missions and which are done.
final tourMissionsProvider = Provider<List<({String id, bool done})>>((ref) {
  ref.watch(tourControllerProvider);
  final store = ref.watch(tourStoreProvider);
  return [
    for (final id in kTourMissionIds) (id: id, done: store.isCompleted(id)),
  ];
});

/// Whether the Arena shows the slim Getting started row.
final tourGettingStartedVisibleProvider = Provider<bool>((ref) {
  if (!ref.watch(tourFeatureEnabledProvider)) return false;
  final s = ref.watch(tourControllerProvider);
  if (s.active) return false;
  final store = ref.watch(tourStoreProvider);
  if (!store.skipped || store.finished) return false;
  return kTourMissionIds.any((id) => !store.isCompleted(id));
});
