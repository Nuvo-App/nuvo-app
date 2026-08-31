# Nuvo Product Model

This is the source of truth for all product, UX, and copy decisions in Nuvo.
Every AI agent and every developer must read this before making product or UI
changes.

---

## One-line definition

Nuvo turns real-life goals into leaderboard races with your crew.

---

## Core product loop

```
Set a finish line → pull in your crew → submit proof → move the leaderboard
```

---

## Race definition

A race is a shared leaderboard with:

- a finish line (the goal)
- participants (the crew)
- proof (how progress is earned)
- progress (each participant's position)
- a completion / winner state

A race is not a challenge. A race is not an event. A race is not a quest.

---

## Proof definition

Proof is how a participant moves on the leaderboard.

Proof types:

| Type | Description |
|---|---|
| AI Motion Proof | Camera + on-device pose detection verifies supported movements live |
| Manual proof | User enters a number and an optional note |
| Photo proof | User submits a photo or video |
| Note proof | User submits a written update |
| Link proof | User submits a URL |
| Daily check-in | User marks completion each day |

**Never fake AI verification.** AI Motion Proof must use real on-device pose
detection. The `confidence` score and `verificationStatus` must come from
`motion_validators.dart`. Do not short-circuit, mock, or bypass.

---

## Leaderboard definition

The leaderboard is the emotional center of Nuvo.

It shows:

- who is in the race
- each participant's rank
- each participant's progress toward the finish line
- proof status (verified, pending, failed)
- what changed after the most recent proof submission

The leaderboard must be the hero of Race Detail — not buried inside a section
among many. Every update to a race should visibly change the leaderboard.

---

## Bottom nav ownership

| Tab | Owns | Does not own |
|---|---|---|
| Arena | What needs my attention right now — next-move board, featured race, quick access to submit proof | Active race lists, dashboards, stats |
| Compete | Start a race or join a race | Active race lists, leaderboard views |
| Crew | People I can race with — search, add, manage | Active races, proof, leaderboard |
| Profile | Identity, member pass, race record, settings | Active race management, proof submission |

---

## Main screen ownership

| Screen | Owns | Answers |
|---|---|---|
| Onboarding | Teach Nuvo by helping the user start their first race | What is Nuvo? What is my first step? |
| Arena | Next-move board — the one race that needs action right now | What race needs my attention? What do I do next? |
| Race Detail | Leaderboard room for one race | Who is winning? What is the finish line? How do I submit proof? |
| Submit Proof | Choose or complete proof | How do I move the leaderboard? What proof do I submit? |
| AI Motion Proof | Verify a supported movement with camera and on-device pose detection | Is my movement verified? What is my count? |
| Crew | Search, add, and manage people | Who is in my crew? How do I add people? |
| Profile | Identity, pass, race history, settings | Who am I? What is my record? |

---

## Race formats

| Format | Description |
|---|---|
| Most | Who can do the most? |
| First to Finish | Who reaches the finish line first? |
| Streak | Who stays consistent? |
| Time | Who logs or lasts the most time? |
| Milestone | Who completes the most steps? |
| Scorecard | Who makes the most total progress? |

---

## Launch race categories

### Fitness
- Most Jumping Jacks
- First to 100 Push-Ups
- Longest Plank
- Summer Fit Race

### School
- Study Sprint
- 20 Math Problems
- Read 5 Chapters
- AP Summer Prep

### Build
- Ship a Side Project
- Fix 20 Bugs
- Launch Landing Page

### Habits
- 30 Days No Scrolling
- Sleep Before 11
- Water Streak

### Summer
- Touch Grass 20
- Cook 5 Meals
- Summer Explorer

---

## Product language

### Use

| Term | Meaning |
|---|---|
| race | A shared leaderboard competition with a finish line |
| crew | The people in a race or the user's social network |
| proof | How a participant moves on the leaderboard |
| progress | A participant's position toward the finish line |
| leaderboard | The ranked list of participants and their progress |
| start line | The moment a race begins |
| finish line | The goal / completion target |
| submit proof | The act of recording progress |
| pull in your crew | Inviting people to join a race |
| arena | The tab showing what needs the user's attention now |
| member pass | The user's identity card with QR code |
| AI Motion Proof | The camera-based live movement verification feature |
| invite code | A short code used to join a race |

### Never use

| Banned term | Use instead |
|---|---|
| challenge | race |
| event | race |
| venue | — |
| journey | — |
| unlock | — |
| discover | — |
| coming soon | Remove or replace with neutral copy |
| needs setup | Remove or replace with neutral copy |
| betting | — |
| gambling | — |
| crypto | — |
| payment | — |
| payout | — |
| sponsor | — |
| investor | — |
| SMS | — |
| Twilio | — |
| Firebase | — |
| Supabase | — |

---

## UX rules

### Every screen must answer

1. What is this?
2. Who is winning, or what is my progress?
3. What do I tap next?

### Every race card must answer

1. What is the race?
2. What is the finish line?
3. Where am I?
4. What moves the leaderboard?

### Primary action rule

Every screen must have one primary action. Screens with more than one primary
button are a product bug, not a design decision.

### What Arena is not

Arena is not a dashboard. Arena is not a list of all active races. Arena is
the next-move surface — it surfaces the one race that needs the user's
attention right now.

### What Race Detail is not

Race Detail must not bury the leaderboard inside a section. The leaderboard is
the first thing the user sees. Everything else (proof method, rules, manage
race) is secondary.

### What Profile is not

Profile must not manage active races. Profile is identity, history, and
settings.

### What Compete is not

Compete must not show active race lists. Compete is the entry point to start or
join a race.

### Dead UI rule

Do not show buttons that do nothing. Do not show "coming soon" copy. If a
feature is not built, remove the tile or button entirely. Placeholder UI
erodes trust.

---

## Do-not-touch areas

The following areas must not be modified without explicit, scoped approval:

| Area | Why |
|---|---|
| Auth logic | Session loss or broken login is demo-breaking |
| Race API / backend contract | API changes must be coordinated with the deployed Cloudflare Worker |
| AI Motion Proof logic (`motion_validators.dart`) | Verification must be real — never fake confidence scores |
| Camera / ML Kit bridge | Camera lifecycle bugs cause leaks on physical iPhone |
| iOS native files (`Podfile`, `project.pbxproj`, `Info.plist`) | Corruption breaks all iOS builds |
| Dependencies (`pubspec.yaml`, `pubspec.lock`) | Upgrades can silently break ML Kit + camera + secure storage |
| Backend schema (`server/worker/`) | D1 schema changes can corrupt production data |
