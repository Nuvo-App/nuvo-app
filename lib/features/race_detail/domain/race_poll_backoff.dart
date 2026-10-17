import '../../races/data/race_models.dart';

/// Poll interval policy for the race detail page: 5 s, easing to 15 s after
/// three consecutive refreshes that returned nothing new. Any change or
/// [reset] drops it back to 5 s.
class RacePollBackoff {
  RacePollBackoff({
    this.fast = const Duration(seconds: 5),
    this.slow = const Duration(seconds: 15),
    this.unchangedBeforeSlow = 3,
  });

  final Duration fast;
  final Duration slow;
  final int unchangedBeforeSlow;

  int _unchanged = 0;

  Duration get current => _unchanged >= unchangedBeforeSlow ? slow : fast;

  void recordResult({required bool changed}) {
    if (changed) {
      _unchanged = 0;
    } else if (_unchanged < unchangedBeforeSlow) {
      _unchanged++;
    }
  }

  void reset() => _unchanged = 0;
}

/// Cheap signature of what the race detail page shows. Two refreshes with the
/// same signature count as "no change".
String raceSignature(Race race) {
  final b = StringBuffer()
    ..write(race.status)
    ..write('|')
    ..write(race.updatedAt)
    ..write('|')
    ..write(race.winnerUserId ?? '')
    ..write('|')
    ..write(race.recentProofs.length)
    ..write('|')
    ..write(race.recentProofs.isEmpty ? '' : race.recentProofs.first.id);
  for (final p in race.participants) {
    b
      ..write('|')
      ..write(p.userId)
      ..write(':')
      ..write(p.progressValue)
      ..write(':')
      ..write(p.rank ?? '');
  }
  return b.toString();
}
