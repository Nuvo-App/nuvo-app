class AssetPaths {
  AssetPaths._();

  static const nuvoLogo = 'assets/branding/trans.png';

  static const splashFrameCount = 91;
  static const splashFrameDir = 'assets/animations/splash';

  static String splashFrame(int index) =>
      '$splashFrameDir/frame_${index.toString().padLeft(3, '0')}.png';
}
