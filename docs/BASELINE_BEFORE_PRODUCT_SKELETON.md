# Baseline — Before Product Skeleton

This document captures the verified state of the Nuvo app immediately before
the `nuvo-next/product-skeleton` branch was created. It exists to allow safe
rollback and to give future agents a clear picture of what was working and what
was known to be broken.

---

## Branch and tag

| Item | Value |
|---|---|
| Protected tag | `demo-working-before-product-skeleton` |
| Working branch | `nuvo-next/product-skeleton` |
| Base branch | `main` |
| Tag points to | HEAD of `main` at the time of this branch cut |

To restore the working state at any time:

```bash
git checkout demo-working-before-product-skeleton
```

---

## Build and analyze status

**Flutter pub get:** Passes. All declared dependencies resolve. 27 transitive
packages have newer versions available but are intentionally locked — do not
update dependencies without explicit approval.

**Flutter analyze (`--no-fatal-infos`):** 4 `info`-level style findings in
`lib/features/auth/presentation/auth_controller.dart` (lines 43, 49, 64, 73).
Missing curly braces in `if` statements. Zero errors. Zero warnings. The app
builds and runs despite these infos.

**Backend worker typecheck (`tsc --noEmit`):** Passes with zero output.

---

## Known stable areas

| Area | Status | Notes |
|---|---|---|
| Email login | Stable | Full OTP email flow → token → secure storage → session restore |
| Physical iPhone release build | Stable | Has been demonstrated on device |
| Race creation | Stable | Full form → backend → returns `Race` model |
| Race detail / leaderboard | Stable | Loads participants, proof rows, progress bars |
| Submit proof (manual) | Stable | Value + note → backend → leaderboard updates |
| AI Motion Proof | Stable | Camera + ML Kit pose detection → real verification → submit |
| Invite code / join by code | Stable | Generates code, clipboard copy, join-by-code screen |
| Crew management | Stable | Search users, add to crew, manage from invite screen |
| Member pass / QR | Stable | Pass tab shows QR code from backend |
| Backend (Cloudflare Worker + D1) | Stable | Deployed and reachable at `nuvo-api.getnuvoapp.workers.dev` |

---

## Known issues — reasons for the product skeleton pass

These are the problems that motivated the `nuvo-next/product-skeleton` branch.
None of them block the demo. They are the target of future cleanup work.

| Issue | Location | Impact |
|---|---|---|
| "Google sign-in — needs setup" visible to all users | `welcome_auth_screen.dart:576` | Looks broken on the auth screen |
| "coming soon" copy in add-crew onboarding | `add_crew_screen.dart:129-178` | 4 prototype labels during new-user onboarding |
| "coming soon" copy in race settings | `race_settings_screen.dart:321,333` | Visible in proof method + review mode selectors |
| "coming soon" copy in submit proof | `submit_proof_screen.dart:535` | Visible in `_DisabledAiCard` |
| "coming soon" copy in create race | `create_race_screen.dart:316` | Visible in activity picker |
| "coming soon" in proof screen | `proof_screen.dart:39` | Visible to users |
| "coming soon" / Privacy dead stub | `profile_screen.dart:169` | Privacy tile opens static sheet |
| Dead notifications bell | `arena_screen.dart:60` | Bell icon always shows "No race updates yet." |
| Dead notifications tile in profile | `profile_screen.dart:158` | Same static sheet |
| Arena feels like a dashboard | `arena_screen.dart` | Shows races list + quick actions instead of "next move" |
| Race detail: too many primary CTAs when owner+participant | `race_detail_screen.dart:340-476` | Submit proof + Start another + Invite + Edit + Settings + Share + Copy |
| UI feels AI-generated / cluttered | Multiple screens | Heavy shadows, dense layouts, inconsistent padding |
| Design system inconsistency | Multiple files | `Color(0xFFE5484D)` hardcoded in 8+ files instead of `NuvoColors` token |
| 18+ orphaned Dart files | `lib/core/widgets/`, `lib/features/auth/presentation/` | Dead code never imported by active screens |
| Duplicate `_kApiBase` constant | `auth_api.dart:7`, `race_api.dart:8` | Must be updated in two places if URL changes |
| Duplicate `/race/:id/edit` route | `router.dart:177-184` | Identical to `/race/:id/settings`, leads to same screen |
| `push_up_counter.dart` is a placeholder | `lib/features/races/ai/push_up_counter.dart` | Contains `placeholder` version string, not imported by anything |
| Old model files in `lib/data/models/` | `friend.dart`, `race.dart`, `user_profile.dart` | Appear superseded by models in `lib/features/` |
| Leaderboard not central enough | `race_detail_screen.dart` | Leaderboard is one section among many rather than the hero |
| Race concept unclear in UI | Multiple screens | "Race" definition not consistently surfaced |

---

## Do-not-touch areas

The following must not be modified without explicit, scoped approval. Casual
edits here can break the demo or corrupt data.

| Area | Files | Risk |
|---|---|---|
| Auth logic | `lib/features/auth/data/auth_api.dart`, `auth_repository.dart`, `auth_controller.dart`, `auth_gate.dart`, `secure_token_store.dart` | Session loss, logout failure, infinite load |
| Race API / backend contract | `lib/features/races/data/race_api.dart`, `race_repository.dart` | Data corruption, API 4xx failures |
| Race controller / state | `lib/features/races/presentation/race_controller.dart` | Shared provider used by all race screens |
| AI Motion Proof logic | `lib/features/races/ai/motion_validators.dart` | Changes threshold/confidence math — never fake |
| AI Motion Proof screen | `lib/features/races/presentation/ai_motion_proof_screen.dart` | Camera lifecycle — wrong dispose = camera leak |
| ML Kit bridge | `lib/features/races/ai/pose_detector_service.dart`, `camera_image_converter.dart` | iOS BGRA8888/NV21 pixel pipeline |
| iOS native files | `ios/Podfile`, `ios/Runner.xcodeproj/project.pbxproj`, `ios/Runner/Info.plist` | Corrupting these breaks all iOS builds |
| Dependencies | `pubspec.yaml`, `pubspec.lock` | Do not add, remove, or upgrade packages |
| Backend schema | `server/worker/` | D1 schema changes can corrupt production data |
