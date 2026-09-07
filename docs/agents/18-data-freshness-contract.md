# Nuvo App Data Freshness Contract

Status: **active** (races + arena implemented, commit `e424726`). Every new
data domain (crew, notifications, activity feed) MUST follow this pattern
rather than adding a page-specific refresh.

---

## 1. Canonical sources of truth

One `StateNotifier` per domain owns the cache. Screens **never** hold their own
copy and **never** call an `*Api` directly.

| Domain | Notifier | Provider | State |
|---|---|---|---|
| Races (list + detail) | `RaceController` | `raceControllerProvider` | `RaceState { races, loading, refreshing, error }` |
| Arena snapshot | `ArenaController` | `arenaControllerProvider` | `ArenaState { snapshot, loading, refreshing, error }` |
| Current user / auth | `AuthController` | `authControllerProvider` | `AuthState` |
| Crew *(planned — see 15)* | `CrewController` | `crewControllerProvider` | `CrewState { members, loading, refreshing, error }` |

Rules for a domain notifier:
- `StateNotifierProvider`, **not** recreated on sign-out — only its `state` is
  reset. Any field that must not outlive a session (cache timestamp,
  `_loadInFlight`) is nulled in `clearX()`, or a hung load wedges the tab until
  an app kill (docs/agents/10 §A1).
- A 5-minute hard cache (`_cacheLifetime`) for "is a forced reload needed",
  plus a short **stale window** (`_staleWindow`, 45 s) for `revalidate()`.
- Single-flight: concurrent `loadX()` calls share one `Future`.

---

## 2. State model — four states, never conflated

```
loading      first fetch, nothing cached      → full skeleton is OK
refreshing   background fetch, data on screen  → keep content, subtle hint only
loaded-data  hasData == true                   → render it
loaded-empty hasData == false, no error, not loading → honest empty state (see §6)
error        initial fetch failed, nothing cached → real error state + retry
```

`hasData` is a getter on the state (`races.isNotEmpty` / `snapshot != null`).

`_fetch()` sets `loading: !hasData` and `refreshing: hasData` at the start. On
failure it **keeps cached data and clears the error** — a failed *background*
refresh must never blank the page or show an error banner. An error is only
surfaced when `!hasData`.

Screen rendering contract:

```dart
if (state.loading && !state.hasData)      => SkeletonOrSpinner()
else if (!state.hasData && state.error != null) => NuvoErrorState(onRetry: ...)
else if (!state.hasData)                   => NuvoEmptyState(...)   // §6
else                                       => Content(state.data)   // + optional
                                                                    //   refreshing chip
```

`test/move_screen_state_test.dart` and `test/compete_screen_state_test.dart`
encode this; copy them for new screens.

---

## 3. Stale-while-revalidate — `revalidate()`

`revalidate()` is the **only** thing a screen calls on focus / resume:

```dart
void revalidate() {
  if (state.hasData && _loadedAt != null &&
      DateTime.now().difference(_loadedAt!) < _staleWindow) return;   // fresh — no-op
  loadX(force: true);                                                 // background refresh
}
```

It renders nothing itself. Current content stays; the fetch runs with
`refreshing: true`.

**Where it fires (`MainShell`, a `ConsumerStatefulWidget` + lifecycle observer):**
- `didChangeAppLifecycleState(resumed)` → `raceController.revalidate()` +
  `arenaController.revalidate()` (high-value user state).
- Tapping a data tab → `revalidate()` for that tab's domain *before* the route
  changes.

Screens still `loadX(force:false)` in `initState` when cold (nothing cached).
They do **not** add their own `initState`/`onResume` force-fetches — that is the
anti-pattern this contract exists to kill.

---

## 4. Write-through / invalidation

Every mutation on a notifier updates local state **synchronously** from the
server's response, then propagates:

1. **Update the canonical cache** with the returned entity (`_upsertRace`,
   prepend on create, remove on delete/leave).
2. **Bump `_loadedAt`** so the fresh state isn't immediately re-fetched.
3. **Notify siblings.** `RaceController.onMutated` (wired in the provider) calls
   `ArenaController.markStale()`, which nulls its timestamp **and pulls a fresh
   snapshot now** — the Arena is derived from races, so a race created in the
   composer appears there without the user navigating.

`getRaceDetail(id)` folds the detail response (freshest participants /
progress / standings) back into the race list via `_upsertRace(silent: true)` —
`silent` skips the sibling nudge because a read is not a write.

Mutations covered today: create, createCustom, join, joinByCode,
addParticipant, leave, delete, archive, cancel, submitProof (×3),
updateRace, reviewProof.

New domains register their own `onMutated` → affected siblings. Example
(planned): `CrewController.onMutated` → `raceController.markParticipantsStale()`
so a crew member added mid-race shows their identity (see 15 + the
`resolveRaceMemberVisibility` policy in `lib/privacy.ts`).

---

## 5. Server freshness metadata

Current: responses carry `updatedAt` on `Race`. There is **no** ETag / revision
header yet. `revalidate()`'s time-window is sufficient for the current scale
(small races, few devices) — do **not** build a sync framework.

Add a lightweight `version` / `revision` integer to a resource **only when**:
- polling cost becomes real (large crews, long feeds), or
- optimistic concurrency is needed (two editors of one race).

When added: the client sends `If-None-Match` / `?since=`, the server returns
`304` / an empty delta, and `_fetch` treats that as "unchanged, keep cache,
bump `_loadedAt`". Keep it per-resource, never a global sync clock.

---

## 6. Empty states (honest, never fabricated)

Never invent races, people, leaderboard rows, or activity. `NuvoEmptyState`
(icon tile · title · body · one primary CTA). Audited surfaces:

| Surface | loaded-empty copy |
|---|---|
| Compete / races | "No races yet" · "Create a race to get started." · **Create race** |
| Arena | "Nothing in your arena yet" · "Join or create a race to get moving." |
| Leaderboard (0–1 racers) | "No one's on the board yet" · "Be the first to submit proof." |
| Race board (owner) | "No one on the board yet" · "Invite your crew" |
| Crew / people | "No crew yet" · "Search a username or member ID to add crew." |
| Profile race history | "Start your first race to build your history." |
| Profile race history (error) | `NuvoErrorState("Couldn't load your race history.", onRetry)` |

`loaded-empty` ≠ `loading` ≠ `error`. A spinner must never persist after the
server returns `[]`; empty copy must never show before the first request
resolves.

---

## 7. Checklist for a new data domain

- [ ] `XController extends StateNotifier<XState>` with `loading` / `refreshing`
      / `error` / `hasData`.
- [ ] `loadX({force})` with 5-min cache + single-flight; `revalidate()` with the
      45-s stale window; `clearX()` nulls timestamp **and** `_loadInFlight`.
- [ ] `_fetch` keeps cache + clears error on background failure.
- [ ] mutations update local state from the response, bump `_loadedAt`, call
      `onMutated`.
- [ ] provider wires `onMutated` → the siblings this domain feeds.
- [ ] `MainShell` (or the domain's screen) calls `revalidate()` on focus/resume.
- [ ] screen renders the four states per §2; empty state per §6.
- [ ] state-behaviour test copied from `move_screen_state_test.dart`.
