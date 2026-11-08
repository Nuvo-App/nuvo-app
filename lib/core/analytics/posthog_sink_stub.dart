import 'analytics_service.dart';

/// Non-io platforms (the web preview) never reach PostHog — analytics simply
/// reports unconfigured. dart.library.io picks posthog_sink_io.dart instead.
class _NullPosthogSink implements AnalyticsSink {
  const _NullPosthogSink();

  @override
  Future<void> start({
    required String apiKey,
    required String host,
    required String distinctId,
    required bool optedOut,
  }) async {}

  @override
  void capture(String event, Map<String, Object> properties) {}

  @override
  Future<void> setOptedOut(bool optedOut) async {}

  @override
  Future<void> reset() async {}

  @override
  Future<void> flush() async {}
}

AnalyticsSink createPosthogSink() => const _NullPosthogSink();
