// Crew activity + reactions at the controller layer: typed feed parsing,
// optimistic add/remove/change, and rollback on failure. Server-side write
// semantics (one-reaction-per-user-per-entity, blocking) live in
// server/worker/src/routes/reactions.ts; these tests pin the client contract.
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/social/data/crew_activity.dart';

class _FakeRepo implements CrewActivityRepository {
  _FakeRepo(this.feed);

  final List<CrewActivityItem> feed;
  ReactionSummary? nextSummary;
  Object? reactError;
  int reactCalls = 0;
  int unreactCalls = 0;
  String? lastEmoji;

  @override
  Future<List<CrewActivityItem>> getFeed({int limit = 40, String? cursor}) =>
      Future.value(feed);

  @override
  Future<ReactionSummary> react(CrewActivityItem item, String emoji) {
    reactCalls++;
    lastEmoji = emoji;
    final err = reactError;
    if (err != null) return Future.error(err);
    return Future.value(nextSummary ??
        const ReactionSummary(counts: {'fire': 1}, myReaction: 'fire'));
  }

  @override
  Future<ReactionSummary> unreact(CrewActivityItem item) {
    unreactCalls++;
    final err = reactError;
    if (err != null) return Future.error(err);
    return Future.value(const ReactionSummary(counts: {}));
  }
}

CrewActivityItem _item({
  String id = 'a1',
  String? entityType = 'race',
  String? entityId = 'race-1',
  Map<String, int> reactions = const {},
  String? myReaction,
}) =>
    CrewActivityItem(
      id: id,
      type: 'progress_accepted',
      occurredAt: DateTime.parse('2026-03-30T12:00:00Z'),
      entityType: entityType,
      entityId: entityId,
      reactions: reactions,
      myReaction: myReaction,
    );

