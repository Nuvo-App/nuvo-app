import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/cadence_detector.dart';

void main() {
  group('CadenceDetector', () {
    test('left-only repeated motion never counts', () {
      final c = CadenceDetector(stableFrames: 2);
      for (var i = 0; i < 20; i++) {
        c.update(CadenceSide.left);
      }
      expect(c.cycles, 0);
    });

    test('right-only repeated motion never counts', () {
      final c = CadenceDetector(stableFrames: 2);
      for (var i = 0; i < 20; i++) {
        c.update(CadenceSide.right);
      }
      expect(c.cycles, 0);
    });

    test('valid left-right alternation counts each confirmed switch', () {
      final c = CadenceDetector(stableFrames: 2);
      // left confirmed (baseline, no count) -> right (1) -> left (2) -> right (3)
      for (var i = 0; i < 2; i++) {
        c.update(CadenceSide.left);
      }
      expect(c.cycles, 0);
      for (var i = 0; i < 2; i++) {
        c.update(CadenceSide.right);
      }
      expect(c.cycles, 1);
      for (var i = 0; i < 2; i++) {
        c.update(CadenceSide.left);
      }
      expect(c.cycles, 2);
      for (var i = 0; i < 2; i++) {
        c.update(CadenceSide.right);
      }
      expect(c.cycles, 3);
    });

    test('rapid alternation at the exact stableFrames floor counts every step',
        () {
      final c = CadenceDetector(stableFrames: 2);
      final sides = [
        CadenceSide.left, CadenceSide.left, // baseline
        CadenceSide.right, CadenceSide.right, // +1
        CadenceSide.left, CadenceSide.left, // +1
        CadenceSide.right, CadenceSide.right, // +1
        CadenceSide.left, CadenceSide.left, // +1
      ];
      for (final s in sides) {
        c.update(s);
      }
      expect(c.cycles, 4);
    });

    test('neutral/null frames between sides do not break alternation', () {
      final c = CadenceDetector(stableFrames: 2);
      c.update(CadenceSide.left);
      c.update(CadenceSide.left);
      c.update(null); // neutral / feet together
      c.update(null);
      c.update(CadenceSide.right);
      c.update(CadenceSide.right);
      expect(c.cycles, 1);
    });

    test('same-side jitter (never 2 consecutive) confirms nothing', () {
      final c = CadenceDetector(stableFrames: 2);
      // left, right, left, right single frames each — never stable.
      for (var i = 0; i < 10; i++) {
        c.update(i.isEven ? CadenceSide.left : CadenceSide.right);
      }
      expect(c.cycles, 0);
      expect(c.currentSide, isNull);
    });

    test('one frame short of stableFrames does not confirm a switch', () {
      final c = CadenceDetector(stableFrames: 3);
      c.update(CadenceSide.left);
      c.update(CadenceSide.left);
      c.update(CadenceSide.left); // baseline confirmed
      c.update(CadenceSide.right);
      c.update(CadenceSide.right); // only 2 of 3 — not confirmed
      expect(c.cycles, 0);
      c.update(CadenceSide.right); // 3rd — confirmed
      expect(c.cycles, 1);
    });

    test('reset clears cycles and side state', () {
      final c = CadenceDetector(stableFrames: 2);
      c.update(CadenceSide.left);
      c.update(CadenceSide.left);
      c.update(CadenceSide.right);
      c.update(CadenceSide.right);
      expect(c.cycles, 1);
      c.reset();
      expect(c.cycles, 0);
      expect(c.currentSide, isNull);
    });

    test('update returns true only on a frame that confirms a switch', () {
      final c = CadenceDetector(stableFrames: 2);
      expect(c.update(CadenceSide.left), isFalse);
      expect(c.update(CadenceSide.left), isFalse); // baseline confirm, no count
      expect(c.update(CadenceSide.right), isFalse);
      expect(c.update(CadenceSide.right), isTrue); // counted here
    });
  });
}
