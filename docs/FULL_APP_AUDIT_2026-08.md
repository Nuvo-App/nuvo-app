# Nuvo — full app UI/UX audit (2026-08-30)

## 1. Method & scope

- **Build audited:** branch `nuvo-visual/compete-design`, working tree at commit `319ce14`.
- **Surface:** the Flutter client (`lib/`), its theme layer (`lib/core/theme`), shared
  widgets (`lib/core/widgets`), routing (`lib/app`), and the auth Worker
  (`server/worker/src/routes/auth.ts`) only as far as it explains client behaviour.
- **How issues were found:** full read of the theme system, routing, auth stack,
  and every top-level screen; `flutter analyze` baseline; static sweeps for
  hardcoded colors, direct font usage, transparent tap targets, fixed dimensions,
  and proof-status string handling.
- **Not covered here (deliberately):** ML pose validators / thresholds, the native
  camera bridge, Worker business logic, and dependency upgrades — these are frozen
  per `docs/agents/07-ui-refinement-and-camera-ai-migration.md` §11. Suspected logic
  bugs in that area are still *listed* below (§5) for owner sign-off, not fixed
  blind.
- **Supersedes:** the June-2026 root-level audit docs (`FULL_UI_UX_AUDIT.md`,
  `BUTTON_AUDIT.md`, `UI_POLISH_AUDIT.md`, `VISUAL_SYSTEM_POLISH_AUDIT.md`,
  `UI_UX_REBUILD_PLAN.md`, `LIVE_DEMO_QA_AUDIT.md`, `QA_CHECKLIST.md`). Those are
  stale; this document is the current reference. Keep them until this audit's
  backlog is closed, then delete.

## 2. Severity legend

| Level | Meaning |
|---|---|
| **P0** | Blocks normal use, loses data, or shows a false result. Fix first. |
| **P1** | Major UX failure — confusing, inconsistent across the app, or breaks on common devices. |
| **P2** | Visible polish problem — wrong color role, weak hierarchy, cramped layout. |
| **P3** | Nice-to-have refinement. |

Every finding is tagged with the plan phase that owns it (see
`/Users/akshaysanjai/.claude/plans/lazy-chasing-shore.md`).

---

## 3. Systemic issues

### S1 — Three overlapping, disagreeing token systems · P1 · Phase 2.1
`lib/core/theme/app_colors.dart` defines **both** `NuvoColors` and `AppColors`;
`lib/core/theme/nuvo_tokens.dart` defines a third, `NuvoTokens`. They disagree on
the semantic colors:

| Role | `NuvoColors` | `NuvoTokens` | Result |
|---|---|---|---|
| success/green | `#66816C` (muddy olive) | `#23B26D` (vivid) | "verified" reads olive on some screens, green on others |
| danger/red | `#B8665E` (brick) | `#F04F59` (vivid) | failure states look brownish, not alarming |
| gold/silver/bronze | one set | a different set | podium colors shift between Arena and Race Detail |

`NuvoColors` also carries ~40 legacy aliases (`icyBlue`, `softBlue`, `blue2`,
`navySoft`, `sectionBlue`, …) that all collapse onto 3–4 real values, so call
sites read as if they're making a color choice when they aren't.

### S2 — No semantic color discipline · P1 · Phase 2.1
The owner's rule: **blue = neutral/brand, green = success, red = failure**. Today
blue is overloaded as the single "important" color — it's the progress arc, the
selected tab, the primary button, the celebration accent, *and* the link color —
so nothing stands out. Green (`NuvoColors.success`) is used for the celebration
screen accent inconsistently and for the Arena activity-stream icons; red is used
for both destructive actions and validation errors with no tint/border variants.

### S3 — No responsive scaling ("looks very different on each phone") · P1 · Phase 2.2
- Typography (`lib/core/theme/app_text_styles.dart`) is fixed px. Nothing multiplies
  by screen size.
- Individual screens then *hardcode* even bigger sizes on top: Arena title
  `fontSize: 44`, Arena hero number `fontSize: 58`, `email_start`/`email_verify`/
  `onboarding` headline `fontSize: 32`, Race Settings title `fontSize: 32`.
- Buttons are fixed 56/46 px (`lib/core/widgets/nuvo_button.dart`); Arena hero is a
  fixed 336–344 px `SizedBox`; the segmented control, nav bar, avatars, and cards
  are all fixed.
