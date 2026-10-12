import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/domain/motion_activity_catalog.dart';

/// Guard against shipping a build where a motion can't be tuned over the air.
/// Every compiled motion must either have a published spec file in
/// server/worker/motion_specs, or be listed here with the reason it doesn't.
const _noSpecYet = <String, String>{};

void main() {
  test(
    'every compiled motion is tunable over the air or explicitly excused',
    () {
      final specs = Directory('server/worker/motion_specs')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .map((f) => f.uri.pathSegments.last.replaceAll('.json', ''))
          .toSet();
      final missing = <String>[];
      for (final type in supportedMotionActivityTypes) {
        final id = type.backendValue;
        if (type == MotionActivityType.remote) continue;
        if (specs.contains(id) || _noSpecYet.containsKey(id)) continue;
        missing.add(id);
      }
      expect(missing, isEmpty, reason: 'no OTA spec for: $missing');
    },
  );

  test('every native_tuned spec file lists exactly its tunables', () {
    for (final id in kNativeTunables.keys) {
      final spec =
          jsonDecode(
                File('server/worker/motion_specs/$id.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(spec['engineType'], 'native_tuned_v1', reason: id);
    }
  });
}
