# Pitfalls & fixes — every issue this codebase has hit, and how not to recreate it

This is the "learn from our scars" file. Each entry: **symptom → root cause →
fix → the rule that prevents it**. If you are about to touch networking, auth,
routing, layout scaling, or tests, read that section first.

Format of a fix reference: `commit <sha>` is where it landed. `AGENTS.md` and
[`../FULL_APP_AUDIT_2026-08.md`](../FULL_APP_AUDIT_2026-08.md) hold the wider
backlog; this file is the "why it broke" companion.

---

## A. Networking / API clients

### A1 — A network call hangs forever; a tab goes blank and needs an app kill
**Symptom:** after sign-out → sign-in, Arena loaded but Compete showed a blank
grey area with no skeleton; only killing and relaunching the app (after a long
wait) recovered it.
**Root causes:**
1. **No HTTP timeout anywhere.** `RaceApi`, `AuthApi`, `ArenaApi` called
   `http.Client` with no `.timeout()`. A stalled socket hangs the request — and
   therefore `getRaces()` / `fetchArenaSnapshot()` / `restoreSession()` —
   indefinitely.
2. **The in-flight future was never cleared on sign-out.**
   `RaceController.clearRaces()` / `ArenaController.clearSnapshot()` reset the
   state and the "loaded-at" timestamp but kept `_loadInFlight`. A load that was
   hung at sign-out meant the next sign-in's `loadRaces(force:false)` returned
   that dead future and never issued a fresh request.
3. **The screen never triggered its own load.** `CompeteScreen` was a pure
   `ref.watch` consumer; its only load triggers were provider-creation and the
   auth listener. When those wedged, it could not self-heal.
4. **No skeleton.** Compete's only loading UI was a bare `CircularProgressIndicator`
   gated on `loading && races.isEmpty`; in the wedged state neither was true.
5. `_get`/`_post` called `jsonDecode(res.body)` *before* the status check, so a
   non-JSON error page (Cloudflare 5xx HTML, empty 502) threw an opaque
   `FormatException` instead of a clean `ApiException`.
**Fix (`commit 5df7064`):**
- 20 s hard `.timeout()` on every request in all three API clients; map
  `TimeoutException` / `SocketException` / `http.ClientException` →
  `ApiException(408 | 0, <friendly copy>)`.
- `clearRaces()` / `clearSnapshot()` also set `_loadInFlight = null`.
- `CompeteScreen.initState` calls `loadRaces(force:false)` when the tab is cold
  (`races.isEmpty && error == null && !loading`) — never stomps in-flight,
  populated, or error state.
- Compete loading state is a shimmer skeleton (`_CompeteSkeleton`).
- JSON decode tolerates non-JSON / empty bodies.
**Rules:**
- **Every `http.Client` call gets a `.timeout()`** and maps transport errors to
  `ApiException`. Copy the `_guard` + `_decode` helpers in `race_api.dart`.
- **Any `*Controller` with an `_loadInFlight` / cache field must null those in
  its `clear*()` method.** A `StateNotifierProvider` is *not* recreated on
  sign-out — only its `state` is reset by you. Internal fields persist across
  sessions unless you clear them.
- A screen that depends on shared state for its content should trigger a
  cold-load in `initState` (guarded), not assume something else did.
- A `408` from a timeout must be treated as *offline / retry*, never as a reason
  to sign the user out (`restoreSession` already does this — keep it).

### A2 — Raw backend error text shown to the user
**Symptom:** "Internal Server Error" / a stack string appears in the UI.
**Rule:** `NuvoErrorState.message` and any user-facing error string is **friendly
copy written by us** ("Couldn't load your races."). Never pass `e.message` /
`error.toString()` straight through. Log the raw error with `debugPrint`, show
the friendly one.

---

## B. Auth / session persistence

### B1 — "Logs users out every single time"
**Symptom:** every cold launch (or a transient server blip / offline launch)
dropped the session back to `/welcome`.
**Root causes:**
- `SecureTokenStore` called `deleteAll()` (every Keychain key) on **any single**
  read/write exception.
- `AuthRepository.restoreSession()` called `_store.clear()` on **any**
  `ApiException` — a transient 500 or an offline launch became a permanent
  logout — and always passed `resetDemo: true`.
**Fix (`commit dcbaae1`):**
- `SecureTokenStore`: retry a read once; never wipe on a transient error;
  `clear()` deletes only the two Nuvo keys, not the whole Keychain.