- `lib/core/widgets/bottom_nav.dart` pins `textScaler: TextScaler.linear(1)` in two
  places, defeating OS text-size settings for the nav labels while the rest of the
  app honours them → misaligned nav.
- `lib/app/app.dart` `_webPreviewBuilder` clamps web to a 430 px column, so the web
  preview is *not* representative of a real 360–400 px phone — small-screen bugs
  hide during development.

Net effect: on a 360 px phone, headers wrap oddly and the Arena `_QuickActions`
row (`flex: 4 / 2 / 2` of three buttons) crowds; on a large phone / tablet
everything floats in a sea of whitespace; with OS text size at max, fixed-height
buttons clip their labels.

### S4 — Button system is inconsistent · P1 · Phase 2.3
`lib/core/widgets/nuvo_button.dart` alone has 6 variants with 3 different shadow
behaviours:

| Widget | Fill | Border | Shadow |
|---|---|---|---|
| `NuvoPrimaryButton` | blue | navy | `hardMedium` |
| `NuvoOutlineButton` | white | navy | `hardSmall` (unless `flat`) |
| `NuvoGhostButton` | **transparent** | none | **none** |
| `NuvoDangerButton` | danger @ 9% alpha | danger | **none** |
| `NuvoBackButton` | white | navy | `hardSmall` |
| `NuvoIconAction` | `panelLight` | border | **none** |

On top of that, screens use raw Material `FilledButton` / `TextButton`
(`board_moved_screen.dart`, `race_settings_screen.dart` dropdowns,
`proof_review_screen.dart`) which the theme sets to `elevation: 0` — flat, no
shadow — and bespoke inline buttons (`arena_screen_fixed.dart` `_ArenaButton`:
transparent, no shadow). The owner wants **every tier filled + shadowed**; right
now roughly half the tappable "buttons" in the app are flat or transparent.

### S5 — Transparent text used as buttons · P1 · Phase 2.3
"See all", "Show less", "See all 12", "View all", the auth mode toggle, and the
legal links are bare `GestureDetector` + `Text` with no fill, no border, no
shadow, and frequently a sub-44 px hit area. Present on Compete, Move/Verify,
Arena, Race Detail, Welcome/Auth. Owner asked for zero exceptions → these become
small filled chips.

### S6 — Font pipeline bypassed in ~14 files · P2 · Phase 2 + 4
`GoogleFonts` / raw `TextStyle(` is called directly (outside `AppTextStyles`) in
`competition_ring.dart`, `nuvo_race_components.dart`, `nuvo_dark_card.dart`,
`nuvo_shared_components.dart`, `nuvo_avatar.dart`, `track_side_orbit.dart`,
`splash_screen.dart`, `welcome_auth_screen.dart`, `race_composer_screen.dart`,
`ai_motion_proof_screen_io.dart`, and the `arena/track_view/*` files. Each is a
place where weight/spacing/scaling silently diverges from the system.

### S7 — ~71 hardcoded `Color(0x…)` outside the theme · P2 · Phase 2 + 4
Concentrated in `splash_screen.dart` (`#FBFCFF`, `#1264FF`, gradient stops),
`welcome_auth_screen.dart`, `bottom_nav.dart`, `nuvo_board_components.dart`,
`ai_motion_proof_screen_io.dart`, `arena/track_view/*`, and the character/animation
painters. These won't move when the palette changes.

### S8 — Dead & shadowed code · P2 · Phase 2.4
- `lib/features/arena/presentation/arena_screen_trackside.dart` (908 lines) — not
  imported anywhere.
- `lib/features/arena/presentation/arena_screen.dart` and
  `lib/features/compete/presentation/compete_screen.dart` are 1-line
  `export '..._fixed.dart';` shims — the real screens are named `*_fixed`, which
  signals "temporary" and makes navigation confusing.
- `arena_screen_fixed.dart` has an unused private `_ArenaButton` *and* uses it in
  three states — actually used, keep, but restyle.
- `lib/features/arena/presentation/track_view/` — verify usage; `track_view_*` and
  `track_side_orbit.dart` / `trackside_layout_diagnostics.dart` look like
  abandoned experiments.

### S9 — Loading / empty / error state coverage is uneven · P1 · Phase 4
Compete, Move, Arena have all three. Submit Proof has skeletons. But:
- Race Settings shows a bare centered `CircularProgressIndicator` (no layout).
- `board_moved_screen.dart` has no error branch — a missing `args` silently
  defaults to `status: 'accepted'`, `value: 0` and shows a *success* celebration.
