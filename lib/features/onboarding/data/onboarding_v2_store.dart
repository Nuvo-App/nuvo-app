import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Install- and account-scoped onboarding-v2 persistence.
///
/// Same storage approach as [FirstUseStore]: one small JSON file in the app
/// documents directory, loaded once, in-memory state authoritative for the
/// session; a corrupt or unreadable file degrades to defaults (a fresh flow)
/// instead of blocking launch.
///
/// What persists and why (build plan: "State persists locally ... resume
/// after kill at earliest owed step"):
/// - [completedSteps] — the set of finished steps. The resume target is
///   derived, not stored: the first enum-ordered step not in this set is the
///   earliest owed step, so a kill+relaunch can never skip or replay one.
/// - [xpAwarded] — XP granted per step. The map is the idempotency record:
///   a step's award is written once and never re-applied on resume.
/// - [answerQ1]/[answerQ2] — the starter-question choices (they drive the
///   seeded race name and tour share step).
/// - [email] — the address typed at S5 so a resume lands on the code screen
///   knowing who the code went to.
/// - [cameraFallback] — S10's reduced-XP path flag (30 → 10).
/// - [tourSkipped] — the S12–14 skip leaves "Getting started" missions on
///   Arena; persisted so the missions row can outlive the flow.
/// - [notifyOutcome] — S11's resolution ('accepted' | 'declined').
/// - [accountEmail] — the normalized email of the account this progress
///   belongs to. Written when auth resolves mid-flow (pre-auth progress is
///   adopted by the account that lands). A different account signing in on
///   the same install resets the record — progress never leaks between
///   people.
///
/// Deliberately separate from `AuthUser.onboardingComplete` (the server
/// flag): this file only schedules WHICH step renders next; the server flag
/// still decides whether onboarding is owed at all, and the flow's final
/// `completeOnboarding()` call is the same write old builds make.
class OnboardingV2Store {
  OnboardingV2Store() : _memoryOnly = false;

  /// In-memory store for tests — never touches disk.
  OnboardingV2Store.memory() : _memoryOnly = true;

  /// In-memory store preloaded from [snapshot] ([toJson] output) — the way
  /// tests simulate kill + relaunch without mocking path_provider.
  factory OnboardingV2Store.fromSnapshot(Map<String, Object?> snapshot) {
    final store = OnboardingV2Store.memory();
    store._applyJson(snapshot);
    store._loaded = true;
    return store;
  }

  final bool _memoryOnly;
  bool _loaded = false;

  String? _accountEmail;
  final Set<String> _completed = {};
  final Map<String, int> _xpAwarded = {};
  String? _answerQ1;
  String? _answerQ2;
  String? _email;
  bool _cameraFallback = false;
  bool _tourSkipped = false;
  String? _notifyOutcome;

  String? get accountEmail => _accountEmail;
  Set<String> get completedSteps => Set.unmodifiable(_completed);
  Map<String, int> get xpAwarded => Map.unmodifiable(_xpAwarded);
  String? get answerQ1 => _answerQ1;
  String? get answerQ2 => _answerQ2;
  String? get email => _email;
  bool get cameraFallback => _cameraFallback;
  bool get tourSkipped => _tourSkipped;
  String? get notifyOutcome => _notifyOutcome;

  bool isStepCompleted(String stepName) => _completed.contains(stepName);

  int get totalXp => _xpAwarded.values.fold(0, (a, b) => a + b);

