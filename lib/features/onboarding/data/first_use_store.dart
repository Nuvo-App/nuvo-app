import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Install- and account-scoped first-use persistence.
///
/// Two independent flags live here:
///
/// - introSeen (install-scoped): legacy flag from the retired pre-auth
///   cinematic. The Nuvo story now runs post-auth and is gated by the
///   server-side onboardingComplete flag instead — introSeen no longer
///   routes anywhere, it is kept only so persisted files decode cleanly.
/// - guide completion (account-scoped): the post-auth first-race coach marks
///   itself done per canonical account email, so a finished guide never
///   re-arms for that account while another account on the same install can
///   still receive its own guide.
///
/// - notificationPromptOwed (install-scoped): set the moment the Nuvo
///   story completes, cleared when the notification education step
///   resolves (enable, maybe-later, or auto-skip). A kill on that screen
///   resumes at it rather than silently skipping the permission moment.
/// - cameraPrimerSeen (install-scoped): the one-time "why the camera"
///   explanation shown before the first AI Motion launch. Contextual
///   first-use education, not a permission state — the OS dialog itself
///   is what the camera plugin fires.
///
/// These are deliberately separate from [AuthUser.onboardingComplete] (the
/// server-side first-use completion written by the Nuvo onboarding story's
/// final CTA) — the flags model different experiences.
class FirstUseStore {
  FirstUseStore() : _memoryOnly = false;

  /// In-memory store for tests — never touches disk.
  FirstUseStore.memory() : _memoryOnly = true;

  final bool _memoryOnly;
  bool _loaded = false;
  bool _introSeen = false;
  bool _notificationPromptOwed = false;
  bool _cameraPrimerSeen = false;
  final Set<String> _guideDone = {};

  bool get introSeen => _introSeen;

  bool get isNotificationPromptOwed => _notificationPromptOwed;

  bool get isCameraPrimerSeen => _cameraPrimerSeen;

  bool isGuideDone(String accountKey) =>
      _guideDone.contains(_normalize(accountKey));

  /// Loads persisted state once; safe to call repeatedly. A corrupt or
  /// unreadable store must never block launch — defaults replay the intro,
  /// which is always safe.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    if (_memoryOnly) return;
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return;
      _introSeen = decoded['introSeen'] == true;
      _notificationPromptOwed = decoded['notificationPromptOwed'] == true;
      _cameraPrimerSeen = decoded['cameraPrimerSeen'] == true;
      final done = decoded['guideDone'];
      if (done is List) {
        _guideDone.addAll(done.whereType<String>().map(_normalize));
      }
    } catch (_) {
      // Swallow — see class doc.
    }
  }

  Future<void> markIntroSeen() async {
    _introSeen = true;
    await _persist();
  }

  Future<void> markGuideDone(String accountKey) async {
    _guideDone.add(_normalize(accountKey));
    await _persist();
  }

  Future<void> markNotificationPromptOwed() async {
    _notificationPromptOwed = true;
    await _persist();
  }

  Future<void> clearNotificationPromptOwed() async {
    _notificationPromptOwed = false;
    await _persist();
  }

  Future<void> markCameraPrimerSeen() async {
    _cameraPrimerSeen = true;
    await _persist();
  }

  /// Store-review demo reset — clears every Nuvo-owned first-use flag that
  /// belongs to [accountKey] so a cold launch replays the experience as a
  /// controlled fresh install: the story, the notification education step,
  /// the camera primer, and this account's first-race guide completion.
  ///
  /// Deliberately NOT touched: OS permission state (cannot be reset), the
  /// session itself, and other accounts' guide completions recorded on this
  /// install.
  Future<void> resetDemoExperience(String accountKey) async {
    _introSeen = false;
    _notificationPromptOwed = false;
    _cameraPrimerSeen = false;
    _guideDone.remove(_normalize(accountKey));
    await _persist();
  }

  static String _normalize(String accountKey) => accountKey.trim().toLowerCase();

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/nuvo_first_use.json');
  }

  Future<void> _persist() async {
    if (_memoryOnly) return;
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode({
          'introSeen': _introSeen,
          'notificationPromptOwed': _notificationPromptOwed,
          'cameraPrimerSeen': _cameraPrimerSeen,
          'guideDone': _guideDone.toList()..sort(),
        }),
      );
    } catch (_) {
      // Persistence failure is not worth a crash — the flag simply reverts.
    }
  }
}

final firstUseStoreProvider = Provider<FirstUseStore>(
  (ref) => FirstUseStore(),
);
