import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/yolox_object_detection.dart';

void main() {
  test('decodes letterboxed ball and rim rows into normalized detections', () {
    const decoder = YoloXBasketballObjectDecoder(
      inputSize: 800,
      confidenceThreshold: 0.2,
    );
    final output = <double>[
      // Ball: source image is 400x800, so letterbox scale is 1.0.
      120, 200, 40, 40, 0.95, 0.9, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      // Rim.
      260, 180, 160, 30, 0.9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.95,
    ];

    final detections = decoder.decode(
      output: output,
      candidateCount: 2,
      attributesPerCandidate: 15,
      sourceWidth: 400,
      sourceHeight: 800,
    );

    expect(detections, hasLength(2));
    final ball = detections.firstWhere((item) => item.label == 'ball');
    final rim = detections.firstWhere((item) => item.label == 'rim');
    expect(ball.centerX, closeTo(0.3, 0.001));
    expect(ball.centerY, closeTo(0.25, 0.001));
    expect(rim.centerX, closeTo(0.65, 0.001));
    expect(rim.centerY, closeTo(0.225, 0.001));
  });

  test('keeps the strongest overlapping detection per object kind', () {
    const decoder = YoloXBasketballObjectDecoder(
      inputSize: 800,
      confidenceThreshold: 0.2,
      iouThreshold: 0.4,
    );
    final output = <double>[
      100,
      100,
      80,
      80,
      0.9,
      0.9,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      105,
      105,
      80,
      80,
      0.8,
      0.8,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      600,
      600,
      80,
      20,
      0.9,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0.9,
    ];

    final detections = decoder.decode(
      output: output,
      candidateCount: 3,
      attributesPerCandidate: 15,
      sourceWidth: 800,
      sourceHeight: 800,
    );

    expect(detections.where((item) => item.label == 'ball'), hasLength(1));
    expect(detections.where((item) => item.label == 'rim'), hasLength(1));
    expect(detections.first.confidence, closeTo(0.81, 0.001));
  });

  test('ignores unsupported classes and low-confidence candidates', () {
    const decoder = YoloXBasketballObjectDecoder(
      inputSize: 800,
      confidenceThreshold: 0.5,
    );
    final output = <double>[
      100,
      100,
      80,
      80,
      0.9,
      0,
      0,
      0,
      0.99,
      0,
      0,
      0,
      0,
      0,
      0,
      200,
      200,
      40,
      40,
      0.2,
      0.99,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ];

    final detections = decoder.decode(
      output: output,
      candidateCount: 2,
      attributesPerCandidate: 15,
      sourceWidth: 800,
      sourceHeight: 800,
    );

    expect(detections, isEmpty);
  });
}
