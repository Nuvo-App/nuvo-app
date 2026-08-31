# Codebase navigation — find the right file fast

Purpose: cut the time an agent spends locating code before it can act. Read this
once; then use the tables as a lookup.

Companion docs: routing → [`../NAVIGATION_MAP.md`](../NAVIGATION_MAP.md);
widgets/tokens → [`09-widget-and-token-reference.md`](09-widget-and-token-reference.md);
known bugs → [`10-pitfalls-and-fixes.md`](10-pitfalls-and-fixes.md);
adding code → [`11-adding-a-feature.md`](11-adding-a-feature.md).

---

## 1. The 4-layer rule (where does a piece of code belong?)

Every feature is split the same way. When you touch one, you almost always touch
its layer only.

| Layer | Directory | Holds | Never holds |
|---|---|---|---|
| **presentation** | `features/<x>/presentation/` | screens, screen-local widgets, `*Controller` (Riverpod `StateNotifier`), screen state | JSON parsing, HTTP, business rules |
| **domain** | `features/<x>/domain/` | pure functions & value types: display formatting, ranking, validation, enums, drafts | `BuildContext`, `http`, widgets |
| **data** | `features/<x>/data/` | `*Api` (HTTP + JSON), `*Repository` (token injection + API→domain), transport models | UI, navigation |
| **core** | `lib/core/` | cross-feature theme, shared widgets, navigation helper, constants | feature-specific logic |

Flow is always one direction: `presentation → domain + data`, `data → core`. A
screen never calls an `*Api` directly — it goes through its `*Controller` →
`*Repository` → `*Api`.

---

## 2. Directory deep-map

```
lib/
  main.dart                     bootstrap: portrait lock, system UI, ProviderScope
  app/
    app.dart                    NuvoApp (MaterialApp.router), _appBuilder wraps NuvoTextScaleScope
    router.dart                 GoRouter: every route, page transitions, ShellRoute. routerProvider.
  core/
    constants/                  api base URL etc.
    navigation/nuvo_navigation.dart   safePopOrGo(context, fallback) — use in every manual back button
    theme/
      app_colors.dart           NuvoColors (raw + semantic), NuvoColorRole, NuvoSemanticColors ext
      app_text_styles.dart      AppTextStyles.*  (Manrope scale)
      app_geometry.dart         NuvoRadii, NuvoSpacing, NuvoBorders
      app_shadows.dart          AppShadows.hard{Small,Medium,Large}, soft*
      nuvo_tokens.dart          NuvoTokens.* — grays, consolidated aliases for newer code
      nuvo_responsive.dart      context.rs(px), TextStyle.scaled(context), NuvoTextScaleScope
      app_theme.dart            Material 3 ThemeData, component themes, semantic ext wiring
    widgets/                    26 shared widgets — see doc 09. Key ones:
      nuvo_button.dart          every button tier
      nuvo_empty_state.dart     NuvoEmptyState — the one empty-state pattern
      nuvo_error_state.dart     NuvoErrorState — retry surface
      nuvo_podium.dart          NuvoPodium / NuvoPodiumEntry — top-3 standings (flat)
      nuvo_avatar.dart          NuvoAvatar, nuvoAvatarColorFor(id), NuvoAvatarSizes
      nuvo_race_components.dart  NuvoFeaturedRaceCard, NuvoRaceRow, NuvoFinishedRaceRow, RacePeople…
      nuvo_board_components.dart leaderboard rows, standings pieces
      bottom_nav.dart           NuvoBottomNav — tab dock, bottomPadding(context)
  features/
    splash/presentation/splash_screen.dart      entry; restore → route
    auth/
      data/  auth_api.dart  auth_repository.dart  secure_token_store.dart  auth_models.dart
      presentation/  auth_controller.dart  auth_gate.dart (RouterNotifier.redirect)
                     welcome_auth_screen.dart  email_start_screen.dart  email_verify_screen.dart
                     welcome_race_builder_screen.dart  welcome_onboarding_state.dart
    onboarding/presentation/  onboarding_screen.dart  member_pass_screen.dart  first_use_guide.dart
    arena/
      data/  arena_api.dart  arena_repository.dart  arena_models.dart
      presentation/  arena_controller.dart  arena_screen.dart (1-line re-export) 
                     arena_screen_fixed.dart (REAL screen)  track_view/ (isolated legacy)
    compete/presentation/  compete_screen.dart (re-export)  compete_screen_fixed.dart (REAL)
    move/presentation/move_screen.dart          "Verify" tab
    pass/presentation/pass_screen.dart          "Crew" tab
    profile/presentation/  profile_screen.dart  edit_profile_screen.dart
    race_detail/presentation/race_detail_screen.dart   /race/:id — the leaderboard room
    proof/presentation/proof_screen.dart        thin shim: /proof/:id → /race/:id/proof
    races/
      domain/  race_display.dart  race_draft.dart  proof_status.dart  motion_activity*.dart
               camera_verification_resolver.dart  chase_context.dart
      data/    race_api.dart  race_repository.dart  race_models.dart  ai_motion_models.dart
               motion_analysis_contract.dart
      presentation/  race_controller.dart  race_composer_screen.dart  submit_proof_screen.dart
                     join_race_screen.dart  invite_crew_screen.dart  race_settings_screen.dart
                     board_moved_screen.dart  proof_review_screen.dart  create_race_screen.dart (legacy)
                     ai_motion_proof_screen{,_io,_web}.dart   widgets/movement_demo.dart
                     custom_pose/teach_movement_screen.dart
      ai/      motion_validators.dart  pose_detector_service.dart  camera_image_converter.dart
               pose_landmark_smoother.dart  verifier_runtime.dart  airborne_state_tracker.dart
               multi_phase_sequence_tracker.dart  preset_motion/  custom_pose/
  data/models/                  shared data models used across features
server/worker/                  Cloudflare Worker (Hono) + D1 — separate contract, see doc 03
test/                           *.dart at top level + test/arena/. test/motion_qa/ is heavy — see doc 10.
```

