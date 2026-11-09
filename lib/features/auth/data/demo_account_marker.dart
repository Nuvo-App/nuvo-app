// R1 (docs/statements/demo-account.md): remembers that the LAST account
// signed in on this device was the store-review/demo account, so the next
// cold start can open completely clean, as a first-ever install.
//
// Local-only: a one-line file in app documents. Nothing here is ever sent
// anywhere.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

abstract class DemoAccountMarker {
  Future<bool> isSet();
  Future<void> set(bool value);

  /// Deletes the local onboarding/first-use state so the next launch behaves
  /// like a first-ever install. Session tokens are cleared by the caller.
  Future<void> wipeLocalState();
}

/// File-backed marker (production).
class FileDemoAccountMarker implements DemoAccountMarker {
  Future<Directory> _dir() => getApplicationDocumentsDirectory();

  Future<File> _file() async =>
      File('${(await _dir()).path}/nuvo_demo_account_marker');

  @override
  Future<bool> isSet() async {
    try {
      return await (await _file()).exists();
    } catch (e) {
      debugPrint('[DemoMarker] read failed (${e.runtimeType})');
      return false;
    }
  }

  @override
  Future<void> set(bool value) async {
    try {
      final f = await _file();
      if (value) {
        await f.writeAsString('1');
      } else if (await f.exists()) {
        await f.delete();
      }
    } catch (e) {
      debugPrint('[DemoMarker] write failed (${e.runtimeType})');
    }
  }

  @override
  Future<void> wipeLocalState() async {
    try {
      final dir = await _dir();
      // The onboarding-v2 progress file and the first-use education flags.
      for (final name in const [
        'nuvo_onboarding_v2.json',
        'nuvo_first_use.json',
      ]) {
        final f = File('${dir.path}/$name');
        if (await f.exists()) await f.delete();
      }
    } catch (e) {
      debugPrint('[DemoMarker] wipe failed (${e.runtimeType})');
    }
  }
}

/// In-memory marker for tests.
class MemoryDemoAccountMarker implements DemoAccountMarker {
  MemoryDemoAccountMarker({this.value = false});
  bool value;
  int wipes = 0;

  @override
  Future<bool> isSet() async => value;

  @override
  Future<void> set(bool v) async => value = v;

  @override
  Future<void> wipeLocalState() async => wipes++;
}
