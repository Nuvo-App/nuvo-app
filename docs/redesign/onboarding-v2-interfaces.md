# Onboarding v2 — Part 0 Interfaces

The contract every later part (A–F) builds against. Part 0 ships the
foundation: one motion language, one shell, one flow state machine, local
persistence, the feature flag + routing, the `ob_*` analytics vocabulary,
and a walkable stub for every step.

**Flag:** `--dart-define=NUVO_ONBOARDING_V2=true`. Default OFF — off builds
behave exactly as before (`NuvoOnboardingScreen` untouched).

---

## 1. Motion — `lib/core/motion/`

One import: `package:nuvo/core/motion/motion.dart` (barrel). All durations,
curves, distances and the spring live in `NuvoMotion`; step files must
NEVER hard-code `Duration(milliseconds:…)` or `Curves.*` — the lint test
`test/onboarding_v2/motion_lint_test.dart` enforces this (allow-list: none).

> ⚠ `lib/core/widgets/nuvo_motion.dart` is the older pre-v13 shell file and
> defines the same public names (`NuvoMotion`, `NuvoHaptics`,
> `NuvoPressable`). The two libraries must never be co-imported — onboarding
> v2 code uses `lib/core/motion/` only.

| Token | Value | Use |
|---|---|---|
| `springDescription` | mass 1 · k 380 · damping 22 | the one spring |
| `spring` / `springDuration` | Curve / 520 ms | entrances, fill, release |
| `pressDown` / `pressDownCurve` | 90 ms / easeOut | press sink |
| `pressSink` / `pressShadowFrom`/`To` | 3 px / 4 → 1 px | press geometry |
| `enter` / `enterOffsetY` / `staggerStep` / `staggerMax` | 480 ms / 28 px / 70 ms / 5 | `NuvoEnter` |
| `exit` / `exitCurve` / `exitOffsetY` / `exitScale` | 260 ms / easeIn / −12 px / .97 | step exit |
| `floatPeriod` / `floatAmplitude` / `floatRotationDeg` / `floatPhaseMax` | 3.2 s / 6 px / 1.2° / 1.6 s | `NuvoFloat` (heroes, tokens, badges ONLY) |
| `tiltParallax` | 8 px | optional accelerometer tilt (Part A) |
| `xpFlyRise` / `xpFly` / `xpFlyCurve` | 24 px / 600 ms / easeInOutCubic | "+N" chip → rail |
| `confetti` / `confettiPieces` | 1.1 s / 40 | level-up burst |
| `trackPan` / `trackPanCurve` / `trackParallax` | 420 ms / easeInOutCubic / 1.15 | Track camera |
| `reduceMotionFade` | 200 ms | the only transition under reduce-motion |
| `ctaFade` / `splashHold` | 180 ms / 1200 ms | CTA label fade / S0 hold |

Helpers:

- `NuvoPressable({child, onTap, shadow, borderRadius, sink, haptic,
  enabled, semanticLabel})` — sinks 3 px, shadow plate compresses 4→1,
  light haptic. Every tappable surface.
- `NuvoEnter({child, index})` — spring from y+28, staggered.
- `NuvoFloat({child, phase})` — idle sine float; hero/badge elements only.
- `NuvoHaptics.select/light/medium/heavy/success()` — gated on the persisted
  Settings haptics toggle (`v13HapticsEnabled`).
- `NuvoSounds` — `pressTick/xpChime/fanfare/enabled`. Shipped impl is
  `NoopNuvoSounds` (pubspec is off-limits — no audio package yet); swap in
  via `nuvoSoundsProvider`. On only inside the flow; the real impl must
  hand the OS an ambient audio session so silent switch wins.
- `NuvoMotion.stepTransition(child, animation)` — the host's
  `AnimatedSwitcher` builder (spring in / ease-out in reverse;
  cross-fade under reduce-motion).
- `NuvoMotion.reduceMotionOf(context)` — the one gate (`MediaQuery`
  `disableAnimations`).

## 2. Shell — `lib/features/onboarding/shell/`

```dart
OnboardingShell(
  step: OnboardingStep.email,   // required — drives chrome defaults
  hero: <Widget>,               // required — the step's centerpiece
  title: '…',                   // required
  subtitle: '…',                // optional
  body: <Widget>,               // optional — chips, fields, tiles
  ctaLabel: 'Send code',        // required — fixed 56px slot, 16px margins
  ctaEnabled: true,             // de-emphasized (not hidden) when false
  onCta: …, onBack: …, onSkip: …,
  skipLabel: ObCopy.skip,       // 'Skip tour' on the tour stops
  background: V13.bg,           // V13.blue only for level-up
  titleColor, subtitleColor,    // level-up only
  showTrack: true,              // off only for level-up
  showRail / showDots / dotIndex / dotCount,  // chrome overrides
)
```

