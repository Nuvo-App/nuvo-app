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
/// The distinct id is a random install UUID persisted locally by
/// [AnalyticsStore] — never an email, name, account id, photo, or free text.
/// Session replay is off; there is no screen/text autocapture.
///
/// The Settings → APP → "Help improve Nuvo" toggle flips [setEnabled]; it
/// applies immediately (capture() drops events while off, and the sink is
/// told to opt out) and persists via the store.
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

  Future<void> flush();
}

/// The shared, app-wide facade. Emit through the named helpers — the property
/// allowlist makes PII inexpressible at the call site, and [capture] drops
/// anything that slips past them anyway.
class NuvoAnalytics {
  NuvoAnalytics._(this._store, [this._sink]);

  /// Inert default for the provider before [ensureAnalyticsLoaded] runs and
  /// for tests that never touch analytics.
  NuvoAnalytics.disabled() : this._(AnalyticsStore.memory());

  final AnalyticsStore _store;
  AnalyticsSink? _sink;

  /// Every property key an event may ever carry. Anything else is dropped in
  /// [capture] — tests assert this list is the whole vocabulary.
  static const Set<String> allowedProperties = {
    'step',
    'format',
    'movement_kind',
    'has_finish_line',
    'attempt_duration_s',
    'via',
    'method',
    'verified',
    'reason_code',
    'place',
    'granted',
  };

  /// Loads the persisted opt-in flag + install id, then starts the sink when
  /// a key was compiled in. A sink that fails to start degrades the whole
  /// service to a no-op rather than risking launch.
  static Future<NuvoAnalytics> load({
    AnalyticsStore? store,
    AnalyticsSink? sink,
    String? apiKey,
    String? host,
  }) async {
    final s = store ?? AnalyticsStore();
    await s.ensureLoaded();
    final key = apiKey ?? _kPostHogApiKey;
    final resolved = key.isEmpty ? null : (sink ?? createPosthogSink());
    final analytics = NuvoAnalytics._(s, resolved);
    if (resolved != null) {
      try {
        await resolved.start(
          apiKey: key,
          host: host ?? _kPostHogHost,
          distinctId: s.distinctId,
          optedOut: !s.enabled,
        );
      } catch (_) {
        analytics._sink = null;
      }
    }
    return analytics;
  }

  /// Whether PostHog is live — a compiled-in key plus a started sink.
  bool get isConfigured => _sink != null;

  /// The user's opt-in state — Settings shows this; capture() honors it.
  bool get enabled => _store.enabled;

  /// Anonymous install id (stable across launches; random, not account-tied).
  String get distinctId => _store.distinctId;

  /// Opt in or out right now — drops/permits capture immediately, persists,
  /// and mirrors into the SDK so queued events don't slip out later.
  Future<void> setEnabled(bool enabled) async {
    await _store.setEnabled(enabled);
    try {
      await _sink?.setOptedOut(!enabled);
    } catch (_) {}
  }

  void capture(String event, [Map<String, Object?> properties = const {}]) {
    final sink = _sink;
    if (!_store.enabled || sink == null) return;
    try {
      sink.capture(event, _sanitize(properties));
    } catch (_) {}
  }

  /// Strip nulls and every key outside [allowedProperties] — the last PII
  /// line of defense behind the typed helpers.
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

  // ── Product events (docs/analytics/POSTHOG.md keeps the table) ───────────

  /// Cold launch — fired once per process from the app shell.
  void appOpened() => capture('app_opened');

  /// Sign-up intent begun (sign-up CTA on welcome, email/Google/Apple while
  /// in sign-up mode).
  void signupStarted() => capture('signup_started');

  /// Auth resolved to authenticated while the intent was sign-up.
  void signupCompleted() => capture('signup_completed');

  /// Onboarding is being rebuilt — the named helpers below are the seam so
  /// the events move with the screens.
  void onboardingStepViewed(String step) =>
      capture('onboarding_step_viewed', {'step': step});

  void onboardingCompleted() => capture('onboarding_completed');

  void onboardingSkipped({required String step}) =>
      capture('onboarding_skipped', {'step': step});

  /// Composer opened — the start of the create funnel.
  void raceCreateStarted() => capture('race_create_started');

  /// [movementKind]: 'preset' | 'custom' | 'goal'.
  /// [hasFinishLine]: the race has a defined end — a goal target or an end date.
  void raceCreated({
    required String format,
    required String movementKind,
    required bool hasFinishLine,
    int? attemptDurationSeconds,
  }) => capture('race_created', {
    'format': format,
    'movement_kind': movementKind,
    'has_finish_line': hasFinishLine,
    'attempt_duration_s': attemptDurationSeconds,
  });

  /// [via]: 'code' | 'invite' | 'open' | 'link' | 'notification'.
  void raceJoined({required String via}) => capture('race_joined', {'via': via});

  /// [method]: 'camera' | 'photo'.
  void proofStarted({required String method}) =>
      capture('proof_started', {'method': method});

  /// [format]: the race's backend format string.
  /// [verified]: the submitted proof landed verified (not pending/failed).
  void proofSubmitted({required String format, required bool verified}) =>
      capture('proof_submitted', {'format': format, 'verified': verified});

  /// [reasonCode]: `http_<status>` | `error` | the proof's failed status.
  void proofRejected({required String reasonCode}) =>
      capture('proof_rejected', {'reason_code': reasonCode});

  /// A best-single / timed attempt opened server-side.
  void attemptStarted() => capture('attempt_started');

  /// An open attempt released with no proof bound (cancelled take).
  void attemptCancelled() => capture('attempt_cancelled');

  /// [place]: the viewer's final rank; 0 when they aren't in the standings.
  void raceFinishedViewed({required int place}) =>
      capture('race_finished_viewed', {'place': place});

  /// A friend link formed — request accepted (either direction), not merely sent.
  void friendAdded() => capture('friend_added');

  /// Joined a named crew (code or invite).
  void crewJoined() => capture('crew_joined');

  /// OS notification permission resolved — [granted] is the real outcome.
  void notificationPermission({required bool granted}) =>
      capture('notification_permission', {'granted': granted});
}

/// The live instance — replaced by [ensureAnalyticsLoaded] before runApp.
NuvoAnalytics _sharedAnalytics = NuvoAnalytics.disabled();

/// Called from main() before the first frame so the persisted opt-out and
/// install id are already resolved when anything emits.
Future<void> ensureAnalyticsLoaded({AnalyticsStore? store}) async {
  _sharedAnalytics = await NuvoAnalytics.load(store: store);
}

/// The analytics facade. Tests override with [FakeNuvoAnalytics].
final analyticsProvider = Provider<NuvoAnalytics>(
  (_) => _sharedAnalytics,
);

/// Test fake — records events locally, never touches the SDK. Widget tests
/// override [analyticsProvider] with this; unit tests drive [NuvoAnalytics]
/// directly with a recording [AnalyticsSink].
class FakeNuvoAnalytics extends NuvoAnalytics {
  FakeNuvoAnalytics({this.enabled = true}) : super.disabled();

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
  void capture(String event, [Map<String, Object?> properties = const {}]) {
    if (!enabled) return;
    events.add((event: event, properties: Map.of(properties)));
  }
}