void main() {
  group('CrewActivityItem.fromJson', () {
    test('parses a race_events-derived row with reactions', () {
      final item = CrewActivityItem.fromJson({
        'id': 'race_events:9',
        'type': 'lead_changed',
        'occurredAt': '2026-03-30T12:00:00.000Z',
        'actor': {'id': 'u1', 'displayName': 'Riley'},
        'raceId': 'r1',
        'raceTitle': 'Pushup Battle',
        'entityType': 'race',
        'entityId': 'r1',
        'destination': {'type': 'race', 'id': 'r1'},
        'payload': {'newRank': 1},
        'reactions': {'fire': 3, 'clap': 1},
        'myReaction': 'fire',
      });
      expect(item.type, 'lead_changed');
      expect(item.actor?.displayName, 'Riley');
      expect(item.raceId, 'r1');
      expect(item.headline, 'Riley took the lead in Pushup Battle');
      expect(item.reactions, {'fire': 3, 'clap': 1});
      expect(item.myReaction, 'fire');
      expect(item.isReactionable, isTrue);
    });

    test('a race_live item exposes the spectator payload', () {
      final item = CrewActivityItem.fromJson({
        'id': 'live:1',
        'type': 'race_live',
        'occurredAt': '2026-03-30T12:00:00.000Z',
        'payload': {
          'live': {
            'title': 'Pushup Battle',
            'endsAt': '2026-03-30T12:01:00.000Z',
            'participants': [
              {'name': 'Riley', 'score': 41, 'rank': 1},
              {'name': 'Maya', 'score': 39, 'rank': 2},
            ],
          },
        },
      });
      final live = item.live;
      expect(live, isNotNull);
      expect(live!.title, 'Pushup Battle');
      expect(live.participants.first.score, 41);
    });

    test('items without entity refs are not reactionable', () {
      expect(_item(entityType: null, entityId: null).isReactionable, isFalse);
    });
  });

  group('CrewActivityItem.involvesUser', () {
    CrewActivityItem event({
      String type = 'rank_changed',
      String actorId = 'u1',
      Map<String, dynamic> payload = const {},
    }) =>
        CrewActivityItem(
          id: 'e1',
          type: type,
          occurredAt: DateTime.parse('2026-03-30T12:00:00Z'),
          actor: CrewActivityActor(id: actorId, displayName: 'Riley'),
          payload: payload,
        );

    test('an overtake naming me is for-you', () {
      expect(
        event(payload: const {
          'newRank': 1,
          'overtakenUserIds': ['me', 'u2'],
        }).involvesUser('me'),
        isTrue,
      );
      expect(
        event(payload: const {
          'newRank': 1,
          'overtakenUserIds': ['u2'],
        }).involvesUser('me'),
        isFalse,
      );
    });

    test('my own actions and events naming me are for-you', () {
      expect(event(actorId: 'me').involvesUser('me'), isTrue);
      expect(
        event(payload: const {'displacedUserId': 'me'}).involvesUser('me'),
        isTrue,
      );
      expect(
        event(payload: const {'winnerUserId': 'me'}).involvesUser('me'),
        isTrue,
      );
      expect(
        event(payload: const {'userId': 'me'}).involvesUser('me'),
        isTrue,
      );
    });

    test('crew-only events are not for-you', () {
      expect(event().involvesUser('me'), isFalse);
      expect(event().involvesUser(''), isFalse);
    });
  });

  group('CrewActivityController reactions', () {
    test('add: server summary replaces the optimistic state', () async {
      final repo = _FakeRepo([_item()]);
      final c = CrewActivityController(repo);
      await c.load();

      final done = c.toggleReaction(c.state.items.single, 'muscle');
      expect(await done, isTrue);
      expect(repo.reactCalls, 1);
      expect(repo.lastEmoji, 'muscle');
      final item = c.state.items.single;
      expect(item.myReaction, 'fire'); // server's summary wins
      expect(item.reactions, {'fire': 1});
      expect(c.state.reactingItemIds, isEmpty);
    });

    test('same reaction again removes it', () async {
      final repo = _FakeRepo([
        _item(reactions: const {'fire': 2}, myReaction: 'fire'),
      ]);
      final c = CrewActivityController(repo);
      await c.load();

      expect(await c.toggleReaction(c.state.items.single, 'fire'), isTrue);
      expect(repo.unreactCalls, 1);
      expect(repo.reactCalls, 0);
      final item = c.state.items.single;
      expect(item.myReaction, isNull);
      expect(item.reactions, isEmpty);
    });

    test('a different reaction switches — one reaction per user', () async {
      final repo = _FakeRepo([
        _item(reactions: const {'fire': 1}, myReaction: 'fire'),
      ])
        ..nextSummary =
            const ReactionSummary(counts: {'muscle': 1}, myReaction: 'muscle');
      final c = CrewActivityController(repo);
      await c.load();

      expect(await c.toggleReaction(c.state.items.single, 'muscle'), isTrue);
      final item = c.state.items.single;
      expect(item.myReaction, 'muscle');
      expect(item.reactions, {'muscle': 1});
    });

    test('failure rolls the item back to its prior state', () async {
      final repo = _FakeRepo([
        _item(reactions: const {'fire': 1}, myReaction: 'fire'),
      ])..reactError = const ApiException(0, 'offline');
      final c = CrewActivityController(repo);
      await c.load();

      expect(await c.toggleReaction(c.state.items.single, 'clap'), isFalse);
      final item = c.state.items.single;
      expect(item.myReaction, 'fire');
      expect(item.reactions, {'fire': 1});
      expect(c.state.reactingItemIds, isEmpty);
    });

    test('non-reactionable items reject the toggle', () async {
      final repo =
          _FakeRepo([_item(entityType: null, entityId: null)]);
      final c = CrewActivityController(repo);
      await c.load();
      expect(await c.toggleReaction(c.state.items.single, 'fire'), isFalse);
      expect(repo.reactCalls, 0);
    });
  });
}
