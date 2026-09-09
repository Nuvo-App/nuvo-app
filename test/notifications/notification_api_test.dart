import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:nuvo/features/notifications/data/notification_api.dart';
import 'package:nuvo/features/social/domain/nuvo_destination.dart';

http.Response _json(Object body, [int code = 200]) =>
    http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});

void main() {
  test('list parses items, unread count, cursor + structured destinations', () async {
    final api = NotificationApi(
      client: MockClient((req) async {
        expect(req.url.path, '/notifications');
        return _json({
          'ok': true,
          'unreadCount': 2,
          'nextCursor': '2026-09-01T00:00:00Z',
          'notifications': [
            {
              'id': 'n1',
              'category': 'race_joined',
              'title': 'Ada joined Squat Sprint',
              'createdAt': '2026-09-09T12:00:00Z',
              'read': false,
              'actor': {'id': 'u2', 'displayName': 'Ada', 'profilePhotoUrl': null},
              'destination': {'type': 'race', 'id': 'r1'},
            },
            {
              'id': 'n2',
              'category': 'crew_request',
              'title': 'Bo wants to connect',
              'createdAt': '2026-09-08T09:00:00Z',
              'read': true,
              'destination': {'type': 'profile', 'id': 'u3'},
            },
          ],
        });
      }),
    );
    final page = await api.list('JWT');
    expect(page.unreadCount, 2);
    expect(page.nextCursor, '2026-09-01T00:00:00Z');
    expect(page.items, hasLength(2));
    expect(page.items[0].read, isFalse);
    expect(page.items[0].actorName, 'Ada');
    expect(page.items[0].destination, isA<RaceDestination>());
    expect((page.items[0].destination! as RaceDestination).location, '/race/r1');
    expect(page.items[1].destination, isA<ProfileDestination>());
    expect(page.items[1].destination!.location, '/u/u3');
  });

  test('list passes the cursor through', () async {
    final api = NotificationApi(
      client: MockClient((req) async {
        expect(req.url.queryParameters['cursor'], 'CUR');
        return _json({'ok': true, 'notifications': [], 'unreadCount': 0});
      }),
    );
    await api.list('JWT', cursor: 'CUR');
  });

  test('markRead / markAllRead hit the right endpoints', () async {
    var readAll = false;
    var readOne = false;
    final api = NotificationApi(
      client: MockClient((req) async {
        if (req.url.path == '/notifications/n9/read') readOne = true;
        if (req.url.path == '/notifications/read-all') readAll = true;
        return _json({'ok': true});
      }),
    );
    await api.markRead('JWT', 'n9');
    await api.markAllRead('JWT');
    expect(readOne, isTrue);
    expect(readAll, isTrue);
  });
}
