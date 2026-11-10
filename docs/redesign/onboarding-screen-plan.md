# Onboarding v2 screen plan (shipped flow)

Shipped order: S1 intro race -> S2 how it works -> login sheet -> email -> code
-> player card -> Q1 -> Q2 -> Level Up -> Arena. Cut (kCutSteps): S9 first race
ready (promised a race that does not exist), S10-S14 tour, notify sheet.

Common rules (all screens)
- ONE header (`OnboardingShell._TopBar`): safe-area top, 16pt sides, 44x44 back
  at the left, progress/dots centered between two equal 56pt slots with 12pt
  gaps (never touching), optional right action. No screen draws its own back.
- Max 1 headline + 1 supporting line. Same title style, same CTA slot
  (56pt, fixed bottom, 16pt margins). 8pt grid, 24pt text margins.
- Layout NEVER depends on the keyboard (no hero/label toggling as it rises):
  a conditional insert in a Column re-creates the field and kills typing.
- Flat hero art: no tilt, no float, no floating cards, no fake tiles.

| Screen | Focal point | Primary CTA | Allowed | Hero decision | Cut |
|---|---|---|---|---|---|
| S1 Race anything | the live tap duel (real interaction) | Next | dots, Skip, hint chip | KEEP (real content, flat) | extra copy |
| S2 Prove it. Climb. | phone demo + board (real product) | Create my player | "I already have an account" link | KEEP | Skip |
| Login / Save your spot | real Nuvo logo + headline on navy | Continue with Apple | Google, Use email, legal | REPLACE card with real logo + one race path | back arrow, rail, handle, subtitle, coral |
| Email | the email field | Send code | app icon header, title, 1 sub line, label, domain chips/typo hint | REPLACE passport ticket with the real app icon | ticket, stamp, N tile, step counter |
| Code | the six boxes | Verify / Next | app icon, title, Change, Resend, tips | REPLACE ticket with app icon; verified = mint checks + "You're verified." | stamp, auto-advance |
| Player card | live player card (real name/@/photo) | That's me | fields, photo row, terms | KEEP (real content), flat | helper lines, step counter |
| Q1 / Q2 | the choices | Next | Skip, race preview (real answer) | KEEP preview (flat) | auto-advance |
| Level Up | avatar/initials + LEVEL N (real) | Enter the Arena | 3 reward tiles, tagline, share link | KEEP | |
| Empty Arena | ghost race (real next step) | Start a race | Join a race link | KEEP (flat) | dashed boxes |
