# App Review Notes — Nuvo iOS

Paste-adaptable notes for the "App Review Information" field in App Store Connect. Keep secrets out of git — see "Review account" below.

## What Nuvo is

Nuvo is a competition app. Members create or join races with friends and the public, submit proof of progress, and follow leaderboards. Races can be private, invite-code, crew-only, or public.

## How races work

- A member creates a race (typing a competition idea — "FlexiRace" interprets it — or picking a format), invites people, or opens it to their crew or the public.
- Members submit proof to log progress: manual entry, photo proof, or AI Motion Proof.
- The race creator can review proofs. Rankings update on the leaderboard.

## AI Motion Proof and camera use

- AI Motion Proof uses the camera to verify a movement live. Camera frames are processed **on-device** (pose extraction runs locally); the camera stream is not uploaded.
- The app asks for camera permission when the member first uses AI Motion Proof or takes a photo.

## Optional motion-data contribution

- During onboarding we ask "Help improve Nuvo" or "Not now". This is optional and off by default; "Not now" does not limit the app.
- If a member opts in, motion-point data (numeric pose landmarks produced on-device — not camera video or audio) may be securely stored to improve and train Nuvo's motion models. It is encrypted, not linked to name/email inside the artifacts, and purged after ~90 days.
- Opt-in requires an age-eligibility confirmation first.
- Members can toggle it any time: **Profile → Privacy & Data → Help improve Nuvo Motion**. Turning it off stops future contributions from being stored.

## Account deletion (in-app, required by App Review)

- **Profile → Delete account.** Deletion is immediate: the session ends, and account, profile, media, device tokens, participation data, and motion artifacts are removed or de-identified as described at https://getnuvo.net/delete-account.

## Moderation features

- Report a person (from their profile), report a race (from the race page), report an individual move (from proof review), and block a person. Reported content enters a moderation queue.

## Permissions declared

- **Camera** — live pose verification for AI Motion Proof; taking proof and profile photos.
- **Photo library** — choosing profile and proof photos.
- **Push notifications** — race and crew updates the member opts into; the device token registers only after sign-in.

## Review account

- The app supports sign-in via one-time email code plus Apple and Google sign-in. The reviewer does **not** need mailbox access.
- Entering `testing@getnuvo.net` on the email screen switches the form to a **password** field. Supply that password privately in the "App Review Information → Sign-in required" section of App Store Connect — **do not put it in this file or in git**. The password is validated server-side; the account is pre-seeded with a full demo world (races, crew, leaderboard, proof).
- Every cold launch opens at the public Welcome screen. From there the same credential supports two paths:
  - **Sign up** walks through Nuvo's complete new-user experience: account setup, the Nuvo story, notification education, then a guided first race ending in the Profile progression payoff. Quitting and reopening the app returns to Welcome, so the flow can be restarted as often as needed.
  - **Sign in** opens the pre-seeded reviewer account directly at the Arena for immediate feature access.
- Notification permission already granted or denied is handled without re-prompting.

## What does not exist

- No payments, no in-app purchases, no gambling or prize mechanics.
- No user-generated content feed beyond race activity inside the member's own races/crew.
- No data sale or advertising.
