# AGENTS.md — Rules for AI Agents Working on Nuvo

All AI agents (Claude Code, Codex, Cursor, Copilot, or any other) must read
this file before making any changes to this repository.

---

## Required reading before product or UI changes

Read these two files first. Always. No exceptions.

```
docs/NUVO_PRODUCT_MODEL.md
docs/BASELINE_BEFORE_PRODUCT_SKELETON.md
```

`NUVO_PRODUCT_MODEL.md` defines what Nuvo is, what every screen owns, what
language to use, and what UX rules apply.

`BASELINE_BEFORE_PRODUCT_SKELETON.md` lists what is stable, what is known to
be broken, and what must not be touched.

---

## Change discipline

### Do small, scoped changes only

Every task must target specific named files. Do not make broad sweeping changes
across multiple unrelated files in one pass. If a task touches more than 5
files, stop and check with the user.

### Never redesign the full app in one pass

Do not rewrite multiple screens, restyle the design system, and restructure
navigation all in one change. One thing at a time.

### Never add new features unless explicitly asked

Do not add screens, routes, API calls, data models, or UI features unless the
user has asked for them in the current task.

### Never change backend contracts unless explicitly asked

Do not rename fields, add or remove API parameters, or change JSON shapes that
the Cloudflare Worker reads or writes. The Worker and D1 schema are deployed —
mismatches cause runtime failures.

---

## Absolute no-touch areas

Never touch these without explicit, scoped approval that names the file and
the exact change:

| Area | Files |
|---|---|
| Auth logic | `lib/features/auth/data/auth_api.dart`, `auth_repository.dart`, `auth_controller.dart`, `auth_gate.dart`, `secure_token_store.dart` |
| AI Motion Proof | `lib/features/races/presentation/ai_motion_proof_screen.dart` |
| Motion validators | `lib/features/races/ai/motion_validators.dart` |
| ML Kit / camera bridge | `lib/features/races/ai/pose_detector_service.dart`, `camera_image_converter.dart` |
| iOS native files | `ios/Podfile`, `ios/Runner.xcodeproj/project.pbxproj`, `ios/Runner/Info.plist` |
| Dependencies | `pubspec.yaml`, `pubspec.lock` |
| Backend | `server/worker/` |

Do not casually touch:

- `lib/features/races/data/race_api.dart` — backend contract
- `lib/features/races/data/race_repository.dart` — token injection
- `lib/features/races/presentation/race_controller.dart` — shared state provider

---

## Product language

Use Nuvo product language in all copy, comments, variable names, and docs:

**Use:** race, crew, proof, progress, leaderboard, start line, finish line,
submit proof, pull in your crew, arena, member pass, AI Motion Proof, invite code

**Never use:** challenge, event, journey, unlock, discover, coming soon, needs
setup, betting, gambling, crypto, payment, payout, sponsor, investor, SMS,
Twilio, Firebase, Supabase

Full language rules are in `docs/NUVO_PRODUCT_MODEL.md`.

---

## Screen ownership

Respect screen ownership. Do not move responsibilities between screens:

- Arena: next-move board only
- Compete: start or join a race only
- Crew: social graph only
- Profile: identity, history, settings only
- Race Detail: leaderboard room for one race
- Submit Proof: choose or complete proof
- AI Motion Proof: live camera verification only

Full ownership rules are in `docs/NUVO_PRODUCT_MODEL.md`.

---

## Task declaration format

Before any broad edit (touching more than 2 files, changing any UI, changing
any logic), state the following:

```
Files to read:      [list]
Files to edit:      [list]
Behavior changes:   [what will change in the running app]
What will NOT change: [explicit list]
Risk level:         low / medium / high
```

If the risk level is medium or high, wait for explicit approval before editing.

---

## Required checks

### After any Flutter file change

```bash
flutter analyze --no-fatal-infos
```

The baseline has 4 `info` findings in `auth_controller.dart`. Do not introduce
new warnings or errors. Do not fix the baseline infos unless that is the
explicit task.

### After any backend file change

```bash
cd server/worker && npm run typecheck
```

The baseline passes with zero output. Any new TypeScript errors must be fixed
before the task is considered done.

---

## Safe cleanup work

The following low-risk cleanup items are pre-approved and can be done without
additional scoped declarations:

- Replacing "coming soon" strings with neutral copy or removing dead UI tiles
- Deleting confirmed-orphaned Dart files (zero imports verified with grep)
- Adding `NuvoColors` tokens to replace inline `Color(0x...)` hex values
- Adding curly braces to the 4 `if` statements in `auth_controller.dart`
- Deduplicating `_kApiBase` into a shared constants file

For all other changes, follow the task declaration format above.

---

## Protection

The tag `demo-working-before-product-skeleton` points to the last known working
state of the app. If anything breaks, recover with:

```bash
git checkout demo-working-before-product-skeleton
```
