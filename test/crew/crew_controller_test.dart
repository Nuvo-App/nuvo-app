// Crew lifecycle at the controller layer: reciprocal visibility, request
// resolution, in-flight dedupe and presentation-demo isolation. The backend
// write semantics live in transitionCrew (server/worker); these tests pin the
// client-side state contract the Crew screen renders.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/crew/application/crew_controller.dart';
import 'package:nuvo/features/crew/data/crew_api.dart';
import 'package:nuvo/features/crew/data/crew_repository.dart';
import 'package:nuvo/features/races/data/race_models.dart';

class _FakeCrewRepo implements CrewRepository {
  List<PublicUser> crew = const [];
  CrewRequestPage requestPage = const CrewRequestPage();
  List<CrewSearchResult> searchResults = const [];
  ConnectOutcome addOutcome = ConnectOutcome.active;
  Completer<ConnectOutcome>? addGate;
  int addCalls = 0;
  int acceptCalls = 0;
  int declineCalls = 0;
  int removeCalls = 0;
  int searchCalls = 0;
  int crewCalls = 0;

  @override
  Future<List<PublicUser>> getCrew() async {
    crewCalls++;
    return crew;
  }

  @override
  Future<CrewRequestPage> getRequestPage() async => requestPage;

  @override
  Future<List<CrewSearchResult>> search(String query) async {
    searchCalls++;
    return searchResults;
  }

  @override
  Future<PublicProfileCard> getUser(String userId) => throw UnimplementedError();

  @override
  Future<ConnectOutcome> add(String userId) async {
    addCalls++;
    final gate = addGate;
    if (gate != null) return gate.future;
    return addOutcome;
  }

  @override
  Future<void> acceptRequest(String userId) async {
    acceptCalls++;
  }

  @override
  Future<void> declineRequest(String userId) async {
    declineCalls++;
  }

  @override
  Future<void> remove(String userId) async {
    removeCalls++;
  }

  @override
  Future<void> reportUser(String userId, {String? reason}) async {}
  @override
  Future<void> reportRace(String raceId, {String? reason}) async {}
  @override
  Future<void> reportContent(String contentId, {String? reason}) async {}
  @override
  Future<void> blockUser(String userId) async {}
  @override
  Future<void> unblockUser(String userId) async {}
}

const _sam = PublicUser(
  id: 'sam',
  displayName: 'Sam Rivera',
  username: 'samr',
  initials: 'SR',
);
const _kim = PublicUser(
  id: 'kim',
  displayName: 'Kim Lee',
  username: 'kiml',
  initials: 'KL',
);

