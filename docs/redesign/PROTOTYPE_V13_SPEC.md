# Nuvo v13 redesign: screen spec from the prototype

Square brackets are placeholders for live data.

## Global rules
- Light mode only for this release. Background #F5F6F8, cards #FFFFFF.
- Signature look: 2 to 2.5 px navy (#07152D) outline and a hard offset shadow (3 to 6 px, no blur) on cards and buttons. Never remove it.
- Color: about 65% off-white/white and 25% navy. Nuvo blue #1264FF covers 10 to 20%, only for the one main action and for "you". Race and crew colors: coral #FF8A65, sun #FFC93C, lilac #CDBFFF, mint #9EE6C4, sky #B8D2FF. Gold #F5B800 is only for 1st place. Divider #E6E9EF, muted text #5E6A80.
- Exactly one colored hero per screen, and one obvious primary action (blue) per screen.
- Lists are open rows with thin 2 px dividers, not boxes. Spacing between sections is 36 to 48 px.
- Font: Manrope 500 to 800. Titles 24 to 28 px at 800, section heads 19 px at 800, body 13 to 15 px.
- Radii: buttons 14, cards 22 to 28, chips and pills 99, icon tiles 10 to 16.
- People always appear as real profile photos in a navy-outlined circle, never initials. With no photo, show a neutral silhouette. "You" gets a blue ring. Tapping any face anywhere opens that person's public profile, or your own Profile tab if it's you.
- Motion: one overshoot spring curve for presses, the tab indicator, toggles and number pops (about 420 to 600 ms). Buttons press by sinking into their shadow, with a light haptic.
- Playful touches only reward an action: confetti when you join, accept or earn something, a floating "+N" when you log a proof, and a number pop when your rank changes. No decorative stickers. No glowing or pulsing dots.
- No dead buttons. Every tap does something real, or the button is not shown.
- Toasts: a small navy pill near the bottom for confirmations.
- Tab bar: white and outlined, not a dark bar. Four tabs (Arena, Compete, Crew, Profile), with a blue spring indicator under the active tab.

## Arena tab (home)
1. Header: "Hey [first name]", with a sub line and flame icon: "[N] day streak · Level [L]". On the right, a bell button that opens Activity (a coral badge shows the unread count), and your avatar inside a blue XP ring. The ring shows XP to the next level. There is no separate level bar.
2. A "YOUR RACES · [count]" label, with "Swipe for more" on the right.
3. Race swiper: horizontally snapping cards, one per active race, with the next card peeking (cards about 318 px, 12 px gap). Each card has:
   - the race color as its background, plus the outline and a 6 px shadow
   - a top row with up to 3 leader faces, "[Movement] · [N] racers", and the time left on the right
   - the race name, 18 px at 800
   - your score in huge type (84 px) with "/ goal", and your place on the right
   - a progress bar, navy fill on a white track
   - a gap line: "9 behind Alex", "Leading Priya by 4", or "You crossed the finish line"
   - a full-width blue "Submit proof" button with a camera icon, which opens Submit proof for THAT race
   - tapping the card body opens Race detail
   The last page is a dashed white card: "Up for another one?", a "Start a race" button that opens New race, and a "Join a race" link to Compete. Page dots sit under the swiper; the active dot is a wide navy pill, and tapping a dot scrolls to that card.
4. Nudge row: the photo of whoever just passed you, "Priya passed you", "Squat Race · 2 ahead", and a "Take it back" button that opens Submit proof for that race. If nobody passed you, show the next most useful nudge.
5. Stats triple: RACING, WINS and WIN RATE, with dividers.
6. Activity heat map: 18 weeks by 7 days of blue intensity squares, with "[N] proofs · 18 weeks", "[N] active days", and a Less to More legend.
7. Achievements: an "[earned] of [total]" link and 4 badge tiles. Tapping opens Badges.
8. Submit proof bottom sheet:
   - A Camera / Manual segmented control.
   - Camera mode shows AI Motion counting: "Put your phone down so Nuvo sees your whole body", a live count, then "Nice set. AI Motion verified it."
   - Manual mode has a minus/plus stepper.
   - A preview line, for example "This moves you to 1st."
   - The main button logs the proof. After logging, the sheet closes and the score animates up. A "+N" floats, the rank pops if it changed, and a toast shows. Confetti fires if you took the lead.
   - The AI Motion Proof camera screen and its validators stay unchanged. Only the entry sheet is restyled.

## Compete tab
- Header "Compete", with a blue "New race" button.
- "Live races" swipe cards, 250 px wide: a race color strip, the name, time left, your rank and trend, a progress bar, and the faces of racers in rank order. Tap to open Race detail.
- "Join a race" cards: open races from friends, with faces, names ("Maya, Theo and Noah"), and a Join button. Joining turns it into "Joined", with confetti and a toast.
- Leaderboard: open rows with rank, photo, name and points. Your row is tinted. No split header. Tapping a row opens the profile.
- Trending moves: small cards with the movement icon tile, "[N] racing", and a "Start" button that opens New race prefilled.
- Trophy shelf: a horizontal row of medals (gold, silver and bronze circles with the place) and past race names.
- A small "more below" chevron (two lines meeting at a point at the bottom) floats above the tab bar. It fades out once you scroll more than 40 px.

## New race (composer, 4 steps)
- Step 1 is the race name: "What are you racing?" with a text field. As you type, it autofills movement, goal, mode (first to, most total, or best single) and finish (today, 3 days, 1 week, or 2 weeks) from the name. Autofilled values are marked "auto", and the user can change any of them.
- Step 2: movement grid (Pushups, Squats, Jumping jacks, Plank, plus custom ones), a goal stepper, and mode chips.
- Step 3: invite friends. Rows show photo, name, "Raced you 9 times", and a checkbox.
- Step 4: review rows (tap a row to edit that step) and a blue "Start race" button. After starting, go to Compete and show a toast: "[name] is live. N invites sent."
- Every step has a back button and a step indicator.

## Race detail
- Back button, race name, rule line ("First to 100 reps"), and time left.
- Podium for the top 3: big photos and medals, with 1st raised and gold. The rest follow as open rows.
- Your progress, the gap line, and the blue Submit proof button.

## Crew tab
- Header "Crew", with a QR code button (opens My Nuvo code) and an "Add friend" button (opens scan).
- "Your crews": outlined cards. Each has a crew icon tile in the crew color, the crew name, "[N] members · Run by Alex", your rank this week ("#2", "this week"), member faces (+N), and the next recurring race ("Pushup Monday · In 2 days"). Tap a card to open the crew page. Below the cards: "+ Start a crew" (dashed) and "Join with a code".
- "Racing right now": a horizontal row of friends who are racing. Each shows a photo, a small movement badge, the name, and what they are doing. Tap a face to open the profile.
- Friend request card (lilac): "Sam Rivera wants to race", "Friends with Priya and Alex", and Accept.
- "What your crew is doing" feed. Each item has:
  - a photo with a kind badge (logged, earned a badge, passed you)
  - the text, for example "[Name] logged 14 pushups"
  - the race color and time
  - a big number chip for logs
  - a cheer button (flame plus count) that toggles
- "Your friends' crews": rows with the crew icon tile, name, faces, "Priya's crew · 6 members", and an "Ask to join" button that turns into "Requested".

## Crew page
- Back button and a 3-dot button. Members get Share crew, Copy invite link, Mute crew, and Leave crew (in red, with a confirm step). Non-members get Report crew.
- Big crew icon tile, crew name, "[N] members · since [month year]", and the crew bio.
- Buttons: a blue "Start a crew race" that opens New race with all members invited (non-members see "Ask to join" or "Requested"), and "Invite", which opens My Nuvo code.
- Stats triple: Crew wins, Races, Crew streak.
- Crew leaderboard with a This week / All time switch: medal circles, photo, name, an Owner/Admin/Member tag, and points. Your row is tinted blue.
- Recurring races: icon tile, name, "Every Monday · First to 100", a tag ("Live now" or "In 2 days"), the faces of who auto-joins, and an Auto-join toggle per race. "+ Add" opens New race prefilled with the crew.
- Crew battle: "[crew] vs [rival crew]", a split bar, points for each side, and "Ends Sunday".
- Members grid: photo, name, and an Owner/Admin tag. Tapping opens the profile, and Back returns to the crew page.

## Profile tab (your profile) and public profiles
- Shared Instagram-like layout: @username at the top. Your own profile also has a QR button and a real gear (settings) button. Then photo, name, level as plain text (no blue box), bio, counts (Races, Wins, Friends), and a favorite movement chip.
- Own profile buttons: "Edit profile" and "Share profile". Below them: activity map, achievements (3 featured badges), and race history with medals.
- Public profile of a friend:
  - a header with photo, name, active status, bio, counts, and mutual friends' faces
  - a blue "Challenge [Name]" button that opens New race with them invited
  - a "Friends" button with an action sheet: Mute, and Remove friend with a confirm
  - a 3-dot button: Share profile, Copy profile link, Mute, Report, and Block with a confirm
  - a "[Name] vs you" scoreboard: both photos, "STATS WON a – b", and rows for Level, Wins, Win rate, Best streak, and Proofs this week. The winner's value is a filled pill (blue for you, navy for them), the loser's is grey text, and a tie is a grey pill. No season stuff.
  - friendship badges, for friends only: First race, Rivals (10 races together), Cheer squad (20 cheers), Best friends (30 days), and Streak buddies (both log 7 days). Locked ones are dashed or grey with a progress bar. Tapping one explains it.
  - their activity map, their achievements (locked ones dashed), and races with you
- A non-friend's profile has "Add friend", which becomes "Requested", and "Message", which explains that you have to be friends. An incoming request shows "Accept".
- Blocking leaves the page and hides them everywhere.

## Badges page
A progress ring, the badge closest to unlocking with a "Find a race" button, your 3 profile slots, filter chips (All, Earned, Locked, Racing, Winning, Streaks), and a grid. Tapping a badge opens a detail sheet with a big tile, description, status, rarity, and "Show on profile" or "Remove from profile" (max 3).

## Settings
An account card at the top, then grouped sections:
- Notifications: passes, invites, results, cheers, reminders.
- Privacy: private profile, show my activity map, who can challenge me.
- App: appearance, haptics, sounds, help improve AI Motion, presentation mode.
- Support.
- Account: sign out, and delete account with a confirm.
Rows have colored icon tiles and spring toggles.

## Edit profile
A Cancel and Done top bar, a photo change, boxed fields (name, username with an availability check, and bio with an 80-character counter), and favorite movement chips. Cancel discards unsaved changes.

## My Nuvo code
A My code / Scan segmented control. My code shows your QR code with the Nuvo logo, @username, Share and Copy link. Scan shows the camera view, finds a code, and shows the person with an "Add friend" button (confetti when added).

## Activity (bell)
Notifications grouped into New and Earlier. Each has a photo, text, time, and an inline action button where it fits (Take it back, Accept, View). Opening the screen clears the badge count.
