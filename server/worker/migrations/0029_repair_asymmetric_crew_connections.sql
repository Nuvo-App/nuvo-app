-- Migration 0029: repair asymmetric crew connections.
--
-- setConnection() (crew.ts) and the invite-redeem connect path (invites.ts)
-- each wrote the two directional rows of a mutual connection as two SEPARATE
-- .run() calls instead of one atomic batch. An interrupted Worker (timeout,
-- transient D1 error) between the two writes could land only one side,
-- producing a permanently asymmetric connection: person A sees B in their
-- crew, but B never sees A in theirs. The write path is now atomic (fixed in
-- the same change as this migration) — this is the one-time data repair for
-- rows already broken before that fix.
--
-- Heals by inserting the missing/inactive reciprocal row as 'active' for
-- every 'active' row that lacks an active reciprocal — matching this app's
-- own invariant (crewLifecycle.ts: "connected: both directional rows are
-- 'active'"). Excludes the known fake d0000000-* seed/demo crew ids, which
-- are legitimately one-directional placeholder data, not real connections.

INSERT INTO crew_connections (id, user_id, crew_user_id, status, requested_by, created_at, updated_at)
SELECT
  lower(hex(randomblob(16))),
  a.crew_user_id,
  a.user_id,
  'active',
  a.user_id,
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
FROM crew_connections a
LEFT JOIN crew_connections b
  ON b.user_id = a.crew_user_id AND b.crew_user_id = a.user_id
WHERE a.status = 'active'
  AND (b.id IS NULL OR b.status != 'active')
  AND a.user_id NOT LIKE 'd0000000%'
  AND a.crew_user_id NOT LIKE 'd0000000%'
ON CONFLICT(user_id, crew_user_id) DO UPDATE SET
  status = 'active',
  updated_at = CURRENT_TIMESTAMP;
