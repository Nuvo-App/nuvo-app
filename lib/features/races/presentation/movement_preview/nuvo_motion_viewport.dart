/// Stable presentation settings for a movement preview.
///
/// The factor enlarges the centered artboard window so transparent artboard
/// padding is cropped by the viewport. It is layout sizing, not a transform.
class NuvoMotionViewportConfig {
  const NuvoMotionViewportConfig({this.artboardExtentFactor = 1.75});

  final double artboardExtentFactor;
}