- Several `NuvoErrorState` "retry" buttons actually navigate away instead of
  retrying (`race_settings_screen.dart` "Only the race creator…" passes
  `onRetry: () => context.go(...)`).

### S10 — Accessibility gaps · P1 · Phase 4
- Icon-only buttons (`NuvoIconAction`, Arena `_QuickActions` add/join, back
  buttons) have no `Semantics` label / tooltip.
- The pinned `TextScaler.linear(1)` (S3) actively fights large-text users.
- Several status colors fail contrast on their tint (olive `#66816C` on white is
  ~3.4:1; brick danger text on the 9%-alpha danger fill is marginal).
- `_ArenaButton` and the "See all" texts are below the 44×44 minimum target.
- No `MediaQuery.boldTextOf` / high-contrast handling.

### S11 — `SafeArea` / inset handling is copy-pasted and inconsistent · P2 · Phase 4
`main_shell.dart` wraps non-Arena tabs in `SafeArea(bottom: false)` but Arena in a
raw `Stack` with a manually `Align`ed nav; each screen then re-adds its own
`MediaQuery.padding.top` (`compete_screen_fixed.dart` `_CompactHeader`) or a magic
`SizedBox(height: 32)` (`move_screen.dart`). Top spacing differs by ~14 px between
tabs.

### S12 — `flutter analyze`: 277 infos · P3 · Phase 2.5
0 errors, 0 warnings. Almost all are `avoid_print` in `test/motion_qa/**` and a
dozen `prefer_const` / `no_leading_underscores_for_local_identifiers`. Non-blocking
but it buries real signal; clean it so future regressions are visible.

---

## 4. Per-screen inventory

Format per screen: **Q** = does it answer *what is this / am I winning / what do I
tap*? · **Primary action** · **States** · **Findings**.

### 4.1 Splash (`splash_screen.dart`)
- **Q:** n/a (transient). **Primary:** none. **States:** single.
- Findings: all colors hardcoded (`#FBFCFF`, `#1264FF`, gradient stops) [S7];
  custom painters bypass theme; routes straight to `/welcome/intro` — fine, but
  there's no "restoring session, tap to retry" affordance for the offline-launch
  case (see B1). **P2.**

### 4.2 Welcome / Auth (`welcome_auth_screen.dart`)
- **Q:** yes / n/a / yes. **Primary:** "Continue with Email". **States:** signup
  vs login, "built a race" preview, per-provider loading + error.
- Findings:
  - **B4 (P1):** Apple button is `SignInWithAppleButton` (SF font, its own height &
    corner radius); Google button is a hand-built Manrope/navy/2 px control with a
    **fake "G"** in a grey circle; Email button is `NuvoPrimaryButton`. Three
    visual languages stacked vertically → "mismatched fonts on the login screen".
  - `Spacer()` inside a `SingleChildScrollView` + `ConstrainedBox(minHeight: maxHeight - 52)`
    — brittle; on a short screen with the keyboard up this can overflow. **P2.**
  - `_BrandMark` is a fixed 116×34 PNG, not scaled. **P3.**
  - Direct `Color(0x…)` and the fake G icon [S7]. **P2.**

### 4.3 Email start (`email_start_screen.dart`) & Email verify (`email_verify_screen.dart`)
- **Q:** yes / n/a / yes. **Primary:** "Send code" / "Verify".
- Findings: headline hard-set to `fontSize: 32` [S3]; "Resend code" is transparent
  text [S5]; after verify, routing diverges from Google — see **B2**. **P1.**

### 4.4 Welcome race builder (`welcome_race_builder_screen.dart`)
- Pre-auth race composer. Direct `GoogleFonts`/`Color` usage [S6][S7]; `LayoutBuilder`
  present but sizes still fixed. Full pass in Phase 4. **P2.**

### 4.5 Onboarding (`onboarding_screen.dart`)
- **Q:** yes / n/a / yes. **Primary:** "Continue".
- Findings: headline `fontSize: 32` [S3]; username-availability uses
  `NuvoColors.success`/`danger` (muddy) [S2]; `NuvoColors.panel.withValues(alpha: 0.58)`
  hand-mixed tint [S2]; otherwise structurally OK.