- `restoreSession()` returns a sealed `RestoreResult` — `RestoreOk(user)` /
  `RestoreNoSession()` / `RestoreUnreachable()`. It only clears tokens on a
  **definitive 401/404**. Network errors / 5xx / timeouts → `RestoreUnreachable`,
  tokens kept.
- New `AuthStatus.offline` + a `_OfflineRetry` state on `/splash`.
- `resetDemo` dropped from the generic restore path.
**Rules:**
- Storage errors are transient. **Retry, don't wipe.**
- Only a server that explicitly says "this session is invalid" (401/404) may
  clear tokens. Everything else keeps them and shows a retry.
- `restoreSession` returns `RestoreResult`, not `AuthUser?`. Any test double
  overriding it must return `RestoreOk(const AuthUser(...))` /
  `const RestoreNoSession()`.

### B2 — Email login behaves differently from Google
**Symptom:** signing in with an email code dropped the user into the pre-auth
race-builder demo; Google sign-in landed in the app. Race page wouldn't load
unless you'd used Google.
**Root cause:** `auth_gate.dart` `redirect` branched on
`loc.startsWith('/auth/')` — email verify happens at `/auth/verify`, so
`guideFirstRace` users got sent to `/welcome/intro`. Google starts from
`/welcome` and skipped that branch.
**Fix (`commit dcbaae1`):** the authenticated destination depends **only** on
`user.onboardingComplete` + `authState.guideFirstRace` — never on which route
sign-in originated from.
**Rule:** **post-auth routing is provider-agnostic.** Email, Google, and Apple
must always land in the same place. Never reintroduce a `loc.startsWith('/auth/')`
(or any origin-route) branch in the redirect. See `NAVIGATION_MAP.md` rule 8.

### B3 — Apple sign-in doesn't complete
**Status:** not a client bug. The Worker needs `APPLE_BUNDLE_ID`, a Services ID,
and nonce config that the owner has not set up. The button is kept and made
**visually identical** to Google/email (one `_ProviderButton` shell — same
height, border, shadow, Manrope). Don't delete the flow; don't fake a success.

### B4 — "Edit race" and "Race settings" were the same page, twice
**Root cause:** `router.dart` mapped both `/race/:id/settings` and
`/race/:id/edit` to `RaceSettingsScreen`, and `race_detail_screen.dart` showed
both menu items.
**Fix:** `/race/:id/edit` is now a `redirect` to `/settings`; one "Edit race"
menu entry; the dead "Move method" dropdown removed.
**Rule:** **one route per screen.** If two paths must show the same screen, one
is a `redirect`, not a second `pageBuilder`.

---

## C. Navigation / routing

### C1 — The same race opened different screens from different places
**Symptom:** Arena "see board" and Compete "view" showed different screens; the
Compete featured card opened the camera when you had no progress yet.
**Root cause:** Compete's featured card navigated to `/race/:id/proof` when
`pct == 0`; every other race tap went to `/race/:id`. Arena's leaderboard was
built from a different data source (`ArenaBoard.miniLeaderboard`) than the race
page.
**Fix (`commit dcbaae1`, `9e427dc`):** every race tap → `/race/:id`. Arena's
standings are built from `serverRankedParticipants(raceById[board.id])` and
render the **same** `NuvoPodium` as Race Detail.
**Rule:** **every "open a race" tap in the whole app goes to `/race/:id`.**
Verify / invite / settings / log-progress are actions *on that screen*, never a
list-tap destination. When two surfaces show "the same" data, they must read the
same source function. Full rules: `NAVIGATION_MAP.md`.

### C2 — Back-swipe into a stale draft / finished recording / celebration
**Root cause:** create/join used `context.push`; the AI-motion → celebration
step used `pushReplacement` into a screen that then popped into a dead-end
submit-proof screen.
**Fix:** flows that *complete* end with `context.go` (or `pushReplacement` for a
linear step). Celebration exits with `context.go('/race/:id')`.
**Rule:** after a create/join/finish flow use `go`; after opening a detail
screen to *look at* use `push`. `NAVIGATION_MAP.md` §4 is the verb table.

### C3 — `context.pop()` crashes on a deep-linked screen
**Rule:** every manually-placed back button calls `safePopOrGo(context,
fallback)`. Bare `context.pop()` is only for dialogs / bottom sheets.

### C4 — A route that needs `extra:` breaks on a cold deep link
`extra:` is not serialized. `/race/:id/board-moved` (needs `BoardMovedArgs`) and
`/auth/verify` (needs the email) both have safe null fallbacks — keep them.
Prefer path/query params for anything that must survive a cold link.

---

## D. Responsive / "the app looks different on every phone"

