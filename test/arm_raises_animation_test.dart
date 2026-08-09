import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/presentation/widgets/arm_raises_animation.dart';
import 'package:nuvo/features/races/presentation/widgets/nuvo_character_painter.dart';

void main() {
  group('NuvoCharacterPose', () {
    test('lerp interpolates all joints linearly', () {
      const a = NuvoCharacterPose(
        head: Offset(0.5, 0.1),
        neck: Offset(0.5, 0.2),
        leftShoulder: Offset(0.4, 0.2),
        rightShoulder: Offset(0.6, 0.2),
        leftElbow: Offset(0.35, 0.3),
        rightElbow: Offset(0.65, 0.3),
        leftWrist: Offset(0.3, 0.4),
        rightWrist: Offset(0.7, 0.4),
        leftHip: Offset(0.45, 0.5),
        rightHip: Offset(0.55, 0.5),
        leftKnee: Offset(0.44, 0.65),
        rightKnee: Offset(0.56, 0.65),
        leftAnkle: Offset(0.43, 0.8),
        rightAnkle: Offset(0.57, 0.8),
      );
      const b = NuvoCharacterPose(
        head: Offset(0.5, 0.05),
        neck: Offset(0.5, 0.15),
        leftShoulder: Offset(0.4, 0.18),
        rightShoulder: Offset(0.6, 0.18),
        leftElbow: Offset(0.35, 0.25),
        rightElbow: Offset(0.65, 0.25),
        leftWrist: Offset(0.3, 0.1),
        rightWrist: Offset(0.7, 0.1),
        leftHip: Offset(0.45, 0.5),
        rightHip: Offset(0.55, 0.5),
        leftKnee: Offset(0.44, 0.65),
        rightKnee: Offset(0.56, 0.65),
        leftAnkle: Offset(0.43, 0.8),
        rightAnkle: Offset(0.57, 0.8),
      );
      final mid = NuvoCharacterPose.lerp(a, b, 0.5);
      expect(mid.head.dx, moreOrLessEquals(0.5));
      expect(mid.head.dy, moreOrLessEquals(0.075));
      expect(mid.leftWrist.dx, moreOrLessEquals(0.3));
      expect(mid.leftWrist.dy, moreOrLessEquals(0.25));
      expect(mid.rightWrist.dx, moreOrLessEquals(0.7));
      expect(mid.rightWrist.dy, moreOrLessEquals(0.25));
    });

    test('lerp at t=0 returns first pose', () {
      const a = NuvoCharacterPose(
        head: Offset(0.5, 0.1),
        neck: Offset(0.5, 0.2),
        leftShoulder: Offset(0.4, 0.2),
        rightShoulder: Offset(0.6, 0.2),
        leftElbow: Offset(0.35, 0.3),
        rightElbow: Offset(0.65, 0.3),
        leftWrist: Offset(0.3, 0.4),
        rightWrist: Offset(0.7, 0.4),
        leftHip: Offset(0.45, 0.5),
        rightHip: Offset(0.55, 0.5),
        leftKnee: Offset(0.44, 0.65),
        rightKnee: Offset(0.56, 0.65),
        leftAnkle: Offset(0.43, 0.8),
        rightAnkle: Offset(0.57, 0.8),
      );
      const b = NuvoCharacterPose(
        head: Offset(0.5, 0.05),
        neck: Offset(0.5, 0.15),
        leftShoulder: Offset(0.4, 0.18),
        rightShoulder: Offset(0.6, 0.18),
        leftElbow: Offset(0.35, 0.25),
        rightElbow: Offset(0.65, 0.25),
        leftWrist: Offset(0.3, 0.1),
        rightWrist: Offset(0.7, 0.1),
        leftHip: Offset(0.45, 0.5),
        rightHip: Offset(0.55, 0.5),
        leftKnee: Offset(0.44, 0.65),
        rightKnee: Offset(0.56, 0.65),
        leftAnkle: Offset(0.43, 0.8),
        rightAnkle: Offset(0.57, 0.8),
      );
      final result = NuvoCharacterPose.lerp(a, b, 0);
      expect(result.head, a.head);
      expect(result.leftWrist, a.leftWrist);
    });

    test('lerp at t=1 returns second pose', () {
      const a = NuvoCharacterPose(
        head: Offset(0.5, 0.1),
        neck: Offset(0.5, 0.2),
        leftShoulder: Offset(0.4, 0.2),
        rightShoulder: Offset(0.6, 0.2),
        leftElbow: Offset(0.35, 0.3),
        rightElbow: Offset(0.65, 0.3),
        leftWrist: Offset(0.3, 0.4),
        rightWrist: Offset(0.7, 0.4),
        leftHip: Offset(0.45, 0.5),
        rightHip: Offset(0.55, 0.5),
        leftKnee: Offset(0.44, 0.65),
        rightKnee: Offset(0.56, 0.65),
        leftAnkle: Offset(0.43, 0.8),
        rightAnkle: Offset(0.57, 0.8),
      );
      const b = NuvoCharacterPose(
        head: Offset(0.5, 0.05),
        neck: Offset(0.5, 0.15),
        leftShoulder: Offset(0.4, 0.18),
        rightShoulder: Offset(0.6, 0.18),
        leftElbow: Offset(0.35, 0.25),
        rightElbow: Offset(0.65, 0.25),
        leftWrist: Offset(0.3, 0.1),
        rightWrist: Offset(0.7, 0.1),
        leftHip: Offset(0.45, 0.5),
        rightHip: Offset(0.55, 0.5),
        leftKnee: Offset(0.44, 0.65),
        rightKnee: Offset(0.56, 0.65),
        leftAnkle: Offset(0.43, 0.8),
        rightAnkle: Offset(0.57, 0.8),
      );
      final result = NuvoCharacterPose.lerp(a, b, 1);
      expect(result.head, b.head);
      expect(result.leftWrist, b.leftWrist);
    });
  });

  group('NuvoCharacterPainter', () {
    testWidgets('renders without exceptions in a widget tree', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 300,
              child: CustomPaint(
                painter: NuvoCharacterPainter(
                  pose: NuvoCharacterPose.lerp(_downPose, _overheadPose, 0.5),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    test('shouldRepaint returns true when pose changes', () {
      final painter1 = NuvoCharacterPainter(pose: _downPose);
      final painter2 = NuvoCharacterPainter(pose: _overheadPose);
      expect(painter2.shouldRepaint(painter1), isTrue);
    });

    test('shouldRepaint returns false when pose is the same', () {
      final painter1 = NuvoCharacterPainter(pose: _downPose);
      final painter2 = NuvoCharacterPainter(pose: _downPose);
      expect(painter2.shouldRepaint(painter1), isFalse);
    });
  });

  group('ArmRaisesAnimation', () {
    testWidgets('renders without exceptions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 300,
              child: ArmRaisesAnimation(),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('animation changes character pose over time', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 300,
              child: ArmRaisesAnimation(),
            ),
          ),
        ),
      );

      // Let the animation start.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Find the CustomPaint whose painter is a NuvoCharacterPainter.
      NuvoCharacterPose poseAtFrame() {
        final paints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
        final cp = paints.firstWhere(
          (w) => w.painter is NuvoCharacterPainter,
          orElse: () => throw StateError('No NuvoCharacterPainter found'),
        );
        return (cp.painter as NuvoCharacterPainter).pose;
      }

      final wrist0 = poseAtFrame().leftWrist;

      // Pump forward to advance the animation.
      await tester.pump(const Duration(milliseconds: 700));

      final wrist1 = poseAtFrame().leftWrist;

      // The pose should have changed (wrists should be higher)
      expect(wrist1.dy, isNot(equals(wrist0.dy)));
    });

    testWidgets('contains NuvoCharacterPainter in widget tree', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 300,
              child: ArmRaisesAnimation(),
            ),
          ),
        ),
      );
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}

