import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'analytics_store.dart';
import 'posthog_sink_stub.dart'
    if (dart.library.io) 'posthog_sink_io.dart';

/// PostHog product analytics — compile-time configured, anonymous by design.
///
/// Configuration is `--dart-define` only, never source:
///   --dart-define=POSTHOG_API_KEY=`<key>`
///   --dart-define=POSTHOG_HOST=https://us.i.posthog.com   (optional; default shown)
///
/// An empty key leaves analytics a complete no-op: no SDK init, no events.
/// The distinct id is a random install UUID persisted in flutter_secure_storage
/// (`anon_id`) by [AnalyticsStore] — never an email, name, account id, photo,
/// pose landmark, or free text. Session replay is off in the Dart config and
/// `com.posthog.posthog.AUTO_INIT` is false in the iOS plist + Android
/// manifest, so the SDK can only ever run with that config; no screen/text
/// autocapture exists anywhere.
///
/// Nothing starts until consent is resolved: [init] awaits the persisted
/// opt-in flag before the sink starts, and [track] drops events until init
/// finished. The Settings → APP → "Help improve Nuvo (usage analytics)"
/// toggle flips [setEnabled]; it applies immediately and persists. It is a
/// separate consent from terms acceptance, age attestation, and
/// motion-training consent — those stay on the server and are never read here.
const String _kPostHogApiKey = String.fromEnvironment('POSTHOG_API_KEY');
const String _kPostHogHost = String.fromEnvironment(
  'POSTHOG_HOST',
  defaultValue: 'https://us.i.posthog.com',
);

/// Event destinations behind the wrapper — PostHog in production, a
/// recording fake in tests. Implemented in posthog_sink_io.dart; on
/// platforms without dart:io (web preview) the stub no-ops.
abstract class AnalyticsSink {
  /// Configure the SDK once per launch. Must not throw — the caller treats a
  /// failure as "not configured".
  Future<void> start({
    required String apiKey,
    required String host,
    required String distinctId,
    required bool optedOut,
  });

  void capture(String event, Map<String, Object> properties);

  Future<void> setOptedOut(bool optedOut);

  /// Rotate identity — the next distinct id is a fresh anonymous UUID.
  Future<void> reset();

  Future<void> flush();
}

/// The shared, app-wide facade. Emit through [track]/[screen] or the named
/// helpers — the event + property allowlists make PII inexpressible at the
/// call site, and both lists are enforced again inside [track].
class AnalyticsService {
  AnalyticsService._(this._store, [this._sink]);

  /// Inert default for the provider before [init] runs and for tests.
  AnalyticsService.disabled() : this._(AnalyticsStore.memory());

  final AnalyticsStore _store;
  AnalyticsSink? _sink;
  bool _initialized = false;

  /// api_error is capped per session — a red screen of failures must not
  /// turn into a red screen of events.
  static const _maxApiErrorsPerSession = 5;
  int _apiErrorCount = 0;

  /// Funnel state the helpers need across calls — no PII, just clocks and
  /// enum strings.
  String? _signupMethod;
  DateTime? _raceCreateStartedAt;
  DateTime? _attemptStartedAt;

  /// Every event name that may ever fire. Anything else is dropped in
  /// [track] — tests assert this list is the whole vocabulary.
  static const Set<String> allowedEvents = {
    'onboarding_started',
    'onboarding_step_viewed',
    'onboarding_step_completed',
    'onboarding_abandoned',
    'onboarding_completed',
    'signup_started',
    'signup_completed',
    'signup_failed',
    'race_create_started',
    'race_create_completed',
    'race_create_failed',
    'race_invite_sent',
    'race_joined',
    'race_join_failed',
    'race_started',
    'race_completed',
    'race_abandoned',
    'proof_started',
    'camera_ready',
    'calibration_failed',
    'proof_result',
    'push_registered',
    'push_register_failed',
    'notif_opened',
    'screen_loaded',
    'api_error',
  };

  /// Every property key an event may ever carry — enums, ints, booleans only.
  /// Never an email, name, user id, token, free text, or media value.
  static const Set<String> allowedProperties = {
    'step_index',
    'step_name',
    'ms_on_step',
    'method',
    'reason',
    'race_type',
    'ms',
    'error',
    'activity_id',
    'outcome',
    'failure_reason',
    'detected_value',
    'duration_s',
    'type',
    'screen',
    'route',
    'status',
  };

  /// Loads the persisted opt-in flag + install id (consent resolved), then
  /// starts the sink when a key was compiled in. A sink that fails to start
  /// degrades the whole service to a no-op rather than risking launch.
  static Future<AnalyticsService> init({
    AnalyticsStore? store,
    AnalyticsSink? sink,
    String? apiKey,
    String? host,
  }) async {
    final s = store ?? AnalyticsStore();
    await s.ensureLoaded(); // consent resolved — nothing starts before this
    final key = apiKey ?? _kPostHogApiKey;
    final resolved = key.isEmpty ? null : (sink ?? createPosthogSink());
    final service = AnalyticsService._(s, resolved);
    if (resolved != null) {
      try {
        await resolved.start(
          apiKey: key,
          host: host ?? _kPostHogHost,
          distinctId: s.distinctId,
          optedOut: !s.enabled,
        );
      } catch (e) {
        service._sink = null;
        _log('sink start failed (${e.runtimeType}) — analytics off');
      }
    }
    service._initialized = true;
    return service;
  }

