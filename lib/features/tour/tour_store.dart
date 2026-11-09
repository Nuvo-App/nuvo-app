import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Local persistence for the guided tour: one small JSON file, loaded once,
/// in-memory state authoritative. A corrupt file degrades to a fresh tour.
///
/// - [completed] — beats finished. The resume target is derived (the first
///   beat of the script's sequence not in this set), never stored, so a kill
///   and relaunch can neither skip nor replay a beat.
/// - [xpAwarded] — XP per beat, written once; a replayed beat never pays
///   again. (Tour XP is the client's running count toward the onboarding
///   level-up; nothing here is sent to the server.)
/// - [skipped] — the user skipped; the Arena shows "Getting started".
/// - [finished] — every beat done; the tour never auto-starts again.
/// - [accountEmail] — progress belongs to one account on a shared device.
class TourStore {
  TourStore() : _memoryOnly = false;
  TourStore.memory() : _memoryOnly = true;

  factory TourStore.fromSnapshot(Map<String, Object?> snapshot) {
    final store = TourStore.memory();
    store._apply(snapshot);
    store._loaded = true;
    return store;
  }

  final bool _memoryOnly;
  bool _loaded = false;

  String? _accountEmail;
  final Set<String> _completed = {};
  final Map<String, int> _xp = {};
  bool _skipped = false;
  bool _finished = false;
  bool _cameraFallback = false;
  String? _notifyOutcome;

  String? get accountEmail => _accountEmail;
  Set<String> get completed => Set.unmodifiable(_completed);
  Map<String, int> get xpAwarded => Map.unmodifiable(_xp);
  bool get skipped => _skipped;
  bool get finished => _finished;
  bool get cameraFallback => _cameraFallback;
  String? get notifyOutcome => _notifyOutcome;
  int get totalXp => _xp.values.fold(0, (a, b) => a + b);
  bool isCompleted(String id) => _completed.contains(id);

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    if (_memoryOnly) return;
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) _apply(decoded);
    } catch (_) {
      // Fresh tour is the safe default.
    }
  }

  void _apply(Map<String, Object?> j) {
    _accountEmail = j['accountEmail'] as String?;
    final c = j['completed'];
    _completed
      ..clear()
      ..addAll(c is List ? c.whereType<String>() : const <String>[]);
    final xp = j['xpAwarded'];
    _xp
      ..clear()
      ..addAll({
        if (xp is Map)
          for (final e in xp.entries)
            if (e.key is String && e.value is num)
              e.key as String: (e.value as num).toInt(),
      });
    _skipped = j['skipped'] == true;
    _finished = j['finished'] == true;
    _cameraFallback = j['cameraFallback'] == true;
    _notifyOutcome = j['notifyOutcome'] as String?;
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'accountEmail': _accountEmail,
    'completed': _completed.toList()..sort(),
    'xpAwarded': _xp,
    'skipped': _skipped,
    'finished': _finished,
    'cameraFallback': _cameraFallback,
    'notifyOutcome': _notifyOutcome,
  };

  /// Marks [id] done and records [xp] once. Returns the XP actually newly
  /// awarded (0 when this beat already paid).
  Future<int> complete(String id, {int xp = 0}) async {
    var awarded = 0;
    if (xp > 0 && !_xp.containsKey(id)) {
      _xp[id] = xp;
      awarded = xp;
    }
    _completed.add(id);
    await _persist();
    return awarded;
  }

  Future<void> setSkipped(bool value) async {
    _skipped = value;
    await _persist();
  }

  Future<void> setFinished(bool value) async {
    _finished = value;
    await _persist();
  }

  Future<void> setCameraFallback(bool value) async {
    _cameraFallback = value;
    await _persist();
  }

  Future<void> setNotifyOutcome(String outcome) async {
    _notifyOutcome = outcome;
    await _persist();
  }

  /// Binds progress to [email]; a different account wipes the record.
  Future<bool> attachAccount(String email) async {
    final n = email.trim().toLowerCase();
    if (n.isEmpty || _accountEmail == n) return false;
    final wipe = _accountEmail != null;
    if (wipe) _clear();
    _accountEmail = n;
    await _persist();
    return wipe;
  }

  /// Replay: walks the stops again. Paid XP stays recorded, so a replay
  /// can never award a beat twice.
  Future<void> replay() async {
    _completed.clear();
    _skipped = false;
    _finished = false;
    await _persist();
  }

  void _clear() {
    _completed.clear();
    _xp.clear();
    _skipped = false;
    _finished = false;
    _cameraFallback = false;
    _notifyOutcome = null;
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/nuvo_tour.json');
  }

  Future<void> _persist() async {
    if (_memoryOnly) return;
    try {
      await (await _file()).writeAsString(jsonEncode(toJson()));
    } catch (_) {
      // Persistence failure is not worth a crash.
    }
  }
}

final tourStoreProvider = Provider<TourStore>((ref) => TourStore());
