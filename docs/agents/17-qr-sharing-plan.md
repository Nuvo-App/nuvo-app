# Nuvo QR Codes & Sharing — Product + Technical Plan

> **SUPERSEDED by [19-social-platform-contract.md](19-social-platform-contract.md).** Kept for design rationale only; where it disagrees with doc 19, doc 19 wins.

Status: **SUPERSEDED by [19-social-platform-contract.md](19-social-platform-contract.md)** — kept for design rationale. Original note: PLAN ONLY. Reviewed with
[15-crew-system-plan.md](15-crew-system-plan.md) and
[16-notification-system-plan.md](16-notification-system-plan.md).

**One invite model for everything.** A race invite, a crew invite, and (later)
a squad invite are the same signed-token universal link, rendered as a QR when
useful. Do not build three formats.

---

## 0. What exists today

- `race_invites(race_id, invite_code, status)` + `POST /races/:id/invite-code`
  + `POST /races/join-code` (client `joinRaceByCode`). Plain short code, no
  expiry, no signature.
- `member_passes(member_id)` — a stable public handle per user.
- No deep-link / universal-link handling in the app yet (`go_router` routes are
  in-app only).

---

## 1. Link format (universal + signed)

```
https://get.nuvo.app/j/<token>
```

- Host `get.nuvo.app` serves an **AASA** (`/.well-known/apple-app-site-assoc`)
  and Android `assetlinks.json` so a tap opens the app; a fallback web page for
  users without the app ("Get Nuvo to join").
- `<token>` is a compact **signed** payload (HMAC with a Worker secret,
  base64url), NOT a guessable id:

```
{ v:1, k:"race"|"crew"|"squad", id:"<entityId>", by:"<inviterUserId>",
  exp:<unix|null>, nonce:"<8b>" }
```

- `k` = kind. `exp` optional (race invites can be open-ended; crew invites
  expire in 7 days; one-time invites carry a `once:true` and are burned on
  first use).
- Signature covers the whole payload → tokens are unforgeable and
  tamper-evident. Rotating the secret invalidates all outstanding links
  (acceptable; regenerate from the entity).

Short code (`race_invites.invite_code`) stays as a **human-typable** alias that
resolves to the same thing server-side — keep both.

---

## 2. Endpoints

| Route | |
|---|---|
| `POST /invites` `{ kind, entityId, expiresIn?, once? }` | mint a token (auth: must be able to invite to that entity) → `{ token, url, code? }` |
| `GET /invites/:token` | **preview** — returns a safe, minimal card for the entity **without joining**: race title / goal / racer count / creator name (anonymized per `resolveRaceMemberVisibility`), or crew inviter's public identity. Works **logged-out** (returns `{ requiresAuth:true, preview }`). |
| `POST /invites/:token/accept` | join the race / connect crew. Auth required — a logged-out tap stashes the token, routes through sign-in, then auto-accepts. Idempotent. Burns a `once` token. |

Invalid / expired / burned token → `410` with a friendly `reason`
(`expired` / `used` / `revoked` / `malformed`). Blocked-by relationship on a
crew token → `403` `blocked`, generic copy.

---

## 3. QR flows

### 3.1 Scanner (one screen, `QrScanScreen`)

Entry points: Pass screen "Find people", composer "Invite racers" → "Scan",
Arena/Compete "+" menu. Camera permission requested **here**, in context, with
a clear reason; denied → a "paste a link" fallback field.

```
open scanner
  → decode → is it a get.nuvo.app/j/<token> ? (reject anything else silently)
    → GET /invites/:token  (preview)
      → show the preview sheet (race card / person card)
        → Join / Connect  → POST /invites/:token/accept
          → on success: go_router to /race/:id  or  /profile/:userId
```

Never auto-join on scan — always preview + explicit confirm.

### 3.2 Race QR

- Race detail → Share → a QR (the mint from §2) + native share sheet (the
  `url`) + the typable code. QR encodes the universal link.
- Scanning → race preview → Join. Private race: the token itself is the
  authorization (no separate approval).

### 3.3 Profile / person QR

- Every user's Pass card shows their **personal QR** = a `crew` token for their
  own id, `exp:null`, reusable (it's just "connect with me"). Equivalent to
  handing out your member ID.
- Scanning someone's QR → profile preview (name/photo if public, `@handle` if
  private) → **Connect** (public → active, private → request; see
  [15](15-crew-system-plan.md) §1.1).

### 3.4 Squad QR *(later)* — join the squad, same token with `k:"squad"`.

---

## 4. Deep links & cold start (shared with push, §16)

- `go_router` gets a top-level redirect: an incoming `https://get.nuvo.app/j/*`
  (or `nuvo://…`) → `/invite/:token`.
- `/invite/:token` screen: fetch preview → render → accept. If unauthenticated,
  stash `pendingInviteToken` (secure storage), send through the auth gate,
  then on `AuthStatus.authenticated` consume it once.
- Push-notification deep links reuse this router redirect + stash mechanism.
- App-not-installed: the universal link's web fallback page has App Store /
  Play buttons and shows the same preview card.

---

## 5. Rendering QR

- `qr_flutter` (pure Dart, no native dep, on the CDN-free allowlist concerns
  don't apply — it's an app dep). Nuvo-styled: rounded modules, logo in the
  centre, brand-navy on white, quiet-zone respected.
- Always pair a QR with the shareable **link** and (for races) the **typable
  code** — QR is a convenience, never the only path.

---

## 6. Abuse & security

- Tokens are signed → not enumerable / not forgeable.
- `once` + expiry for sensitive invites; open reusable tokens only for "connect
  with me" and open races.
- Preview endpoint returns the **minimum** and honours privacy/blocking — a
  scraped token reveals no more than opening the app would.
- Rate-limit `POST /invites` (10/user/hour) and `/accept` (20/user/hour).
- Revoke: `DELETE /invites/:token` (creator) → future taps `410 revoked`.
  Regenerating a race's invite revokes the previous one.
- Logged-out preview is read-only and rate-limited by IP.

---

## 7. Build order

1. `get.nuvo.app` host + AASA / assetlinks + web fallback page.
2. Signed-token mint/verify lib in the Worker; `POST /invites`,
   `GET /invites/:token`, `POST /invites/:token/accept` (races first).
3. `go_router` universal-link redirect + `/invite/:token` screen + cold-start
   stash.
4. Race Share sheet + QR render.
5. `QrScanScreen` + camera permission + preview sheet.
6. Personal / crew QR on the Pass card + connect flow.
7. Squad tokens when Squads exist.

---

## 8. Cross-references

- Crew connect semantics (public vs private, blocking):
  [15-crew-system-plan.md](15-crew-system-plan.md) §1.
- Deep-link router redirect + cold-start stash is the same code path push
  notifications use: [16-notification-system-plan.md](16-notification-system-plan.md) §4.
- Preview anonymization: `resolveRaceMemberVisibility` in
  `server/worker/src/lib/privacy.ts`.
