import 'package:flutter/material.dart';

enum NuvoPreviewStyle {
  startingLine,
  trackside,
  crewMomentum;

  String get name => switch (this) {
    startingLine => 'Starting Line',
    trackside => 'Trackside',
    crewMomentum => 'Crew Momentum',
  };

  String get description => switch (this) {
    startingLine => 'Open progress view with a clear finish line',
    trackside => 'Dark race view with your crew on the track',
    crewMomentum => 'Warm social view centered on crew progress',
  };
}

@immutable
class NuvoVisualTheme extends ThemeExtension<NuvoVisualTheme> {
  const NuvoVisualTheme({
    required this.style,
    required this.page,
    required this.surface,
    required this.surfaceMuted,
    required this.ink,
    required this.mutedInk,
    required this.border,
    required this.action,
    required this.accent,
    required this.secondaryAccent,
    required this.navigation,
    required this.onNavigation,
    required this.hero,
    required this.onHero,
    required this.cardRadius,
    required this.heroRadius,
    required this.darkHero,
    required this.floatingNavigation,
  });

  final NuvoPreviewStyle style;
  final Color page;
  final Color surface;
  final Color surfaceMuted;
  final Color ink;
  final Color mutedInk;
  final Color border;
  final Color action;
  final Color accent;
  final Color secondaryAccent;
  final Color navigation;
  final Color onNavigation;
  final Color hero;
  final Color onHero;
  final double cardRadius;
  final double heroRadius;
  final bool darkHero;
  final bool floatingNavigation;

  static const startingLine = NuvoVisualTheme(
    style: NuvoPreviewStyle.startingLine,
    page: Color(0xFFFCFCFB),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF0F3F8),
    ink: Color(0xFF07152C),
    mutedInk: Color(0xFF69788C),
    border: Color(0xFFDDE3EB),
    action: Color(0xFF176BEE),
    accent: Color(0xFF176BEE),
    secondaryAccent: Color(0xFF7D8DA2),
    navigation: Color(0xFFFFFFFF),
    onNavigation: Color(0xFF07152C),
    hero: Color(0xFFFFFFFF),
    onHero: Color(0xFF07152C),
    cardRadius: 18,
    heroRadius: 22,
    darkHero: false,
    floatingNavigation: false,
  );

  static const trackside = NuvoVisualTheme(
    style: NuvoPreviewStyle.trackside,
    page: Color(0xFFF4F6F9),
    surface: Color(0xFFFDFDFD),
    surfaceMuted: Color(0xFFE9EDF3),
    ink: Color(0xFF07152C),
    mutedInk: Color(0xFF657286),
    border: Color(0xFFD9E0E9),
    action: Color(0xFF2A82FC),
    accent: Color(0xFF2A82FC),
    secondaryAccent: Color(0xFF8D98A8),
    navigation: Color(0xFF09223F),
    onNavigation: Color(0xFFF7F9FC),
    hero: Color(0xFF09223F),
    onHero: Color(0xFFF7F9FC),
    cardRadius: 16,
    heroRadius: 0,
    darkHero: true,
    floatingNavigation: false,
  );

  static const crewMomentum = NuvoVisualTheme(
    style: NuvoPreviewStyle.crewMomentum,
    page: Color(0xFFFBF9F7),
    surface: Color(0xFFFBF9F7),
    surfaceMuted: Color(0xFFF0ECE5),
    ink: Color(0xFF07152C),
    mutedInk: Color(0xFF6F7886),
    border: Color(0xFFDDDAD6),
    action: Color(0xFF2A82FC),
    accent: Color(0xFF2A82FC),
    secondaryAccent: Color(0xFF78917A),
    navigation: Color(0xFFFBF9F7),
    onNavigation: Color(0xFF07152C),
    hero: Color(0xFFFBF9F7),
    onHero: Color(0xFF07152C),
    cardRadius: 20,
    heroRadius: 28,
    darkHero: false,
    floatingNavigation: false,
  );

  static NuvoVisualTheme forStyle(NuvoPreviewStyle style) => switch (style) {
    NuvoPreviewStyle.startingLine => startingLine,
    NuvoPreviewStyle.trackside => trackside,
    NuvoPreviewStyle.crewMomentum => crewMomentum,
  };

  static NuvoVisualTheme of(BuildContext context) =>
      Theme.of(context).extension<NuvoVisualTheme>() ?? startingLine;

  @override
  NuvoVisualTheme copyWith({
    NuvoPreviewStyle? style,
    Color? page,
    Color? surface,
    Color? surfaceMuted,
    Color? ink,
    Color? mutedInk,
    Color? border,
    Color? action,
    Color? accent,
    Color? secondaryAccent,
    Color? navigation,
    Color? onNavigation,
    Color? hero,
    Color? onHero,
    double? cardRadius,
    double? heroRadius,
    bool? darkHero,
    bool? floatingNavigation,
  }) {
    return NuvoVisualTheme(
      style: style ?? this.style,
      page: page ?? this.page,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      ink: ink ?? this.ink,
      mutedInk: mutedInk ?? this.mutedInk,
      border: border ?? this.border,
      action: action ?? this.action,
      accent: accent ?? this.accent,
      secondaryAccent: secondaryAccent ?? this.secondaryAccent,
      navigation: navigation ?? this.navigation,
      onNavigation: onNavigation ?? this.onNavigation,
      hero: hero ?? this.hero,
      onHero: onHero ?? this.onHero,
      cardRadius: cardRadius ?? this.cardRadius,
      heroRadius: heroRadius ?? this.heroRadius,
      darkHero: darkHero ?? this.darkHero,
      floatingNavigation: floatingNavigation ?? this.floatingNavigation,
    );
  }

  @override
  NuvoVisualTheme lerp(
    covariant ThemeExtension<NuvoVisualTheme>? other,
    double t,
  ) {
    if (other is! NuvoVisualTheme) return this;
    return NuvoVisualTheme(
      style: t < 0.5 ? style : other.style,
      page: Color.lerp(page, other.page, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      mutedInk: Color.lerp(mutedInk, other.mutedInk, t)!,
      border: Color.lerp(border, other.border, t)!,
      action: Color.lerp(action, other.action, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      secondaryAccent: Color.lerp(secondaryAccent, other.secondaryAccent, t)!,
      navigation: Color.lerp(navigation, other.navigation, t)!,
      onNavigation: Color.lerp(onNavigation, other.onNavigation, t)!,
      hero: Color.lerp(hero, other.hero, t)!,
      onHero: Color.lerp(onHero, other.onHero, t)!,
      cardRadius: _lerpDouble(cardRadius, other.cardRadius, t),
      heroRadius: _lerpDouble(heroRadius, other.heroRadius, t),
      darkHero: t < 0.5 ? darkHero : other.darkHero,
      floatingNavigation: t < 0.5
          ? floatingNavigation
          : other.floatingNavigation,
    );
  }
}

double _lerpDouble(double a, double b, double t) => a + (b - a) * t;
