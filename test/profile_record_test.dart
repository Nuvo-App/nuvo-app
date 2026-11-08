import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/profile/data/progression_models.dart';

const _record = {'active': 7, 'finished': 12, 'wins': 9, 'winRatePercent': 75};

NuvoProgression _prog({Map<String, dynamic>? record}) =>
    NuvoProgression.fromBody({
      'progression': {'level': 3},
      'record': ?record,
    });

void main() {
  group('ProfileRecord parsing', () {
    test('full', () {
      final p = _prog(record: _record);
      expect(p.record!.active, 7);
      expect(p.record!.finished, 12);
      expect(p.record!.wins, 9);
      expect(p.record!.winRatePercent, 75);
    });
    test('missing record is null (older server)', () {
      expect(_prog().record, isNull);
    });
    test('null winRatePercent', () {
      final r = ProfileRecord.fromJson({
        'active': 1,
        'finished': 0,
        'wins': 0,
        'winRatePercent': null,
      });
      expect(r.winRatePercent, isNull);
      expect(r.finished, 0);
    });
  });
}
