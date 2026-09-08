import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:nuvo/features/auth/data/auth_api.dart' show ApiException;
import 'package:nuvo/features/social/data/invite_api.dart';
import 'package:nuvo/features/social/data/invite_models.dart';
import 'package:nuvo/features/social/domain/nuvo_destination.dart';

http.Response _json(Object body, [int code = 200]) =>
    http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});

void main() {
  group('InviteApi.preview — logged-out safe preview', () {
    test('active race invite parses into a card + destination', () async {
      final api = InviteApi(
        client: MockClient((req) async {
          expect(req.url.path, '/invites/tok123');
          expect(req.headers['Authorization'], isNull); // logged-out
          return _json({
            'ok': true,
            'status': 'active',
            'kind': 'race_join',
            'requiresAuth': true,
            'destination': {'type': 'race', 'id': 'r1'},
            'preview': {
              'race': {
                'id': 'r1',
                'title': 'Squat Sprint',
                'activityId': 'squats',
                'targetValue': 100,
                'targetUnit': 'reps',
                'participantCount': 3,
                'creator': {'displayName': 'Riley', 'profilePhotoUrl': null},
                'alreadyJoined': false,
              },
            },
          });
        }),
      );
      final p = await api.preview('tok123');
      expect(p.status, InviteStatus.active);
      expect(p.kind, 'race_join');
      expect(p.race!.title, 'Squat Sprint');
      expect(p.race!.participantCount, 3);
      expect(p.destination, isA<RaceDestination>());
      expect((p.destination! as RaceDestination).raceId, 'r1');
    });

    test('expired invite → status, no throw (410 is not an error here)', () async {
      final api = InviteApi(
        client: MockClient((req) async => _json({'ok': false, 'status': 'expired'}, 410)),
      );
      final p = await api.preview('x');
      expect(p.status, InviteStatus.expired);
      expect(p.isAvailable, isFalse);
    });

    test('5xx does throw', () async {
      final api = InviteApi(client: MockClient((req) async => http.Response('boom', 500)));
      expect(() => api.preview('x'), throwsA(isA<ApiException>()));
    });
  });

  group('InviteApi.accept', () {
    test('race join → destination + alreadyJoined flag', () async {
      final api = InviteApi(
        client: MockClient((req) async {
          expect(req.method, 'POST');
          expect(req.headers['Authorization'], 'Bearer JWT');
          return _json({
            'ok': true,
            'kind': 'race_join',
            'alreadyJoined': true,
            'destination': {'type': 'race', 'id': 'r9'},
          });
        }),
      );
      final r = await api.accept('t', 'JWT');
      expect(r.ok, isTrue);
      expect(r.alreadyJoined, isTrue);
      expect((r.destination! as RaceDestination).raceId, 'r9');
    });

    test('crew connect to a private profile → pending', () async {
      final api = InviteApi(
        client: MockClient((req) async => _json({
              'ok': true,
              'kind': 'crew_connect',
              'connectionStatus': 'pending',
              'destination': {'type': 'profile', 'id': 'u2'},
            })),
      );
      final r = await api.accept('t', 'JWT');
      expect(r.connectionStatus, 'pending');
      expect(r.destination, isA<ProfileDestination>());
    });

    test('403 with a reason surfaces as ApiException (blocked / terms)', () async {
      final api = InviteApi(
        client: MockClient((req) async =>
            _json({'ok': false, 'error': 'Accept the Terms of Service to join a race'}, 403)),
      );
      expect(() => api.accept('t', 'JWT'), throwsA(isA<ApiException>()));
    });

    test('unavailable token → result carries the status, no throw', () async {
      final api = InviteApi(
        client: MockClient((req) async => _json({'ok': false, 'status': 'revoked'}, 410)),
      );
      final r = await api.accept('t', 'JWT');
      expect(r.ok, isFalse);
      expect(r.status, InviteStatus.revoked);
    });
  });

  group('InviteApi.mint', () {
    test('returns token + url + code', () async {
      final api = InviteApi(
        client: MockClient((req) async {
          expect(jsonDecode(req.body)['kind'], 'race_join');
          return _json({
            'ok': true,
            'token': 'abc',
            'url': 'https://nuvo-api.getnuvoapp.workers.dev/j/abc',
            'code': 'BRAVO7',
            'kind': 'race_join',
          });
        }),
      );
      final m = await api.mint('JWT', kind: 'race_join', targetId: 'r1');
      expect(m.url, endsWith('/j/abc'));
      expect(m.code, 'BRAVO7');
    });
  });
}