void main() {
  group('CrewController mutations', () {
    test('add → active lands the member and reports connected', () async {
      final repo = _FakeCrewRepo();
      var resolved = '';
      final controller = CrewController(
        repo,
        onRequestResolved: (id) => resolved = id,
      );
      final outcome = await controller.add(_sam);
      expect(outcome, ConnectOutcome.active);
      expect(controller.state.members.single.id, 'sam');
      expect(
        controller.state.relationshipFor('sam'),
        CrewConnectionStatus.connected,
      );
      expect(resolved, 'sam');
    });

    test('add → pending tracks the sent request, not a member', () async {
      final repo = _FakeCrewRepo()..addOutcome = ConnectOutcome.pending;
      final controller = CrewController(repo);
      final outcome = await controller.add(_sam);
      expect(outcome, ConnectOutcome.pending);
      expect(controller.state.members, isEmpty);
      expect(controller.state.outgoing.single.id, 'sam');
      expect(
        controller.state.relationshipFor('sam'),
        CrewConnectionStatus.pendingOutgoing,
      );
    });

    test('acceptRequest moves the requester into members', () async {
      final repo = _FakeCrewRepo()
        ..requestPage = const CrewRequestPage(incoming: [_sam]);
      var resolved = '';
      final controller = CrewController(
        repo,
        onRequestResolved: (id) => resolved = id,
      );
      await controller.load();
      expect(controller.state.requests.single.id, 'sam');

      await controller.acceptRequest(_sam);
      expect(controller.state.requests, isEmpty);
      expect(controller.state.members.single.id, 'sam');
      expect(
        controller.state.relationshipFor('sam'),
        CrewConnectionStatus.connected,
      );
      expect(repo.acceptCalls, 1);
      expect(resolved, 'sam');
    });

    test('declineRequest forgets the requester', () async {
      final repo = _FakeCrewRepo()
        ..requestPage = const CrewRequestPage(incoming: [_sam]);
      final controller = CrewController(repo);
      await controller.load();
      await controller.declineRequest(_sam);
      expect(controller.state.requests, isEmpty);
      expect(
        controller.state.relationshipFor('sam'),
        CrewConnectionStatus.none,
      );
      expect(repo.declineCalls, 1);
    });

    test('remove drops the member from crew', () async {
      final repo = _FakeCrewRepo()..crew = const [_sam];
      final controller = CrewController(repo);
      await controller.load();
      expect(controller.state.members.single.id, 'sam');
      await controller.remove('sam');
      expect(controller.state.members, isEmpty);
      expect(
        controller.state.relationshipFor('sam'),
        CrewConnectionStatus.none,
      );
      expect(repo.removeCalls, 1);
    });

    test('the same mutation twice shares one in-flight call', () async {
      final repo = _FakeCrewRepo()..addGate = Completer<ConnectOutcome>();
      final controller = CrewController(repo);
      final first = controller.add(_sam);
      final second = controller.add(_sam);
      expect(controller.state.pendingUserIds, {'sam'});
      repo.addGate!.complete(ConnectOutcome.active);
      expect(await first, ConnectOutcome.active);
      expect(await second, ConnectOutcome.active);
      expect(repo.addCalls, 1);
      expect(controller.state.pendingUserIds, isEmpty);
    });

    test('a different mutation on the same user fails fast', () async {
      final repo = _FakeCrewRepo()..addGate = Completer<ConnectOutcome>();
      final controller = CrewController(repo);
      final first = controller.add(_sam);
      expect(
        controller.remove('sam'),
        throwsA(isA<ApiException>().having(
          (e) => e.statusCode,
          'statusCode',
          409,
        )),
      );
      repo.addGate!.complete(ConnectOutcome.active);
      await first;
    });
  });

  group('CrewController load + refresh', () {
    test('load merges members, incoming and outgoing into relationships', () async {
      final repo = _FakeCrewRepo()
        ..crew = const [_kim]
        ..requestPage = const CrewRequestPage(incoming: [_sam], outgoing: [
          PublicUser(
            id: 'jo',
            displayName: 'Jo Fox',
            username: 'jo',
            initials: 'JF',
          ),
        ]);
      final controller = CrewController(repo);
      await controller.load();
      expect(
        controller.state.relationshipFor('kim'),
        CrewConnectionStatus.connected,
      );
      expect(
        controller.state.relationshipFor('sam'),
        CrewConnectionStatus.pendingIncoming,
      );
      expect(
        controller.state.relationshipFor('jo'),
        CrewConnectionStatus.pendingOutgoing,
      );
      expect(controller.state.outgoing.single.id, 'jo');
    });

    test('a member never double-lists as an incoming request', () async {
      final repo = _FakeCrewRepo()
        ..crew = const [_sam]
        ..requestPage = const CrewRequestPage(incoming: [_sam]);
      final controller = CrewController(repo);
      await controller.load();
      expect(controller.state.requests, isEmpty);
      expect(controller.state.members.single.id, 'sam');
    });
  });

  group('presentation demo isolation', () {
    test('demo mode never touches the repository', () async {
      final repo = _FakeCrewRepo();
      final controller = CrewController(
        repo,
        isPresentationDemo: () => true,
      );
      await controller.load();
      expect(repo.crewCalls, 0);
      // Demo members come from the fixture, not the API.
      expect(controller.state.members, isNotEmpty);

      final outcome = await controller.add(_kim);
      expect(outcome, ConnectOutcome.active);
      expect(repo.addCalls, 0);
      // The mutation still updates local state for the demo.
      expect(controller.state.members.first.id, 'kim');
    });

    test('demo search filters fixtures without hitting the API', () async {
      final repo = _FakeCrewRepo();
      final controller = CrewController(
        repo,
        isPresentationDemo: () => true,
      );
      await controller.load();
      final results = await controller.search('priya');
      expect(repo.searchCalls, 0);
      expect(results, isNotEmpty);
    });
  });

  group('account safety', () {
    test('clear() discards state so a new account starts empty', () async {
      final repo = _FakeCrewRepo()..crew = const [_sam];
      final controller = CrewController(repo);
      await controller.load();
      expect(controller.state.hasData, isTrue);
      controller.clear();
      expect(controller.state.members, isEmpty);
      expect(controller.state.hasData, isFalse);
    });
  });
}
