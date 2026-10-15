import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nuvo/core/config/nuvo_flags.dart';
import 'package:nuvo/features/races/ai/motion_v2/engine/demo_clip.dart' as clip;

void main() {
  setUp(() => NuvoFlags.customMotion.value = false);

  test('stays off when the worker is unreachable', () async {
    await NuvoFlags.load(
      client: MockClient((_) async => throw http.ClientException('down')),
    );
    expect(NuvoFlags.customMotionOn, isFalse);
  });

  test('stays off on a non-200 or junk reply', () async {
    await NuvoFlags.load(
      client: MockClient((_) async => http.Response('x', 500)),
    );
    expect(NuvoFlags.customMotionOn, isFalse);
    await NuvoFlags.load(
      client: MockClient((_) async => http.Response('[]', 200)),
    );
    expect(NuvoFlags.customMotionOn, isFalse);
  });

  test('turns on and tunes the clip when the worker says so', () async {
    await NuvoFlags.load(
      client: MockClient(
        (_) async => http.Response(
          '{"custom_motion":true,"clip_settle_factor":1.2}',
          200,
        ),
      ),
    );
    expect(NuvoFlags.customMotionOn, isTrue);
    expect(clip.clipSettleFactor, 1.2);
    clip.clipSettleFactor = 1.15;
  });

  test('ignores an out-of-range clip setting', () async {
    await NuvoFlags.load(
      client: MockClient(
        (_) async => http.Response('{"clip_settle_factor":9}', 200),
      ),
    );
    expect(clip.clipSettleFactor, 1.15);
  });
}
