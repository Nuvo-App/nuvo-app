# Flutter app architecture and feature map

Companion references: [`08-codebase-navigation.md`](08-codebase-navigation.md)
(directory deep-map, provider graph, "where do I change X"),
[`12-screen-reference.md`](12-screen-reference.md) (every route → file →
primary action → states).

## Entry and routing

- `lib/main.dart` initializes Flutter, locks portrait orientation, applies system UI styling, and mounts `ProviderScope`.
- `lib/app/app.dart` creates `NuvoApp`, installs the theme/router, and dismisses keyboard focus on taps and scrolls.
- `lib/app/router.dart` owns route registration, page transitions, the main `ShellRoute`, and the `routerProvider`.
- `lib/features/auth/presentation/auth_gate.dart` supplies the redirect notifier. Route changes must be checked against loading, offline, authenticated, onboarding-complete, and onboarding-incomplete states.

**Before adding or changing any navigation, read `docs/NAVIGATION_MAP.md`** — the
full route table, navigation graph, the `push` / `go` / `pushReplacement` /
`safePopOrGo` rules, and the 10 rules for future changes. Core rule: every "open
a race" tap goes to `/race/:id`; verify/invite/settings are actions on that
screen, never a separate list-tap destination.

The shell currently hosts `/arena`, `/pass`, `/compete`, `/move`, and `/profile`. Detail routes include race creation/join/settings/invite, race detail, proof submission/review, profile editing, and the internal teach-movement route.

## Riverpod ownership

| Provider | Owns |
|---|---|
| `authControllerProvider` | session, current user, onboarding, sign-in/out |
| `authRepositoryProvider` | auth API plus secure token store |
| `routerNotifierProvider` | auth-aware navigation refresh |
| `raceControllerProvider` | races, crew operations, race mutations, proof submission |
| `arenaControllerProvider` | arena snapshot/next-move data |

Read shared state through its provider. Do not create a second local source of truth for races or auth in a screen.

## Editing patterns

- Screens belong in their feature’s `presentation/` directory.
- Domain types and transformations belong in `domain/`, not in widgets.
- HTTP serialization belongs in `data/`.
- Reusable visual elements belong in `lib/core/widgets/` only when they are genuinely shared.
- Keep movement-specific logic out of generic animation widgets. `movement_demo.dart` renders data supplied by `MovementDemo`; it should not become a validator or camera implementation.

## Common flow: submit proof

```text
Race Detail / Arena
  → SubmitProofScreen
    → manual/photo/note/link OR AI Motion Proof
      → raceControllerProvider
        → RaceRepository (token injection)
          → RaceApi
            → Worker /races/:id/proof
```

After a successful proof submission, the race state and leaderboard must refresh from the returned backend model. Do not locally fake a verified result.

## Known duplication to resolve deliberately

There are historical model/widget variants and duplicate route/API constants in the tree. Before deleting or consolidating one, prove import reachability with `rg`, run tests, and update all consumers in one scoped change. Do not “clean up” these areas incidentally while implementing a feature.
