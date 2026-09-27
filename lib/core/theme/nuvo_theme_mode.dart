import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Install-scoped light/dark preference.
///
/// Nuvo ships two explicit modes — no system/auto. The stored choice is read
/// once at launch (main() awaits [ensureNuvoThemeModeLoaded] before runApp) so
/// the first frame already paints in the right brightness. A corrupt or
/// unreadable file falls back to light, matching the historical default.
class NuvoThemeModeStore {
  NuvoThemeModeStore() : _memoryOnly = false;

  /// In-memory store for tests — never touches disk.
  NuvoThemeModeStore.memory() : _memoryOnly = true;

  final bool _memoryOnly;
  bool _loaded = false;
  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    if (_memoryOnly) return;
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic> && decoded['mode'] == 'dark') {
        _mode = ThemeMode.dark;
      }
    } catch (_) {
      // Swallow — see class doc; falling back to light is always safe.
    }
  }

  Future<void> persist() async {
    if (_memoryOnly) return;
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode({'mode': _mode == ThemeMode.dark ? 'dark' : 'light'}),
      );
    } catch (_) {
      // Persistence failure is not worth a crash — the choice just reverts.
    }
  }

  void set(ThemeMode mode) => _mode = mode;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/nuvo_theme_mode.json');
  }
}

final _themeModeStore = NuvoThemeModeStore();

/// Called from main() before runApp so the router/first frame see the
/// persisted brightness instead of flashing light on a dark preference.
Future<void> ensureNuvoThemeModeLoaded() => _themeModeStore.ensureLoaded();

/// Live mode exposed to MaterialApp. The toggle flips this; the store write
/// is fire-and-forget — the in-memory state is authoritative for the session.
class NuvoThemeModeController extends StateNotifier<ThemeMode> {
  NuvoThemeModeController([NuvoThemeModeStore? store])
    : _store = store ?? _themeModeStore,
      super((store ?? _themeModeStore).mode);

  final NuvoThemeModeStore _store;

  Future<void> set(ThemeMode mode) {
    state = mode;
    _store.set(mode);
    return _store.persist();
  }

  Future<void> toggle() =>
      set(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
}

final nuvoThemeModeProvider =
    StateNotifierProvider<NuvoThemeModeController, ThemeMode>(
      (ref) => NuvoThemeModeController(),
    );
