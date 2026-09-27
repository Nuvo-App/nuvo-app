/// Compact timing profile derived from real Nuvo Jumping Jack sessions.
///
/// The profile is semantic: it contains normalized motion progress, not a
/// person's coordinates. The locked Rive endpoints remain the source of
/// appearance; these samples only determine when each channel moves during a
/// closed -> open -> closed repetition.
///
/// Source data (read-only Cloudflare R2 motion-session artifacts):
/// - ms_2ef07c38d7204c3ba36564d06365af7a: 9 completed cycles
/// - ms_8d59320ff9764fcbba37bb0c0bf4636b: 5 completed cycles
/// - ms_1a74cfee7f59482780ceace059464b61: 2 completed cycles
///
/// Each cycle was bounded by the existing Jumping Jacks verifier's
/// rep-counted closed transitions, normalized to 17 phase samples, and
/// aggregated with the median. A light three-sample temporal smoother was
/// applied after aggregation to reduce landmark jitter without changing the
/// phase shape.
class JumpingJackHumanMotionProfile {
  const JumpingJackHumanMotionProfile._();

  /// Slightly relaxed playback based on the Cloudflare median of 866 ms.
  static const cycleDuration = Duration(milliseconds: 1000);

  /// Normalized arm-raise progress over one complete repetition.
  static const armRaise = <double>[
    0.000,
    0.000,
    0.000,
    0.000,
    0.178,
    0.403,
    0.658,
    0.841,
    0.945,
    0.982,
    0.993,
    0.963,
    0.857,
    0.671,
    0.428,
    0.205,
    0.014,
  ];

  /// Normalized elbow-bend progress over one complete repetition.
  static const elbowBend = <double>[
    0.000,
    0.000,
    0.000,
    0.057,
    0.162,
    0.324,
    0.515,
    0.715,
    0.887,
    0.972,
    0.978,
    0.832,
    0.630,
    0.385,
    0.212,
    0.081,
    0.000,
  ];

  /// Normalized ankle-spread progress over one complete repetition.
  static const legSpread = <double>[
    0.000,
    0.000,
    0.000,
    0.024,
    0.130,
    0.315,
    0.565,
    0.793,
    0.941,
    1.000,
    0.979,
    0.909,
    0.783,
    0.584,
    0.351,
    0.144,
    0.005,
  ];

  /// Normalized upward root displacement. It is mapped to the existing
  /// display-only root amplitude; it never changes a Rive property.
  static const rootRise = <double>[
    0.000,
    0.219,
    0.292,
    0.194,
    0.072,
    0.024,
    0.157,
    0.411,
    0.710,
    0.911,
    0.934,
    0.724,
    0.413,
    0.136,
    0.022,
    0.000,
    0.000,
  ];

  /// Smoothly samples measured data without replacing it with a designed
  /// ease-in/ease-out curve. Catmull-Rom interpolation is allocation-free;
  /// clamping prevents detector noise from overshooting the channel range.
  static double sample(List<double> samples, double phase) {
    final normalized = phase.isFinite ? phase.clamp(0.0, 1.0) : 0.0;
    final position = normalized * (samples.length - 1);
    final index = position.floor();
    if (index >= samples.length - 1) return samples.last;

    final t = position - index;
    final t2 = t * t;
    final t3 = t2 * t;
    final p0 = samples[index == 0 ? 0 : index - 1];
    final p1 = samples[index];
    final p2 = samples[index + 1];
    final p3 = samples[index + 2 < samples.length ? index + 2 : index + 1];
    final value =
        0.5 *
        ((2 * p1) +
            (-p0 + p2) * t +
            (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
            (-p0 + 3 * p1 - 3 * p2 + p3) * t3);
    return value.clamp(0.0, 1.0);
  }
}
