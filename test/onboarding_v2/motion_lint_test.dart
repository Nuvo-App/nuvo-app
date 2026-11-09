// Motion lint — every duration/curve in the v2 onboarding code must
// come from lib/core/motion (NuvoMotion), never a hard-coded literal. The
// allow-list is intentionally empty: new animation values go into
// NuvoMotion as named tokens. The legacy v1 subtree (presentation/) is
// untouched code predating the rule and is out of scope.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final banned = [
    RegExp(r'Duration\(\s*(milliseconds|microseconds|seconds|minutes)\s*:'),
    RegExp(r'Curves\.'),
  ];

  test('no hard-coded Duration/Curves under lib/features/onboarding', () {
    final dir = Directory('lib/features/onboarding');
    final violations = <String>[];
    for (final file in dir.listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      // v1 legacy screens — no-touch code the rule doesn't apply to.
      if (file.path.contains('/presentation/')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final re in banned) {
          if (re.hasMatch(lines[i])) {
            violations.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
