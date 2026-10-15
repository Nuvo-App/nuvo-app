import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_v2/engine/demo_clip.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

NuvoPoseFrame _f(double sw) {
  NuvoPosePoint p(double x) =>
      NuvoPosePoint(x: x, y: 0.4, z: 0, likelihood: 0.9);
  return NuvoPoseFrame(
    points: {'leftShoulder': p(0.5 - sw / 2), 'rightShoulder': p(0.5 + sw / 2)},
    imageWidth: 1,
    imageHeight: 1,
    createdAt: DateTime(2026),
  );
}

List<NuvoPoseFrame> _demo(List<double> sizes) => [for (final s in sizes) _f(s)];

void main() {
  test('drops the phone walk-in and walk-out', () {
    final sizes = [
      for (var i = 0; i < 20; i++) 0.68, // at the phone
      for (var i = 0; i < 15; i++) 0.68 - i * 0.034, // walking back
      for (var i = 0; i < 60; i++) 0.17, // working spot
      for (var i = 0; i < 15; i++) 0.17 + i * 0.034, // walking to the phone
      for (var i = 0; i < 20; i++) 0.68,
    ];
    final c = clipDemoToWorkingSpot(_demo(sizes));
    expect(c.clipped, isTrue);
    expect(c.start, inInclusiveRange(29, 36));
    expect(c.end, inInclusiveRange(98, 108));
    expect(c.workingSize, closeTo(0.17, 0.01));
  });

  test('leaves a demo alone when the person never came from the phone', () {
    final c = clipDemoToWorkingSpot(_demo([for (var i = 0; i < 90; i++) 0.2]));
    expect(c.clipped, isFalse);
  });

  test('leaves sparse pose alone', () {
    final c = clipDemoToWorkingSpot(_demo([0.7, 0.2, 0.2]));
    expect(c.clipped, isFalse);
  });
}
