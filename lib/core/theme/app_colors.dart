import 'package:flutter/material.dart';

final class NuvoColors {
  NuvoColors._();

  // ── Brand core ────────────────────────────────────────────────────────────────
  /// Primary dark — headlines, outlines, nav active state.
  static const Color navy = Color(0xFF07152D);

  /// Primary action color — CTA, progress, chips.
  static const Color blue = Color(0xFF1264FF);

  /// Alias of [blue] for explicit call sites.
  static const Color actionBlue = blue;

  /// Legacy gradient partner / pressed state.
  static const Color blue2 = blue;

  /// Pressed / deeper variant — ink state.
  static const Color blueInk = navy;

  /// Light blue tint.
  static const Color blueLight = Color(0xFFE1ECFF);

  /// Quiet structural ink used by legacy offset surfaces.
  static const Color inkNavy = Color(0xFF07152D);

  /// Slightly deeper navy for layered surfaces (alias of ink).
  static const Color navy2 = navy;

  /// Platinum — legacy alias.
  static const Color platinum = Color(0xFFEFF3FA);

  /// Disabled / locked state.
  static const Color paleSlate = Color(0xFF929CAD);
  static const Color disabledSurface = Color(0xFFEEF1F5);
  static const Color disabledText = paleSlate;

  // ── Accent palette ────────────────────────────────────────────────────────────
  static const Color aqua = Color(0xFF718B79);
  static const Color coral = Color(0xFFC97968);
  static const Color sunshine = Color(0xFFD5AA63);

  /// Secondary brand accent — matches the marketing site's `#ff6b21`.
  /// Reserved for CTA emphasis and accent shadows only; never used as a
  /// broad surface fill. Pairs with navy-deep text/border, never white text.
  static const Color orange = Color(0xFFFF6B21);

  // ── Page & surfaces ───────────────────────────────────────────────────────────
  /// Main page background — clean soft white.
  static const Color page = Color(0xFFFBFCFF);

  /// Alias of [page].
  static const Color pageIce = page;

  static const Color pageWarm = page;
  static const Color surface = Color(0xFFFFFFFF);
  static const Color card = surface;

  /// Light tint background — active pills, "you" row highlight.
  static const Color panel = Color(0xFFE1ECFF);
  static const Color panelLight = Color(0xFFF0F5FF);

  static const Color inkWash = Color(0xFFF0F5FF);

  // ── Lines and tracks ──────────────────────────────────────────────────────────
  static const Color trackBg = Color(0xFFE1ECFF);
  static const Color divider = Color(0xFFDCE3EE);

  /// Structural outline used on cards, fields, chips, and controls.
  /// Keep this dark so outlined surfaces carry Nuvo's signature ink edge.
  static const Color border = navy;
  static const Color borderStrong = navy;

  /// Solid grey hard-offset plate for secondary cards (CTA construction,
  /// grey instead of ink navy). Must read clearly against white faces.
  static const Color offsetGrey = navy;

  // ── Legacy aliases kept stable for existing screens ───────────────────────────
  static const Color icyBlue = panelLight;
  static const Color softBlue = panel;
  static const Color lavenderRow = panelLight;
  static const Color sectionBlue = icyBlue;
  static const Color bluePale = softBlue;
  static const Color blueSoft = blue2;
  static const Color navySoft = navy2;

  // ── Text & semantic ───────────────────────────────────────────────────────────
  static const Color muted = Color(0xFF5E6C85);
  static const Color textMuted = Color(0xFF718097);
  static const Color textDim = Color(0xFF929CAD);
  static const Color white = surface;

  // Semantic roles — values taken from the Nuvo palette reference.
  // Blue (above) is neutral/brand and must never signal success or failure.
  // Green = success/verified/finished. Red = failure/rejected/destructive.
  // Orange/gold = needs-attention / warning. Tan = warm accent.
  //
  // Each role has: `base` fill, a `Shadow` (darker same-hue hard-offset), a
  // `Bright` accent (glows / progress fills), a `Surface` tint background, a
  // `Border` mid tint, and an `On` text colour for use on the surface tint.

  /// Success — grass green (#3BC448 in the reference).
  static const Color success = Color(0xFF3BC448);
  static const Color successShadow = Color(0xFF1B8445);
  static const Color successBright = Color(0xFF3BC448);
  static const Color successSurface = Color(0xFFE7F8E9);
  static const Color successBorder = Color(0xFF9EE0A6);
  static const Color successOn = Color(0xFF15602B);

  /// Danger — assertive red (#DC2529).
  static const Color danger = Color(0xFFDC2529);
  static const Color dangerShadow = Color(0xFF841918);
  static const Color dangerBright = Color(0xFFDC2529);
  static const Color dangerSurface = Color(0xFFFCE8E8);
  static const Color dangerBorder = Color(0xFFF1AFAF);
  static const Color dangerOn = Color(0xFF991A1A);

