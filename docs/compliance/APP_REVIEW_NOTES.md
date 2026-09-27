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

- A reviewer sign-in method exists: the app supports sign-in via one-time email code (enter the email, receive a code) plus Apple and Google sign-in.
- **Do not put credentials in this file or in git.** Supply the review email/code privately in the "App Review Information → Sign-in required" section of App Store Connect, or coordinate a live code at review time through the demo account (`testing@getnuvo.net` routes to the internal review flow).

## What does not exist

- No payments, no in-app purchases, no gambling or prize mechanics.
- No user-generated content feed beyond race activity inside the member's own races/crew.
- No data sale or advertising.