### D1 — Fixed pixels everywhere
**Root cause:** the app was authored at ~390 px logical width with hard-coded
sizes; `bottom_nav.dart` even pinned `TextScaler.linear(1)`.
**Fix (`commit dcbaae1`):** `lib/core/theme/nuvo_responsive.dart` —
`context.rs(px)`, `TextStyle.scaled(context)`, width buckets; a single
app-wide `TextScaler` clamp `[0.85, 1.30]` via `NuvoTextScaleScope` in
`app.dart`.
**Rule:** wrap size-like values in `context.rs()`. Never pin `TextScaler`
anywhere again. Test at 320 / 390 / 430 / tablet widths and at max OS text size.

### D2 — Button text truncates to "Submit…" on small screens
**Symptom (owner, verbatim):** "when my friends use the phone and their screen is
smaller the text shows … like in the arena screen it goes from submit proof to
submit…".
**Root cause:** button labels were plain `Text` with ellipsis overflow inside a
constrained `Row`.
**Fix (`commit 5df7064`):** `_buttonContent` in `nuvo_button.dart` wraps every
label in `FittedBox(fit: BoxFit.scaleDown)` — a too-narrow button scales the
label down a hair instead of clipping it. This is a **widget-level** fix; it
needs no layout change.
**Rule:** solve label-fit at the button widget, not by restructuring a screen's
layout. When we first "fixed" this by stacking Arena's `_QuickActions` into a
`Column`, the owner disliked it — we reverted to the one-row layout
(`commit 890c67b`) and kept the `FittedBox` as the real fix. Don't reach for a
layout change when a text-fit change will do.

### D3 — Auto-scaling controls broke layout tests
**Symptom:** widget tests on the default 800×600 test surface failed after
button height started scaling by shortest-side factor (→ 1.18× taller buttons).
**Fix:** `_buttonShell` scales height **only when width ≥ 430 px**, capped at
1.10×. Small screens and test viewports keep the exact designed height.
**Rule:** device-size scaling must be a no-op at typical test surface sizes, or
it silently rewrites every layout golden.

### D4 — `Spacer()` inside a `SingleChildScrollView`
Unbounded-height crash risk. Don't. Use explicit `SizedBox` / `Expanded` inside
a bounded parent.

---

## E. Flutter rendering gotchas

### E1 — Rounded-border corners look chewed off
`Container(decoration: BoxDecoration(border: …, borderRadius: …), clipBehavior:
Clip.antiAlias)` clips the **outer half of the border** at every rounded corner.
**Fix:** put the border on the `Container`, wrap the child in a `ClipRRect` with
`radius - borderWidth`. Reusable as `_OutlinedSheet` in `race_detail_screen.dart`
/ `arena_screen_fixed.dart` / `pass_screen.dart`. (An alternative that also
works: draw the border again via `foregroundDecoration`.)
**Rule:** never `Container(border) + clipBehavior` for a bordered container whose
children need clipping.

### E2 — `Shimmer` animates forever → `pumpAndSettle()` hangs
The `shimmer` package's animation never settles. Any widget test that reaches a
shimmer skeleton and calls `pumpAndSettle()` will time out.
**Rule:** only render a shimmer while `loading` is true; loading-state tests use
`await tester.pump()` (one frame), never `pumpAndSettle()`. Give the skeleton a
`ValueKey` so tests can `find.byKey` it.

---

## F. Colours & design system

### F1 — Three token systems that disagreed
`NuvoColors`, `AppColors`, and `NuvoTokens` all defined colours; green was a
muddy olive in one and vivid in another; red was brick vs vivid.
**Fix (`commit dcbaae1`):** `NuvoColors` semantic values retuned to the owner's
palette reference (green `#3BC448`, red `#DC2529`, orange `#EA8E1C`, gold
`#F1C22D`, neutral blue `#1961F2`, tan `#E2C9B5`), each with `Shadow` / `Bright`
/ `Surface` / `Border` / `On` stops. `NuvoColorRole` + `NuvoSemanticColors`
`ThemeExtension` + `context.semanticColors`.
**Rules:**
- **No new colour without a semantic token.** Add it to `app_colors.dart`.
- Blue is never a success/failure signal; green/red are never decorative.
- Prefer `context.semanticColors.<role>` in new code so roles are themeable in
  one place.

### F2 — Transparent buttons / hard shadows on flat content
Ghost buttons had no fill and no shadow; some content cards carried hard
offsets.
**Fix:** every button tier is filled + shadowed (`nuvo_button.dart`).
**Rule (enforced):** a hard-offset shadow means "tap me." Buttons and tappable
cards get one; leaderboards, podiums, progress cards, list rows stay flat (navy
border only). A bare `Text` in a `GestureDetector` is not a button.

