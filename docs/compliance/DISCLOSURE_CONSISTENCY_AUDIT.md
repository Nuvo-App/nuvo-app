# Disclosure Consistency Audit

Contradiction sweep run across: `lib/`, `server/worker/src/`, `ios/`, `docs/`, marketing site `src/`, `legal/`, `public/`. Result of each searched claim below.

| Claim searched | Found | Verdict | Action |
|---|---|---|---|
| "akaash deepak" / "Treeswing" | `legal/finalize_legal.py` (generator), `legal/07_FINAL_REPORT.md`, `docs/compliance/PRODUCT_TRUTH_AUDIT.md` (as historical finding) | STALE — generator would rewrite wrong entity into live pages | Script disabled (exits with deprecation notice); internal docs marked SUPERSEDED; new docs use Get Nuvo LLC / 312 Leyton Lane, Cary NC |
| "we don't upload photos / no photo proof" | `legal/finalize_legal.py` §97 ("does not upload photos or videos as race proof") | FALSE claim — proof photos upload to R2 today | Script disabled; new policy discloses proof photos (§3.3, §4) |
| "pose landmarks never leave device" | `docs/motion_runtime/cloudflare_delivery.md` ("pose never uploads"), audit §194 (historical finding) | STALE — landmarks upload when user opts in | Doc line corrected + cross-linked to DATA_FLOW_MAP; audit marked historical |
| "no push tokens collected / push dormant" | Old `Runner.entitlements` comment ("dormant until GoogleService-Info.plist") | STALE — push is live; `device_tokens` registers via `device_api.dart` | Entitlement comment rewritten; policy §3.4 discloses tokens; privacy map includes Device ID |
| "all data is anonymous" | None claiming anonymity. Apps Script error text "Anyone, even anonymous" is Google deployment jargon, not a privacy claim | OK — landmarks described as pseudonymized, never anonymous | — |
| "camera video is uploaded" | None. Camera string previously implied recording ("record moves") | String corrected: "...verify your movement live...Camera video is not uploaded" | Info.plist updated |
| "motion contribution is mandatory" | None | OK — onboarding offers real "Not now"; settings toggle exists | — |
| "we collect DOB" | None | OK — attestation only, no birthdate field anywhere | — |
| "motion data is sold/licensed" | None | OK — policy states no sale, no ad sharing | — |
| "Google Play" | `legal/06_DATA_SAFETY_WORKSHEET.md` (Android worksheet), `legal/07_FINAL_REPORT.md`, `StoreButtons.tsx` ("Early access for Google Play"), Footer trademark line | Internal docs marked SUPERSEDED. **Store buttons + footer are live marketing** — founder decision whether to keep an Android early-access badge on an iOS-only launch site; flagged, not changed | — |
| "challenge" (product language) | `CompetitionChips.tsx` ("Pick a challenge", "CREW CHALLENGE"), `FutureSection.tsx` | STALE copy vs product language | Replaced with "race". Community Guidelines deliberately describe prohibited behavior categories ("competitions involving drugs/pills/tobacco") without the word |
| Old permission strings | `NSPhotoLibraryAddUsageDescription` unused; camera/photo strings incomplete | STALE/unused | Removed add-key; camera + library strings rewritten |
| `aps-environment=development` | Hardcoded for all build configs | Would force sandbox APNs in App Store build | Removed; provisioning profile supplies correct value |
| Deletion "30 days" | Old deletion page claimed delete/anonymize within 30 days | STALE — deletion is immediate | Rewritten: immediate deletion + de-identification model |

## User-facing surfaces verified clean

- Onboarding Terms/Privacy links → getnuvo.net/privacy + /terms (live, correct pages)
- Motion contribution screen: "Camera video and audio are not uploaded" — TRUE for that pipeline
- Privacy & Data toggle copy matches policy §5
- All four legal routes render current Get Nuvo LLC documents; `_redirects` SPA fallback + static route copies cover direct loads

## Residual flagged items (not changed — founder decisions)

1. StoreButtons "Google Play early access" + footer Google Play trademark line on an iOS-only launch.
2. `legal/01/02/06/07` internal docs retained as historical (marked SUPERSEDED — safe to delete entirely if preferred).
3. Waitlist Google Apps Script — outside app data lifecycle; retained in processor inventory.
