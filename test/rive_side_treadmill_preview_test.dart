import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/presentation/movement_preview/side_rig_treadmill_preview.dart';
import 'package:rive/rive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'treadmill side sequence loops with opposite front/back gait phases',
    () {
      final sequence = TreadmillRunningSideSequence();
      final start = sequence.poseAt(0);
      final halfway = sequence.poseAt(0.5);
      final end = sequence.poseAt(1);

      expect(end.frontHipAngle, closeTo(start.frontHipAngle, 0.001));
      expect(end.backShoulderAngle, closeTo(start.backShoulderAngle, 0.001));
      expect(start.frontHipAngle, greaterThan(start.backHipAngle));
      expect(start.backShoulderAngle, greaterThan(start.frontShoulderAngle));
      expect(start.frontElbowAngle, lessThan(0));
      expect(start.backElbowAngle, greaterThan(0));
      expect(halfway.frontHipAngle, lessThan(halfway.backHipAngle));
      expect(
        halfway.frontShoulderAngle,
        greaterThan(halfway.backShoulderAngle),
      );
      expect(halfway.frontElbowAngle, greaterThan(0));
      expect(halfway.backElbowAngle, lessThan(0));
      expect(start.isFinite, isTrue);
      expect(halfway.isFinite, isTrue);
      expect(end.isFinite, isTrue);
    },
  );

  test(
    'side sequence keeps authored neutral scales and bounded presentation bounce',
    () {
      final sequence = TreadmillRunningSideSequence();
      for (final time in [0.0, 0.125, 0.25, 0.5, 0.75, 0.999, 1.0]) {
        final pose = sequence.poseAt(time);
        expect(pose.frontUpperArmScale, 100);
        expect(pose.backLowerArmScale, 100);
        expect(pose.frontUpperLegScale, 100);
        expect(pose.backLowerLegScale, 100);
        expect(pose.torsoScaleY, 100);
        expect(pose.rootYOffset, inInclusiveRange(-6, 0));
      }
      expect(sequence.poseAt(double.nan).isFinite, isTrue);
    },
  );

  testWidgets('corrected side Rive asset exposes the treadmill contract', (
    tester,
  ) async {
    final file = await File.asset(
      'assets/animations/preverify/nuvo_stickman_side.riv',
      riveFactory: Factory.flutter,
    );
    expect(file, isNotNull);

    final loadedFile = file!;
    final artboard = loadedFile.defaultArtboard();
    expect(artboard, isNotNull);
    expect(artboard!.name, 'Nuvo stickman side');
    expect(artboard.stateMachineAt(0)?.name, 'Nuvo State machine');

    final viewModel = loadedFile.defaultArtboardViewModel(artboard);
    expect(viewModel?.name, 'NuvoAngledataset');
    final instance = viewModel?.createDefaultInstance();
    expect(instance, isNotNull);

    final propertyNames = instance!.properties
        .map((property) => property.name)
        .toSet();
    expect(
      propertyNames,
      containsAll(<String>{
        'rootY',
        'rootX',
        'torsoScaleY',
        'backLowerLegScale',
        'backUpperLegScale',
        'frontLowerLegScale',
        'frontUpperLegScale',
        'backLowerArmScale',
        'backUpperArmScale',
        'frontLowerArmScale',
        'frontUpperArmScale',
        'backKneeAngle',
        'backHipAngle',
        'frontKneeAngle',
        'frontHipAngle',
        'backElbowAngle',
        'backShoulderAngle',
        'frontElbowAngle',
        'frontShoulderAngle',
        'torsoAngle',
      }),
    );

    expect(instance.number('torsoAngle')?.value, 0);
    expect(instance.number('frontShoulderAngle')?.value, 0);
    expect(instance.number('frontUpperArmScale')?.value, 0);

    final controller = SideRigPoseController(instance);
    expect(controller.isUsable, isTrue);
    controller.apply(SideRigPose.base);
    expect(instance.number('rootX')?.value, 244.5);
    expect(instance.number('rootY')?.value, 277);
    expect(instance.number('frontShoulderAngle')?.value, 90);
    expect(instance.number('backHipAngle')?.value, 90);
    expect(instance.number('frontUpperArmScale')?.value, 100);
    expect(instance.number('torsoScaleY')?.value, 100);

    instance.dispose();
    loadedFile.dispose();
  });
}