---

## 3. File-naming glossary

| Pattern | Meaning |
|---|---|
| `*_screen.dart` that is one line | **re-export shim** — the real screen is `*_screen_fixed.dart`. Edit the `_fixed` file. (`arena_screen.dart`, `compete_screen.dart`.) The shim exists so route imports and tests don't churn. |
| `*_screen_fixed.dart` | the live implementation of that screen. |
| `*_io.dart` / `*_web.dart` | platform split via conditional import. `ai_motion_proof_screen.dart` picks `_io` (mobile, real camera) or `_web` (stub) at compile time. Edit the platform file, keep the public API identical. |
| `*_controller.dart` | Riverpod `StateNotifier` owning a feature's shared state + the mutations screens call. |
| `*_api.dart` | HTTP + JSON only. One method per endpoint. Takes a `token` string. |
| `*_repository.dart` | wraps `*_api` with `_withRefresh` (token load + 401 retry) and maps to domain types. |
| `*_models.dart` | `fromJson` / `toJson` transport types. Field names must match the Worker. |
| `nuvo_*.dart` in `core/widgets/` | shared, reusable visual primitive. Search here before building anything. |
| `_PrivateWidget` inside a screen file | screen-local; not reusable; fine to change freely within that screen. |

---

## 4. Provider graph (shared state)

Read state with `ref.watch(xProvider)`; call mutations with
`ref.read(xProvider.notifier).method()`. Never build a second source of truth.

| Provider | File | Type | Owns |
|---|---|---|---|
| `authControllerProvider` | `auth/presentation/auth_controller.dart` | `StateNotifier<AuthState>` | session, current `AuthUser`, onboarding flags, sign-in/out. `AuthStatus` = loading / authenticated / unauthenticated / **offline** |
| `authRepositoryProvider` | `auth/presentation/auth_controller.dart` | `Provider` | `AuthRepository(authApi, secureTokenStore)` |
| `secureTokenStoreProvider` | same | `Provider` | Keychain/keystore token IO |
| `routerNotifierProvider` | `auth/presentation/auth_gate.dart` | `ChangeNotifierProvider` | `RouterNotifier.redirect` — the route guard |
| `routerProvider` | `app/router.dart` | `Provider<GoRouter>` | the router instance |
| `raceControllerProvider` | `races/presentation/race_controller.dart` | `StateNotifier<RaceState>` | `races` list, `loading`, `error`; create/join/leave/archive/cancel/delete race; submit proof; crew add/remove. **Auto-loads** on first read if authenticated; reloads on auth→authenticated; `clearRaces()` on sign-out. 5-min cache + in-flight de-dup. |
| `raceRepositoryProvider` | same | `Provider` | `RaceRepository(raceApi, secureTokenStore, authApi)` |
| `arenaControllerProvider` | `arena/presentation/arena_controller.dart` | `StateNotifier<ArenaState>` | `snapshot` (next-move board), `loading`, `error`. Same auto-load / cache / clear pattern as races. `onSessionExpired` → `authController.sessionExpired()` |
| `firstRaceGuideProvider` | `onboarding/presentation/first_use_guide.dart` | `StateProvider<FirstRaceGuideStep>` | the coach-mark walkthrough step for a brand-new user |
| `_composerDraftProvider` | `race_composer_screen.dart` | `StateProvider.autoDispose<RaceDraft>` | in-progress race being created (private to the composer) |
| `recentMovementIdsProvider` / `recentMovementsStoreProvider` | `races/.../custom_pose/recent_movements_provider.dart` | | recently used movements |
| `learnedCustomMovementProvider` | `first_use_guide.dart` region | `StateProvider` | a movement just taught in the teach flow |
| `demoReplayProvider` | `auth_gate` region | `StateProvider<bool>` | keeps an authed user in the pre-auth demo builder |