const _downPose = NuvoCharacterPose(
  head: Offset(0.50, 0.10),
  neck: Offset(0.50, 0.17),
  leftShoulder: Offset(0.42, 0.20),
  rightShoulder: Offset(0.58, 0.20),
  leftElbow: Offset(0.39, 0.30),
  rightElbow: Offset(0.61, 0.30),
  leftWrist: Offset(0.38, 0.39),
  rightWrist: Offset(0.62, 0.39),
  leftHip: Offset(0.45, 0.42),
  rightHip: Offset(0.55, 0.42),
  leftKnee: Offset(0.44, 0.58),
  rightKnee: Offset(0.56, 0.58),
  leftAnkle: Offset(0.44, 0.74),
  rightAnkle: Offset(0.56, 0.74),
);

const _overheadPose = NuvoCharacterPose(
  head: Offset(0.50, 0.10),
  neck: Offset(0.50, 0.17),
  leftShoulder: Offset(0.42, 0.20),
  rightShoulder: Offset(0.58, 0.20),
  leftElbow: Offset(0.40, 0.08),
  rightElbow: Offset(0.60, 0.08),
  leftWrist: Offset(0.42, 0.01),
  rightWrist: Offset(0.58, 0.01),
  leftHip: Offset(0.45, 0.42),
  rightHip: Offset(0.55, 0.42),
  leftKnee: Offset(0.44, 0.58),
  rightKnee: Offset(0.56, 0.58),
  leftAnkle: Offset(0.44, 0.74),
  rightAnkle: Offset(0.56, 0.74),
);
