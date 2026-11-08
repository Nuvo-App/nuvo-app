import 'package:posthog_flutter/posthog_flutter.dart';

import 'analytics.dart';

/// PostHog-backed [AnalyticsSink]. Keeps every posthog_flutter call behind
/// the wrapper so tests and opted-out users never touch the SDK.
///
/// Session replay is left at the SDK default — OFF — and is never enabled
/// here. No screen() calls exist anywhere, so there is no screen-name or
/// text autocapture either.
class _PosthogAnalyticsSink implements AnalyticsSink {
  bool _ready = false;

  @override
  Future<void> start({
    required String apiKey,
    required String host,
    required String distinctId,
    required bool optedOut,
  }) async {
    final config = PostHogConfig(apiKey)
      ..host = host
      ..captureApplicationLifecycleEvents = false
      // The persisted "Help improve Nuvo" choice — the SDK starts opted out,
      // so nothing can queue before the flag is read.
      ..optOut = optedOut;
    await Posthog().setup(config);
    // The anonymous install id becomes the distinct id — never the account
    // id, email, or name. No user properties are attached, so the person
    // record stays anonymous.
    await Posthog().identify(userId: distinctId);
    _ready = true;
  }

  @override
  void capture(String event, Map<String, Object> properties) {
    if (!_ready) return;
    Posthog().capture(
      eventName: event,
      properties: properties.isEmpty ? null : properties,
    );
  }

  /// The SDK's opt-out/opt-in pair — disable() drops queued events and stops
  /// all capture; enable() reopens it.
  @override
  Future<void> setOptedOut(bool optedOut) =>
      optedOut ? Posthog().disable() : Posthog().enable();

  @override
  Future<void> flush() => Posthog().flush();
}

AnalyticsSink createPosthogSink() => _PosthogAnalyticsSink();
