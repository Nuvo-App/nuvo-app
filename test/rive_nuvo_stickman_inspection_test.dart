import 'package:flutter_test/flutter_test.dart';
import 'package:rive/rive.dart';

void main() {
  testWidgets('inspect Nuvo stickman Rive contract', (tester) async {
    final file = await File.asset(
      'assets/animations/preverify/nuvo_stickman.riv',
      riveFactory: Factory.flutter,
    );
    expect(file, isNotNull);
    final artboard = file!.defaultArtboard();
    expect(artboard, isNotNull);
    final viewModel = file.defaultArtboardViewModel(artboard!);
    expect(artboard.name, 'nuvo stickman elite');
    // ignore: avoid_print
    print(
      'NUVO_RIVE bounds=${artboard.bounds} layout=${artboard.layoutBounds}',
    );
    expect(viewModel?.name, 'NuvoPoseModel');
    expect(viewModel?.properties.length, 18);
    final instance = viewModel?.createDefaultInstance();
    expect(instance, isNotNull);
    expect(artboard.stateMachineCount(), 1);
    expect(artboard.stateMachineAt(0)?.name, 'Nuvo pose');
    final stateMachine = artboard.stateMachineAt(0)!;
    for (var i = 0; i < 32; i++) {
      final input = stateMachine.inputAt(i);
      if (input == null) break;
      // ignore: avoid_print
      print('NUVO_RIVE input[$i]=${input.name}');
    }
    for (final property
        in instance?.properties ?? const <ViewModelProperty>[]) {
      if (property.type == DataType.number) {
        expect(instance!.number(property.name), isNotNull);
      }
    }
    expect(instance!.number('leftShoulderAngle')!.value, -90);
    expect(instance.number('torsoAngle')!.value, 0);
    expect(instance.number('rightShoulderAngle')!.value, 0);
    expect(instance.number('rightElbowAngle')!.value, 20);
    expect(instance.number('leftUpperArmScale')!.value, 0);
    expect(instance.number('torsoScaleY')!.value, 0);
    instance!.dispose();
    file.dispose();
  });
}
