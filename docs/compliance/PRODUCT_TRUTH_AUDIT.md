# PRODUCT TRUTH AUDIT — Pre-Launch Legal / Privacy / Store Compliance

Audit date: 2026-09-27. Audited against `main` @ `fb26c42`, deployed Worker
`nuvo-api` version `6897f5c5` + `nuvo-api-dev` `0420703a`, deployed site
getnuvo.net (bundle `index-BPUDfM7V.js`), prod D1 `nuvo_db` + R2 `nuvor2`.

Status vocabulary: PASS / PARTIAL / FAIL / UNKNOWN.
Severity: P0 = materially false claim or serious privacy/deletion issue;
P1 = launch compliance/safety blocker; P2 = disclosure mismatch; P3 = cleanup.

---

## 1. Executive summary

The deployed policies describe a **much smaller product** than the code now
ships. Six hard blockers:

1. **Account deletion is broken in production.** `DELETE /auth/account` calls
   `deleteUserMotionData`, which throws when `MOTION_DATA_MASTER_KEY` is unset.
   The secret is **not configured on prod** (verified: `wrangler secret list`
   + live 500 on the master-key path). Every delete request currently 500s.
   Even if it ran, it misses `device_tokens`, `notifications`,
   `notification_preferences`, `personal_bests`, `activity_reactions`,
   `invites`, `race_attempts`, `race_events`, `verification_sessions`.
2. **`GET /races/:id` has no access check.** Any signed-in user can read any
   race — including `private` ones — and the response **embeds the active
   invite code**, so a private/invite_code race ID yields both full content
   and the key to join it.
3. **Pose landmarks ARE designed to leave the device on every AI Motion Proof
   session** (auto-uploaded gzip artifact with the full landmark stream).
   In prod this currently fails closed (503, same missing master key), but
   the code intends transmission on every proof — the policy's "no
   body-position data leaves the device" claim is architecturally false the
   moment the secret is set.
4. **FlexiRace has no content-safety layer.** All 12 dangerous prompts tested
   (starvation, weight loss, breath-holding, speeding, theft, pills,
   gambling, violence, smoking) produce creatable races — 12/12 ALLOWED.
5. **Report/block has no UI.** Server endpoints exist, no Dart code calls
   them. Terms claim "report a user, report race/content, block a user" is
   unreachable by users. The admin review route (`GET/POST
   /reports/admin/...`) is mounted under the normal authed router — **any
   signed-in user can read all reports and mark them reviewed.**
6. **Members can force-add any user to a race** (`POST /races/:id/members`,
   `/participants`) — no consent, no block check. A blocked user can be
   pulled into a race.

The motion side is in genuinely good shape: per-account AES-GCM encrypted
artifacts, key-revocation erasure design, 90-day purge cron, fail-closed
release pipeline. But the privacy plumbing it depends on (`MOTION_DATA_MASTER_KEY`)
is unconfigured, which is why two distinct features are dead in prod.

---

## 2. P0 findings

