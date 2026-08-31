# UI Polish Audit

_Conducted: 2026-06-18. Based on full code read of lib/. Physical device testing not performed in this pass._

---

## Global Issues

- **Status bar:** `AppTheme.overlay` (dark icons on icy-white) is defined in `app_theme.dart` and set on `AppBarTheme`, but not applied globally via `SystemChrome`. Screens without an AppBar (most custom screens) may show the wrong icon brightness on iOS.
- **SafeArea:** All main screens wrap content in `SafeArea`. The AI Motion Proof back button has 18px top padding inside SafeArea — safe on iPhone, but could clip on very small devices. Standardising to `NuvoBackButton` removes inconsistency.
- **Button consistency:** Core system (`NuvoPrimaryButton`, `NuvoOutlineButton`, `NuvoGhostButton`, `NuvoDangerButton`) exists and is used. Arena screen `_FeaturedRaceCard` has a raw `GestureDetector` mini-button that bypasses the system.
- **Card hierarchy:** Cards are white with border. Featured/leader cards should use navy fill with backplate to signal importance.
- **Empty states:** `NuvoEmptyState` is clean but the compete screen has a duplicate "Start a race" CTA (one at top, one inside the empty state widget).
- **Typography:** Consistent Inter usage across all screens. Some display labels use `labelSmall` with manual muted color — fine.
- **Spacing:** Horizontal padding is 20px globally. Some sections feel slightly cramped. No critical gaps found.

---

## Screen Issues

### Race Detail

- **Issues:**
  - `_ActionPanel` opens the screen with a large "Race actions" card dominating the view. Makes it feel like an admin dashboard, not a race.
  - Danger actions (Archive, Cancel, Delete) are exposed as `ActionChip` widgets directly on the main race view.
  - Proof method shows raw API strings: `"Self report · manual · auto accept"` — confusing for an AI motion race.
  - "Copy invite code" label likely truncates on standard iPhone widths.
  - No "My progress" card showing the user's current position before the leaderboard.
  - Race title is shown without title-case cleanup, so `"do 10 jumping jacks"` appears raw.

- **Fixes:**
  - Remove `_ActionPanel` panel. Place `Submit proof` / `Join race` as the dominant CTA right after the header.
  - Move Edit race, Race settings, Share race, Copy code to a bottom "Manage race" section.
  - Move Archive, Cancel, Delete lifecycle chips to the bottom of the Manage race section (or redirect to Race Settings).
  - Add `_MyProgressCard` for participants with a goal.
  - Fix proof method display: detect AI motion races by `proofRequirement == 'ai_check'` or title containing "jumping jack".
  - Change "Copy invite code" → "Copy code".
  - Display-sanitise race title to title case.

### AI Motion Proof

- **Issues:**
  - Back button uses `IconButton.filledTonal` — inconsistent with desired round lavender circle style.
  - Record button uses `Icons.fiber_manual_record_rounded` (white dot on blue) with label "Record" — looks like a random dot, not a clear record action.
  - Result states (verified/failed) show inside the small `_statusPanel` card rather than a premium full-width result view.
  - No differentiation between the camera panel and result panel — same card used for everything.

- **Fixes:**
  - Use `NuvoBackButton` consistently.
  - Change "Record" → "Record proof", icon → `Icons.videocam_rounded`.
  - For `aiVerified` state: replace camera panel with premium navy result card (large verified badge, reps, confidence, AI accepted label).
  - For `aiFailed` state: replace camera panel with coaching card (detected reps, encouragement copy, not an error).
  - Hide `_statusPanel` for terminal result states (info is in the result panel).

### Compete

- **Issues:**
  - Two "Start a race" buttons: one primary CTA at top, one inside `NuvoEmptyState`. Duplicate primary action.
  - Quick starts are generic (race to a 6-pack, most books read). Top one should feature "10 Jumping Jacks · AI Motion Proof" for launch alignment.
  - Quick start tiles lack icons and right-arrow affordance.
  - Quick start tiles use `auto_awesome_rounded` (sparkle) icon for all — not contextual.

- **Fixes:**
  - Remove CTA from the empty state (primary "Start a race" at top is sufficient).
  - Replace quick start list with AI-demo-aligned content: "10 Jumping Jacks" first.
  - Add contextual icons and subtitle per quick start.
  - Add right arrow to quick start tiles to signal tappability.
  - Use `PressableScale` or `InkWell` with press feedback.

### Arena

- **Issues:**
  - Featured race card has a "Log progress" mini-button — should use Nuvo language "Submit proof".
  - Quick action card "Start race" should read "Start a race" (consistent with other screens).

- **Fixes:**
  - Change "Log progress" → "Submit proof".
  - Change "Start race" → "Start a race".

### Submit Proof

- **Issues:**
  - Back button uses `IconButton.filledTonal` — inconsistent.
  - The `_AiMotionProofCard` says "Start AI proof" as the CTA — task spec says "Use your iPhone camera to verify reps live" is good copy but the CTA label is fine.

- **Fixes:**
  - Replace `IconButton.filledTonal` back buttons with `NuvoBackButton`.

### Profile / Pass

- **Issues:**
  - No critical UI Polish issues in this pass (profile/pass screens are functional and reasonably clean).

---

## Design System Changes

- **Button variants:** All existing. Adding `NuvoBackButton` as a dedicated round circle nav widget.
- **Card variants:** Race detail leader row now uses navy fill. AI result panels use navy (success) and icy (coaching) fills.
- **Status pills:** Race status chip added to race detail header area.
- **Empty states:** Compete empty state loses duplicate CTA. Copy updated to Nuvo language.

---

## Implementation Order

1. `UI_POLISH_AUDIT.md` — this doc ✓
2. Status bar fix — `main.dart` + `app.dart`
3. `NuvoBackButton` — `nuvo_button.dart`
4. Race detail screen restructure — hierarchy, proof method, leaderboard, manage section
5. Compete screen — duplicate CTA fix, quick starts
6. AI Motion Proof — button labels, result states
7. Arena screen — copy fixes
8. Docs update — `QA_CHECKLIST.md`, `BUTTON_AUDIT.md`
9. `flutter pub get` + `flutter analyze`
