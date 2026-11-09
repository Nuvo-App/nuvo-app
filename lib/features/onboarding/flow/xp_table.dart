import 'onboarding_step.dart';

/// Onboarding-v2 XP table — the single source of truth for per-step awards.
///
/// Spec (`docs/redesign/onboarding-v2-spec.md` §CONCEPT):
/// "verified code +10, player card +15, starter questions +10, first proof
/// +30 (10 if camera fallback), Compete +10, Crew +10, Profile +5,
/// notification accepted +5 = 100."
///
/// DEVIATION (documented in docs/redesign/onboarding-v2-interfaces.md):
/// the spec's enumerated values sum to 95 while the spec's stated total is
/// 100 (also the "+100 XP" reward tile and the 100-XP server grant). The
/// missing +5 is carried by [firstRaceReady] — the only spec-silent
/// post-auth step, so every named value stays spec-exact and no stated
/// cumulative checkpoint breaks (S4 rail: "Level 1, 0 XP"; S7: "10 XP").
/// Only Part 0 and Part E may edit this file (build plan).
abstract final class OnboardingXp {
  /// S6 — the email code verifies (social sign-ins land the same award:
  /// the account is verified either way — Part B decides presentation).
  static const int verifiedCode = 10;

  /// S7 — player card saved (name + @username + 13+/terms).
  static const int playerCard = 15;

  /// S8 — starter questions answered OR skipped (spec: "+10 XP after Q2 or
  /// skip"). Awarded on questions2; Q1 itself carries no award.
  static const int starterQuestions = 10;

  /// S10 — first proof completed with the real camera path.
  static const int firstProof = 30;

  /// S10 — camera denied/unavailable: reduced Practice proof award.
  static const int firstProofCameraFallback = 10;

  /// S9 — "Your first race is ready" beat. See the class doc deviation:
  /// carries the +5 the spec's list omits so the rail totals exactly 100.
  static const int firstRaceReady = 5;

  /// S12 — tour stop 1 (Compete): Join tapped.
  static const int tourCompete = 10;

  /// S13 — tour stop 2 (Crew): My Nuvo code opened.
  static const int tourCrew = 10;

  /// S14 — tour stop 3 (Profile): first badge tile seen.
  static const int tourProfile = 5;

  /// S11 — notification permission accepted (declining costs nothing).
  static const int notifyAccepted = 5;

  /// The full-flow total on the real camera path — exactly moves a fresh
  /// account Level 1 → 2 (spec target; server grants the same 100 once).
  static const int total = 100;

  /// The full-flow total when the camera path fell back (D3 reduced XP).
  static const int totalCameraFallback = 80;

  /// The step's award. [cameraFallback] applies only to the first proof
  /// (D3); [notifyAccepted] gates the conditional S11 award — pass the
  /// step's resolved outcome, not the raw intent.
  static int xpFor(
    OnboardingStep step, {
    bool cameraFallback = false,
    bool notifyAccepted = false,
  }) => switch (step) {
    OnboardingStep.code => verifiedCode,
    OnboardingStep.playerCard => playerCard,
    OnboardingStep.questions2 => starterQuestions,
    OnboardingStep.firstRaceReady => firstRaceReady,
    OnboardingStep.arenaTour =>
      cameraFallback ? firstProofCameraFallback : firstProof,
    OnboardingStep.notifyOptIn =>
      notifyAccepted ? OnboardingXp.notifyAccepted : 0,
    OnboardingStep.tourCompete => tourCompete,
    OnboardingStep.tourCrew => tourCrew,
    OnboardingStep.tourProfile => tourProfile,
    _ => 0,
  };

  /// Sum of every award the table can grant — used by the unit test that
  /// pins the "= 100" spec total.
  static int sum({bool cameraFallback = false, bool notifyAccepted = true}) =>
      OnboardingStep.values.fold(
        0,
        (sum, step) =>
            sum +
            xpFor(
              step,
              cameraFallback: cameraFallback,
              notifyAccepted: notifyAccepted,
            ),
      );
}