---

## 5. "Where do I change X?" lookup

| I want to change… | Go to |
|---|---|
| a colour / token value | `core/theme/app_colors.dart` (+ `docs/UI_STRUCTURE.md` for the map). Never inline `Color(0x…)`. |
| a button's look / add a tier | `core/widgets/nuvo_button.dart` |
| the empty state on any screen | that screen renders `NuvoEmptyState` — change the props there; change the pattern in `core/widgets/nuvo_empty_state.dart` |
| a route / where a tap goes | `app/router.dart` + read `docs/NAVIGATION_MAP.md` first |
| post-login landing screen | `auth/presentation/auth_gate.dart` `redirect` (never branch on origin route) |
| "logs out too easily" / session | `auth/data/secure_token_store.dart` + `auth_repository.dart` `restoreSession` — see doc 10 §Auth |
| a network call hangs / no error | the relevant `*_api.dart` — check it has `.timeout()` — see doc 10 §Networking |
| race list not refreshing | `races/presentation/race_controller.dart` (`loadRaces`, cache, `_loadInFlight`) |
| how a race renders its progress / rank / title | `races/domain/race_display.dart` (`raceProgressLabel`, `rankForUser`, `serverRankedParticipants`, …) |
| leaderboard / podium UI | `core/widgets/nuvo_podium.dart` (top 3) + `nuvo_board_components.dart` (rows) |
| proof status labels/colours | `races/domain/proof_status.dart` |
| adding a field to a race | `race_models.dart` (parse) → `race_draft.dart` (create payload) → composer/settings UI → Worker (separate approval) |
| a screen's layout on small phones | wrap sizes in `context.rs()`, check `docs/agents/02` responsive rules |
| the bottom nav | `core/widgets/bottom_nav.dart` |
| the camera / ML verification | **stop** — read `docs/agents/07` §11 and `AGENTS.md` no-touch list first |
| a Worker endpoint / DB | `server/worker/` — read `docs/agents/03` + `docs/API_CONTRACT.md`, separate release |

---

## 6. Trace a feature in 3 greps

To understand any flow before editing:

```bash
# 1. Where does this screen live and what route hits it?
rg -n "class SomeScreen|/some-path" lib/app/router.dart lib/features

# 2. What state does it read, and who mutates that state?
rg -n "someControllerProvider" lib

# 3. What API/endpoint backs it?
rg -n "class SomeApi|/some/endpoint" lib/features/*/data server/worker/src/routes
```

Example — "how does submitting proof move the board?":
`submit_proof_screen.dart` → `raceControllerProvider.notifier.submitProof()` →
`RaceRepository.submitProof` (`_withRefresh`) → `RaceApi._post('/races/:id/proof')`
→ Worker → returns updated `Race` → controller replaces it in `state.races` →
screens watching `raceControllerProvider` rebuild. Celebration is
`pushReplacement('/race/:id/board-moved', extra: BoardMovedArgs(...))`.

---

## 7. Reading order by task

| Task | Read, in order |
|---|---|
| UI tweak on one screen | `AGENTS.md` · `02-ui-and-design-system.md` · `09-widget-and-token-reference.md` · the screen file |
| new screen / route | `NAVIGATION_MAP.md` · `01-app-architecture.md` · `11-adding-a-feature.md` · `router.dart` |
| auth / session / API | `03-data-auth-and-backend.md` · `10-pitfalls-and-fixes.md` §Auth/§Networking · the `data/` files |
| race / proof logic | `04-race-and-ai-motion.md` · `race_display.dart` · `race_models.dart` |
| camera / ML | `07-ui-refinement-and-camera-ai-migration.md` (all) · `04-race-and-ai-motion.md` — then usually **don't** |
| tests failing | `05-testing-and-release.md` · `10-pitfalls-and-fixes.md` §Testing |
| "find every issue" | `../FULL_APP_AUDIT_2026-08.md` · `10-pitfalls-and-fixes.md` |
