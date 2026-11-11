import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// "The intro has been shown on this device." The onboarding intro opens
/// automatically ONLY on the very first open; afterwards a signed-out user
/// goes straight to the login. A one-line local file, never sent anywhere.
///
/// R1 (docs/statements/demo-account.md): the demo-account marker's wipe
/// deletes this file too, so a cold open after testing@getnuvo.net is a
/// clean first run again. Keep [fileName] in sync with
/// `FileDemoAccountMarker.wipeLocalState`.
abstract class FirstRunFlag {
  static const String fileName = 'nuvo_first_run_done';

  Future<bool> isDone();
  Future<void> markDone();
}

class FileFirstRunFlag implements FirstRunFlag {
  Future<File> _file() async => File(
    '${(await getApplicationDocumentsDirectory()).path}/${FirstRunFlag.fileName}',
  );

  @override
  Future<bool> isDone() async {
    try {
      return await (await _file()).exists();
    } catch (e) {
      debugPrint('[FirstRun] read failed (${e.runtimeType})');
      return false;
    }
  }

  @override
  Future<void> markDone() async {
    try {
      await (await _file()).writeAsString('1');
    } catch (e) {
      debugPrint('[FirstRun] write failed (${e.runtimeType})');
    }
  }
}

class MemoryFirstRunFlag implements FirstRunFlag {
  MemoryFirstRunFlag({this.done = false});
  bool done;

  @override
  Future<bool> isDone() async => done;

  @override
  Future<void> markDone() async => done = true;
}

final firstRunFlagProvider = Provider<FirstRunFlag>((_) => FileFirstRunFlag());
