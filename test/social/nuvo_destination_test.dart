import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/social/domain/nuvo_destination.dart';

void main() {
  group('NuvoDestination.tryParse — one model for every entry source', () {
    test('universal link https://<host>/j/<token>', () {
      final d = NuvoDestination.tryParse(
        Uri.parse('https://nuvo-api.getnuvoapp.workers.dev/j/abc123XYZ'),
      );
      expect(d, isA<InviteDestination>());
      expect((d! as InviteDestination).token, 'abc123XYZ');
      expect(d.location, '/invite/abc123XYZ');
      expect(d.requiresAuth, isFalse); // previews logged-out
    });

    test('custom scheme nuvo://j/<token>', () {
      final d = NuvoDestination.tryParse(Uri.parse('nuvo://j/tok_9'));
      expect(d, isA<InviteDestination>());
      expect((d! as InviteDestination).token, 'tok_9');
    });

    test('in-app race path with a sub-context', () {
      final d = NuvoDestination.tryParse(Uri.parse('nuvo://app/race/r1/leaderboard'));
      expect(d, isA<RaceDestination>());
      final r = d! as RaceDestination;
      expect(r.raceId, 'r1');
      expect(r.context, 'leaderboard');
      expect(r.location, '/race/r1');
    });

    test('race review context maps to settings', () {
      final d = NuvoDestination.tryParse(Uri.parse('https://x.dev/race/r1/review'))
          as RaceDestination;
      expect(d.location, '/race/r1/settings');
    });

    test('profile / pass / notifications', () {
      expect(
        NuvoDestination.tryParse(Uri.parse('https://x.dev/profile/u1')),
        isA<ProfileDestination>(),
      );
      expect(
        NuvoDestination.tryParse(Uri.parse('nuvo://app/pass')),
        isA<CrewDestination>(),
      );
      expect(
        NuvoDestination.tryParse(Uri.parse('https://x.dev/notifications')),
        isA<NotificationsDestination>(),
      );
    });

    test('a non-Nuvo URL is null (scanner must never open it)', () {
      expect(NuvoDestination.tryParse(Uri.parse('https://evil.example/j/x')),
          isA<InviteDestination>()); // host-agnostic /j/ — server validates token
      expect(NuvoDestination.tryParse(Uri.parse('https://google.com/search?q=nuvo')),
          isNull);
      expect(NuvoDestination.tryParse(Uri.parse('https://x.dev/')), isNull);
      expect(NuvoDestination.tryParse(Uri.parse('mailto:a@b.com')), isNull);
    });
  });

  group('NuvoDestination.fromDescriptor — server-structured, never a route string', () {
    test('race with context', () {
      final d = NuvoDestination.fromDescriptor(
        {'type': 'race', 'id': 'r9', 'context': 'leaderboard'},
      );
      expect(d, isA<RaceDestination>());
      expect((d! as RaceDestination).raceId, 'r9');
    });

    test('invite token via "token" key', () {
      final d = NuvoDestination.fromDescriptor({'type': 'invite', 'token': 't1'});
      expect((d! as InviteDestination).token, 't1');
    });

    test('unknown / malformed → null', () {
      expect(NuvoDestination.fromDescriptor(null), isNull);
      expect(NuvoDestination.fromDescriptor({'type': 'wormhole'}), isNull);
      expect(NuvoDestination.fromDescriptor({'type': 'race'}), isNull); // no id
    });
  });

  test('value equality (so a re-delivered link is a no-op)', () {
    expect(const RaceDestination('r1'), const RaceDestination('r1'));
    expect(const InviteDestination('t'), const InviteDestination('t'));
    expect(const RaceDestination('r1', context: 'x'),
        isNot(const RaceDestination('r1')));
  });
}
