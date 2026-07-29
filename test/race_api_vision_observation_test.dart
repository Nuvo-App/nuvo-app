import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/universal_proof_rule.dart';

void main() {
  test('analyzeVisionObservation posts sampled frame payload', () async {
    late Uri requestedUri;
    late Map<String, dynamic> requestedBody;

    final api = RaceApi(
      client: MockClient((request) async {
        requestedUri = request.url;
        requestedBody = jsonDecode(request.body) as Map<String, dynamic>;
        expect(request.headers['Authorization'], 'Bearer token');
        return http.Response(
          jsonEncode({
            'ok': true,
            'observation': {
              'observationId': 'obs-1',
              'activityId': 'basketball_shots',
              'activityDetected': true,
              'actionComplete': true,
              'confidence': 0.87,
              'summary': 'Shot released toward hoop.',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final observation = await api.analyzeVisionObservation(
      'token',
      'race-1',
      observationId: 'obs-1',
      activityId: 'basketball_shots',
      prompt: 'Count one clean basketball shot release.',
      imageBase64: 'abc123',
    );

    expect(requestedUri.path, '/races/race-1/proof/vision-observation');
    expect(requestedBody['observationId'], 'obs-1');
    expect(requestedBody['activityId'], 'basketball_shots');
    expect(requestedBody['prompt'], contains('basketball'));
    expect(requestedBody['imageBase64'], 'abc123');
    expect(observation.actionComplete, isTrue);
    expect(observation.confidence, 0.87);
  });

  test('buildUniversalProofRule posts teaching example payload', () async {
    late Uri requestedUri;
    late Map<String, dynamic> requestedBody;

    final api = RaceApi(
      client: MockClient((request) async {
        requestedUri = request.url;
        requestedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'ok': true,
            'rule': {
              'version': 'nuvo-universal-rule-v1',
              'unit': 'basketball shots',
              'countRule': 'Count one when the ball leaves the hand.',
              'rejectRule': 'Reject dribbles and repeated frames.',
              'framingTip': 'Keep the player, ball, and hoop visible.',
              'promptText': 'Return actionComplete for one clean shot release.',
              'confidenceThreshold': 0.74,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final rule = await api.buildUniversalProofRule(
      'token',
      actionName: 'basketball shots',
      unit: 'basketball shots',
      positiveImageBase64: 'base64-frame',
      negativeImageBase64: 'base64-reject-frame',
      negativeNote: 'Do not count dribbles.',
    );

    expect(requestedUri.path, '/races/proof-rule');
    expect(requestedBody['actionName'], 'basketball shots');
    expect(requestedBody['positiveImageBase64'], 'base64-frame');
    expect(requestedBody['negativeImageBase64'], 'base64-reject-frame');
    expect(rule.unit, 'basketball shots');
    expect(rule.confidenceThreshold, 0.74);
  });

  test('UniversalProofRule embeds and parses from race description', () {
    const rule = UniversalProofRule(
      version: 'nuvo-universal-rule-v1',
      unit: 'basketball shots',
      countRule: 'Count one clean release.',
      rejectRule: 'Reject dribbles.',
      framingTip: 'Keep the hoop visible.',
      promptText: 'Return actionComplete for a clean release.',
      confidenceThreshold: 0.72,
    );

    final description = rule.encodeForDescription(
      visibleDescription: 'Nuvo AI universal proof.',
    );
    final parsed = UniversalProofRule.fromDescription(description);

    expect(parsed, isNotNull);
    expect(parsed!.unit, 'basketball shots');
    expect(parsed.promptText, contains('clean release'));
  });
}
