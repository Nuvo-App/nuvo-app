import 'package:flutter_test/flutter_test.dart';
import 'package:rive/rive.dart';

void main() {
  testWidgets('records corrected Nuvo rig neutral values and control writes', (
    tester,
  ) async {
    final file = await File.asset(
      'assets/animations/preverify/nuvo_stickman.riv',
      riveFactory: Factory.flutter,
    );
    expect(file, isNotNull);
    final artboard = file!.defaultArtboard()!;
    final model = file.defaultArtboardViewModel(artboard)!;
    final instance = model.createDefaultInstance()!;
    final names = [
      'torsoAngle',
      'leftShoulderAngle',
      'leftElbowAngle',
      'rightShoulderAngle',
      'rightElbowAngle',
      'leftHipAngle',
      'leftKneeAngle',
      'rightHipAngle',
      'rightKneeAngle',
      'leftUpperArmScale',
      'leftLowerArmScale',
      'rightUpperArmScale',
      'rightLowerArmScale',
      'leftUpperLegScale',
      'leftLowerLegScale',
      'rightUpperLegScale',
      'rightLowerLegScale',
      'torsoScaleY',
    ];

    final defaults = <String, double>{};
    for (final name in names) {
      final property = instance.number(name);
      expect(property, isNotNull, reason: 'missing $name');
      defaults[name] = property!.value;
    }
    // ignore: avoid_print
    print('NUVO_RIVE_CORRECTED_DEFAULTS $defaults');

    for (final name in names) {
      final property = instance.number(name)!;
      final probe = defaults[name]! + (name.contains('Scale') ? 1 : 7);
      property.value = probe;
      instance.requestAdvance();
      expect(property.value, closeTo(probe, 0.0001), reason: name);
      property.value = defaults[name]!;
    }

    instance.dispose();
    file.dispose();
  });
}
