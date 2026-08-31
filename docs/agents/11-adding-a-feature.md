# Adding a feature without breaking anything

Concrete, copy-the-pattern recipes. Every recipe assumes you have already:

1. Read `AGENTS.md` and written the **task declaration** (files to read / edit,
   behaviour change, what will NOT change, risk level). > 5 files → stop and ask.
2. Read [`08-codebase-navigation.md`](08-codebase-navigation.md) so you know
   which of the 4 layers you're in.
3. `rg`'d for an existing widget / helper / token before adding a new one.

Baseline checks after **any** Dart change:
```bash
flutter analyze --no-fatal-infos            # 0 new findings
flutter test --concurrency=4 test/*.dart test/arena/   # 0 NEW failures vs baseline (doc 10 §I2)
```
Backend change → also `cd server/worker && npm run typecheck && npm test`.

---

## Recipe 1 — Tweak one screen's UI (the 80% case)

**Layer: presentation only.**

1. Open the real screen file (`*_screen_fixed.dart` if a shim exists).
2. Use tokens + shared widgets from
   [`09-widget-and-token-reference.md`](09-widget-and-token-reference.md). No
   `Color(0x…)`, no raw `TextStyle`, no transparent buttons, no hard shadow on
   flat content.
3. Wrap new size-like values in `context.rs()`.
4. Every empty/zero state → `NuvoEmptyState`. Every error state →
   `NuvoErrorState` with **friendly** copy. Every loading state → a skeleton or
   the existing spinner, gated on `loading && data.isEmpty`.
5. The screen keeps **one** primary action. Don't add a second CTA of equal
   weight.
6. If a control references a race, its tap target is `/race/:id` — nothing else.
7. Add/adjust a focused widget or layout test. Run it at 320 / 390 / 430 width.
8. If a golden changed, open the rendered image and justify it.

**Do not:** move a responsibility to another screen, restructure a layout to fit
a label (fix the label — `FittedBox` already does), or "clean up" nearby
unrelated code.

---

## Recipe 2 — Add a field to an existing API response

**Layers: data → domain → presentation.** (Backend is a *separate* task — see
Recipe 6.)

1. **Parse it** — `features/<x>/data/*_models.dart`. Add the field to the class
   and to `fromJson` with a **safe default that matches the server default**
   (`json['newField'] as String? ?? 'sensible_default'`). If the server sends it
   back on writes, add it to `toJson` too.
   - Gotcha (G1): a status/enum default of `'accepted'`/`'verified'` is a silent
     success. Default to the *cautious* value.
2. **Expose it** — if it needs formatting, add a pure function in
   `features/<x>/domain/*_display.dart` (e.g. `raceProgressLabel`). Widgets never
   format domain data inline.
3. **Render it** — read it in the screen via the existing controller/provider.
4. **Test** — a `fromJson` test with the field present and absent; a display
   test for the formatter.

---

## Recipe 3 — Add a new API call / mutation

**Layers: data → presentation.**

1. **`*_api.dart`** — one method, one endpoint. Route it through the existing
   `_guard(() => _client.<verb>(...))` + `_decode(res)` helpers so it gets the
   timeout + tolerant decode for free. Take a `token` string param.
   ```dart
   Future<Race> setRacePinned(String token, String id, bool pinned) async {
     final res = await _guard(() => _client.patch(
       Uri.parse('$_kApiBase/races/$id'),
       headers: _headers(token), body: jsonEncode({'pinned': pinned})));
     return Race.fromJson(_decode(res)['race'] as Map<String, dynamic>);
   }
   ```
2. **`*_repository.dart`** — wrap it in `_withRefresh` so it gets token injection
   + 401-retry:
   ```dart
   Future<Race> setRacePinned(String id, bool pinned) =>
     _withRefresh((t) => _api.setRacePinned(t, id, pinned));
   ```
3. **`*_controller.dart`** — expose a method that calls the repo and updates
   `state` from the **returned** model. Reuse the existing `_upsertRace` /
   `copyWith(races: …)` pattern; refresh the cache timestamp.
   ```dart
   Future<Race> setRacePinned(String id, bool pinned) async {
     final race = await _repo.setRacePinned(id, pinned);
     _upsertRace(race);            // updates state.races + rebuilds watchers
     return race;
   }
   ```
   - Never fake the new state locally then "reconcile later." Update from the
     server response only.
4. **Screen** — `ref.read(raceControllerProvider.notifier).setRacePinned(...)`.
   Handle the thrown `ApiException` (show `NuvoErrorState` / a snackbar with
   friendly copy).
5. **Test** — a repo test with a stub API (success + `ApiException` paths), a
   controller test asserting `state` updates.

**If you added a controller field** (cache, in-flight future, timestamp): null
it in `clear*()` (pitfall A1).

---

## Recipe 4 — Add a new screen + route

