# Nuvo Onboarding v2 — Spec

Constraints: accounts required, no guest mode; navy #07152D 2-2.5px outline + hard offset shadow (no blur) everywhere; 2 base colors (#F5F6F8/white, navy) + blue #1264FF accent at 10-20% for the one main action and "you"; one colored hero per screen from coral #FF8A65, sun #FFC93C, lilac #CDBFFF, mint #9EE6C4, sky #B8D2FF; one obvious CTA per screen; Submit proof is the main focal point; floating dock; every press sinks + haptic; font Manrope; light mode.

Why v1 failed: empty welcome, email screen with dead zone and grey Send code button, empty dashed Arena card, no tutorial/progress/reward. Fix: no empty screen (each has one moving hero); product teaches by doing with a hand-holding tour on the real UI; one continuous XP rail turns first run into Level 1 to 2; ends on a real celebration.

## CONCEPT
Thin XP rail (outlined bar, level badge 1 left, 2 right) visible from S4 until level-up; each completed step flies a "+N" chip into it (spring fill). Pre-auth: 3 page dots instead. XP: verified code +10, player card +15, starter questions +10, first proof +30 (10 if camera fallback), Compete +10, Crew +10, Profile +5, notification accepted +5 = 100, target exactly Level 1 to 2 on the real server (read the real XP curve first, adjust).

THE TRACK: one continuous background layer, navy 2.5px curved race path with beads per step; never resets; pans left 420ms easeInOutCubic per step with parallax (path 1.0x, foreground 1.15x); user's avatar bead springs to next bead.

## MOTION TOKENS
Single NuvoMotion file; no screen defines own numbers.
- spring = mass 1, stiffness 380, damping 22 (~520ms, 6-8% overshoot) for press release/toggles/number pops/entrances.
- pressDown 90ms easeOut, translate 3px into shadow, shadow 4px to 1px, on every button/chip/tab/actionable row.
- enter 480ms spring from y+28 opacity 0, stagger 70ms max 5.
- exit 260ms easeIn y-12 opacity 0 scale .97.
- float: idle translateY sine +-6px period 3.2s random phase 0-1.6s rotation +-1.2deg on hero cards/avatar tokens/badges only, never text/buttons.
- tiltParallax accelerometer +-8px optional.
- xpFly: chip rises 24px then curves 600ms to rail easeInOutCubic, rail fills with spring.
- confetti: existing app confetti, 1.1s, 40 pieces, brand colors.
- Primary CTA never moves between steps (fixed bottom, 16px side margins, 56px high, label changes only; docks above keyboard with spring).

## HAPTICS
Flutter HapticFeedback, respect Settings toggle: selectionClick for chips/dots/XP ticks; lightImpact on every press; mediumImpact on step complete/Track advance; heavyImpact once at level-up; success pattern (light, 70ms, medium, 70ms, heavy) for level-up and email verified.

## SOUND
Default on only in onboarding + level-up, respects silent switch: soft tick on press, rising chime on XP, fanfare on level-up, each asset <60KB.

## REDUCE MOTION
No float/parallax/confetti, 200ms cross-fade transitions, XP rail still fills without overshoot.

## PERF
60fps on iPhone 12+ release; first frame <100ms; CustomPainter/implicit animations only (no video/heavy Lottie); size growth <400KB excl. sounds.

## SCREENS
Side margin 16 CTA, 24 text; titles Manrope 800 28-34px; body 15px/500; muted #5E6A80; back = existing outlined square; Skip = quiet text link top right where allowed.

**S0 Splash (retired in-flow)**: the real app shows its own splash before the flow, so the flow renders no second splash. `OnboardingStep.splash` stays in the enum for saved-state/analytics-index compatibility and is always auto-completed; a fresh install goes app splash -> S1 duel directly.

**S1 Intro "Race anything"** (tap duel, no data/permissions): dots + Skip; coral hero card 300px; title "Race anything." sub "Pushups, reading, anything. Beat your friends." Hero: mini lane with 3 racer tokens: you (blue ring, silhouette labeled You) + 2 ghosts (Nuvo Crew photos if assets exist else silhouette bots), beads, finish flag; ghosts creep with float. For 5s each tap moves your token one bead (spring), tick + selectionClick, big count pops. Ghosts scripted so a normal tapper wins by 1-2 beads at the last second (never lose). End: flag drops, confetti, mediumImpact, chip "You won. That took 5 seconds." Idle 3s: hand pointer taps once (one time, no loop). Chip "Tap the card as fast as you can". CTA "Next" (arrow), pressable any time; if pressed early the duel auto-plays and finishes in 1.5s.

