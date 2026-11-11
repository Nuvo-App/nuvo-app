# Onboarding v2 screen plan (shipped flow)

Principles (Duolingo / Strava / Headspace / Airbnb): value first in a few
swipeable screens, then sign-in, then minimal setup, then straight into the
real app. No giant cards, no tap-through-only steps, no gates. XP/level is a
small reward (one welcome toast), never a step.

Standing rules: flat hero art (AGENTS.md), one header, one CTA slot, max 1
headline + 1 supporting line per screen, layout never depends on the keyboard
(stable widget tree), 8pt grid, 24pt text margins.

## Before -> after

| # | Before (v2.0) | After (shipped) |
|---|---|---|
| 1 | S1 tap duel (giant coral card, 20 taps) | Intro page 1 "Race anything." |
| 2 | S2 phone demo + board (giant) | Intro 2 "Prove it on camera." (rep counter) |
| 3 | - | Intro 3 "Climb the board." (YOU climbs to 1st) |
| 4 | - | Intro 4 "Race with your crew." (crew joins) |
| 5 | - | Intro 5 "Level up." (XP bar, LEVEL 1 -> 2) |
| 6 | Login sheet | Login sheet + "Create one" |
| 7 | - | Create page: Apple / Google / email (explicit choice) |
| 8 | Email (ticket card) | Email: big title, one field, one button |
| 9 | Code + stamp | Code: boxes, explicit Next |
| 10 | Player card (giant coral card) + terms | Player setup: name, @username, photo (optional), 13+ |
| 11 | Q1, Q2, S9 first race, Level Up gate | CUT (setup never asks what the app can learn later) |
| 12 | Tour stubs | CUT (flag off) |
| 13 | - | Arena + one welcome toast "+100 XP, you are Level 2" |

## Taps from the first open to inside the app (typing is not a tap)

| Path | Before | After |
|---|---|---|
| Fastest (Skip -> Apple/Google -> terms -> That's me) | ~27 (duel 20 + Next x2 + ...) | **4** |
| Email (Skip -> email -> Send -> Next -> terms -> That's me) | ~30 | **6** |
| Full intro (5 pages: 4 Next + Get started) then Apple | - | 5 + 3 = 8, all optional (Skip, or swipe) |
| Returning user, logged out | intro again | **0** intro taps: login sheet directly |

Asserted by `test/onboarding_v2/auth_matrix_test.dart` ("tap count" tests).

## Progress bar (exact formula)

Hidden on intro page 1. Shown from page 2 on through setup (intro pages 2-5,
email, code, player setup).

- One unit = one real screen the player passes: 5 intro pages + 3 setup stages
  (sign in, verify, profile) = **8 units** (`ObProgress.total`).
- `done` while a screen shows: intro page p (1-based) -> `p - 1`; sign-in /
  create / email -> 5; code -> 6; player setup -> 7; finished -> 8.
- Shown fraction: `1 - (1 - done/8)^1.5` (an ease-out of the real ratio:
  starts quicker so progress is felt, exactly 0 at the start and exactly 1.0
  at the end, so it never claims completion early).
- Monotone by construction, plus a per-run floor (`ObProgress.shown`) so Back
  can never make it move backwards.
- Honest: it counts real remaining screens; it only changes the *shape*, never
  the endpoints. Tests: `intro_pages_test.dart` (monotone, 0 -> 1, bounded by
  real ratio + 0.30, floor).
- Values: p2 19%, p3 35%, p4 51%... (page 5 65%), sign-in 77%, code 88%,
  profile 96%, done 100%.

## First open only

A local `nuvo_first_run_done` file is written the first time the intro opens
(and whenever anyone signs in). Later signed-out opens, and every logout, land
on the login sheet. R1 (testing@getnuvo.net last signed in): cold start wipes
local onboarding + this flag -> a clean first-run intro. R2 sign-in skips
onboarding, R3 create walks it, R4 fake-data pill.

## Per-screen hero decisions

| Screen | Focal point | CTA | Hero |
|---|---|---|---|
| Intro 1-5 | one flat demo on a color field | Next / Get started | KEEP: race lanes, rep counter, board climb, crew join, XP fill. Flat, no card |
| Login / Create | real Nuvo logo + typewriter on navy | Continue with Apple | KEEP (unmodified logo asset) |
| Email / Code | the field / the boxes | Send code / Verify, Next | none |
| Player setup | live player preview + fields | That's me | KEEP (real content) |
| Arena (first) | the app itself | - | empty-state hero |
