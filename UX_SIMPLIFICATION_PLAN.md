# Nuvo UX Simplification Plan
_Updated: 2026-06-19_

## Problem

The app looks strong visually but the UX is cluttered. Competing sections, duplicate race lists, and always-visible system controls make the app feel like a settings panel rather than a race command centre.

## New Mental Model

| Tab | Job |
|---|---|
| **Arena** | Your current races + next action. What should I do right now? |
| **Crew** | Member pass + find/add people. Who is in my crew? |
| **Compete** | Start or join something new. Nothing else. |
| **Profile** | Account only. Settings, sign out. |

Each screen has one job. No screen duplicates another screen's primary content.

## Changes Made

### 1. Bottom Nav — Pass → Crew
- `bottom_nav.dart`: `(Icons.badge_rounded, 'Pass')` → `(Icons.group_rounded, 'Crew')`
- Route stays `/pass`. Label and icon change to reflect the job: find and add crew.

### 2. Compete — Start or Join Only
- Removed "Your races" section from `compete_screen.dart`
- Arena already owns the race list; Compete showing it again created a competing home base
- Compete is now: Start a race → Join with code → Quick starts
- Changed `ConsumerWidget` → `StatelessWidget` (no longer needs race state)
- Updated subtitle: removed "with proof" to be more welcoming

### 3. Arena — State-Aware Featured Card
- `_FeaturedRaceCard` now accepts `userId` and checks the current user's own progress
- If user's progress ≥ 100: shows "Finished" label + green "Complete" pill instead of "Submit proof" button
- Unchanged races still show "Your next move" + "Submit proof"
- Quick action "Pull crew" renamed to "Invite crew" (more specific action)

### 4. Race Detail — State-Aware CTAs
- Added `myRaceComplete = myParticipant?.progressPercent >= 100`
- Complete state: shows `_RaceCompleteCard` + "Start another race" primary + "Submit more proof" ghost
- Incomplete state: shows "Submit proof" primary (unchanged)
- "Invite crew" stays for owner regardless of completion state

### 5. Create Race — Template Confirmation Mode
- Added `_showDetails = false` state (toggled to `true` for Custom or when user taps "Customize")
- For non-Custom templates (including 10 Jumping Jacks prefill): Goal and Unit fields collapse into `_LockedGoalRow`
- User sees: template pills → race title → locked goal summary → proof mode card → Start CTA
- Tapping "Customize" in the locked row reveals the full fields
- Custom template always shows all fields

### 6. Submit Proof — Direct AI Flow
- For AI races (`isSupportedAiMotionRace && !_showManualFallback`):
  - Compact header row: Back button + "AI Motion Proof" title inline
  - AI Motion Proof card as the hero content (already has Start AI proof CTA inside)
  - Small "Use manual proof instead" text link below (not a prominent outline button)
- Manual races and manual fallback: keep existing layout

## Screens Not Changed

- `pass_screen.dart` — layout unchanged; tab label changed only
- `profile_screen.dart` — untouched
- All onboarding screens — untouched
- AI Motion Proof screen — untouched
- Race Settings / Danger Zone — untouched
- Proof Review — untouched

## What Did NOT Change

- All routes and navigation paths
- All backend calls and API integration
- All AI detection logic (only 10 Jumping Jacks is AI-ready, unchanged)
- All visual system: colours, shadows, typography, card styles
- No fake data added anywhere
- No new AI activities

## Demo Path After This Change

1. Open app → Arena (your races or empty start line)
2. Tap **Compete** → "Start a race" + clean Quick Starts (no race list cluttering the decision)
3. Tap **10 Jumping Jacks** → Create Race in confirm mode (race title + locked goal + AI card)
4. Tap "Start AI race" → Race Detail
5. Tap "Submit proof" → AI Motion Proof direct (compact header, card as hero, no friction)
6. Verify reps → submit → Race Detail shows updated progress
7. Tap **Crew** (was Pass) → member pass + crew section