**S2 Intro "Prove it on camera"**: hero = phone outline (navy 2.5px, hard shadow) with a stick-figure skeleton (blue joints, navy bones) doing a squat loop (CustomPainter keyframes); counter pops 1,2,3 on squat bottom (spring, lightImpact); pill "AI Motion verified" slides in after rep 3. Title "Prove it on camera." sub "Nuvo counts every rep. No faking, no arguing." Runs by itself; tap restarts.

**S3 Intro "Climb the board"**: hero = leaderboard card, 4 open rows (rank, photo circle, name, points); user's row (silhouette, blue ring) starts 4th; every 2.4s points tick up, row swaps upward with spring, rank number pops; at 1st gold ring flash + small confetti. Title "Climb the board." sub "Every proof moves you up. Friends see it live." CTA "Create my player" (blue); link "I already have an account" (Log in). CTA raises S4 sheet over the same hero (board freezes at 1st, blurs 6px).

**S4 Sign in** = bottom sheet over the hero (replaces empty welcome): white, 28px top radius, navy outline top edge, rises 480ms spring, drag handle. Title "Save your spot" (800/26px), sub "So your races, friends and level are yours." Rail first appears (Level 1, 0 XP). Buttons 56px, 12px gap, hard shadow: Continue with Apple (navy fill, white text, primary), Continue with Google (white outlined), "Use email instead" text link. One legal line "By continuing you agree to the Terms and Privacy Policy". Loading: pressed button shows inline navy spinner, others fade to 40%. Errors: sheet shakes 6px twice + coral error line, no dialog. Existing Apple/Google flows unchanged, visuals only.

**S5 Email** = "player pass" ticket filling as you type: top back + rail (Level 1, 0%, "Step 1 of 4"). Hero (upper third): outlined sky ticket with perforated edge, Nuvo logo mark, label PLAYER PASS, monospace line with typed email (each char scale-in 60ms), floats/tilts; stamp slot "Not verified yet". Title "What's your email?" sub "We send a 6 digit code. No password to remember." Field 60px outlined, label above, autofocus, email keyboard, AutofillHints.email, textInputAction send, blue 2.5px focus ring. Domain chips above keyboard (gmail.com, icloud.com, school domain after "@") insert with selectionClick. Valid format: stamp "Ready" (mint), CTA turns blue (spring pop), lightImpact. Typo hint "Did you mean gmail.com?". CTA "Send code" blue fixed above keyboard; disabled = muted outlined + hint "Enter your email". Keyboard up: ticket shrinks to 60% (spring). Sending: "Sending..." + ticket print animation (up 12px and back). Rate-limit/network errors inline coral.

**S6 Code**: ticket stays with "Code sent to name@email.com" + Change. Title "Check your email." sub "Enter the 6 digit code." Six outlined boxes 52x64, gap 8, active box blue; scale-in on type; auto-advance; paste of 6 digits fills all with 40ms stagger; AutofillHints.oneTimeCode; clipboard chip "Paste 482915?". Auto-submit on 6th digit ("Verifying..."). Success: boxes flip to checkmarks (80ms stagger), stamp slams "VERIFIED" (spring overshoot, mediumImpact then success pattern), +10 XP flies to rail, hold 700ms, Track advances. Error: shake (6px x3, 280ms), coral 600ms, clear, heavyImpact, "That code did not match. Try again." After 5 wrong: "Too many tries. Wait 1 minute." Resend link with 30s countdown ("Resend in 24s" then "Send a new code"). "Didn't get it?" sheet with tips (spam, change email, use Apple/Google). OTP APIs unchanged.