  /// Whether PostHog is live — a compiled-in key plus a started sink.
  bool get isConfigured => _sink != null;

  /// The user's opt-in state — Settings shows this; track() honors it.
  bool get enabled => _store.enabled;

  /// Anonymous install id (stable across launches; random, not account-tied).
  String get distinctId => _store.distinctId;

  /// Opt in or out right now — drops/permits capture immediately, persists,
  /// and mirrors into the SDK so queued events don't slip out later.
  Future<void> setEnabled(bool enabled) async {
    try {
      await _store.setEnabled(enabled);
      await _sink?.setOptedOut(!enabled);
    } catch (e) {
      _log('setEnabled failed (${e.runtimeType})');
    }
  }

  /// Rotate the anonymous identity — a fresh UUID, plus an SDK reset so no
  /// queued state carries over. The opt-in choice is the user's and stays.
  Future<void> reset() async {
    try {
      await _store.rotateDistinctId();
      await _sink?.reset();
    } catch (e) {
      _log('reset failed (${e.runtimeType})');
    }
  }

  /// The one primitive every event flows through. Unknown event names and
  /// non-allowlisted properties are dropped — the PII line of defense.
  void track(String event, [Map<String, Object?> properties = const {}]) {
    final sink = _sink;
    if (!_initialized || !_store.enabled || sink == null) return;
    if (!allowedEvents.contains(event)) {
      _log('dropped unknown event "$event"');
      return;
    }
    try {
      sink.capture(event, _sanitize(properties));
    } catch (e) {
      _log('capture "$event" failed (${e.runtimeType})');
    }
  }

  /// Manual screen event — the only "screen" tracking that exists. [ms] is
  /// the measured load time the caller observed; omit when unmeasured.
  void screen(String name, {int? ms}) =>
      track('screen_loaded', {'screen': name, 'ms': ms});