### 4.6 Arena (`arena_screen_fixed.dart`) — **highest cross-device risk**
- **Q:** yes / yes / yes. **Primary:** "Submit proof" (or open board). **States:**
  loading / error / empty / loaded, preview mode.
- Findings:
  - Fixed hero height 336–344 px with a `Flexible` child doing the absorbing — on
    a large OS text size the title + 58 px number + track + chase line + details
    **will** clip. **P1 [S3].**
  - `_QuickActions`: `Row` of `flex: 4/2/2` buttons; two of them are
    `NuvoOutlineButton(label: '', iconOnly: true)` — empty-string labels, icon-only,
    no semantics [S10]. On a 320 px screen the primary button's label ("Submit
    proof") + camera icon crowds. **P1.**
  - `_ArenaButton` (empty state, error state) is transparent / flat [S4][S5]. **P1.**
  - The blue footer bar of `_NextMoveHero` is a `GestureDetector` styled as a bar,
    not a button — inconsistent affordance. **P2.**
  - `_arenaGreen = NuvoColors.success` (olive) on activity icons [S2]. **P2.**
  - Hardcoded `fontSize: 44/58/28/24` [S3]. **P1.**
  - Custom `Stack` + manual nav `Align` in `main_shell.dart` for Arena only — the
    nav overlaps content on very short screens; `extendBody` logic branches on
    `isArena`. **P1 [S11].**
  - Header greeting is hardcoded **"Good evening"** regardless of time of day. **P2.**

### 4.7 Compete (`compete_screen_fixed.dart`)
- **Q:** yes / yes / yes. **Primary:** "Start" (header) — competes with the
  featured card's CTA. **States:** loading / error / empty / loaded, first-run guide.
- Findings:
  - **B5 (P1):** filters the whole list to
    `resolveCameraVerification(race).isCameraVerifiable` — every non-camera
    ("nonphysical") race is invisible here and on Move. Combined with the composer
    (§4.11) having no non-movement path, nonphysical goals are effectively
    unreachable.
  - Header has two competing CTAs ("Start" + "Join") *and* the featured card has
    its own → violates "one primary action". **P2.**
  - "See all" / "Show less" transparent text [S5]. **P1.**
  - Quick-start chips are horizontally scrolling 56 px `PressableScale` containers
    with no shadow [S4]. **P2.**
  - `_EmptyState` copy is fine but there is no distinct "you have races, just none
    in this section" placeholder — owner asked for real placeholder text. **P2 (§3.7).**
  - `_CompactHeader` re-adds `MediaQuery.padding.top` [S11]. **P2.**

### 4.8 Crew / Pass (`pass_screen.dart`, 726 lines)
- **Q:** partial — the screen mixes the member pass (identity/QR) with crew
  management; the "what is this" answer is muddy. **Primary:** unclear.
- Findings: one `fontSize` override; a `LayoutBuilder`; one transparent tap
  target. Needs a focal-point pass in Phase 4 — likely split "your pass" from
  "your crew" visually. **P1.**

### 4.9 Move / Verify (`move_screen.dart`)
- **Q:** yes / yes / yes. **Primary:** "Start verification" (Up-next card).
- Findings:
  - Same `isCameraVerifiable` filter as Compete [B5]. **P1.**
  - Segmented control fill = `NuvoColors.actionBlue` on `NuvoColors.navy` — blue on
    navy, low separation; selected border is the same blue (invisible) [S2]. **P2.**
  - Three separate "See all N" transparent texts [S5]. **P1.**
  - `_RecentProofRow` status colors: `NuvoColors.success` / `danger` / `muted`
    [S2]; "needs_review" → grey "Under review" is easy to miss. **P2.**
  - Root padding is a magic `SizedBox`-equivalent `EdgeInsets.fromLTRB(22, 32, …)`
    [S11]. **P2.**

### 4.10 Profile (`profile_screen.dart`) & Edit Profile (`edit_profile_screen.dart`)
- **Q:** yes / partial / yes. Findings: 3 semantic-color uses [S2]; photo upload is
  a 3-step flow (`auth_controller.uploadProfilePhoto`) with limited progress
  feedback; `debugPrint('REFRESHED_USER_PHOTO_URL…')` left in
  (`auth_controller.dart`, `auth_api.dart` — several). Phase 4 pass. **P2.**

### 4.11 Race Composer (`race_composer_screen.dart`, 2005 lines) — `/races/new`
- **Q:** yes (per step) / n/a / yes. **Primary:** "Next" / "Create race". **Steps:**
  name → activity → goal → racers → review.
