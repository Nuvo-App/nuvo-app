import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/analytics/analytics.dart';
import 'package:nuvo/core/analytics/analytics_store.dart';

/// A sink that records what the wrapper would have sent PostHog — the tests
/// assert on the wire shape without ever touching the SDK.
class _RecordingSink implements AnalyticsSink {
  bool started = false;
  String? apiKey;
  String? host;
  String? distinctId;
  bool? optedOutAtStart;
  bool? lastOptedOut;
  final List<({String event, Map<String, Object> properties})> events = [];

  @override
  Future<void> start({
    required String apiKey,
    required String host,
    required String distinctId,
    required bool optedOut,
  }) async {
    started = true;
    this.apiKey = apiKey;
    this.host = host;
    this.distinctId = distinctId;
    optedOutAtStart = optedOut;
  }

  @override
  void capture(String event, Map<String, Object> properties) {
    events.add((event: event, properties: properties));
  }

  @override
  Future<void> setOptedOut(bool optedOut) async {
    lastOptedOut = optedOut;
  }

  @override
  Future<void> flush() async {}
}

Future<NuvoAnalytics> _analyticsWith(
  _RecordingSink sink, {
  AnalyticsStore? store,
  String apiKey = 'test_key',
}) => NuvoAnalytics.load(
  store: store ?? AnalyticsStore.memory(),
  sink: sink,
  apiKey: apiKey,
);

void main() {
  group('NuvoAnalytics wrapper', () {
    test('is a complete no-op without an API key', () async {
      final sink = _RecordingSink();
      final analytics = await _analyticsWith(sink, apiKey: '');

      expect(analytics.isConfigured, isFalse);
      expect(sink.started, isFalse);

      analytics.appOpened();
      analytics.raceJoined(via: 'code');
      await analytics.flush();
      expect(sink.events, isEmpty);
    });

    test('starts the sink with the compiled-in key and default host', () async {
      final sink = _RecordingSink();
      final analytics = await _analyticsWith(sink);

      expect(analytics.isConfigured, isTrue);
      expect(sink.started, isTrue);
      expect(sink.apiKey, 'test_key');
      expect(sink.host, 'https://us.i.posthog.com');
      // The distinct id is the anonymous install UUID — not an email,
      // username, or account id. UUID shape only; no identity fields.
      expect(sink.distinctId, analytics.distinctId);
      expect(
        sink.distinctId,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(sink.optedOutAtStart, isFalse);
    });

    test('opt-out stops capture until opted back in', () async {
      final sink = _RecordingSink();
      final analytics = await _analyticsWith(sink);

      analytics.appOpened();
      expect(sink.events, hasLength(1));

      await analytics.setEnabled(false);
      expect(analytics.enabled, isFalse);
      expect(sink.lastOptedOut, isTrue);

      analytics.appOpened();
      analytics.friendAdded();
      expect(sink.events, hasLength(1));

      await analytics.setEnabled(true);
      expect(sink.lastOptedOut, isFalse);
      analytics.appOpened();
      expect(sink.events, hasLength(2));
    });

    test('a persisted opt-out starts the sink already opted out', () async {
      String? written;
      final store = AnalyticsStore(
        read: () async => jsonEncode({'enabled': false, 'distinctId': 'id-1'}),
        write: (json) async => written = json,
      );
      final sink = _RecordingSink();
      final analytics = await _analyticsWith(sink, store: store);

      expect(sink.optedOutAtStart, isTrue);
      analytics.appOpened();
      expect(sink.events, isEmpty);
      // ensureLoaded eagerly re-persists what it read (so the install id is
      // durable) — the stored flag stays false.
      expect(written, contains('"enabled":false'));
      expect(analytics.enabled, isFalse);
    });

    test('every captured event only carries allowlisted properties', () async {
      final sink = _RecordingSink();
      final analytics = await _analyticsWith(sink);

      // Drive every named helper once — the helpers are the only event
      // producers in the app, so this is the whole vocabulary.
      analytics
        ..appOpened()
        ..signupStarted()
        ..signupCompleted()
        ..onboardingStepViewed('profile')
        ..onboardingCompleted()
        ..onboardingSkipped(step: 'story_p3')
        ..raceCreateStarted()
        ..raceCreated(
          format: 'timed_attempt',
          movementKind: 'preset',
          hasFinishLine: true,
          attemptDurationSeconds: 60,
        )
        ..raceJoined(via: 'invite')
        ..proofStarted(method: 'camera')
        ..proofSubmitted(format: 'first_to_goal', verified: true)
        ..proofRejected(reasonCode: 'ai_failed')
        ..attemptStarted()
        ..attemptCancelled()
        ..raceFinishedViewed(place: 2)
        ..friendAdded()
        ..crewJoined()
        ..notificationPermission(granted: false)
        // A stray/forged call still cannot smuggle keys through.
        ..capture('forged', {
          'email': 'someone@example.com',
          'user_id': 'u-1',
          'name': 'Nadia',
          'note': 'free text',
          'photo': 'bytes',
          'format': 'manual', // the one legitimate key survives
        });

      expect(sink.events, hasLength(19));
      for (final e in sink.events) {
        expect(
          e.properties.keys.toSet().difference(NuvoAnalytics.allowedProperties),
          isEmpty,
          reason: '${e.event} carried a non-allowlisted property',
        );
      }
      final forged = sink.events.last;
      expect(forged.event, 'forged');
      expect(forged.properties, {'format': 'manual'});
      // The required prop spellings land exactly as the event table specifies.
      final created = sink.events[7];
      expect(created.event, 'race_created');
      expect(created.properties, {
        'format': 'timed_attempt',
        'movement_kind': 'preset',
        'has_finish_line': true,
        'attempt_duration_s': 60,
      });
      expect(sink.events[8].properties, {'via': 'invite'});
      expect(sink.events[9].properties, {'method': 'camera'});
      expect(sink.events[10].properties, {
        'format': 'first_to_goal',
        'verified': true,
      });
      expect(sink.events[11].properties, {'reason_code': 'ai_failed'});
      expect(sink.events[14].properties, {'place': 2});
      expect(sink.events[17].properties, {'granted': false});
    });
  });

  group('AnalyticsStore', () {
    test('defaults to enabled and generates a stable anonymous id', () async {
      final store = AnalyticsStore.memory();
      await store.ensureLoaded();
      expect(store.enabled, isTrue);
      expect(store.distinctId, isNotEmpty);
      expect(store.distinctId, store.distinctId); // stable within the session
    });

    test('persists the toggle so the next load sees it', () async {
      String? blob;
      AnalyticsStore fresh() => AnalyticsStore(
        read: () async => blob,
        write: (json) async => blob = json,
      );

      final first = fresh();
      await first.ensureLoaded();
      final id = first.distinctId;
      await first.setEnabled(false);

      final second = fresh();
      await second.ensureLoaded();
      expect(second.enabled, isFalse);
      // The install id survives a reload — it is install-scoped, not session.
      expect(second.distinctId, id);

      await second.setEnabled(true);
      final third = fresh();
      await third.ensureLoaded();
      expect(third.enabled, isTrue);
    });

    test('falls back to defaults on a corrupt blob', () async {
      final store = AnalyticsStore(
        read: () async => '{not json',
        write: (_) async {},
      );
      await store.ensureLoaded();
      expect(store.enabled, isTrue);
      expect(store.distinctId, isNotEmpty);
    });
  });
}