**Read [`../NAVIGATION_MAP.md`](../NAVIGATION_MAP.md) fully first.**

1. Create `features/<x>/presentation/<name>_screen.dart`. `ConsumerWidget` /
   `ConsumerStatefulWidget`. `Scaffold(backgroundColor: NuvoColors.page, …)`.
2. Register in `app/router.dart` using an **existing** page builder
   (`_authPage` / `_detailPage` / `_cameraPage` / `_tabPage`) — don't invent a
   transition.
3. Decide the verb callers use to reach it (`NAVIGATION_MAP.md` §4). A detail
   screen you back out of → `push`. A flow end → `go`.
4. Manual back button → `NuvoBackButton(onPressed: () => safePopOrGo(context,
   '/arena'))`.
5. If it's protected, confirm its path prefix is covered by `_isProtected` in
   `auth_gate.dart` (`/arena|/pass|/compete|/move|/profile|/race/|/races/|
   /proof/|/onboarding/`). Add the prefix if it's new.
6. If it needs `extra:`, give the route a **null-safe fallback** (see how
   `/race/:id/board-moved` does it).
7. **One route per screen.** Alias paths are `redirect:`, not a second
   `pageBuilder`.
8. Update `NAVIGATION_MAP.md` (route table + graph + verb) in the same commit.
9. Add a smoke test that mounts the screen and checks its primary action.

**Don't** add a screen unless the task asked for one (`AGENTS.md`).

---

## Recipe 5 — Add a shared widget

Only if it's **genuinely reused** (2+ screens) and nothing in
`lib/core/widgets/` already does it.

1. `lib/core/widgets/nuvo_<name>.dart`. A `///` dartdoc saying what it is and
   the one rule for using it (see `nuvo_empty_state.dart` for the style).
2. Tokens only — `NuvoColors`, `AppTextStyles`, `NuvoRadii`, `NuvoSpacing`,
   `AppShadows`. Hard shadow only if it's tappable.
3. Sizes via `context.rs()` where it matters.
4. Add it to the tables in
   [`09-widget-and-token-reference.md`](09-widget-and-token-reference.md).
5. Add a render test in `test/` (see `nuvo_design_components_test.dart`).

A screen-local `_PrivateWidget` inside the screen file is the right choice when
it's used once — don't promote it to `core/` prematurely.

---

## Recipe 6 — Add / change a proof type

1. **Spec first** — answer the 12 questions in
   [`07-ui-refinement-and-camera-ai-migration.md`](07-ui-refinement-and-camera-ai-migration.md)
   §8. If you can't, it's not ready.
2. **Camera / ML proof** → `AGENTS.md` no-touch list applies. `motion_validators.dart`,
   the pose bridge, and thresholds are off-limits without a fixture-backed
   evaluation report. Most "add a proof" tasks should be **manual** proof, not
   camera.
3. **Manual proof** — the model already supports `goalType` /
   `proofRequirement` (`manual|photo|note|link|daily_check`) / `proofReviewMode`.
   - `race_draft.dart`: `RaceGoalKind`, the manual create payload.
   - `race_composer_screen.dart`: the Movement / Custom-goal toggle.
   - `submit_proof_screen.dart`: `_ManualLogCard` + "Log progress".
   - Do **not** re-add a client filter that hides non-camera races from Compete /
     Move (pitfall G2).
4. **Status mapping** — go through `proof_status.dart`. An unmapped result is
   `unknown` and never renders green (pitfall G1).

---

## The pre-commit checklist

- [ ] Task declaration written; scope ≤ 5 files (or asked).
- [ ] `flutter analyze --no-fatal-infos` — 0 new findings.
- [ ] `flutter test --concurrency=4 test/*.dart test/arena/` — 0 NEW failures
      vs baseline (`comm -13`, doc 10 §I2). **Never** ran `test/motion_qa/`.
- [ ] No `Color(0x…)`, no raw `TextStyle`, no transparent button, no hard shadow
      on flat content.
- [ ] Every empty/error/loading state handled with the shared pattern + friendly
      copy.
- [ ] Any race tap → `/race/:id`. Flows end with `go`. Back buttons use
      `safePopOrGo`.
- [ ] New controller fields cleared in `clear*()`.
- [ ] New network calls go through `_guard` + `_decode` (timeout + tolerant
      decode).
- [ ] Test doubles for any changed repository signature updated.
- [ ] Docs updated: `NAVIGATION_MAP.md` (routes), doc 09 (widgets/tokens),
      `FULL_APP_AUDIT_2026-08.md` (if it closed/opened a known issue), this
      file's sibling docs if a rule changed.
- [ ] `git status` reviewed — no secrets, no `.dev.vars`, no generated
      `test/motion_qa/lab/` artifacts, no unrelated user work staged.
- [ ] Commit only if the user asked. Feature branch, not `main`.