- **Track** — `TrackBackground`/`TrackPainter` paint the navy 2.5 px curved
  path + beads; camera pans `trackPan` 420 ms from
  `OnboardingShellController.trackFrom → trackIndex`; path at 1.0x, beads at
  1.15x, avatar bead on the spring. Never resets — the pan origin lives in
  the controller, not the widget.
- **XpRail** — outlined bar, Level 1 / Level 2 badges, spring fill toward
  `OnboardingXp.total` (100). Rides S4–S15 (`step.showsRail`); S1–S3 show
  3 page dots instead (`step.showsDots`).
- **CTA** — identical geometry on every step; label cross-fades
  `ctaFade`; docks above the keyboard with the spring
  (`resizeToAvoidBottomInset: false` + animated bottom pad).
- **`OnboardingShellScope.of(context)`** → `OnboardingShellController`:
  `award(int)` queues a "+N" flight into the rail; `syncXp(total)` snaps
  the rail (restore); `panTrackTo(index)` is host-only.
- **`obAdvance(context, ref, step)`** — the stub idiom:
  `completeStep` then `award(awarded)` with the controller captured before
  the await.
- **`XpFlyOverlay`** — mounted once by the host above everything; drains
  the controller's pending flights (rises 24 px off the CTA, then 600 ms
  into the rail). Under reduce-motion XP lands without flying.

## 3. Flow — `lib/features/onboarding/flow/`

- **`OnboardingStep`** — S0–S16 enum in flow order:
  `splash, introRace, introCamera, introBoard, signIn, email, code,
  playerCard, questions1, questions2, firstRaceReady, arenaTour,
  notifyOptIn, tourCompete, tourCrew, tourProfile, levelUp`.
  Extension: `index`, `analyticsName`, `next`, `previous`, `showsDots`,
  `dotIndex`, `showsRail`, `isSkippable`, `showsBack`.
- **`OnboardingXp`** (`xp_table.dart`) — per-step awards; edit only in
  Part 0/E. `xpFor(step, cameraFallback:, notifyAccepted:)`,
  `sum(cameraFallback:, notifyAccepted:)`, `total` = 100.
- **`ObCopy`** (`onboarding_copy.dart`) — every user-facing string.
- **`OnboardingFlowController`** (`onboardingFlowProvider`,
  `StateNotifier<OnboardingFlowState>`):

  | Member | Meaning |
  |---|---|
  | `restore({accountEmail})` | load store, land on earliest owed step |
  | `attachAccount(email)` | adopt anonymous progress / wipe a different account's record |
  | `completeStep(step)` → `Future<int>` | mark done + award (idempotent) + advance; returns granted XP |
  | `goTo(step)` / `goBack()` | pointer moves without completing |
  | `skipIntros()` / `skipQuestions()` / `skipTour()` | the three skip groups (questions pay +10 anyway; tour-skip defers level-up to the Getting-started row) |
  | `setAnswer(q, v)` / `setEmail(v)` / `setCameraFallback(b)` / `setNotifyOutcome(s)` | persisted flags |
  | `proofStarted()` / `proofCompleted(cameraFallback:)` → `Future<int>` | S11 proof seam |
  | `tourStopViewed(stop)` | `ob_tour_stop` |
  | `levelUpSeen()` | `ob_level_up_seen` + heavy haptic + fanfare |
  | `graduate()` → `Future<bool>` | the `completeOnboarding()` server write (same write v1 makes); true ⇒ host routes to /arena |
  | `reset()` | wipe + splash (demo replay) |

  `OnboardingFlowState`: `restored`, `step`, `completed`,
  `xpAwarded`, `totalXp`, `answerQ1/Q2`, `email`, `cameraFallback`,
  `tourSkipped`, `notifyOutcome`, `earliestOwed`, `allStepsComplete`,
  `readyToGraduate`.

## 4. Persistence — `lib/features/onboarding/data/onboarding_v2_store.dart`

