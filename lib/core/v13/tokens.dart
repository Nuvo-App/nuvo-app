import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// v13 design tokens — the single source of truth for the redesign.
///
/// Spec: `docs/redesign/PROTOTYPE_V13_SPEC.md` ("Global rules"). Light mode
/// only. Signature look: a 2–2.5 px navy outline plus a hard offset shadow
/// (3–6 px, zero blur). Every v13 widget reads from this class — no other
/// colors may appear in `lib/core/v13/` or `lib/features/*/presentation/v13/`.
abstract final class V13 {
  // ── Surfaces ──────────────────────────────────────────────────────────
  /// Page background — soft off-white.
  static const Color bg = Color(0xFFF5F6F8);

  /// Card / sheet / raised surface fill.
  static const Color card = Color(0xFFFFFFFF);

  /// Alias for places that read "white" semantically (text on blue, etc.).
  static const Color white = card;

  // ── Ink ───────────────────────────────────────────────────────────────
  /// Primary ink — outlines, titles, hard shadows.
  static const Color navy = Color(0xFF07152D);

  /// Secondary text / inactive icons.
  static const Color muted = Color(0xFF5E6A80);

  // ── Brand action ──────────────────────────────────────────────────────
  /// Nuvo blue — the one main action per screen, "you" treatments, the tab
  /// indicator, XP ring and heat map. Never a broad surface fill.
  static const Color blue = Color(0xFF1264FF);

  // ── Race & crew palette ───────────────────────────────────────────────
  static const Color coral = Color(0xFFFF8A65);
  static const Color sun = Color(0xFFFFC93C);
  static const Color lilac = Color(0xFFCDBFFF);
  static const Color mint = Color(0xFF9EE6C4);
  static const Color sky = Color(0xFFB8D2FF);

  /// The five approved race colors, in palette order.
  static const List<Color> racePalette = [coral, sun, lilac, mint, sky];

  // ── Podium metals ─────────────────────────────────────────────────────
  /// Gold is reserved for 1st place only.
  static const Color gold = Color(0xFFF5B800);
  static const Color silver = Color(0xFFC9CFDB);
  static const Color bronze = Color(0xFFCD8A50);

  // ── Lines & semantic ──────────────────────────────────────────────────
  /// Thin row divider.
  static const Color divider = Color(0xFFE6E9EF);

  /// Destructive actions and error states.
  static const Color danger = Color(0xFFE72025);

  // ── Outline widths ────────────────────────────────────────────────────
  /// Standard card/button outline.
  static const double outline = 2;

  /// Emphasis outline ("you" ring, hero surfaces).
  static const double outlineThick = 2.5;

  // ── Hard shadows — navy plate, zero blur ──────────────────────────────
  static const List<BoxShadow> shadow3 = [
    BoxShadow(color: navy, blurRadius: 0, offset: Offset(3, 3)),
  ];
  static const List<BoxShadow> shadow4 = [
    BoxShadow(color: navy, blurRadius: 0, offset: Offset(4, 4)),
  ];
  static const List<BoxShadow> shadow6 = [
    BoxShadow(color: navy, blurRadius: 0, offset: Offset(6, 6)),
  ];

  /// Custom hard offset when the presets don't fit.
  static List<BoxShadow> hardShadow({double x = 4, double y = 4}) => [
    BoxShadow(color: navy, blurRadius: 0, offset: Offset(x, y)),
  ];

  // ── Radii ─────────────────────────────────────────────────────────────
  static const double radiusButton = 14;
  static const double radiusCard = 24;
  static const double radiusCardLg = 28;
  static const double radiusPill = 99;
  static const double radiusTile = 12;
  static const double radiusTileLg = 16;

  // ── Spacing scale ─────────────────────────────────────────────────────
  static const double gapXs = 4;
  static const double gapSm = 8;
  static const double gapMd = 12;
  static const double gapLg = 16;
  static const double gapXl = 20;
  static const double gapXxl = 24;

  /// Space between screen sections (spec: 36–48).
  static const double gapSection = 40;

  /// Standard horizontal page padding.
  static const double pagePad = 20;

  // ── Race & crew color resolution ──────────────────────────────────────

  /// FNV-1a over UTF-16 code units — a stable, platform-independent hash.
  /// (`String.hashCode` is not stable across runs and must not be used for
  /// persisted identity → color mapping.)
  static int _fnv1a(String s) {
    var h = 0x811c9dc5;
    for (final unit in s.codeUnits) {
      h ^= unit;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  /// A15: a race's card color is client-deterministic —
  /// `racePalette[fNV(race.id) % 5]`. Same id always lands on the same color.
  static Color raceColor(String id) =>
      racePalette[_fnv1a(id) % racePalette.length];

  /// Crew color: the server's `color_key` when present (W2), falling back to
  /// the same deterministic hash on the crew id so crews are stable even
  /// before the key column ships.
  static Color crewColor(String? key, String id) =>
      _crewColorKeys[key] ?? raceColor(id);

  static const Map<String, Color> _crewColorKeys = {
    'coral': coral,
    'sun': sun,
    'lilac': lilac,
    'mint': mint,
    'sky': sky,
  };

  // ── Type — Manrope 500–800 ────────────────────────────────────────────
  static TextStyle _m(
    double size,
    FontWeight weight, {
    Color? color,
    double? height,
    double letterSpacing = 0,
    bool tabular = false,
  }) => GoogleFonts.manrope(
    fontSize: size,
    fontWeight: weight,
    color: color ?? navy,
    height: height ?? 1.3,
    letterSpacing: letterSpacing,
    fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    // Overlays (toasts, +N) render above any Material; without this the
    // framework's fallback style underlines the text.
    decoration: TextDecoration.none,
  );

  /// Screen titles — 26/800 ("title left" in top bars).
  static TextStyle get title => _m(26, FontWeight.w800, height: 1.15);

  /// Section heads — 19/800.
  static TextStyle get sectionHead => _m(19, FontWeight.w800, height: 1.2);

  /// Race card titles — 18/800 (spec: the name on a race swiper card).
  static TextStyle get cardTitle => _m(18, FontWeight.w800, height: 1.2);

  /// Body copy — 14/500.
  static TextStyle get body => _m(14, FontWeight.w500, height: 1.45);

  /// Emphasized body / row titles — 14/700.
  static TextStyle get bodyStrong => _m(14, FontWeight.w700, height: 1.4);

  /// Secondary captions — 12/600 muted.
  static TextStyle get caption =>
      _m(12, FontWeight.w600, color: muted, height: 1.3);

  /// Micro label — 11/800, tracked out, meant to be uppercased at the
  /// call site (`text.toUpperCase()`).
  static TextStyle get label =>
      _m(11, FontWeight.w800, color: muted, letterSpacing: 1.2, height: 1.2);

  /// Hero score on race cards — 84/800 tabular.
  static TextStyle get hugeNumber =>
      _m(84, FontWeight.w800, height: 1.0, tabular: true);

  /// Large stat/leaderboard number — 22/800 tabular.
  static TextStyle get number =>
      _m(22, FontWeight.w800, height: 1.1, tabular: true);

  /// Compact number (chips, gap lines) — 16/800 tabular.
  static TextStyle get numberSm =>
      _m(16, FontWeight.w800, height: 1.15, tabular: true);

  /// Button label — 15/800.
  static TextStyle get buttonLabel => _m(15, FontWeight.w800, height: 1.1);
}
