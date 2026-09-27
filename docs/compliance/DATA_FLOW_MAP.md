# Nuvo Data Flow Map

Engineering privacy reference — the actual paths user data takes, verified against current code.

## Signup / sign-in

```
Flutter (welcome_auth / email_start)
  ├─ Email path: POST /auth/request-code → Worker → email_codes (hash, ≤24h) → Resend API → user's inbox
  │              POST /auth/verify-code  → Worker → auth_identities + users + session tokens → D1
  ├─ Google:     google_sign_in SDK → Google token → POST /auth/google → verify vs Google → D1
  └─ Apple:      sign_in_with_apple → Apple credential → POST /auth/apple → verify vs appleid.apple.com → D1

  → session tokens → flutter_secure_storage (device keychain)
  → onboarding: Terms checkbox → POST /auth/terms-acceptance
  → onboarding: "I am at least 13" → POST /auth/age-attestation
  → onboarding: Help improve Nuvo / Not now → POST /motion/consent (consent+version+timestamp; opt-in requires age_attested_at — server 403 otherwise)
```

## AI Motion Proof (live verification)

```
Camera frames (device) → ML Kit pose detection / ONNX (on-device)
  → pose landmarks evaluated on-device
  → verification outcome + metadata (verifier/model versions, timing, outcome)
     → POST race proof endpoints → D1 (proofs, race_attempts, verification_sessions)

RAW VIDEO: never leaves the device via this pipeline.
RAW AUDIO: not part of this pipeline.
```

## Motion contribution (optional training pipeline)

```
Pose landmarks (from AI Motion Proof session, on-device)
  → client checks server consent state (motion_session_providers)
  → consent ON + age attested
       → staged locally (≤7d) → POST /motion-sessions (+ artifact upload)
       → Worker: consent re-checked server-side (fail-closed)
       → encrypted per-account (key wrapped under MOTION_DATA_MASTER_KEY)
       → R2 motion objects + D1 rows keyed by derived account reference
       → purged ~90d by daily cron
  → consent OFF/revoked → server returns {stored:false}; nothing persisted
```

## Proof photos

```
image_picker (camera or gallery) → submit_proof_screen / profile
  → upload authorization from Worker → R2 (proof-evidence/<race>/... or profile-avatars/)
  → media_objects row (D1) → served to authenticated race participants only
  → re-encoded server-side/on-upload (EXIF/location metadata stripped)
```

## Push notifications

```
App event (race/crew activity) → notification_jobs → notifications inbox (D1)
  → device_tokens (D1) → FCM → APNs → device
  → token registration: firebase_messaging → device_api.dart → Worker (auth)
  → token removal: logout unregister + account deletion
  → in-app preferences: notification_preferences gate what sends
```

## Crew / social

```
Crew requests, accept/decline → crew_connections (D1)
Blocks → blocked_users (D1) → enforced in race access + social surfaces server-side (raceAccess.ts)
Reports → reports (D1) → internal triage only: /internal/reports behind X-Internal-Key
```

## Private race access

```
GET /races/:id → raceAccess.ts: owner | active member | (public/crew_only/invite_code rules) | blocked check
  → invite codes never serialized to non-authorized callers
  → outsider: denied before race detail or code disclosure
```

## Account deletion

```
Profile → Delete account → DELETE /auth/account (authed)
  → deleteUserMotionData (R2 objects + rows + wrapped key; works w/o master key)
  → R2: all owned media_objects deleted
  → D1 deletes: auth_identities, sessions, email_codes, crew_connections,
    member_passes, profiles, blocked_users, device_tokens, notifications(+prefs+jobs),
    activity_reactions, personal_bests, race_attempts, verification_sessions,
    proofs, race_participants, people, invites(+uses), owned solo races (full cascade
    incl. proof-evidence R2 prefix)
  → D1 de-identify: race_members → 'Deleted User', move_logs.summary NULL,
    race_events actor/subject NULL, notifications actor NULL
  → users: status='deleted', primary_email=NULL
  → reports: retained (safety/legal)
```

## Website (separate from app account data)

```
getnuvo.net waitlist / feedback / NC State forms → Google Apps Script → Google Sheet
  → Resend for transactional email where used on site
```
