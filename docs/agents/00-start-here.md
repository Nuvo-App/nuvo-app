# Nuvo architecture at a glance

> **New to this codebase?** After this file, read — in order —
> [`08-codebase-navigation.md`](08-codebase-navigation.md) (where everything is),
> [`10-pitfalls-and-fixes.md`](10-pitfalls-and-fixes.md) (what breaks and why),
> and the recipe in [`11-adding-a-feature.md`](11-adding-a-feature.md) that
> matches your task. [`12-screen-reference.md`](12-screen-reference.md) is the
> per-screen lookup; [`09-widget-and-token-reference.md`](09-widget-and-token-reference.md)
> is the library cookbook.

## Product loop

Nuvo’s loop is: **set a finish line → pull in your crew → submit proof → move the leaderboard**.

Use the product terms in `docs/NUVO_PRODUCT_MODEL.md`: race, crew, proof, progress, leaderboard, start line, finish line, submit proof, member pass, and AI Motion Proof. Do not introduce banned terms such as “challenge” or “coming soon”.

## Runtime flow

```text
lib/main.dart
  ProviderScope
    NuvoApp (MaterialApp.router)
      GoRouter + RouterNotifier
        auth/onboarding routes
        ShellRoute: Arena, Pass/Crew, Compete, Move, Profile
        race/proof detail routes
```

The app starts at `/splash`. Auth state restoration controls redirects. Protected app and race routes must not be made reachable by bypassing `auth_gate.dart`.

## Directory map

| Area | Responsibility |
|---|---|
| `lib/app/` | `MaterialApp.router` and GoRouter route composition |
| `lib/core/theme/` | colors, typography, geometry, shadows, tokens, theme |
| `lib/core/widgets/` | reusable visual primitives and shared race components |
| `lib/features/auth/` | auth API, token storage, session state, auth UI |
| `lib/features/arena/` | next-move surface and arena data |
| `lib/features/races/domain/` | race drafts, display rules, movement identities, proof routing |
| `lib/features/races/data/` | race models, HTTP API, repository, AI motion payloads |
| `lib/features/races/presentation/` | create/join/settings/invite/proof screens and shared race state |
| `lib/features/races/ai/` | camera conversion, pose detection, smoothing, validators, custom pose runtime |
| `lib/features/onboarding/`, `profile/`, `pass/`, `compete/`, `proof/` | user-facing feature screens |
| `server/worker/src/` | Hono Worker entry point, routes, domain rules, libraries |
| `server/worker/migrations/` | ordered D1 schema migrations |
| `test/` | widget, domain, motion, layout, and regression tests |

## Ownership boundaries

- Arena answers “what needs my attention now?”
- Compete starts or joins a race.
- Crew manages people and invitations.
- Profile owns identity, pass, race history, and settings.
- Race Detail is the leaderboard room for one race.
- Submit Proof chooses or completes proof.
- AI Motion Proof is only the live camera verification flow.

Do not move responsibilities between screens to make a local UI problem disappear.

## First commands

```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test
cd server/worker && npm run typecheck && npm test
```

Use `flutter run --dart-define=NUVO_API_BASE_URL=...` when testing against a specific Worker. Never put secrets in Dart source or commit `.dev.vars`.