### F3 — "Produce more colour variety"
The owner asked for more colour on Profile, Crew, and Verify. Done by tinting
**existing semantic roles** into those surfaces (verify segment tabs
blue/green/amber; profile header stats blue/green/amber/gold; crew section ticks
+ closest-race status green/red/amber). Not by adding new hues.
**Rule:** "more colour" = apply the semantic roles more widely, not invent a
palette.

---

## G. Proof / verification

### G1 — Silent success: an unknown proof status counted as verified
**Root cause:** `RaceProof.fromJson` / `race_models.dart` defaulted an
unrecognised `verificationStatus` to `'accepted'`.
**Fix (`commit dcbaae1`):** default is `'needs_review'`. New
`lib/features/races/domain/proof_status.dart` — one `ProofStatus` enum
(`verified / needsReview / notVerified / pending / unknown`) +
`proofStatusPresentation()` (label / colour / icon). `unknown` never renders as
success.
**Rules:**
- **No silent success.** A failed, uncertain, missing, or unmapped result stays
  visibly non-verified.
- Never colour a non-`verified` result green. `needsReview` = amber,
  `notVerified` = red, `verified` = green.
- The celebration screen with no args renders a neutral state, not a fake green
  success.

### G2 — Non-camera ("nonphysical") goals were impossible to create or act on
**Root cause:** the composer's activity step was movement-only; Compete and Move
filtered the race list to `resolveCameraVerification(race).isCameraVerifiable`,
hiding every manual/check-in/photo goal.
**Fix (`commit dcbaae1`):** `RaceGoalKind { movement, manual }` on `RaceDraft`
(+ manual create payload); composer gets a Movement / Custom-goal toggle;
Compete & Move stopped filtering; `submit_proof_screen` shows a `_ManualLogCard`
+ "Log progress" for non-camera races → celebration.
**Rule:** the data model already supports `goalType` / `proofRequirement` /
`proofReviewMode`. Don't re-add a client-side filter that hides valid races.

---

## H. Ranking & display

### H1 — Tied scores showed "2nd, 2nd" / "Tied"
**Owner ask:** "if multiple people have the same amount don't just do 2nd or the
same rank — just rank one above the other for now."
**Fix:** `serverRankedParticipants(race)` sorts deterministically;
`positionalRank(race, userId)` returns the 1-based index so tied server ranks
render as distinct 1, 2, 3, 4. `rankForUser` prefers `finalStandings` then falls
back to positional.
**Rule:** display rank comes from `race_display.dart` helpers, never formatted
inline in a widget.

---

## I. Testing

### I1 — `flutter test` (bare) launches a runaway
`test/motion_qa/` contains long-run harnesses (`motion_lab_overnight_test.dart`,
`motion_lab_validation_test.dart`, …) that run hundreds of thousands of search
iterations and write ~1 GB of artifacts. A bare `flutter test` runs them.
`--exclude-tags` does not help — they are not tagged.
**Rule:** run an explicit set:
```bash
flutter test --concurrency=4 test/*.dart test/arena/
```
Never run `test/motion_qa/` unless that is the explicit task.
`test/motion_qa/lab/` and `test/motion_qa/experiment_results/` are gitignored
(they were ~967 MB tracked once).

### I2 — Regression baseline & the `[E]` suffix
There is a standing set of **pre-existing** failures (≈37 in the focused UI
suite, ≈40 across the full runnable suite — the extra are ML-threshold tests
like `airborne_state_tracker_test.dart` that are out of scope). Judge a change by
**new** failures only:
```bash
# capture baseline once on the untouched tree
flutter test --concurrency=4 test/*.dart test/arena/ 2>&1 \
  | grep -oE "test/[a-z_/]+\.dart: [A-Za-z].*\[E\]" | sed 's/ \[E\]$//' | sort -u > /tmp/base_f.txt
# after your change, same command → /tmp/cur_f.txt
comm -13 /tmp/base_f.txt /tmp/cur_f.txt      # <-- must be empty
```
Strip the trailing ` [E]` before diffing (older baselines were captured without
it). `timeout` is not on macOS — use `gtimeout` or omit.

### I3 — Signature / copy changes cascade into test doubles
- Changing `restoreSession()`'s return type broke 13 test files whose
  `_FakeAuthRepo extends AuthRepository` overrode it. When you change a
  repository method signature, `rg` for `extends AuthRepository` /
  `extends RaceRepository` and fix every double in the same commit.
