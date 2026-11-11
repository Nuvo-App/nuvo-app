/// The onboarding-v2 step machine — one enum value per spec screen S0–S15.
///
/// Enum order IS flow order: `earliestOwed` is computed as the first value
/// not in the persisted completed set, which is what makes kill + relaunch
/// resume exactly where the user left off.
enum OnboardingStep {
  /// S0 — retired. The real app shows its own splash before the flow, so
  /// this step never renders: the controller treats it as always complete
  /// (kept in the enum so old saved state and analytics indices stay valid).
  splash,

  /// S1 — "Race anything." One composed hero: the tap duel is the first
  /// thing on screen.
  introRace,

  /// S2 — "How it works": camera proof + leaderboard climb on a single
  /// screen, with "Create my player" and "I already have an account".
  /// Replaces the old introCamera / introBoard pair.
  introHow,

  /// S4 — "Save your spot" sign-in sheet (Apple / Google / email).
  signIn,

  /// S5 — "What's your email?" player-pass ticket.
  email,

  /// S6 — "Check your email." six code boxes; verified code awards XP.
  code,

  /// S7 — Player card: name, @username, photo, 13+/terms.
  playerCard,

  /// S8a — Q1 "What do you want to race?"
  questions1,

  /// S8b — Q2 "Race solo or with friends?"
  questions2,

  /// S9 — "Your first race is ready" transition beat.
  firstRaceReady,

  /// S10 — Arena tour: practice race + first proof (camera or fallback).
  arenaTour,

  /// S11 — Notification opt-in in context.
  notifyOptIn,

  /// S12 — Tour stop 1: Compete.
  tourCompete,

  /// S13 — Tour stop 2: Crew.
  tourCrew,

  /// S14 — Tour stop 3: Profile.
  tourProfile,

  /// S15 — LEVEL UP, the one full-bleed blue screen.
  levelUp,

  /// "Create one": the account-choice page (Apple / Google / email). Not a
  /// linear step — reached only by goTo from the login sheet, always cut
  /// (auto-complete). Last in the enum so `previous` of every real step is
  /// unchanged.
  createAccount,
}

extension OnboardingStepX on OnboardingStep {
  /// Position in the flow (S0–S15) — used for the Track, the analytics
  /// `step_index`, and ordering.
  int get index => OnboardingStep.values.indexOf(this);

  /// Analytics `step_name` — the enum's stable identifier.
  String get analyticsName => name;

  /// The step after this one, or null at [OnboardingStep.levelUp].
  OnboardingStep? get next {
    final n = index + 1 < OnboardingStep.values.length
        ? OnboardingStep.values[index + 1]
        : null;
    return n == OnboardingStep.createAccount ? null : n; // a page, not a step
  }

  /// The step before this one, or null at [OnboardingStep.splash].
  OnboardingStep? get previous =>
      index > 0 ? OnboardingStep.values[index - 1] : null;

  /// Pre-auth intro pages show page dots (and no Track) instead of the XP
  /// rail.
  bool get showsDots =>
      this == OnboardingStep.introRace || this == OnboardingStep.introHow;

  /// The dot this step lights (0–1). Only meaningful when [showsDots].
  int get dotIndex => index - OnboardingStep.introRace.index;

  /// The XP rail rides from S4 until level-up (spec). Neither the splash
  /// nor the level-up celebration itself shows it.
  bool get showsRail =>
      index >= OnboardingStep.signIn.index &&
      index < OnboardingStep.levelUp.index;

  /// The Track paints only once the player is in: post-auth XP-rail steps
  /// (player card onward). Pre-auth screens — splash, intros, the sheet,
  /// email and code — carry dots or the rail alone, so no path ever runs
  /// behind their copy.
  bool get showsTrack => showsRail && index >= OnboardingStep.playerCard.index;

  /// Steps the user may pass without acting — S1–S2 (Skip), the two
  /// starter questions (skippable), and the tour stops (Skip tour).
  bool get isSkippable =>
      showsDots ||
      this == OnboardingStep.questions1 ||
      this == OnboardingStep.questions2 ||
      this == OnboardingStep.tourCompete ||
      this == OnboardingStep.tourCrew ||
      this == OnboardingStep.tourProfile;

  /// Steps the user may go BACK to via the shell's back square. Splash and
  /// the first intro have no back; the tour/level-up own their exits.
  bool get showsBack =>
      this != OnboardingStep.splash &&
      this != OnboardingStep.introRace &&
      this != OnboardingStep.arenaTour &&
      this != OnboardingStep.levelUp;
}

/// Steps that exist in code but are CUT from the shipped flow until they are
/// finished to the quality bar: the tour (practice race S10, notification
/// sheet S11, three stops S12-S14) are still placeholder screens. Cut steps
/// resolve silently (no XP, no screen) so the flow runs S9 -> Level Up.
/// Re-enable a step by removing it here; nothing else changes.
const Set<OnboardingStep> kCutSteps = {
  OnboardingStep.createAccount,
  // The rethought flow (docs/redesign/onboarding-screen-plan.md): one
  // swipeable intro, sign-in, minimal setup, straight into the app. No
  // second intro page, no questions, no level-up gate.
  OnboardingStep.introHow,
  OnboardingStep.questions1,
  OnboardingStep.questions2,
  OnboardingStep.levelUp,
  // S9 promised a practice race that no longer exists (the tour is cut) and
  // showed placeholder racers: cut until the Arena really has one.
  OnboardingStep.firstRaceReady,
  OnboardingStep.arenaTour,
  OnboardingStep.notifyOptIn,
  OnboardingStep.tourCompete,
  OnboardingStep.tourCrew,
  OnboardingStep.tourProfile,
};
