import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/tour/tour_script.dart';

void main() {
  test('stop ids are unique and the sequence covers every stop + notify', () {
    final ids = kTourScript.map((s) => s.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(kTourSequence.toSet(), {...ids, kTourNotifyId});
    expect(kTourSequence.first, 'arenaRace');
    expect(kTourMissionIds.every(kTourSequence.contains), isTrue);
    expect(kTourMissionIds.length, 5);
  });

  test('copy: short, no exclamation marks, at most 3 lines of text', () {
    final all = [
      for (final s in kTourScript) ...[s.copy, ?s.dockCopy, s.mission],
      kTourNotifyTitle,
      kTourLesson,
      kTourDone,
      kTourPracticeCamera,
    ];
    for (final t in all) {
      expect(t.contains('!'), isFalse, reason: t);
      expect(t.length <= 90, isTrue, reason: '$t is too long for 3 lines');
    }
  });

  test('the three counted stops are Compete, Crew, Profile (N of 3)', () {
    final counted = kTourScript.where((s) => s.counter != null).toList();
    expect(counted.map((s) => s.id), ['compete', 'crew', 'profile']);
    expect(counted.map((s) => s.counter), [1, 2, 3]);
    expect(tourCounterLabel(2), 'Tour 2 of 3');
    expect(counted.map((s) => s.route), ['/compete', '/pass', '/profile']);
  });

  test('XP table matches the spec', () {
    int xp(String id) => tourStopById(id)!.xp;
    expect(xp('arenaProof'), 30);
    expect(tourStopById('arenaProof')!.fallbackXp, 10);
    expect(xp('compete'), 10);
    expect(xp('crew'), 10);
    expect(xp('profile'), 5);
    expect(kTourNotifyXp, 5);
  });

  test('every spotlight stop has a dock fallback to reach its screen', () {
    for (final s in kTourScript) {
      expect(s.dockIndex, isNotNull, reason: s.id);
      expect(s.dockCopy, isNotNull, reason: s.id);
    }
  });
}