`OnboardingV2Store` (provider `onboardingV2StoreProvider`): JSON file
`nuvo_onboarding_v2.json` in app documents (FirstUseStore pattern).
Persists `accountEmail`, `completed` step set, `xpAwarded` map (the
no-double-award record), `answerQ1/Q2`, `email`, `cameraFallback`,
`tourSkipped`, `notifyOutcome`. `OnboardingV2Store.memory()` /
`.fromSnapshot(json)` for tests — `toJson()`/`fromSnapshot` is the
kill+relaunch seam. `attachAccount` wipes a different account's record.

## 5. Routing — `lib/app/router.dart` + `lib/core/config/nuvo_flags.dart`

- `NuvoFlags.onboardingV2` — `String.fromEnvironment('NUVO_ONBOARDING_V2')
  == 'true'`. Compile-time; never server-controlled.
- `/onboarding-v2` hosts `OnboardingV2Screen`. Outside `/onboarding/` so
  auth_gate leaves it reachable in both auth states.
- Flag ON: `/onboarding/profile`, `/onboarding/motion-consent`,
  `/onboarding/nuvo`, `/onboarding/notifications` redirect to
  `/onboarding-v2`. Flag OFF: `/onboarding-v2` redirects to
  `/onboarding/nuvo`; every v1 route behaves exactly as before.
- `auth_gate.dart` is UNTOUCHED — the destination still depends only on
  onboarding flags; the v2 host graduates itself.

## 6. Step → file map (one file, one widget per step)

| Step | Enum | File | Widget |
|---|---|---|---|
| S0 | `splash` | `intro/splash_step.dart` | `ObSplashStep` |
| S1 | `introRace` | `intro/intro_race_step.dart` | `ObIntroRaceStep` |
| S2 | `introCamera` | `intro/intro_camera_step.dart` | `ObIntroCameraStep` |
| S3 | `introBoard` | `intro/intro_board_step.dart` | `ObIntroBoardStep` |
| S4 | `signIn` | `auth_visuals/sign_in_step.dart` | `ObSignInStep` |
| S5 | `email` | `auth_visuals/email_step.dart` | `ObEmailStep` |
| S6 | `code` | `auth_visuals/code_step.dart` | `ObCodeStep` |
| S7 | `playerCard` | `player/player_card_step.dart` | `ObPlayerCardStep` |
| S8 | `questions1` | `player/questions_one_step.dart` | `ObQuestionsOneStep` |
| S9 | `questions2` | `player/questions_two_step.dart` | `ObQuestionsTwoStep` |
| S10 | `firstRaceReady` | `player/first_race_ready_step.dart` | `ObFirstRaceReadyStep` |
| S11 | `arenaTour` | `tour/arena_tour_step.dart` | `ObArenaTourStep` |
| S12 | `notifyOptIn` | `tour/notify_opt_in_step.dart` | `ObNotifyOptInStep` |
| S13 | `tourCompete` | `tour/tour_compete_step.dart` | `ObTourCompeteStep` |
| S14 | `tourCrew` | `tour/tour_crew_step.dart` | `ObTourCrewStep` |
| S15 | `tourProfile` | `tour/tour_profile_step.dart` | `ObTourProfileStep` |
| S16 | `levelUp` | `levelup/level_up_step.dart` | `ObLevelUpStep` |

Host: `onboarding_v2_screen.dart` → `OnboardingV2Screen`. Shared stub hero:
`shell/placeholder_hero.dart` → `ObPlaceholderHero`.

## 7. Part 0 deviations (flagged for review)

1. **XP +5 at `firstRaceReady`.** The spec's named awards sum to 95 while
   the spec states the total is 100 (three places). The missing +5 rides
   S10 (`OnboardingXp.firstRaceReady`) — the only post-auth step the list
   omits. Named values unchanged; checkpoints intact (S4 shows 0 XP, S7
   shows 10 XP). Part E may move it — `xp_table.dart` is the single source.
2. **`/onboarding-v2` pre-auth entry is stub-only.** Under the flag the
   post-auth redirect is live, but signed-out users are NOT yet routed into
   the intros (splash/welcome redirects would need auth_gate or the splash
   screen). Dev entry: `NUVO_INITIAL_LOCATION=/onboarding-v2` or a deep
   link. Part A/B owns the pre-auth handoff.
3. **`NuvoSounds` ships as `NoopNuvoSounds`** — no audio package may be
   added (pubspec is protected). Interface + provider are the seam.
4. **`OnboardingV2Screen` owns its own graduation** (`context.go('/arena')`)
   because `/onboarding-v2` is intentionally outside the guard's
   auth/or-onboarding bucket.