- Findings:
  - **B5/§3.5 (P1):** `activity` step is movement-only (`MotionActivityDefinition`
    catalog). No "manual / honor / daily check-in / photo / link" goal kind, even
    though `race_settings_screen.dart` *has* a non-camera editing branch and the
    Worker + `race_repository` already persist `goalType` / `proofRequirement` /
    `proofReviewMode`.
  - 2005 lines in one file, direct `GoogleFonts` / `Color` usage [S6][S7]. **P2.**
  - `minHeight: MediaQuery.of(context).size.height - …` inside a scroll view — the
    only place that reads raw screen height; fragile with keyboard. **P2.**
  - "Teach a movement" is a demoted text link [S5]. **P2.**
  - `_StepButton` +/- controls: bespoke, unshadowed [S4]. **P2.**

### 4.12 Race Settings / "Edit race" (`race_settings_screen.dart`) — `/race/:id/settings` **and** `/race/:id/edit`
- **Q:** yes / n/a / yes. **Primary:** "Save changes".
- Findings:
  - **B3 (P1):** `router.dart` maps *both* `/race/:id/settings` and `/race/:id/edit`
    to this exact screen, and `race_detail_screen.dart` (~line 560–569) shows *both*
    a "Edit race" and a "Race settings" menu item → "Edit Race and Race Settings are
    the same page".
  - The non-camera "Moves" section renders a dead dropdown:
    `_Menu(value: 'unsupported', values: {'unsupported': 'unsupported movement'}, onChanged: (_) {})`
    — a control that looks interactive and does nothing. **P1 [S10].**
  - Uses raw `DropdownButtonFormField` with a hand-rolled `InputDecoration` instead
    of the themed input [S4]. **P2.**
  - Lifecycle actions (Archive / Cancel / Delete) are `NuvoGhostButton` (transparent)
    + `NuvoDangerButton` (flat tint) [S4]. **P1.**
  - Loading state is a bare centered spinner [S9]. **P2.**
  - "Only the race creator can edit" error's retry button navigates away [S9]. **P2.**

### 4.13 Race Detail (`race_detail_screen.dart`, 1732 lines)
- **Q:** yes / yes / yes. **Primary:** "Submit proof". **States:** loading / error /
  the leaderboard room.
- Findings: duplicate Edit/Settings menu items [B3]; 6 semantic-color uses [S2];
  proof-status mapping duplicated here vs Move vs Celebration vs Proof Review with
  slightly different label wording (§5 B6); needs a focal-point pass (leaderboard
  should dominate). **P1.**