**S7 Player card**: back, rail (Level 1, 10 XP), "Step 2 of 4". Hero player card 300x190 outlined hard shadow floating: left photo circle (silhouette + "+" camera badge; tap = sheet Take photo/Choose photo/Skip), right name (live), @username (live), "Level 1" pill, tiny XP ring; typing scale-ins chars; picking a photo flips the card 360deg (400ms), 12 confetti, mediumImpact. Fields: Name, Username (live availability: green check or coral "taken, try @name12" with one-tap alternatives), optional photo row. One mandatory checkbox "I'm 13 or older and I agree to the Terms, Privacy Policy and Guidelines". CTA "That's me" blue, disabled until name+username+checkbox valid. Why-lines: name "Friends find you by this", username "Your @ for races and invites", photo "Faces make races real". Complete: card stamp press, +15 XP. Reuse existing username-check and photo-upload code.

**S8 Starter questions** (2, one per screen, skippable): Q1 "What do you want to race?" outlined icon chips, 2 columns, 56px: Fitness, Running, Reading, Studying, Gaming, Something else (single choice; chip sinks + selectionClick; a preview race card below rewrites its title live e.g. "Pushup Race", "Reading Race"). Q2 "Race solo or with friends?" three big cards: "With friends", "Solo first", "Surprise me" ("With friends" adds QR share step in tour; "Solo first" skips it). Footer "Skip" + CTA "Next". +10 XP after Q2 or skip. Under titles "This picks your first race. You can change anything later."

**S9 "Your first race is ready"**: 2.2s transition, no input; player card shrinks and flies to top-left avatar position, Track fades to Arena layout, three racer cards deal in (90ms stagger): "Building your first race..." then "Practice race vs Nuvo Crew is live". Dock (hidden until now) slides up with spring. Then S10.

**S10 Arena tour: practice race + first proof.** Arena never empty: a "Practice race" card (coral, small "Practice" tag, race name from Q1 e.g. "Squat Race · First to 10") first in the swiper; Submit proof is the one blue focal point. Racers labeled "Nuvo Crew" (real photos if assets exist else silhouette bots), scores 6 and 4, user 0, "3rd place". Coach mark (spotlight on card, bubble below): "This is a race. You are 3rd. Beat them." Only tapping the highlighted Submit proof advances; hand pointer taps once. Submit proof sheet = real camera sheet with real AI Motion proof (restyled look only; camera logic/validators untouched). Camera permission requested HERE with one line above the system prompt: "Nuvo counts your reps with the camera. Video stays on your phone." Live encouragement changes every 4s ("Nice depth", "Keep going"). Practice goal 3 reps (squat) to pass the first racer, <20s; count ticks with lightImpact. Fallback if camera denied/unavailable (simulator): "Skip camera for now" completes as a Practice proof worth 10 XP instead of 30 (tutorial-only; real races never allow manual proof for camera movements). Result: sheet closes, score animates up, "+3" floats, rank pops 3rd to 2nd (spring), confetti, toast "You passed <racer>", +30 XP flies to rail. 3s later scripted surprise: nudge row slides in (photo, "<racer> passed you", "Take it back"); bubble: "That's how Nuvo works. Someone passes you, you take it back."

**S11 Notification opt-in in context**: right after the nudge, light bottom sheet (not full screen), hero = nudge row. "Want a buzz when someone passes you?" CTA "Turn on notifications" (blue, triggers iOS prompt), secondary "Maybe later". +5 XP if accepted; declining costs nothing; offered again after first real race. Motion-data consent stays deferred (after 3rd proof/Settings).

**S12-14 TOUR**, 3 stops, one mission each, one real tap on real UI, dim everything else, max 3 lines of copy, counter "Tour 1 of 3" in bubble, demo data labeled "Practice".
- Stop 1 Compete: dock tab highlights (hand taps once). "Compete is where races find you." Spotlight on "Join a race" card; mission tap Join (becomes "Joined", small confetti); +10 XP; "Joined. You can start your own anytime with New race."
- Stop 2 Crew: "Crew is your people." Spotlight on My Nuvo code (QR) button; mission tap it, QR sheet opens (Nuvo style), bubble "Anyone who scans this becomes your friend."; close sheet to continue; if Q2 was "With friends" highlight Share: "Send this to one friend." (optional); +10 XP.
- Stop 3 Profile: "Profile is you." Spotlight on first badge tile ("Day One" earned); mission tap it, detail sheet opens, "Show on profile"; +5 XP.
- After: "That's the whole app. One more thing." and the dock slides down/out as the level-up takes over.
- "Skip tour" text link top right after 2s; skipping leaves a slim "Getting started" row on Arena (5 missions, progress dots) so the user can finish and still earn Level 2; nothing forced.