  /// Strip nulls and every key outside [allowedProperties].
  static Map<String, Object> _sanitize(Map<String, Object?> properties) {
    final out = <String, Object>{};
    for (final entry in properties.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value == null || !allowedProperties.contains(key)) continue;
      out[key] = value;
    }
    return out;
  }

  Future<void> flush() async {
    try {
      await _sink?.flush();
    } catch (_) {}
  }

  static void _log(String message) {
    if (kDebugMode) debugPrint('[Analytics] $message');
  }

  // ── Onboarding funnel ───────────────────────────────────────────────────
  // Steps are (index, name): 0 profile, 1 motion_consent, 2..9 story pages,
  // 10 notifications. docs/ANALYTICS.md keeps the table.

  void onboardingStarted() => track('onboarding_started');

  void onboardingStepViewed({required int stepIndex, required String stepName}) =>
      track('onboarding_step_viewed', {
        'step_index': stepIndex,
        'step_name': stepName,
      });

  void onboardingStepCompleted({
    required int stepIndex,
    required String stepName,
    int? msOnStep,
  }) => track('onboarding_step_completed', {
    'step_index': stepIndex,
    'step_name': stepName,
    'ms_on_step': msOnStep,
  });

  /// Left the flow before [onboardingCompleted] — e.g. the story "Skip".
  void onboardingAbandoned({int? stepIndex, String? stepName}) => track(
    'onboarding_abandoned',
    {'step_index': stepIndex, 'step_name': stepName},
  );

  void onboardingCompleted() => track('onboarding_completed');

  // ── Signup funnel ───────────────────────────────────────────────────────

  /// [method]: 'apple' | 'google' | 'email'. Remembered so completed/failed
  /// carry the same method without the auth seam needing to know it.
  void signupStarted({String? method}) {
    _signupMethod = method;
    track('signup_started', {'method': method});
  }

  void signupCompleted() =>
      track('signup_completed', {'method': _signupMethod});

  /// [reason] enum: 'cancelled' | 'error' | `http_<status>`.
  void signupFailed({String? method, required String reason}) => track(
    'signup_failed',
    {'method': method ?? _signupMethod, 'reason': reason},
  );

  // ── Race create / join ──────────────────────────────────────────────────

  /// Composer opened — starts the create-funnel clock for the ms props.
  void raceCreateStarted() {
    _raceCreateStartedAt = DateTime.now();
    track('race_create_started');
  }

  /// [raceType]: the race's backend format string.
  void raceCreateCompleted({required String raceType}) => track(
    'race_create_completed',
    {'race_type': raceType, 'ms': _elapsedMs(_raceCreateStartedAt)},
  );

  /// [error] enum: `http_<status>` | 'error'.
  void raceCreateFailed({String? raceType, required String error}) => track(
    'race_create_failed',
    {
      'race_type': raceType,
      'ms': _elapsedMs(_raceCreateStartedAt),
      'error': error,
    },
  );

  /// A race invite code was created/shared from the invite sheet.
  void raceInviteSent() => track('race_invite_sent');

  void raceJoined() => track('race_joined');

  /// [reason] enum: `http_<status>` | 'error' | 'invalid_code'.
  void raceJoinFailed({required String reason}) =>
      track('race_join_failed', {'reason': reason});

  // ── Race lifecycle (the user's own participation) ───────────────────────

  /// An attempt window opened — the user's run has started.
  void raceStarted() {
    _attemptStartedAt = DateTime.now();
    track('race_started');
  }

  /// The submit that finished the user's race (result.raceCompleted).
  void raceCompleted() => track('race_completed');

  /// An open attempt released with no proof bound — abandoned take.
  void raceAbandoned() => track('race_abandoned');

  // ── Proof pipeline ──────────────────────────────────────────────────────

  /// [activityId]: the race's activityId/aiActivityType — a movement enum,
  /// never a user value.
  void proofStarted({required String activityId}) =>
      track('proof_started', {'activity_id': activityId});

  /// The AI Motion camera reached its live ready state — [ms] is the
  /// screen-open → first-preview latency, fired once per open.
  void cameraReady({int? ms}) => track('camera_ready', {'ms': ms});

  /// A camera take ended unverified. [reason] is the verifier's internal
  /// failure enum (`missing_landmarks`, `hold_broken`, `shot_not_confirmed`,
  /// …), never a user-facing message.
  void calibrationFailed({String? reason}) =>
      track('calibration_failed', {'reason': reason});

  /// [outcome]: 'verified' | 'needs_review' | 'pending' | 'rejected' |
  ///   'submit_failed'.
  /// [failureReason] enum: proof status or `http_<status>` — never a message.
  /// [detectedValue] bucket: '0' | '1-9' | '10-49' | '50-99' | '100+'.
  /// [durationS]: seconds from attempt open to this result.
  void proofResult({
    required String outcome,
    String? failureReason,
    int? detectedValue,
    int? durationS,
  }) => track('proof_result', {
    'outcome': outcome,
    'failure_reason': failureReason,
    'detected_value':
        detectedValue == null ? null : _bucket(detectedValue),
    'duration_s': durationS,
  });

  /// Seconds since [raceStarted] opened the attempt — proof duration.
  int? elapsedAttemptSeconds() => _attemptStartedAt == null
      ? null
      : DateTime.now().difference(_attemptStartedAt!).inSeconds;

  static String _bucket(int v) => switch (v) {
    <= 0 => '0',
    < 10 => '1-9',
    < 50 => '10-49',
    < 100 => '50-99',
    _ => '100+',
  };

  // ── Push ────────────────────────────────────────────────────────────────

  /// The device token reached the server.
  void pushRegistered() => track('push_registered');

  /// Permission/registration failed. [reason] enum: 'denied' | 'error'.
  void pushRegisterFailed({String? reason}) =>
      track('push_register_failed', {'reason': reason});

  /// [type]: the push payload's destType (e.g. 'race', 'crew') — an enum,
  /// never the notification body.
  void notifOpened({required String type}) =>
      track('notif_opened', {'type': type});

  // ── Errors (capped) ─────────────────────────────────────────────────────

  /// [route]: the logical API route tag ('submit_proof', 'join_race', …).
  /// Capped at [_maxApiErrorsPerSession] per launch.
  void apiError({required String route, int? status}) {
    if (_apiErrorCount >= _maxApiErrorsPerSession) return;
    _apiErrorCount++;
    track('api_error', {'route': route, 'status': status});
  }

  static int? _elapsedMs(DateTime? from) =>
      from == null ? null : DateTime.now().difference(from).inMilliseconds;
}

/// The live instance — replaced by [ensureAnalyticsLoaded] before runApp.
AnalyticsService _sharedAnalytics = AnalyticsService.disabled();

/// Called from main() before the first frame so the persisted opt-out and
/// install id are already resolved when anything emits.
Future<void> ensureAnalyticsLoaded({AnalyticsStore? store}) async {
  _sharedAnalytics = await AnalyticsService.init(store: store);
}

/// The analytics facade. Tests override with [FakeAnalyticsService].
final analyticsProvider = Provider<AnalyticsService>(
  (_) => _sharedAnalytics,
);

/// Test fake — records events locally, never touches the SDK. Widget tests
/// override [analyticsProvider] with this; unit tests drive
/// [AnalyticsService] directly with a recording [AnalyticsSink].
class FakeAnalyticsService extends AnalyticsService {
  FakeAnalyticsService({this.enabled = true}) : super.disabled();

  final List<({String event, Map<String, Object?> properties})> events = [];

  @override
  bool isConfigured = true;

  @override
  bool enabled;

  @override
  Future<void> setEnabled(bool enabled) async {
    this.enabled = enabled;
  }

  @override
  void track(String event, [Map<String, Object?> properties = const {}]) {
    if (!enabled) return;
    events.add((event: event, properties: Map.of(properties)));
  }
}
