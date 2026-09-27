import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/presentation/movement_preview/rive_pose_controller.dart';
import 'package:nuvo/features/races/presentation/movement_preview/rive_pose_frame.dart';
import 'package:rive/rive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('writes only the six Jumping Jack controls', () async {
    final file = await File.asset(
      'assets/animations/preverify/nuvo_stickman.riv',
      riveFactory: Factory.flutter,
    );
    expect(file, isNotNull);

    final artboard = file!.artboard('nuvo stickman elite');
    expect(artboard, isNotNull);
    final model = file.defaultArtboardViewModel(artboard!);
    expect(model, isNotNull);
    final instance = model!.createDefaultInstance();
    expect(instance, isNotNull);

    final controller = RivePoseController(instance!);
    expect(controller.isUsable, isTrue);

    controller.applyJumpingJackMotion(
      const RivePoseFrame(
        torsoAngle: 25,
        leftShoulderAngle: -80,
        leftElbowAngle: 7,
        rightShoulderAngle: 10,
        rightElbowAngle: 13,
        leftHipAngle: -12,
        leftKneeAngle: 9,
        rightHipAngle: 12,
        rightKneeAngle: 9,
        leftUpperArmScale: 100,
        leftLowerArmScale: 100,
        rightUpperArmScale: 100,
        rightLowerArmScale: 100,
        leftUpperLegScale: 100,
        leftLowerLegScale: 100,
        rightUpperLegScale: 100,
        rightLowerLegScale: 100,
        torsoScaleY: 100,
      ),
    );

    expect(instance.number('leftShoulderAngle')!.value, -80);
    expect(instance.number('leftElbowAngle')!.value, 7);
    expect(instance.number('rightShoulderAngle')!.value, 10);
    expect(instance.number('rightElbowAngle')!.value, 13);
    expect(instance.number('leftHipAngle')!.value, -12);
    expect(instance.number('rightHipAngle')!.value, 12);

    expect(instance.number('torsoAngle')!.value, 0);
    expect(instance.number('leftKneeAngle')!.value, 0);
    expect(instance.number('rightKneeAngle')!.value, 0);
    expect(instance.number('leftUpperArmScale')!.value, 0);
    expect(instance.number('rightUpperArmScale')!.value, 0);
    expect(instance.number('leftUpperLegScale')!.value, 0);
    expect(instance.number('rightUpperLegScale')!.value, 0);
    expect(instance.number('torsoScaleY')!.value, 0);

    instance.dispose();
    file.dispose();
  });
}