  /// Warning — orange (#EA8E1C).
  static const Color warning = Color(0xFFEA8E1C);
  static const Color amber = warning;
  static const Color warningShadow = Color(0xFFBF601E);
  static const Color warningBright = Color(0xFFEA8E1C);
  static const Color warningSurface = Color(0xFFFBEEDC);
  static const Color warningBorder = Color(0xFFEFC996);
  static const Color warningOn = Color(0xFF8A5210);
  static const Color amberTint = warningSurface;

  /// Gold — the warm yellow warning alt (#F1C22D); also podium 1st.
  static const Color goldWarn = Color(0xFFF1C22D);
  static const Color goldWarnShadow = Color(0xFF9F8012);

  /// Warm tan accent (#E2C9B5 fill, #D8AE87 edge). Sparing use — highlights,
  /// premium/pass surfaces. Never a success/failure signal.
  static const Color accent = Color(0xFFE2C9B5);
  static const Color accentBorder = Color(0xFFD8AE87);
  static const Color accentOn = navy;

  /// Neutral (blue) role — reference fill #1961F2, hard-shadow #0A3B6B.
  static const Color neutral = Color(0xFF1961F2);
  static const Color neutralShadow = Color(0xFF0A3B6B);
  static const Color blueSurface = blueLight;
  static const Color blueBorder = Color(0xFFA9C8FF);
  static const Color blueOn = navy;

  // Podium colours — richer and more distinct from each other than the old
  // three muted browns.
  static const Color gold = Color(0xFFE0A72E);
  static const Color brightGold = Color(0xFFFACC15);
  static const Color silver = Color(0xFF95A0B3);
  static const Color bronze = Color(0xFFB2703C);

  // ── Avatar colors — flat, saturated-but-not-neon, never gradients ────────────
  // A wide, evenly-spread hue set so a crew of avatars reads as varied and
  // lively rather than four muted browns. Deterministically assigned by id.
  static const Color avatarTerracotta = Color(0xFFC96F4C);
  static const Color avatarOchre = Color(0xFFCE9B33);
  static const Color avatarDustyBlue = Color(0xFF4E7CB5);
  static const Color avatarSage = Color(0xFF5E9E6B);
  static const Color avatarPlum = Color(0xFF8A5CB0);
  static const Color avatarTeal = Color(0xFF2FA3A3);
  static const Color avatarCoral = Color(0xFFDA5D6E);
  static const Color avatarIndigo = Color(0xFF5B63C4);
  static const List<Color> avatarPalette = [
    avatarDustyBlue,
    avatarTerracotta,
    avatarSage,
    avatarPlum,
    avatarOchre,
    avatarTeal,
    avatarCoral,
    avatarIndigo,
  ];

  // ── Race-state semantic aliases ───────────────────────────────────────────────
  // Map to existing canonical colors. New race UI should prefer these names so
  // the role/state is readable at the call site.

  /// Active/live race state — same as action blue.
  static const Color raceLive = blue;

  /// Crew-waiting / incomplete-attention state — same as warning.
  static const Color crewWaiting = warning;
  static const Color crewWaitingTint = amberTint;

  /// Finished / completed race state — same as success.
  static const Color raceFinished = success;

  /// 1st place / leader — same as gold.
  static const Color position1 = gold;

  /// 2nd place — same as silver.
  static const Color position2 = silver;

  /// 3rd place — same as bronze.
  static const Color position3 = bronze;

  // ── Short aliases ─────────────────────────────────────────────────────────────
  static const Color mint = success;
  static const Color prize = gold;
}

abstract final class AppColors {
  static const Color background = NuvoColors.page;
  static const Color backgroundSoft = NuvoColors.panel;
  static const Color surface = NuvoColors.surface;
  static const Color surfaceElevated = NuvoColors.inkWash;
  static const Color border = NuvoColors.border;
  static const Color borderStrong = NuvoColors.borderStrong;
  static const Color primary = NuvoColors.blue;
  static const Color primarySoft = NuvoColors.softBlue;
  static const Color primaryDeep = NuvoColors.navy;
  static const Color dreamPink = NuvoColors.coral;
  static const Color mint = NuvoColors.success;
  static const Color success = NuvoColors.success;
  static const Color warning = NuvoColors.warning;
  static const Color danger = NuvoColors.danger;
  static const Color textPrimary = NuvoColors.navy;
  static const Color textSecondary = NuvoColors.muted;
  static const Color textMuted = NuvoColors.textMuted;
  static const Color textInverse = NuvoColors.white;
  static const Color electricBlue = NuvoColors.blue;
  static const Color deepBlue = NuvoColors.navy;
  static const Color neonMint = NuvoColors.aqua;
  static const Color hotAmber = NuvoColors.sunshine;
  static const Color orange = NuvoColors.orange;
}