  /// Loads persisted state once; safe to call repeatedly.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    if (_memoryOnly) return;
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return;
      _applyJson(decoded);
    } catch (_) {
      // Swallow — see class doc. Defaults = a fresh flow, which is safe.
    }
  }

  void _applyJson(Map<String, Object?> decoded) {
    _accountEmail = decoded['accountEmail'] as String?;
    final completed = decoded['completed'];
    if (completed is List) {
      _completed
        ..clear()
        ..addAll(completed.whereType<String>());
    }
    final xp = decoded['xpAwarded'];
    if (xp is Map) {
      _xpAwarded
        ..clear()
        ..addAll({
          for (final e in xp.entries)
            if (e.key is String && e.value is num)
              e.key as String: (e.value as num).toInt(),
        });
    }
    _answerQ1 = decoded['answerQ1'] as String?;
    _answerQ2 = decoded['answerQ2'] as String?;
    _email = decoded['email'] as String?;
    _cameraFallback = decoded['cameraFallback'] == true;
    _tourSkipped = decoded['tourSkipped'] == true;
    _notifyOutcome = decoded['notifyOutcome'] as String?;
  }

  /// Serializable snapshot — the test seam for kill + relaunch.
  Map<String, Object?> toJson() => {
    'version': 1,
    'accountEmail': _accountEmail,
    'completed': _completed.toList()..sort(),
    'xpAwarded': _xpAwarded,
    'answerQ1': _answerQ1,
    'answerQ2': _answerQ2,
    'email': _email,
    'cameraFallback': _cameraFallback,
    'tourSkipped': _tourSkipped,
    'notifyOutcome': _notifyOutcome,
  };

  /// Records the XP granted for [stepName]. Idempotent — an existing entry
  /// is never overwritten, so a relaunched step cannot double-award.
  /// Returns the amount actually recorded (0 when already awarded).
  Future<int> awardXp(String stepName, int amount) async {
    if (_xpAwarded.containsKey(stepName) || amount <= 0) return 0;
    _xpAwarded[stepName] = amount;
    await _persist();
    return amount;
  }

  Future<void> markStepCompleted(String stepName) async {
    if (!_completed.add(stepName)) return;
    await _persist();
  }

  Future<void> setAnswer(int question, String? value) async {
    if (question == 1) {
      _answerQ1 = value;
    } else {
      _answerQ2 = value;
    }
    await _persist();
  }

  Future<void> setEmail(String? value) async {
    _email = value;
    await _persist();
  }

  Future<void> setCameraFallback(bool value) async {
    if (_cameraFallback == value) return;
    _cameraFallback = value;
    await _persist();
  }

  Future<void> setTourSkipped() async {
    if (_tourSkipped) return;
    _tourSkipped = true;
    await _persist();
  }

  Future<void> setNotifyOutcome(String outcome) async {
    _notifyOutcome = outcome;
    await _persist();
  }

  /// Binds the stored progress to [email] once auth resolves mid-flow.
  ///
  /// - No account recorded yet → the pre-auth progress is adopted by this
  ///   account (normal path: intros → sign-in → the rest of the flow).
  /// - Same account → no-op.
  /// - A DIFFERENT account → the record is wiped and re-keyed: a person's
  ///   half-finished flow never bleeds into someone else's sign-in on a
  ///   shared device.
  ///
  /// Returns true when a different account's record was wiped.
  Future<bool> attachAccount(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (_accountEmail == normalized) return false;
    if (_accountEmail != null) {
      _completed.clear();
      _xpAwarded.clear();
      _answerQ1 = null;
      _answerQ2 = null;
      _email = null;
      _cameraFallback = false;
      _tourSkipped = false;
      _notifyOutcome = null;
    }
    _accountEmail = normalized;
    await _persist();
    return true;
  }

  /// Clears the whole record — used by demo replay and by tests.
  Future<void> reset() async {
    _accountEmail = null;
    _completed.clear();
    _xpAwarded.clear();
    _answerQ1 = null;
    _answerQ2 = null;
    _email = null;
    _cameraFallback = false;
    _tourSkipped = false;
    _notifyOutcome = null;
    await _persist();
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/nuvo_onboarding_v2.json');
  }

  Future<void> _persist() async {
    if (_memoryOnly) return;
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(toJson()));
    } catch (_) {
      // Persistence failure is not worth a crash — progress simply reverts.
    }
  }
}

final onboardingV2StoreProvider = Provider<OnboardingV2Store>(
  (ref) => OnboardingV2Store(),
);
