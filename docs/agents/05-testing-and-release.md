# Testing, QA, and release checklist

## Fast local checks

```bash
flutter pub get
dart format --set-exit-if-changed lib test
flutter analyze --no-fatal-infos
flutter test --concurrency=4 test/*.dart test/arena/
```

**Do NOT run `flutter test` bare.** It executes `test/motion_qa/`, which
includes long-run search harnesses (`motion_lab_overnight_test.dart`,
`motion_lab_validation_test.dart`, …) that run hundreds of thousands of
iterations and write ~1 GB of artifacts — a runaway. Run the explicit set above;
only run `test/motion_qa/` when that is the task. See
[`10-pitfalls-and-fixes.md`](10-pitfalls-and-fixes.md) §I1.

**Judge a change by NEW failures only.** There is a standing set of pre-existing
failures (≈37 focused / ≈40 full; the extra are out-of-scope ML-threshold tests).
Capture a baseline on the untouched tree, then diff:

```bash
flutter test --concurrency=4 test/*.dart test/arena/ 2>&1 \
  | grep -oE "test/[a-z_/]+\.dart: [A-Za-z].*\[E\]" | sed 's/ \[E\]$//' | sort -u > /tmp/base_f.txt
# ...make the change, re-run into /tmp/cur_f.txt...
comm -13 /tmp/base_f.txt /tmp/cur_f.txt        # must be empty
```

Strip the trailing ` [E]` before diffing. `timeout` is not on macOS (`gtimeout`
or omit). When you change a repository method signature, `rg` for
`extends AuthRepository` / `extends RaceRepository` and fix every test double in
the same commit. When you change user-facing copy, update the asserting test to
the new string — never weaken it to `findsWidgets`.

The repository baseline documents four pre-existing info findings in `auth_controller.dart`. Do not add new warnings/errors or “fix” the baseline incidentally.

For a focused change, run the smallest relevant test first, then the full suite. UI work should include narrow-layout and widget tests; movement work should include motion validator/runtime tests; auth work should include auth and redirect tests.

## Backend checks

```bash
cd server/worker
npm run typecheck
npm test
```

If migrations or route contracts changed, test local D1 migrations and endpoint behavior before considering a remote release. Never use a production database as a test fixture.

## Manual smoke matrix

### Launch/auth

- cold launch and splash
- unauthenticated protected route redirects
- email start, invalid code, valid code, refresh, restore, logout
- onboarding incomplete vs complete redirects

### Core product

- Arena loads its next move and handles empty/error states
- create race, join by code, invite crew
- race detail shows leaderboard and updates after proof
- manual proof success/failure/review
- profile/pass/edit profile

### AI Motion Proof

- camera permission denied/granted
- supported movement selection
- pose not visible, low confidence, invalid form, successful verification
- submit proof and leaderboard update
- camera stops/disposes on back, error, and route replacement
- custom pose calibration if touched

### Layout/accessibility

- small phone, large phone, web preview
- text scale and keyboard
- long names/titles, loading, empty, error states
- primary action is clear and tappable
- no prototype/dead “coming soon” affordances in shipped paths

## Release gate

Before deploy:

1. Confirm branch and dirty files.
2. Review the diff for secrets, local URLs, debug flags, test fixtures, and generated artifacts.
3. Run Flutter and Worker checks.
4. Verify client API base and Worker environment.
5. Apply only reviewed migrations, in order.
6. Deploy only the explicitly requested target.
7. Smoke test health, auth, a read path, a mutation, and rollback readiness.

No documentation or local test result means a deployment was performed. Record the actual command and result in the handoff.