/// A semantic colour role — `base` fill, a same-hue-darker `shadow` for the
/// hard offset, a contrast-exempt `bright` accent, a tint `surface`, a mid-tint
/// `border`, and an `on` text colour for use on the surface tint.
@immutable
class NuvoColorRole {
  const NuvoColorRole({
    required this.base,
    required this.shadow,
    required this.bright,
    required this.surface,
    required this.border,
    required this.on,
  });

  final Color base;
  final Color shadow;
  final Color bright;
  final Color surface;
  final Color border;
  final Color on;

  /// A hard-offset shadow tinted to this role.
  List<BoxShadow> hardShadow({Offset offset = const Offset(3, 3)}) => [
    BoxShadow(color: shadow, blurRadius: 0, offset: offset),
  ];

  NuvoColorRole lerpTo(NuvoColorRole other, double t) => NuvoColorRole(
    base: Color.lerp(base, other.base, t)!,
    shadow: Color.lerp(shadow, other.shadow, t)!,
    bright: Color.lerp(bright, other.bright, t)!,
    surface: Color.lerp(surface, other.surface, t)!,
    border: Color.lerp(border, other.border, t)!,
    on: Color.lerp(on, other.on, t)!,
  );
}

/// Theme-level access to the semantic roles. Prefer
/// `Theme.of(context).extension<NuvoSemanticColors>()!` (or the
/// `context.semanticColors` getter) over reaching for raw `NuvoColors.*` in new
/// code, so the roles can be themed/overridden in one place.
@immutable
class NuvoSemanticColors extends ThemeExtension<NuvoSemanticColors> {
  const NuvoSemanticColors({
    required this.neutral,
    required this.success,
    required this.danger,
    required this.warning,
    required this.accent,
  });

  final NuvoColorRole neutral;
  final NuvoColorRole success;
  final NuvoColorRole danger;
  final NuvoColorRole warning;
  final NuvoColorRole accent;

  static const NuvoSemanticColors standard = NuvoSemanticColors(
    neutral: NuvoColorRole(
      base: NuvoColors.neutral,
      shadow: NuvoColors.neutralShadow,
      bright: NuvoColors.blue,
      surface: NuvoColors.blueSurface,
      border: NuvoColors.blueBorder,
      on: NuvoColors.blueOn,
    ),
    success: NuvoColorRole(
      base: NuvoColors.success,
      shadow: NuvoColors.successShadow,
      bright: NuvoColors.successBright,
      surface: NuvoColors.successSurface,
      border: NuvoColors.successBorder,
      on: NuvoColors.successOn,
    ),
    danger: NuvoColorRole(
      base: NuvoColors.danger,
      shadow: NuvoColors.dangerShadow,
      bright: NuvoColors.dangerBright,
      surface: NuvoColors.dangerSurface,
      border: NuvoColors.dangerBorder,
      on: NuvoColors.dangerOn,
    ),
    warning: NuvoColorRole(
      base: NuvoColors.warning,
      shadow: NuvoColors.warningShadow,
      bright: NuvoColors.warningBright,
      surface: NuvoColors.warningSurface,
      border: NuvoColors.warningBorder,
      on: NuvoColors.warningOn,
    ),
    accent: NuvoColorRole(
      base: NuvoColors.accent,
      shadow: NuvoColors.accentBorder,
      bright: NuvoColors.accent,
      surface: Color(0xFFF6EEE4),
      border: NuvoColors.accentBorder,
      on: NuvoColors.accentOn,
    ),
  );

  @override
  NuvoSemanticColors copyWith({
    NuvoColorRole? neutral,
    NuvoColorRole? success,
    NuvoColorRole? danger,
    NuvoColorRole? warning,
    NuvoColorRole? accent,
  }) => NuvoSemanticColors(
    accent: accent ?? this.accent,
    neutral: neutral ?? this.neutral,
    success: success ?? this.success,
    danger: danger ?? this.danger,
    warning: warning ?? this.warning,
  );

  @override
  NuvoSemanticColors lerp(ThemeExtension<NuvoSemanticColors>? other, double t) {
    if (other is! NuvoSemanticColors) return this;
    return NuvoSemanticColors(
      neutral: neutral.lerpTo(other.neutral, t),
      success: success.lerpTo(other.success, t),
      danger: danger.lerpTo(other.danger, t),
      warning: warning.lerpTo(other.warning, t),
      accent: accent.lerpTo(other.accent, t),
    );
  }
}

extension NuvoSemanticColorsX on BuildContext {
  /// Semantic colour roles for this context's theme.
  NuvoSemanticColors get semanticColors =>
      Theme.of(this).extension<NuvoSemanticColors>() ??
      NuvoSemanticColors.standard;
}