**S15 LEVEL UP**: full-screen route over everything, the ONE full-bleed Nuvo blue #1264FF screen in the app; white + navy outlines.
- t0: dock slides down, scrim fades to blue 320ms easeOut.
- t250: avatar (photo 140px) rises to center (spring), ring at 96%, soft whoosh.
- t600: ring fills to 100% over 450ms easeIn with 10 selectionClick ticks.
- t1050: ring flash, shockwave (scale 1 to 1.6, fade), confetti (white/sun/coral), heavyImpact, fanfare.
- t1100: "LEVEL 1" rolls to "LEVEL 2" via existing NuvoNumberFlow (700ms, rapid ticks).
- t1700: "LEVEL UP" letters drop in (40ms stagger, overshoot), success pattern.
- t2100: three reward tiles slide up (70ms stagger): "+100 XP", badge "Day One" (earned), "1 day streak started"; lightImpact each.
- t2600: CTA "Enter the Arena" (white, navy outline, hard shadow) rises + floats; secondary "Share my level".
- Tap anywhere after 900ms speeds to CTA (never a trap). CTA press: blue floods out in a circle (500ms) revealing Arena while dock slides up (spring).
- Reward data real: server XP/level, real badge, real streak. Share card 1080x1350 (avatar, name, Level 2, "Join me on Nuvo", QR in Nuvo QR style), optional. If tour skipped: no celebration until missions done, then same moment.

## EMPTY STATES
Rule: moving hero + one sentence + one blue CTA; no dashed empty boxes.
- Arena no races: coral hero same size as race card (318px) with ghost race preview (3 silhouette racers, track, flag), "Your first race", blue "Start a race", link "Join a race"; card floats; "Getting started" row if missions remain. Header "Hey <name>" + "Level 1 · Day 1"; avatar = user photo or neutral silhouette inside blue XP ring (real progress), never a bare grey circle.
- Stats triple with all zeros shows "Your first win is 1 proof away".
- Activity map: empty 18x7 faded grid, first square outlined blue, "Today starts your map".
- Achievements: locked tiles with progress arc, "0 of 43", closest says "1 proof to go" and is tappable.
- Compete empty: "No races yet" hero + Start a race; Leaderboard "Add friends to see a board" + QR button.
- Crew no friends: "Racing is better together", QR preview, "Share my code" and "Add friend".

## TOUR ENGINE
Overlay above the whole Navigator; scrim navy 72% with rounded cutout (target radius + 8px, 2.5px navy outline, 4px hard shadow); scrim absorbs touches except the cutout; target keeps real behavior. Bubble white/outlined/hard shadow with tail, max 3 lines 15px, coach chip (navy circle with white M logo) top-left, counter muted; enters 480ms spring from target direction; never covers target; flips above/below. Pointer: hand icon taps target once (700ms press), idle 6s tap once more then stop; no looping, no glow, no pulsing dots. Persistence: step stored locally (optionally server flag onboarding_tour_step); resume after kill at earliest owed step. Back/Close always works. Off-screen targets auto-scroll 400ms easeInOutCubic; if target not found within 1.5s skip the step and log (never block). Anchors via GlobalKeys: Submit proof button, race card, dock tabs, "Join a race" card, My Nuvo code button, first badge tile; tests assert anchors exist. Script in one Dart file tour_script.dart (id, target key, copy, mission, XP). TourFixtures provider overlays demo race/joinable race/demo friends only during the tour; labeled "Practice"; never sent to server; removed when tour ends.

## COPY
Voice: short, warm, direct, a little competitive, no exclamation marks except level-up.

## DECISIONS (approved)
- D1 practice racers real Nuvo Crew photos only if assets exist else silhouette bots
- D2 level-up full-bleed blue
- D3 reduced-XP camera fallback
- D4 server grants 100 XP once, idempotent, additive
- D5 practice data client-only labeled Practice
- D6 sounds only in onboarding
- D7 reuse onboarding-v13 logic/tests if available, redraw all screens
