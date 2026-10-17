// Entry point for tool/motion-replay.sh — `flutter test` is the runner that can
// load the app's Dart code (the validators sit behind Flutter-only imports).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'motion_replay.dart' as replay;

void main() {
  test('motion replay', () {
    final args = (jsonDecode(Platform.environment['MOTION_REPLAY_ARGS'] ?? '[]')
            as List)
        .cast<String>();
    replay.main(args);
  });
}