### 4.14 Submit Proof (`submit_proof_screen.dart`)
- **Q:** yes / n/a / yes. **Primary:** "Begin" (camera).
- Findings:
  - For camera races with a demo it shows a centered pre-verify screen; without a
    demo it *auto-pushes* to `/proof/ai-motion` from `initState` → a flash of this
    screen then a second navigation. **P2.**
  - Non-camera races get the `_UnsupportedVerificationCard` ("videocam off / this
    proof type is not available") instead of a manual-entry path — the other half
    of [B5]. **P1 (§3.5).**
  - "Back to race" / "View race" are `NuvoGhostButton` (transparent) [S4]. **P1.**
  - Bottom bar always reserves camera-button height even for the error/unsupported
    case → dead space. **P2.**

### 4.15 AI Motion Proof (`ai_motion_proof_screen_io.dart`, 1767 lines)
- **Q:** partial. **Primary:** implicit (the camera counts).
- Findings (UI only — no ML changes):
  - ~~Developer internals surface in the UI path~~ **Corrected on review:** the
    `validatorState=` / `confidence=` traces (lines ~441–525) are all inside
    `_debugLog()`, which is wrapped in `assert(() {…}())` — debug-build only,
    never shipped or rendered. The on-screen debug widgets (lines ~975, ~1181)
    are already `if (kDebugMode …)` gated. No action needed. **Resolved.**
  - 10 semantic-color uses, 1 `fontSize` override, direct `Color`/`GoogleFonts` [S2][S6][S7].
  - State coverage vs the `docs/agents/07` §4 table is incomplete — no distinct
    "poor light" / "move back" / "needs review" visual treatments; retry/submit
    actions can appear together. **P1.**
  - See §5 for suspected status-mapping bugs.

### 4.16 Celebration / Board Moved (`board_moved_screen.dart`)
- **Q:** yes / yes / yes. **Primary:** "View race".
- Findings:
  - Owner wants it **fully green**; today it's `NuvoColors.navy` with a
    `NuvoColors.blue` check circle. **P1 (§3.6).**
  - Animation is minimal (one scale + a few `fadeIn`s). Owner wants "fun". **P2 (§3.6).**
  - Haptics exist (`mediumImpact` / `selectionClick` / `lightImpact`) — keep, add a
    landing tick. **P3.**
  - No `args` → silently renders a success celebration with `#0` rank and `+0`
    value [S9]. **P1.**
  - "View race" is a raw `FilledButton` (flat); "Record again" is transparent text
    [S4][S5]. **P1.**
  - `_RejectedView` "Try again" is a raw `FilledButton` with a bare `Text` child
    (no style) — will render in the default theme size. **P2.**

### 4.17 Proof Review (`proof_review_screen.dart`)
- Reviewer accept / needs_review / reject. `NuvoColors.success`/`danger`/`muted`
  status colors [S2]; three action buttons of differing weight. Phase 4. **P2.**

### 4.18 Invite Crew (`invite_crew_screen.dart`) & Join Race (`join_race_screen.dart`)
- Not yet deep-read; scheduled for Phase 4. Expect the same token / button issues.

---

## 5. Functional bugs

### B1 — "Logs users out every single time" · P0 · Phase 3.1
Two client-side amplifiers turn any transient hiccup into a permanent logout:

1. `SecureTokenStore` (`lib/features/auth/data/secure_token_store.dart`): **every**
   catch block calls `_nativeClearAll()` → `_secureStorage.deleteAll()`. A single
   Keychain read that throws (common on iOS cold start before first unlock, or a
   `PlatformException` during a system update) wipes **both** tokens.
2. `AuthRepository.restoreSession()` (`lib/features/auth/data/auth_repository.dart`):
   catches **any** `ApiException` from `/auth/refresh` *or* `/auth/me` and calls
   `_store.clear()`. So a transient 500, a 429, or launching offline (network
   error is rethrown, but a 5xx from a cold Worker is an `ApiException`) → tokens
   cleared → back to `/welcome`.

It also always calls `getMe(accessToken, resetDemo: true)` on restore, which runs
the heavy `resetTestDemoAccount` server path for the demo account on *every*
launch.

**Fix (Phase 3.1):** only `clear()` on a definitive **401** from `/auth/refresh`;
keep tokens on network / 5xx / Keychain-read errors and expose a "couldn't reach
server, retry" auth state; retry a Keychain read once before giving up; stop
wiping *all* keys on a single-key error; drop `resetDemo: true` from the generic
restore path.

### B2 — Email login behaves differently from Google · P1 · Phase 3.2
`auth_gate.dart` `RouterNotifier.redirect`:
```
if ((user.isDemo || authState.guideFirstRace) && loc.startsWith('/auth/'))
  return '/welcome/intro';
```
After **email** verify the user is on `/auth/verify` and `guideFirstRace` is
`true`, so they're bounced to `/welcome/intro` (the pre-auth race builder) instead
of into the app. **Google/Apple** sign-in happens from `/welcome` (not `/auth/*`),
so that branch doesn't fire and they land on `/onboarding/profile` or `/compete`.
Same backend (`auth.ts` — email/google/apple all call `createSession` identically
and return the same shape), different client routing.

**Fix (Phase 3.2):** base the post-auth destination on `onboardingComplete` +
`guideFirstRace` only, never on whether `loc` starts with `/auth/`. Add a widget
test asserting identical routing for an email `AuthUser` and a Google `AuthUser`.

### B3 — "Edit Race" and "Race Settings" are the same page · P1 · Phase 2.4
`router.dart` lines 165–178: `/race/:id/settings` and `/race/:id/edit` both build
`RaceSettingsScreen`. `race_detail_screen.dart` shows both menu items.
**Fix:** one menu entry, one screen titled "Edit race"; keep `/settings` as a
redirect alias.

### B4 — Apple / Google / Email buttons are visually inconsistent · P1 · Phase 3.3
See §4.2. The owner has confirmed Apple sign-in **cannot complete yet** (server
`APPLE_BUNDLE_ID` / Services ID / nonce not configured — `server/worker/src/lib/apple.ts`)
and that this is expected. Scope here is **visual only**: rebuild all three
provider buttons on one shell (same height, Manrope label, consistent border/fill,
real provider glyphs), and make the failure/loading states identical. Keep the
real Apple call wired.

### B5 — Nonphysical goals are unreachable · P1 · Phase 3.5
Composer offers movements only (§4.11); Compete + Move filter them out (§4.7/4.9);
Submit Proof shows "unsupported" (§4.14). The data model and Worker already
support `goalType` / `proofRequirement` (`manual | photo | note | link | daily_check`).
**Fix:** add a goal-kind branch to the composer, stop the `isCameraVerifiable`
filter on Compete/Move, and give non-camera races a manual-entry proof sheet.

### B6 — Proof-status handling is duplicated and lenient · P1 (confirm before code) · Phase 3.4
Status strings in play: `ai_verified`, `accepted`, `ai_failed`, `rejected`,
`needs_review`, plus `ai_pending`/`logged` implied.

- `race_models.dart:456` — `RaceProof.fromJson` defaults an **unknown / missing**
  `verificationStatus` to `'accepted'`. That's a silent success on malformed data
  (violates `docs/agents/07` §2 "no silent success").
- `board_moved_screen.dart` — `BoardMovedArgs.status` defaults to `'accepted'`; a
  celebration with no args renders as a verified rank-up.
- `push_up_counter.dart:11` hardcodes `verificationStatus: 'needs_review'` for
  every push-up result, while `jumping_jack_counter.dart` and
  `motion_validators.dart` emit `ai_verified` / `ai_failed`, and
  `ai_motion_proof_screen_io.dart:659` hardcodes `'ai_verified'` on one accepted
  path. Inconsistent — a verified push-up always lands in "review".
- The verified/failed label + color mapping is re-implemented in `move_screen.dart`,
  `race_detail_screen.dart` (×2), `proof_review_screen.dart`, and
  `board_moved_screen.dart`, each with slightly different wording ("Not counted" vs
  "Move didn't count" vs "Not verified").

**Recommendation:** one `ProofStatus` enum + one `proofStatusPresentation(status)`
helper (label + semantic color + icon) in `lib/features/races/domain/`, an explicit
`unknown` case that is **not** treated as success, and owner confirmation on the
push-up `needs_review` behaviour before touching it (it may be intentional — the
counter file is validator-adjacent).

### B7 — Dead controls · P2 · Phase 2.4 / 4
- Race Settings "Move method" dropdown (§4.12) — interactive-looking, `onChanged: (_) {}`.
- Arena `_NextMoveHero` footer bar reads as a button but is a `GestureDetector`.
- `race_settings_screen.dart` "Back to race" duplicates the back button.

### B8 — Leftover debug output in production paths · P3 · Phase 2.5 / 3
`debugPrint` calls with `REFRESHED_USER_PHOTO_URL`, `PATCH_PROFILE_PHOTO_URL`,
`UPLOAD_PUBLIC_URL`, `[TokenStore] …`, `[AuthApi] …`, `[Router] …` run in profile
builds. Gate behind `kDebugMode` or a logger.

### B9 — Network calls hang forever; races tab can wedge until app kill · P0 · Fixed
Reported: after sign-out → sign-in, Arena loaded but Compete showed a blank grey
area with no skeleton, and only an app restart (after a long wait) recovered it.

Root causes:
1. **No HTTP timeout anywhere.** `RaceApi`, `AuthApi`, `ArenaApi` all call
   `http.Client` with no `.timeout(...)`. A stalled socket (cold launch, flaky
   Wi-Fi, VPN) hangs the request — and therefore `getRaces()` / `fetchArenaSnapshot()`
   / `restoreSession()` — indefinitely.
2. **`_loadInFlight` was never cleared on sign-out.** `RaceController.clearRaces()`
   / `ArenaController.clearSnapshot()` reset state + `_…LoadedAt` but kept the
   in-flight future. If a load was hung when the user signed out, the next
   sign-in's `loadRaces(force: false)` returned that dead future and never issued
   a fresh request — the tab stayed empty/non-loading/non-error forever.
3. **CompeteScreen never triggered its own load.** It was a pure `ref.watch`
   consumer; the only load triggers were provider-creation and the auth listener.
   When those were wedged (cause 2) the screen had no way to self-heal.
4. **No skeleton.** Compete's only loading affordance was a bare
   `CircularProgressIndicator` gated on `loading && races.isEmpty`; in the wedged
   state neither was true, so the user saw nothing.
5. Minor: `_get`/`_post` called `jsonDecode(res.body)` before the status check, so
   a non-JSON error page (Cloudflare 5xx HTML, empty 502) threw an opaque
   `FormatException` instead of a clean `ApiException`.

Fixes: 20 s hard timeout on every request in all three API clients, mapping
`TimeoutException` / `SocketException` / `ClientException` → `ApiException`
(408 / 0) with friendly copy; `clearRaces()` / `clearSnapshot()` now also null
`_loadInFlight`; `CompeteScreen.initState` kicks `loadRaces(force: false)` when
the tab is genuinely cold (empty, not loading, no error); Compete loading state
is now a shimmer skeleton (`_CompeteSkeleton`); JSON decode tolerates non-JSON
bodies. `restoreSession` already treats a 408 as `RestoreUnreachable` (keeps
tokens, offline retry) rather than a logout.

---

## 6. Prioritised backlog

| ID | Title | Sev | Phase |
|---|---|---|---|
| B1 | Session cleared on any transient error | P0 | 3.1 |
| B6 | Unknown proof status defaults to success | P0→confirm | 3.4 |
| S9 | Celebration renders success with no args | P1 | 3.6 |
| B2 | Email ≠ Google post-auth routing | P1 | 3.2 |
| B3 | Edit vs Settings duplication | P1 | 2.4 |
| B4 | Provider buttons visually inconsistent | P1 | 3.3 |
| B5 | Nonphysical goals unreachable | P1 | 3.5 |
| S1 | Fragmented token systems | P1 | 2.1 |
| S2 | No semantic color discipline | P1 | 2.1 |
| S3 | No responsive scaling | P1 | 2.2 |
| S4 | Inconsistent button system | P1 | 2.3 |
| S5 | Transparent text-as-buttons | P1 | 2.3 |
| S9 | Uneven loading/empty/error states | P1 | 4 |
| S10 | Accessibility gaps | P1 | 4 |
| 4.6 | Arena cross-device layout | P1 | 4 |
| 4.15 | AI Motion Proof shows dev internals | P1 | 3.4 |
| B7 | Dead controls | P2 | 2.4 / 4 |
| S6 | Font pipeline bypassed | P2 | 2 / 4 |
| S7 | Hardcoded colors | P2 | 2 / 4 |
| S8 | Dead code (`arena_screen_trackside`, shims) | P2 | 2.4 |
| S11 | Inconsistent SafeArea/insets | P2 | 4 |
| §3.6 | Celebration is navy, weak animation | P1/P2 | 3.6 |
| §3.7 | Compete lacks real placeholder copy | P2 | 3.7 |
| B8 | Debug output in prod | P3 | 2.5 / 3 |
| S12 | 277 analyzer infos | P3 | 2.5 |
| — | Arena "Good evening" hardcoded | P2 | 4 |

## 7. What's already fixed (this pass)

Tracked in detail in `/Users/akshaysanjai/.claude/plans/lazy-chasing-shore.md`.
Summary:

- **App icon** — Icon-Composer "M" flattened onto field-blue `#438FFD`,
  regenerated for iOS + Android.
- **Design system** — one semantic token set from the owner's palette PNG
  (S1/S2); `NuvoSemanticColors` extension. **`flutter analyze lib/` is clean**
  (S12: 291 → 32 project-wide, 0 in `lib/`).
- **Responsive** (S3) — `context.rs()` + app-wide `TextScaler` clamp.
- **Buttons** (S4/S5) — every tier filled + shadowed; ghost/transparent gone.
- **Dead code** (S8) — 8 widget files + a stale test removed.
- **B1** session persistence, **B2** email = Google routing, **B3** Edit/Settings
  dedup, **B4** provider-button parity, **B5** nonphysical goals (create + act +
  celebrate), **B6** silent-success default + shared `proofStatusPresentation`,
  **B7** dead "Move method" dropdown.
- **Celebration** — fully green with a burst + count-up (§3.6).
- **Leaderboard** — `NuvoPodium` from the Changers-team reference, wired into the
  race board.
- **Test status** — 37 pre-existing failures at commit `319ce14` (stale
  compete/quality-gate/submit-proof tests from an earlier incomplete refactor),
  **0 regressions** from any of the above.
