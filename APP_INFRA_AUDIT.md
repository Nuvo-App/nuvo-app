# Nuvo App — Infrastructure Audit

_Generated: 2026-06-18_

---

## 1. Navigation Issues

### 1.1 Stack-clearing `context.go` in auth flow

| File | Line | Issue | Fix |
|------|------|-------|-----|
| `lib/features/auth/presentation/welcome_auth_screen.dart` | 170 | `context.go('/auth/email')` clears the navigator stack; back button on EmailStartScreen crashes ("nothing to pop"). | Changed to `context.push('/auth/email')`. |
| `lib/features/auth/presentation/email_start_screen.dart` | 46 | `context.go('/auth/verify', extra: email)` clears stack; back button on EmailVerifyScreen crashes. | Changed to `context.push('/auth/verify', extra: email)`. |

### 1.2 Route protection gap

| File | Issue | Fix |
|------|-------|-----|
| `lib/features/auth/presentation/auth_gate.dart` `_isProtected` | `/races/` prefix missing — `/races/new` (create race) is accessible without authentication. | Added `loc.startsWith('/races/')` to condition. |

---

## 2. Back Button Issues

All `context.pop()` calls without canPop checks will crash if the screen is the root of the navigator stack (e.g., deep-linked or navigated to via `context.go`). Fixed with `safePopOrGo(context, fallback)` from `lib/core/navigation/nuvo_navigation.dart`.

| File | Location | Fallback |
|------|----------|----------|
| `lib/features/auth/presentation/email_start_screen.dart` | Back arrow GestureDetector | `/welcome` |
| `lib/features/auth/presentation/email_verify_screen.dart` | Back arrow GestureDetector | `/auth/email` |
| `lib/features/races/presentation/create_race_screen.dart` | Back arrow IconButton | `/compete` |
| `lib/features/races/presentation/submit_proof_screen.dart` | Back arrow in `_successContent` | `/race/{raceId}` |
| `lib/features/races/presentation/submit_proof_screen.dart` | Back arrow in `_formContent` | `/race/{raceId}` |
| `lib/features/races/presentation/submit_proof_screen.dart` | "Back to race" NuvoOutlineButton | `/race/{raceId}` |
| `lib/features/profile/presentation/edit_profile_screen.dart` | Back arrow IconButton | `/profile` |
| `lib/features/profile/presentation/edit_profile_screen.dart` | After save success (`context.pop()`) | `/profile` |
| `lib/features/race_detail/presentation/race_detail_screen.dart` | Back arrow (error state) | `/arena` |
| `lib/features/race_detail/presentation/race_detail_screen.dart` | Back arrow (main body) | `/arena` |
| `lib/features/proof/presentation/proof_screen.dart` | Back arrow IconButton | `/arena` |

---

## 3. Loading / Error / Empty State Gaps

| Screen | Missing State | Recommendation |
|--------|--------------|----------------|
| `race_detail_screen.dart` | Error state has no retry button | Use `NuvoErrorState` widget with `onRetry: _load` |
| `arena_screen.dart` | Race load error is silently ignored | Display `NuvoErrorState` when `raceState.error != null` |
| `pass_screen.dart` | Pass fetch failure shows nothing | Show error message with retry |
| `profile_screen.dart` | No explicit empty state for missing user data | Guard UI against null user |

New shared widgets created:
- `lib/core/widgets/nuvo_error_state.dart` — error display with retry button
- `lib/core/widgets/nuvo_empty_state.dart` — empty state with optional CTA

---

## 4. Dead or Misleading Buttons

| File | Button | Status |
|------|--------|--------|
| `lib/features/arena/presentation/arena_screen.dart` | Notifications bell | Fixed — shows bottom sheet "No updates yet" |
| `lib/features/race_detail/presentation/race_detail_screen.dart` | "Share race" | Fixed — calls `Share.share(...)` via share_plus |
| `lib/features/pass/presentation/pass_screen.dart` | QR scanner IconButton | Fixed — shows "QR scanning coming soon" bottom sheet |
| `lib/features/onboarding/presentation/member_pass_screen.dart` | "Copy link" | Fixed — copies share URL to clipboard, shows SnackBar |

---

## 5. Data Refresh Issues

### 5.1 Stale race data on logout/re-login

**File:** `lib/features/races/presentation/race_controller.dart`

**Issue:** `RaceController` loaded races on construction and never cleared them when the user logged out. On re-login with a different account, the previous user's race data was visible until the next reload.

**Fix:** Added `clearRaces()` method and updated `raceControllerProvider` to listen to `authControllerProvider`. Clears data on `unauthenticated`, reloads on transition to `authenticated`.

---

## 6. Form Validation Gaps

| File | Field | Gap |
|------|-------|-----|
| `email_start_screen.dart` | Email field | Only checks for `@` — does not validate full email format |
| `create_race_screen.dart` | Goal amount | Accepts non-numeric characters until `int.tryParse` silently ignores them |
| `edit_profile_screen.dart` | Username | Min-length check only; no character whitelist (spaces, special chars allowed) |
| `submit_proof_screen.dart` | Progress value | Rejects ≤ 0 but accepts arbitrarily large values |

These are low-priority for the current pass but should be addressed before beta.

---

## 7. Priority Fix Order

1. **Critical — crash on navigation:** back button + stack-clearing `context.go` fixes (all done in this pass)
2. **Critical — security:** route protection gap for `/races/` (fixed)
3. **High — data integrity:** stale race data on re-login (fixed)
4. **Medium — dead buttons:** notifications, share, QR scanner, copy link (all done in this pass)
5. **Medium — error states:** surfaces for race load errors in arena and race detail screens (new widgets created, wiring deferred)
6. **Low — form validation:** email format, username character rules, numeric range guards

---

## 8. Race System Completion Addendum

_Updated: 2026-06-19_

New backend-backed routes added:
- `PATCH /races/:id`
- `POST /races/:id/archive`
- `POST /races/:id/cancel`
- `DELETE /races/:id`
- `POST /races/:id/leave`
- `POST /races/:id/join`
- `POST /races/:id/invite-code`
- `POST /races/join-code`
- `PATCH /races/:id/proofs/:proofId`

New Flutter routes added:
- `/race/:id/settings`
- `/race/:id/edit`
- `/race/:id/invite`
- `/races/join`
- `/race/:id/proofs/:proofId`

Navigation notes:
- Race settings and proof review are owner-gated in UI and backend.
- Destructive lifecycle actions require confirmation dialogs.
- Invite/join uses codes only; Universal Links are not implemented.
- Proof review statuses are AI-ready, but no AI validation runs in this pass.
