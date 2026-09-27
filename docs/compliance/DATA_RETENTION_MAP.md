# Nuvo Data Retention Map

Every meaningful data category: where it lives, how long it stays, what removes it. Verified against `server/worker/src/` (routes, `lib/dataRetention.ts`, `lib/motion_privacy.ts`, `auth.ts` `hardDeleteAccount`, `index.ts` scheduled handler `0 3 * * *` cron).

| Data | Location | Purpose | Retention | Purge mechanism | Account-deletion behavior | User control | Policy section |
|---|---|---|---|---|---|---|---|
| Email OTP codes (`email_codes`) | D1 | Sign-in | Hash stored; row deleted ≤24h after expiry or use | Daily cron `purgeExpiredAuthData` | Deleted for user's email | n/a | PP §3.1, §8 |
| Sessions / refresh (`sessions`) | D1 | Auth | Row deleted ≤30d after expiry/revocation | Daily cron | Deleted | Logout revokes | PP §3.1, §8 |
| Auth identities (`auth_identities`) | D1 | Apple/Google/email sign-in mapping | Account lifetime | — | Deleted | Sign-out | PP §3.1 |
| User record (`users`) | D1 | Account | Tombstoned on deletion (`status='deleted'`, `primary_email=NULL`, demo fields nulled) | — | Soft-delete, email cleared | Delete account | PP §9, Del page |
| Profile (`profiles`, `member_passes`) | D1 | Identity, pass | Account lifetime | — | Deleted | Edit profile, delete | PP §3.2 |
| Profile photos (`media_objects`, R2 `profile-avatars/*`) | D1 + R2 | Avatar | Until replaced or deletion (prior files also deleted) | Replace deletes old object | All owned objects deleted from R2 | Change/remove photo, delete | PP §3.2, §9 |
| Crew connections, blocks (`crew_connections`, `blocked_users`) | D1 | Social graph | Account lifetime | — | Deleted both directions | Remove/block/unblock, delete | PP §3.2, §10 |
| Races you own — no other active members | D1 + R2 | Races | Until deletion | — | Fully deleted incl. all race data + `proof-evidence/<race>/` R2 prefix | Delete account | Del page |
| Races with surviving members (`race_members`, `race_progress`, `move_logs`, `race_events`) | D1 | Shared race record | Race lifetime | — | **De-identified:** display name → 'Deleted User', avatar NULL, `move_logs.summary` NULL, `race_events` actor/subject NULL | Delete account | Del page |
| Proof submissions (`proofs`, `race_participants`, `race_attempts`, `verification_sessions`, `personal_bests`) | D1 | Verification | Account lifetime | — | Deleted | n/a, delete | PP §3.3, §9 |
| Proof photos (`media_objects`, R2 `proof-evidence/*`) | D1 + R2 | Race evidence | Until account deletion or owning-race deletion | — | User's owned objects deleted always; entire race prefix deleted when race fully deleted | n/a | PP §3.3, §9 |
| Activity (`activity_reactions`) | D1 | Reactions | Account lifetime | — | Deleted (user's) + race-scoped for dead races | Delete | PP §3.3 |
| Notifications (`notifications`, `notification_preferences`, `notification_jobs`, `device_tokens`) | D1 | Delivery | Account lifetime | — | Deleted; `actor_user_id` nulled in others' feeds | Preferences, logout (token unregister), delete | PP §3.4 |
| **UNRESOLVED — no purge period:** `notifications`, `notification_jobs`, `race_events`, `reports` | D1 | Feeds, audit, moderation | Indefinite today | None | Account deletion cleans user's rows; reports intentionally kept | — | Flag: founder decision on periods |
| Reports / moderation (`reports`) | D1 | Safety | Indefinite (safety/legal) | None | **Retained** even on deletion (both directions) | Report UI | PP §8, §9 |
| Invites (`invites`, `invite_uses`, `race_invites`) | D1 | Joining | Race/invite lifetime | — | User-minted invites + uses deleted | Delete | PP §9 |
| Motion landmarks + metadata (`motion_sessions`, `motion_motion_data`/artifacts) + R2 `motion/*` | D1 + R2, encrypted per-account key under master key | Consent-gated model training | ~90 days | Daily cron `purgeExpiredMotionData` deletes R2 objects + rows | `deleteUserMotionData`: R2 objects + rows + wrapped key deleted — works without master key (object keys stored) | Privacy & Data toggle stops new storage; delete removes history | PP §3.6, §5 |
| Staged motion artifacts on-device | App sandbox | Upload queue | ≤7d client-side prune, removed on upload or revocation flush | Client queue prune | Uninstall clears; deletion prevents upload | Toggle off drops staged artifacts from upload eligibility | PP §5 (server-side note) |
| Waitlist / feedback (website) | Google Apps Script → Sheet | Marketing | Indefinite | Manual | Manual via email request | Email request | PP §3.7 |

## Unresolved policy choices (founder)

1. Retention period for `notifications`, `notification_jobs`, `race_events`, `reports` — none set; policy says "as needed for safety/legal".
2. Whether tombstoned `users` rows should eventually be hard-purged (currently permanent minimal record).
3. On-device staged-artifact window is 7d — not user-facing, documented here only.
4. Waitlist retention (website) — no policy period; acceptable for launch but note it.
