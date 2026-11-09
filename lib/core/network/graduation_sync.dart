/// Network timing for the onboarding graduation write (not motion — kept
/// outside lib/features/onboarding so the motion lint stays strict).
abstract final class GraduationSync {
  /// How long the finish screen waits on the server before going ahead.
  static const Duration timeout = Duration(seconds: 8);

  /// Per-attempt timeout for background retries.
  static const Duration retryTimeout = Duration(seconds: 10);

  /// Background retry schedule after a failed / timed-out write.
  static const List<Duration> retryDelays = [
    Duration(seconds: 3),
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(seconds: 90),
  ];
}
