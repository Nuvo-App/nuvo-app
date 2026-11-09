import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Onboarding-v2 sound vocabulary — soft tick on press, rising chime on XP,
/// fanfare on level-up.
///
/// Spec: "Default on only in onboarding + level-up, respects silent switch,
/// each asset <60KB." No audio package exists in pubspec.yaml (and the file
/// is off-limits), so the shipped implementation is [NoopNuvoSounds] — a
/// safe no-op with the full call surface. When a player package lands, a
/// real implementation drops in behind this interface without touching any
/// call site; it should read `enabled` and hand the OS audio session the
/// ambient category so the hardware silent switch still wins.
abstract class NuvoSounds {
  const NuvoSounds();

  /// Soft tick on a physical press.
  void pressTick();

  /// Rising chime when XP lands in the rail.
  void xpChime();

  /// Fanfare at level-up.
  void fanfare();

  /// Whether sounds are allowed to play. Default on ONLY inside onboarding
  /// + the level-up moment — callers outside the flow must not construct or
  /// enable it. The OS silent switch additionally gates real playback.
  bool get enabled;
}

/// The no-op implementation — silently swallows every cue. Selected
/// unconditionally today since no audio backend is bundled.
class NoopNuvoSounds extends NuvoSounds {
  const NoopNuvoSounds();

  @override
  void pressTick() {}

  @override
  void xpChime() {}

  @override
  void fanfare() {}

  @override
  bool get enabled => false;
}

/// The app's sound surface for onboarding v2. Overridden in tests; when a
/// real player exists the provider swaps the implementation, nothing else.
final nuvoSoundsProvider = Provider<NuvoSounds>((_) => const NoopNuvoSounds());
