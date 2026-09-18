import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nuvo/features/races/data/race_api.dart';

void main() {
  test('downloads a model artifact with identity headers', () async {
    final api = RaceApi(
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.path,
          '/motion/models/basketball-yolox-s-800/artifact',
        );
        expect(request.headers['authorization'], 'Bearer token');
        expect(request.headers['accept'], 'application/octet-stream');
        expect(request.headers['if-none-match'], isNull);
        return http.Response.bytes(
          Uint8List.fromList([1, 2, 3, 4]),
          200,
          headers: {
            'etag': 'artifact-etag',
            'x-model-version': 'basketball-yolox-s-800',
            'x-model-sha256': 'checksum',
          },
        );
      }),
    );

    final result = await api.getMotionModelArtifact(
      'token',
      'basketball-yolox-s-800',
    );

    expect(result.notModified, isFalse);
    expect(result.bytes, Uint8List.fromList([1, 2, 3, 4]));
    expect(result.etag, 'artifact-etag');
    expect(result.modelVersion, 'basketball-yolox-s-800');
    expect(result.sha256, 'checksum');
  });

  test('passes cached identity and preserves 304 metadata', () async {
    final api = RaceApi(
      client: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer token');
        expect(request.headers['if-none-match'], 'artifact-etag');
        return http.Response(
          '',
          304,
          headers: {
            'etag': 'artifact-etag',
            'x-model-version': 'basketball-yolox-s-800',
            'x-model-sha256': 'checksum',
          },
        );
      }),
    );

    final result = await api.getMotionModelArtifact(
      'token',
      'basketball-yolox-s-800',
      etag: 'artifact-etag',
    );

    expect(result.notModified, isTrue);
    expect(result.bytes, isNull);
    expect(result.etag, 'artifact-etag');
    expect(result.modelVersion, 'basketball-yolox-s-800');
    expect(result.sha256, 'checksum');
  });
}
