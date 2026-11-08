import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/analytics/analytics_service.dart';
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
  bool resetCalled = false;
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
  Future<void> reset() async {
    resetCalled = true;
  }

  @override
  Future<void> flush() async {}
}

class _ThrowingSink implements AnalyticsSink {
  @override
  Future<void> start({
    required String apiKey,
    required String host,
    required String distinctId,
    required bool optedOut,
  }) async => throw StateError('no posthog');

  @override
  void capture(String event, Map<String, Object> properties) {}

  @override
  Future<void> setOptedOut(bool optedOut) async {}

  @override
  Future<void> reset() async {}

  @override
  Future<void> flush() async {}
}

Future<AnalyticsService> _analyticsWith(
  _RecordingSink sink, {
  AnalyticsStore? store,
  String apiKey = 'test_key',
}) => AnalyticsService.init(
  store: store ?? AnalyticsStore.memory(),
  sink: sink,
  apiKey: apiKey,
);

/// A key-value map standing in for flutter_secure_storage.
Map<String, String> _backing() => <String, String>{};
AnalyticsStore _storeFrom(Map<String, String> backing) => AnalyticsStore(
  read: (k) async => backing[k],
  write: (k, v) async => backing[k] = v,
  delete: (k) async => backing.remove(k),
);

void main() {
  group('AnalyticsService', () {
    test('is a complete no-op without an API key', () async {
      final sink = _RecordingSink();
      final analytics = await _analyticsWith(sink, apiKey: '');

      expect(analytics.isConfigured, isFalse);
      expect(sink.started, isFalse);

      analytics.onboardingStarted();
      analytics.raceJoined();
      analytics.track('proof_result', {'outcome': 'verified'});
      await analytics.flush();
      expect(sink.events, isEmpty);
    });

    test('starts the sink with the key, default host, and anon id', () async {
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

      analytics.raceJoined();
      expect(sink.events, hasLength(1));

      await analytics.setEnabled(false);
      expect(analytics.enabled, isFalse);
      expect(sink.lastOptedOut, isTrue);

      analytics.raceJoined();
      analytics.pushRegistered();
      expect(sink.events, hasLength(1));

      await analytics.setEnabled(true);
      expect(sink.lastOptedOut, isFalse);
      analytics.raceJoined();
      expect(sink.events, hasLength(2));
    });

    test('a persisted opt-out starts the sink already opted out', () async {
      final backing = _backing()
        ..[AnalyticsStore.anonIdKey] = 'id-1'
        ..['nuvo_analytics_enabled'] = 'false';
      final sink = _RecordingSink();
      final analytics = await _analyticsWith(sink, store: _storeFrom(backing));

      expect(sink.optedOutAtStart, isTrue);
      expect(sink.distinctId, 'id-1'); // persisted id reused, not regenerated
      analytics.raceJoined();
      expect(sink.events, isEmpty);
      expect(analytics.enabled, isFalse);
    });

    test('every allowed event name is accepted, unknown names dropped',
        () async {
      final sink = _RecordingSink();
      final analytics = await _analyticsWith(sink);

      for (final event in AnalyticsService.allowedEvents) {
        analytics.track(event, {'method': 'email'});
      }
      analytics.track('app_opened'); // removed from the vocabulary
      analytics.track('friend_added');
      analytics.track('per_rep_detected');
      analytics.track('');

      expect(sink.events, hasLength(AnalyticsService.allowedEvents.length));
      for (final e in sink.events) {
        expect(AnalyticsService.allowedEvents, contains(e.event));
      }
    });

    test('every captured event only carries allowlisted properties', () async {
      final sink = _RecordingSink();
      final analytics = await _analyticsWith(sink);

      // Drive every named helper once — the helpers are the only event
      // producers in the app, so this is the whole vocabulary.
      analytics
        ..onboardingStarted()
        ..onboardingStepViewed(stepIndex: 0, stepName: 'profile')
        ..onboardingStepCompleted(
          stepIndex: 1,
          stepName: 'motion_consent',
          msOnStep: 1200,
        )
        ..onboardingAbandoned(stepIndex: 5, stepName: 'story_p3')
        ..onboardingCompleted()
        ..signupStarted(method: 'google')
        ..signupCompleted()
        ..signupFailed(reason: 'cancelled')
        ..raceCreateStarted()
        ..raceCreateCompleted(raceType: 'first_to_goal')
        ..raceCreateFailed(raceType: 'most_reps', error: 'http_500')
        ..raceInviteSent()
        ..raceJoined()
        ..raceJoinFailed(reason: 'invalid_code')
        ..raceStarted()
        ..raceCompleted()
        ..raceAbandoned()
        ..proofStarted(activityId: 'pushups')
        ..cameraReady(ms: 450)
        ..calibrationFailed(reason: 'no_person')
        ..proofResult(
          outcome: 'verified',
          detectedValue: 42,
          durationS: 30,
        )
        ..proofResult(outcome: 'rejected', failureReason: 'ai_failed')
        ..pushRegistered()
        ..pushRegisterFailed(reason: 'denied')
        ..notifOpened(type: 'race')
        ..screen('compete', ms: 88)
        ..apiError(route: 'submit_proof', status: 503);

      expect(sink.events, hasLength(27));
      for (final e in sink.events) {
        expect(
          e.properties.keys.toSet().difference(
            AnalyticsService.allowedProperties,
          ),
          isEmpty,
          reason: '${e.event} carried a non-allowlisted property',
        );
      }
      // The required prop spellings land exactly as the event table says.
      expect(sink.events[2].properties, {
        'step_index': 1,
        'step_name': 'motion_consent',
        'ms_on_step': 1200,
      });
      expect(sink.events[7].properties, {
        'method': 'google', // remembered from signupStarted
        'reason': 'cancelled',
      });
      expect(sink.events[18].properties, {'ms': 450});
      expect(sink.events[19].properties, {'reason': 'no_person'});
      expect(sink.events[20].properties, {
        'outcome': 'verified',
        'detected_value': '10-49', // bucketed, not the raw count
        'duration_s': 30,
      });
      expect(sink.events[21].properties, {
        'outcome': 'rejected',
        'failure_reason': 'ai_failed',
      });
      expect(sink.events[26].properties, {
        'route': 'submit_proof',
        'status': 503,
      });
    });

    test('PII properties are scrubbed by the allowlist', () async {
      final sink = _RecordingSink();
      final analytics = await _analyticsWith(sink);

      analytics.track('race_joined', {
        'email': 'someone@example.com',
        'user_id': 'u-1',
        'name': 'Nadia',
        'username': 'nadia_runs',
        'token': 'tok_abc',
        'note': 'free text the user typed',
        'photo': 'bytes',
        'pose': 'landmarks',
        'race_id': 'r-9', // even innocuous ids are off-list
      });

      expect(sink.events, hasLength(1));
      expect(sink.events.single.properties, isEmpty);
    });

    test('api_error is capped at five per session', () async {
      final sink = _RecordingSink();
      final analytics = await _analyticsWith(sink);

      for (var i = 0; i < 8; i++) {
        analytics.apiError(route: 'submit_proof', status: 500);
      }

      final apiErrors = sink.events.where((e) => e.event == 'api_error');
      expect(apiErrors, hasLength(5));
    });

    test('reset rotates the anonymous id and resets the sink', () async {
      final sink = _RecordingSink();
      final analytics = await _analyticsWith(sink);
      final firstId = analytics.distinctId;

      await analytics.reset();

      expect(analytics.distinctId, isNot(firstId));
      expect(sink.resetCalled, isTrue);
      // The opt-in choice survives — identity rotation is not a logout.
      expect(analytics.enabled, isTrue);
    });

    test('a sink that throws on start degrades to no-op', () async {
      final analytics = await AnalyticsService.init(
        store: AnalyticsStore.memory(),
        sink: _ThrowingSink(),
        apiKey: 'test_key',
      );
      expect(analytics.isConfigured, isFalse); // start failure ⇒ inert
      analytics.raceJoined(); // must not throw
    });
  });

  group('camera + proof events', () {
    test('camera_ready carries only the open-to-ready ms', () async {
      final sink = _RecordingSink();
      final analytics = await _analyticsWith(sink);

      analytics.cameraReady(ms: 812);

      expect(sink.events.single.event, 'camera_ready');
      expect(sink.events.single.properties, {'ms': 812});
    });

    test('calibration_failed carries only the reason enum', () async {
      final sink = _RecordingSink();
      final analytics = await _analyticsWith(sink);

      analytics.calibrationFailed(reason: 'missing_landmarks');

      expect(sink.events.single.event, 'calibration_failed');
      expect(sink.events.single.properties, {'reason': 'missing_landmarks'});
    });

    test('proof_result buckets detected_value and drops null props',
        () async {
      final sink = _RecordingSink();
      final analytics = await _analyticsWith(sink);

      analytics.proofResult(
        outcome: 'verified',
        detectedValue: 120,
        durationS: 45,
      );
      expect(sink.events.single.event, 'proof_result');
      expect(sink.events.single.properties, {
        'outcome': 'verified',
        'detected_value': '100+', // bucketed, never the raw count
        'duration_s': 45,
      });

      analytics.proofResult(
        outcome: 'submit_failed',
        failureReason: 'http_503',
      );
      expect(sink.events.last.properties, {
        'outcome': 'submit_failed',
        'failure_reason': 'http_503',
      });
    });
  });

  group('AnalyticsStore (secure-storage backed)', () {
    test('defaults to enabled and generates a stable anonymous id', () async {
      final store = AnalyticsStore.memory();
      await store.ensureLoaded();
      expect(store.enabled, isTrue);
      expect(store.distinctId, isNotEmpty);
      expect(store.distinctId, store.distinctId); // stable within the session
    });

    test('persists the toggle + id under their secure keys', () async {
      final backing = _backing();
      AnalyticsStore fresh() => _storeFrom(backing);

      final first = fresh();
      await first.ensureLoaded();
      final id = first.distinctId;
      expect(backing[AnalyticsStore.anonIdKey], id); // stored as anon_id
      await first.setEnabled(false);

      final second = fresh();
      await second.ensureLoaded();
      expect(second.enabled, isFalse);
      expect(second.distinctId, id); // install-scoped, survives reload

      await second.setEnabled(true);
      final third = fresh();
      await third.ensureLoaded();
      expect(third.enabled, isTrue);
    });

    test('rotating writes a fresh id to anon_id', () async {
      final backing = _backing();
      final store = _storeFrom(backing);
      await store.ensureLoaded();
      final first = store.distinctId;

      await store.rotateDistinctId();
      expect(store.distinctId, isNot(first));
      expect(backing[AnalyticsStore.anonIdKey], store.distinctId);
    });

    test('falls back to defaults on a read failure', () async {
      final store = AnalyticsStore(
        read: (_) async => throw StateError('keychain unavailable'),
        write: (_, _) async {},
      );
      await store.ensureLoaded();
      expect(store.enabled, isTrue);
      expect(store.distinctId, isNotEmpty);
    });
  });
}