| # | Finding | Evidence |
|---|---|---|
| P0-1 | Account deletion 500s in prod | `auth.ts:749` → `hardDeleteAccount` → `deleteUserMotionData` throws `MOTION_DATA_MASTER_KEY is not configured` (motion_privacy.ts:185). Secret absent from `wrangler secret list` (prod). Live probe of the master-key codepath (`GET /internal/users/:id/motion-sessions`) returns 500. |
| P0-2 | Any authed user reads any race + gets its invite code | `races.ts:1323` `GET /races/:id` → `buildRaceResponse` with zero membership/visibility check; `shapeRaceResponse` returns `inviteCode` from an unconditional `race_invites` query (l.877–879, 736). Participants, move logs (proof notes), standings all leak. |
| P0-3 | Landmark stream designed to upload on every verification; claim says never | `ai_motion_proof_screen_io.dart:1124` auto-enqueues `MotionSessionArtifact` containing `frames: List<NuvoPoseFrame>` + platform/OS/buildMode. Server `POST /motion-sessions` stores it (encrypted) in R2 for ≤90d. Currently 503s in prod (P0-1's cause) — policy is only accidentally true. |
| P0-4 | Deletion coverage gaps even when fixed | `hardDeleteAccount` never touches: `device_tokens`, `notifications`, `notification_preferences`, `personal_bests`, `activity_reactions`, `invites` (actor_user_id), `race_attempts`, `race_events` (actor/subject), `verification_sessions`, `reports` (defensible ≤90d, but no TTL exists). `move_logs`/`race_members` keep raw `user_id` (display-name anonymization only). |

## 3. P1 findings

| # | Finding | Evidence |
|---|---|---|
| P1-1 | FlexiRace: 12/12 dangerous prompts create races | Ran `interpretRaceName` live in a Dart harness: starvation/weight-loss/breath-hold/speeding/theft/pills/BMI/gambling/violence/smoking all → `RaceGoalKind.manual` with the harmful subject as title. "first to lose 20 pounds" = high confidence, target 20. No safety layer exists anywhere. |
| P1-2 | Report/block unreachable + admin review is public-to-users | Endpoints exist (`reports.ts`) but no Dart caller anywhere in `lib/`. `GET /reports/admin/reports` and `POST /reports/admin/reports/:id` sit under `requireAuth` only — any user can read/triage reports (code comment admits: "role-based auth should be added in production"). |
| P1-3 | Forced race adds bypass consent + blocks | `POST /races/:id/participants` and `/members`: any active member adds any `userId`; no target consent, no `blocked_users` check. |
| P1-4 | Terms acceptance not enforced server-side | `hasAcceptedTerms()` returns `true` unconditionally ("Dev override"). UI checkbox + `POST /auth/terms` + `terms_accepted_at` column exist, but every gate (race create, join, photo upload, profile) passes trivially. Policy §5.4 "you cannot create content" is false at API level. |
| P1-5 | No age gate | No DOB, age question, or attestation anywhere in auth/onboarding. The "13+" is a Terms representation only. |
| P1-6 | Community Guidelines: MISSING | Site footer = privacy/terms/delete-account/feedback only. No safety-rules document exists in the bundle or repo. |

## 4. Policy vs code table

| Public claim | Actual implementation | Match | Severity |
|---|---|---|---|
| "No video, photos, or body-position images sent to our servers" | Landmark frames auto-upload on every proof session (encrypted, 90d). Currently 503-fails because key unset. Photo proofs upload to R2 for FlexiRace. | **FAIL** | P0 |
| "does not upload photos or videos as race proof" | `proof-evidence/` R2 objects + `media_objects` + participant-only GET — photo proof is live (photo only; no video path exists). | **FAIL** | P0 |
| "do not collect push-notification device tokens" | `device_tokens` table + `POST/DELETE /devices` + `push_service.dart` + firebase_messaging all ship. No tokens stored *today* (Firebase config files absent → initializeApp throws → dormant). | PARTIAL (claim true only accidentally) | P1 |
| "Delete account" works (app + email) | In-app button calls the broken endpoint (P0-1); email path is manual. | **FAIL** | P0 |
| Deletion covers listed data classes | Misses device tokens, notifications, prefs, personal bests, reactions, invites, attempts, sessions; display-name anonymization only elsewhere | PARTIAL→FAIL | P0 |
| "private profile hides races/progress/history" | Profile/search gating is real (`canViewFullProfile`, minimal card, crew-only presence) — BUT `GET /races/:id` leaks any private/invite race's contents+invite code | PARTIAL | P0 |
| "Terms acceptance required before UGC" | Checkbox + `/auth/terms` + column exist; server enforcement stubbed to `return true` | **FAIL** | P1 |
| "report user / report race / block user / moderation review" | Server endpoints + `blocked_users` enforcement (search, profile 403, crew both-ways, race anonymization, notification suppression) exist; ZERO client UI; admin queue readable by any authed user | **FAIL** | P1 |
| "OTP hash stored, deleted ≤24h after expiry" | SHA-256 hash, expiry+attempt cap, `used_at` set — but NO purge job deletes expired rows | PARTIAL | P2 |
| "tokens revoked/expired deleted ≤30d" | Refresh hashed, `revoked_at`/`expires_at` enforced at use; no periodic row deletion | PARTIAL | P2 |
| "security/audit events ≤90d" | `audit_events` table is dead (zero writes). `verifier_audit_log` covers control plane only; no TTL | PARTIAL | P2 |
| "move/verification logs ≤30d after deletion" | No deletion machinery beyond the (broken) account path + motion 90d purge | FAIL | P1 |
| "no analytics/crash SDKs" | True — no analytics in pubspec/Pods (firebase_core+messaging only, dormant) | PASS | — |
| "no intentional location collection" | No location permission (iOS Info.plist / manifest), no geolocation calls; photo EXIF stripped by picker re-encode in practice | PASS (EXIF formally unverified) | P3 |
| "photo removed/replaced deletes prior R2 object" | Confirmed `deleteR2Object` on replace/remove (profile.ts:243-251) | PASS | — |
| "HTTPS; tokens hashed; secure storage; sanitized errors" | HTTPS; refresh+OTP SHA-256; `flutter_secure_storage`; `response.ts` sanitizes | PASS | — |
| Operator = "akaash deepak" | Site shows NC LLC mention + 7-person team roster; operator field is a personal name + residential address | MISMATCH (founder decision needed) | P2 |
| "US only, no ads/sale" | Consistent with code; no ads SDK | PASS | — |

## 5. Data inventory (authoritative)

| Data | Storage | 3rd party | Other users see | Deletion path | Status |
|---|---|---|---|---|---|
| Email | `users.primary_email`, `auth_identities.email` | Resend (OTP send) | No | NULL'd on delete | OK |
| OTP code | `email_codes.code_hash` (SHA-256) + attempts/expiry | — | No | deleted w/ account; **no expiry purge** | PARTIAL |
| Google sub/name/photo | `auth_identities` | Google | avatar per privacy | deleted w/ account | OK |
| Apple identity | `auth_identities` (provider=apple) | Apple | No | deleted w/ account | OK (not disclosed) |
| Session/refresh | `sessions.refresh_token_hash` | — | No | deleted w/ account | OK |
| Name/username/photo/bio/private flag | `profiles`; photos R2 `profile-*` | R2 public GET | per privacy | deleted + R2 objects deleted | OK |
| Crew connections/requests | `crew_connections` | — | mutual | deleted w/ account | OK |
| Race defs/membership/progress/standings | `races`,`race_members`,`race_progress`,`race_final_standings` | — | participants (see P0-2 leak) | anonymize/soft-delete; **user_id remains** | PARTIAL |
| Manual proofs + notes | `move_logs` | — | participants | summary nulled; row+user_id kept | PARTIAL |
| Proof photos | R2 `proof-evidence/` + `media_objects` + `move_logs.media_object_key` | — | **active participants only (bearer)** | owner delete works | OK* |
| Motion session artifacts (**landmarks**) | R2 `motion-sessions/` AES-GCM/account-key + `motion_sessions` | — | internal only | 90d purge + user delete (needs key) | PARTIAL (undisclosed) |
| Teach Nuvo frames | `motion_training_examples` + R2 `motion-training/` | — | internal | same | PARTIAL (undisclosed, consent-gated `motion-training-v1`) |
| Feedback labels | `motion_feedback_labels` | — | internal | deleted w/ motion data | OK |
| Notifications + prefs | `notifications`, `notification_preferences` | — | self | **not deleted** | GAP |
| Device/push tokens | `device_tokens` (token, platform, app_version) | FCM (dormant) | No | sign-out only; **not on account delete** | GAP |
| Reports | `reports` | — | **any authed user via /admin** | none | GAP |
| Blocks | `blocked_users` | — | counterparty effect | deleted w/ account | OK |
| Reactions | `activity_reactions` | — | race members | **not deleted** | GAP |
| Personal bests | `personal_bests` | — | ? | **not deleted** | GAP |
| Invites | `invites`,`race_invites`,`invite_uses` | — | invitees | race_invites on sole-race delete; `invites` never | GAP |
| Verification sessions | `verification_sessions` (release pin, result) | — | race | **not deleted** | GAP |
| Race events | `race_events` (actor/subject user ids) | — | race | **not deleted** | GAP |
| Attempts | `race_attempts` (user_id) | — | race | **not deleted** | GAP |
| Control-plane audit | `verifier_audit_log` | — | internal | indefinite | OK (internal) |
| IP/user-agent/timestamps | Cloudflare edge logs | Cloudflare | — | CF-managed | disclosed |
| Local: tokens | `flutter_secure_storage` | — | — | sign-out/delete | OK |
| Local: staged session artifacts | app dir, unencrypted gzip (landmarks) | — | — | deleted on upload/max-age | **undisclosed** |
| Local: image cache | cached_network_image | — | — | OS cache | minor |

## 6. Third-party data map

| Provider | Data sent | When | Choice | Disclosed |
|---|---|---|---|---|
| Cloudflare (Worker/D1/R2/edge) | All API traffic + stored data + IP/UA | Always | n/a | Yes |
| Resend | Email + OTP at send time | Login | n/a | Yes |
| Google Sign-In | sub/email/name/photo | Login (optional) | Yes | Yes |
| Apple Sign-In | sub/email/name | Login (optional) | Yes | **No** |
| Firebase/FCM | Token→Google only when configured | dormant (no config files) | permission-gated | No (claims none) |
| Google ML Kit | None — on-device inference | camera verification | camera permission | implied |
| Google Apps Script + Google Forms | waitlist name/email/goal/phone-type | website waitlist | Yes | **No** |
| Hack Club (hcb) | none (link only) | donate link | Yes | covered by links clause |
| ML Kit barcode | on-device | — | — | n/a |

## 7. Account deletion test

Live end-to-end test was **not executable**: creating a real account requires
email-OTP delivery or OAuth; no test credentials exist locally. Static +
runtime proof instead:

- `DELETE /auth/account` → `hardDeleteAccount` → first step throws (key
  unset) → **500, nothing deleted**. Runtime confirmation: master-key path
  500s on the deployed prod worker.
- Coverage analysis (when the throw is fixed): DELETED — media_objects+files,
  auth_identities, sessions, email_codes, crew, passes, profiles, blocks,
  motion stack; ANONYMIZED — race_members display name, move_logs summary,
  users row; RETAINED — move_logs/race_progress/standings rows w/ user_id,
  reports, audit; **ORPHANED — device_tokens, notifications, prefs,
  personal_bests, reactions, invites, attempts, race_events,
  verification_sessions**.

## 8. UGC / report / block results

- Report user/race/content: server writes `reports` rows = EXISTS; client UI
  = **NONE**; admin review = EXISTS but reachable by any authed user = **FAIL**.
- Block: writes + enforcement in search (excluded), profile (403), crew
  connect/accept (both ways), race identity (anonymized), notification
  suppression. Gaps: force-add to races, no block check on `/members` adds,
  no UI. = **PARTIAL**.

## 9. FlexiRace safety results

12/12 prompts → ALLOWED as manual races (titles preserved verbatim:
"Go The Longest Without Eating", "Take The Most Pills", "Punch Someone The
Hardest", "Money Gambling"…). Interpreter is purely grammatical. Enforcement
point: single canonical choke in `interpretRaceName` (client edge) + a
server-side `POST /races` subject-policy check — never 100 string bans;
needs a policy layer decision.

## 10. Age reality

No DOB, no age question, no attestation gate. Terms assert 13+ textually.
Minimum-data option: one-tap "I am 13 or older" attestation stored as a
boolean on `users` (not DOB).

## 11. Apple privacy map (draft, factual)

- Contact info (email): YES, linked, app functionality. (Google/Apple name+photo.)
- Identifiers (user id, Google sub, device tokens): YES linked (tokens dormant).
- User content (profile photo, proof photos, race titles/notes, crew): YES linked.
- Usage/activity (races, progress, standings, move logs, reactions,
  notifications): YES linked.
- Diagnostics (motion session artifacts w/ landmarks, device platform/OS,
  app/git/verifier versions, feedback labels): YES linked — **currently
  undisclosed and mis-claimed as "never leaves device"**.
- Health/fitness-adjacent (motion counts): linked usage data.
- Location: NO. Contacts: NO. Precise device IDs/IDFA: NO. Tracking: NO.

## 12. Google Play Data Safety (draft)

Collects: email, name, username, photos (profile + proof), app activity
(races/proofs), user IDs, device tokens (dormant), in-app messages(notes),
fitness-ish performance data, crash-free diagnostics (landmark artifacts).
No sale/share-for-ads. Encryption in transit; at-rest encryption for motion
artifacts. **Flag: app counts body movements → Google Health Apps
declaration review likely triggered** (fitness/activity-tracking
functionality) — needs founder/product answer.

## 13. Required product changes (not implemented — audit only)

1. Configure `MOTION_DATA_MASTER_KEY` (prod+dev) OR wrap `deleteUserMotionData`
   so deletion can't 500; then extend `hardDeleteAccount` to the full table
   list (§7 orphaned set).
2. Add viewer-access check to `GET /races/:id` (member/crew/invite-code per
   visibility) and stop leaking `inviteCode` to non-members.
3. Gate `/reports/admin/*` behind internal auth; ship report/block UI.
4. Consent + block checks on force-add member endpoints.
5. Wire `hasAcceptedTerms` to `users.terms_accepted_at`.
6. FlexiRace subject-policy layer (reject/question dangerous goals) enforced
   client-edge + server create.
7. Decide whether landmark artifacts are actually wanted; either configure
   the pipeline + disclose, or strip `frames` from the upload schema.
8. Minimal age attestation.
9. Retention jobs: email_codes expiry purge, sessions purge, reports TTL,
   notifications TTL.

## 14. Required policy changes

Proof photos uploaded; landmark stream + device metadata transmitted;
push-token collection exists (dormant); Apple Sign-In + Google Apps
Script/Forms + FCM are undisclosed processors; OTP/session/audit retention
claims have no machinery; report/block/moderation claims overstate; operator
entity + address need founder input; add deletion-gap honesty or fix code
first.

## 15. Founder decisions needed

- Legal entity name (LLC) to replace "akaash deepak"; business mailing
  address (current is residential-looking).
- Keep or kill automatic landmark telemetry (product vs privacy posture).
- Whether to ship report/block UI now or trim Terms claims.
- Age attestation approach.
- Whether force-add-to-race stays (with consent?) or becomes invite-only.

## 16. Lawyer review needed

- COPPA posture given 13+ claim with zero gate; teen users' proof photos.
- Fitness/wellness liability + the dangerous-race gap (self-harm, ED,
  dares).
- Retention claims (numbers) vs missing jobs.
- Biometric-adjacent language for landmark telemetry if enabled (state BIPA-
  style exposure even though it's not identification).
- Moderation obligations once report/block go live; Play UGC policy.
