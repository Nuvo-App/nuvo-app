# Nuvo — Attorney Review Brief

For counsel review of the iOS launch package: Privacy Policy, Terms of Service, Account Deletion page, Community Guidelines (all at getnuvo.net, source in the marketing repo `legal/` directory), plus this repository's compliance docs.

**Company:** Get Nuvo LLC, 312 Leyton Lane, Cary, North Carolina, United States.
**Product:** iOS competition app ("races") with social crews, proof submissions (manual/photo/camera-verified), and an optional on-device-extracted motion-landmark contribution used to train Nuvo's own verification models.

---

## MUST RESOLVE BEFORE SUBMISSION

### 1. Minors aged 13–17 contributing motion-landmark data for model training

Nuvo allows users aged 13+ and currently lets any age-eligible user opt in to "Help improve Nuvo," which stores pose-landmark (motion-point) data for Nuvo's own model training/evaluation. Landmarks are encrypted, pseudonymized (no name/email/username inside artifacts), purged after ~90 days, deleted on account deletion, never sold, and camera video/audio is never uploaded.

- Is it lawful and prudent to allow 13–17-year-olds to contribute this data with only an attestation + in-app toggle, or should contribution be restricted to 18+ (or require parental consent) for launch?
- If restriction is recommended: the consent architecture supports a segment gate without re-architecting — a one-line server-side eligibility change. Is that sufficient remediation if done pre-launch?
- Do COPPA (under-13 boundary), or any state minors'-privacy statutes (e.g., California AADC-adjacent rules, other state teen-privacy laws) affect the current design even though 13 is the floor?

### 2. Age-attestation design sufficiency

Current design: user checks "I am at least 13" at signup and again before motion opt-in; the server stamps `age_attested_at`. **No birthdate is collected** (deliberate minimum-data choice). Legacy accounts were explicitly NOT fabricated into attested status (migration 0038).

- Is attestation-only sufficient for the 13+ claim under COPPA's "actual knowledge" and FTC guidance for a general-audience app?
- Does attestation-only create exposure we should mitigate (e.g., re-prompt cadence, neutral age gate, DOB collection for the motion feature only)?

### 3. Legacy account Terms treatment

Users who joined before server-side Terms enforcement were backfilled to `terms_version='legacy'` and `terms_accepted_at` = their original acceptance (they did check a Terms box at signup historically — enforcement just wasn't server-tracked). Terms mutations are now server-enforced for everyone.

- Is grandfathering legacy acceptance under a `'legacy'` version flag defensible, or must all accounts re-accept on next login?
- If a Terms vNext ships, what notice/consent mechanics do we need for both legacy and current-version users?

### 4. UGC / content license scope

Terms §6 grants Nuvo a non-exclusive worldwide royalty-free license to host/process user content "as needed to operate, provide, secure, and improve the Service," explicitly including opt-in motion data per the Privacy Policy.

- Is the license scope appropriately narrow (service-operation purposes only, no promotional-use rights)?
- Is "improve the Service" + the opt-in motion paragraph together sufficient cover for internal model training on contributed data, or does training need its own explicit grant?
- Any issue with content surviving deletion only in de-identified form inside other members' race records ("Deleted User" label)?

### 5. Liability / fitness disclaimer adequacy

Terms §8 disclaims medical/fitness advice, tells users to compete within their limits, and §14 caps liability at US$100 with standard exclusions.

- For a product whose core loop encourages physical and other competitions between members, is the current disclaimer/cap structure reasonable for a pre-revenue consumer app in NC?
- Should the Community Guidelines' prohibited-competition list be referenced in, or incorporated into, the Terms themselves (they currently sit as a separate page cross-linked from Terms §7–§9)?

### 6. North Carolina governing law & venue

Terms §16 selects NC law and NC courts.

- Any enforceability concern for a nationwide consumer app (consumer-protection carve-outs in other states)?
- Should we add an arbitration clause or small-claims carve-out, or deliberately omit arbitration for a small launch? (We have intentionally omitted it pending counsel's view.)

---

## CAN REVIEW POST-LAUNCH / AS NUVO GROWS

### 7. Pose-landmark characterization under privacy law

- What is the correct legal characterization of numeric body-pose landmarks (skeleton keypoints + session metadata, pseudonymized, encrypted, no raw media) under: CCPA/CPRA "personal information" and "sensitive PI" (biometric information processing for identification vs. non-identification), Illinois BIPA (does "biometric identifier/information" reach pose keypoints used for model training, not identity recognition?), Texas CUBI, Washington My Health My Data (fitness data), and GDPR/UK GDPR if reached?
- Is "pseudonymized" the accurate descriptor, or does any regime treat the derived-account-reference linkage as making it identifiable regardless?
- Does model-training use trigger any "biometric" consent requirements in states where pose data could qualify?

### 8. Retention language adequacy

- Current stated periods: OTP ≤24h, sessions ≤30d, motion artifacts ~90d; everything else "account lifetime" or "safety/legal need" with no fixed period. Reports are retained even after deletion.
- Is purpose/lifecycle-based retention language (no fixed number) acceptable for reports/notifications/race history, or do regulators/Apple expect concrete periods for each class?
- Any issue with the minimal tombstoned account record (`status='deleted'`, email cleared) being retained permanently?

### 9. State privacy-law applicability as Nuvo grows

- Which comprehensive state laws (VA, CO, CT, UT, TX, OR, MT, etc.) plausibly apply at our scale, and at what thresholds?
- Our DSAR surface today: in-app deletion, email requests, no export tool. Is a manual email-based access/correction process sufficient initially?
- Do we need a "Do Not Sell/Share" or GPC-honoring mechanism given we don't sell/share — is the negative statement in the policy adequate?

### 10. Additional teen safeguards

- Beyond a possible 18+ gate on contribution: are chat-adjacent features (notes, reactions, race names) sufficient risk to warrant teen-specific default privacy settings (e.g., private profile by default for self-attested minors)?
- Should block/report SLAs or a minor-safety contact be formalized?

### 11. Cross-border & processor items

- Resend, Cloudflare, Google, Apple DPAs — verify adequacy; any SCCs needed if EU users sign up?
- Google Apps Script waitlist (marketing site) — separate mini-policy needed or covered?

### 12. Employment/contest law

- Community Guidelines prohibit gambling/prize mechanics. If races ever carry stakes (entry fees, prizes), what triggers gaming-lottery analysis — confirm current "no value exchanged" position avoids it.

---

## Documents for review

- `legal/03_PRIVACY_POLICY.md`, `04_TERMS_OF_SERVICE.md`, `05_ACCOUNT_DELETION.md`, `08_COMMUNITY_GUIDELINES.md` (site repo)
- `docs/compliance/PRODUCT_TRUTH_AUDIT.md`, `APP_STORE_PRIVACY_MAP.md`, `DATA_RETENTION_MAP.md`, `DATA_FLOW_MAP.md`, `DATA_PROCESSOR_INVENTORY.md`, `PERMISSION_AUDIT.md` (this repo)