- Changing user-facing copy (e.g. empty-state title) breaks any test asserting
  the old string. Update the assertion **to the new copy** in the same commit —
  don't weaken the test to `findsWidgets`.
- When a screen's design changes intentionally (e.g. Arena quick-action button
  tiers), update its smoke test to the new structure; don't leave it red.

### I4 — Never hide a failure
Do not weaken an assertion, add a fake success state, swallow an API error, or
add mock fallback data to a production path to make a test pass. `AGENTS.md`.

---

## J. App icons (iOS 18 layered)

**Symptoms hit:** black/rounded-corner margin around the mark; the tinted
variant rendered too dark and low-contrast.
**Facts:**
- iOS cannot take an icon with alpha or a pre-rounded corner — the source PNG
  must be a full-bleed opaque square. Flatten the Icon Composer export onto its
  field colour.
- iOS 18 layered icons need three 1024s — Default, Dark, Tinted — wired through
  `flutter_launcher_icons` (`pubspec.yaml`):
  `image_path_ios_dark_transparent`, `image_path_ios_tinted_grayscale`,
  `desaturate_tinted_to_grayscale_ios: true`, `remove_alpha_ios: true`. That
  produces an appearance-based `Contents.json` with
  `appearances: [{appearance: luminosity, value: dark|tinted}]`.
- The tinted layer is a grayscale mask; if the mark is too dark it disappears on
  a dark tint. Lift its midtones (gamma ≈ 0.6) before generating.
- Regenerate: `dart run flutter_launcher_icons`. Sources live in
  `assets/branding/nuvo_app_icon{,_dark,_tinted}.png`.
**Rule:** icon work touches `pubspec.yaml` (a no-touch file) — it needs explicit
scoped approval, and you must regenerate + eyeball the booted-simulator home
screen, not just trust the generator.

---

## K. Git / repository

- **A 442 MB blob** (`test/motion_qa/lab/EXPERIMENTS.jsonl`) is in an older
  commit and blocks `git push`. Clearing it is history rewriting — **the
  owner's call**: `git filter-repo --path test/motion_qa/lab/EXPERIMENTS.jsonl
  --invert-paths --force`, then re-add the remote and push. Do not do this
  unasked.
- Current work is on branch `nuvo-visual/compete-design`, **not** `main`.
- **Commit/push only when the user asks.** ("deploy and do everything" has been
  treated as authorizing commits on the feature branch, not `main`, not a
  history rewrite.)
- Never `git checkout`/`stash pop` in a way that can drop the user's unrelated
  uncommitted work — inspect `git status` first.

---

## L. Worker / backend

- The Worker + D1 schema are **deployed**. A field rename or JSON-shape change
  breaks the running app. Backend changes are a separate, explicitly-scoped task
  — see [`03-data-auth-and-backend.md`](03-data-auth-and-backend.md).
- Migrations are additive and ordered; `migrations/0012_motion_analysis.sql`
  used `CREATE TABLE IF NOT EXISTS`. Apply with
  `wrangler d1 migrations apply nuvo_db --remote`; deploy with `wrangler deploy`.
- API base: `https://nuvo-api.getnuvoapp.workers.dev` (override at build time
  with `--dart-define=NUVO_API_BASE_URL=…`).
- Do **not** touch Worker business logic, scoring, or thresholds during a
  client/UI task.

---

## M. Process & scope (from `AGENTS.md`)

- **> 2 files, or any UI/logic change → write the task declaration** (files to
  read / edit, behaviour change, what will NOT change, risk level). Medium/high
  risk → wait for approval.
- **> 5 files → stop and check with the user.**
- **No-touch without named, scoped approval:** `auth_*` (api/repo/controller/
  gate/token store), `ai_motion_proof_screen.dart`, `motion_validators.dart`,
  `pose_detector_service.dart`, `camera_image_converter.dart`, iOS native files,
  `pubspec.yaml`/`pubspec.lock`, `server/worker/`.
- **"Make it work" does not authorize bypassing those boundaries.**
- **Screen ownership is fixed.** Don't move a responsibility to another screen to
  make a local UI problem disappear (Arena = next move; Compete = start/join;
  Crew = people; Profile = identity/history; Race Detail = one race's
  leaderboard; Submit Proof = choose/complete proof; AI Motion Proof = live
  camera only).
- **Product language:** use race / crew / proof / progress / leaderboard / start
  line / finish line / arena / member pass / AI Motion Proof. Never challenge,
  event, journey, unlock, discover, coming soon, betting, payout, Firebase, etc.
- **Update the docs in the same change** when routes, providers, API fields,
  proof semantics, or protected files change.
