import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireAuth } from '../lib/jwt';
import { generateDemoSnapshot } from '../lib/demoArenaWorld';
import type { ArenaBoard, ArenaSnapshot, ArenaMiniLeaderboardRow } from '../lib/demoArenaWorld';

export const arenaRouter = new Hono<AppEnv>();

arenaRouter.use('*', requireAuth);

// ── Result detection (mirrors Flutter-side _isResult logic) ──────────────────

const RESULT_STATUSES = new Set([
  'completed',
  'complete',
  'finished',
  'archived',
  'cancelled',
]);

interface LightRaceRow {
  id: string;
  title: string;
  status: string;
  target_value: number | null;
  unit: string | null;
  proof_requirement: string;
  proof_mode: string | null;
  ai_activity_type: string | null;
  creator_id: string;
}

interface LightParticipantRow {
  race_id: string;
  user_id: string;
  display_name: string | null;
  progress_value: number;
  progress_percent: number;
}

function isResultRace(race: LightRaceRow, myProgress: number): boolean {
  if (RESULT_STATUSES.has(race.status)) return true;
  if (myProgress >= 100) return true;
  return false;
}

function buildBadge(race: LightRaceRow): string | undefined {
  if (race.proof_requirement === 'ai_check' || race.proof_mode === 'ai_check') return 'AI';
  return undefined;
}

function buildProgressLabel(
  race: LightRaceRow,
  myParticipant: LightParticipantRow | undefined,
  participantCount: number,
): string {
  if (!myParticipant) {
    return `${participantCount} ${participantCount === 1 ? 'racer' : 'racers'} on the board`;
  }
  const { progress_value: val, progress_percent: pct } = myParticipant;
  if (race.target_value) {
    return `${val} / ${race.target_value} ${race.unit ?? 'reps'}`;
  }
  if (pct > 0) return `${pct}% to the finish line`;
  return 'Submit your first proof';
}

function buildRowSubtitle(
  race: LightRaceRow,
  myParticipant: LightParticipantRow | undefined,
  participantCount: number,
): string {
  const racerLabel = `${participantCount} ${participantCount === 1 ? 'racer' : 'racers'}`;
  if (myParticipant && race.target_value) {
    return `${myParticipant.progress_value} / ${race.target_value} ${race.unit ?? 'reps'} · ${racerLabel}`;
  }
  if (myParticipant && myParticipant.progress_percent > 0) {
    return `${myParticipant.progress_percent}% to the finish line · ${racerLabel}`;
  }
  if (myParticipant && participantCount === 1) {
    return 'Solo · add crew from the race room';
  }
  if (myParticipant) {
    return `Submit your first proof · ${racerLabel}`;
  }
  return `${racerLabel} on the board`;
}

// ── GET /arena ────────────────────────────────────────────────────────────────

arenaRouter.get('/', async (c) => {
  const userId = c.get('userId');
  const db = c.env.DB;

  // Read demo flags (added in migration 0006 — columns may not exist on older DBs).
  let demoEnabled = false;
  let demoSeed: string | null = null;
  let demoVariant = 'summer_v1';

  try {
    const userRow = await db
      .prepare(
        'SELECT demo_world_enabled, demo_world_seed, demo_world_variant FROM users WHERE id = ?',
      )
      .bind(userId)
      .first<{ demo_world_enabled: number; demo_world_seed: string | null; demo_world_variant: string | null }>();

    if (!userRow) {
      return c.json({ ok: false, error: 'User not found' }, 404);
    }
    demoEnabled = Boolean(userRow.demo_world_enabled);
    demoSeed = userRow.demo_world_seed;
    demoVariant = userRow.demo_world_variant ?? 'summer_v1';
  } catch {
    // Migration 0006 not yet applied — verify user exists then fall through to real mode.
    const exists = await db
      .prepare('SELECT id FROM users WHERE id = ?')
      .bind(userId)
      .first<{ id: string }>();
    if (!exists) return c.json({ ok: false, error: 'User not found' }, 404);
  }

  // ── Demo mode ─────────────────────────────────────────────────────────────

  if (demoEnabled) {
    const snapshot = generateDemoSnapshot(userId, demoSeed, demoVariant);
    return c.json({ ok: true, snapshot });
  }

  // ── Real mode ─────────────────────────────────────────────────────────────

  const snapshot = await buildRealSnapshot(db, userId);
  return c.json({ ok: true, snapshot });
});

async function buildRealSnapshot(db: D1Database, userId: string): Promise<ArenaSnapshot> {
  // Fetch races this user created or joined (same criteria as GET /races).
  const raceRows = await db
    .prepare(
      `SELECT DISTINCT r.id, r.title, r.status, r.target_value, r.unit,
              r.proof_requirement, r.proof_mode, r.ai_activity_type, r.creator_id
       FROM races r
       LEFT JOIN race_participants rp ON rp.race_id = r.id AND rp.user_id = ?
       WHERE r.deleted_at IS NULL AND (r.creator_id = ? OR rp.user_id IS NOT NULL)
       ORDER BY r.created_at DESC`,
    )
    .bind(userId, userId)
    .all<LightRaceRow>();

  const races = raceRows.results;
  if (races.length === 0) {
    return {
      mode: 'real',
      headerPulse: 'Start a race with your crew',
      focusBoard: null,
      liveBoards: [],
      activity: [],
      results: [],
    };
  }

  // Fetch all participant rows for these races in one query.
  const raceIds = races.map((r) => r.id);
  const placeholders = raceIds.map(() => '?').join(', ');
  const participantRows = await db
    .prepare(
      `SELECT rp.race_id, rp.user_id,
              COALESCE(rp.display_name, p.full_name, 'Unknown') as display_name,
              rp.progress_value, rp.progress_percent
       FROM race_participants rp
       LEFT JOIN profiles p ON p.user_id = rp.user_id
       WHERE rp.race_id IN (${placeholders})
       ORDER BY rp.progress_percent DESC, rp.progress_value DESC, rp.joined_at ASC`,
    )
    .bind(...raceIds)
    .all<LightParticipantRow>();

  // Index participants by race_id.
  const participantsByRace = new Map<string, LightParticipantRow[]>();
  for (const p of participantRows.results) {
    const list = participantsByRace.get(p.race_id) ?? [];
    list.push(p);
    participantsByRace.set(p.race_id, list);
  }

  // Bucket races into live and result.
  const live: LightRaceRow[] = [];
  const resultRaces: LightRaceRow[] = [];

  for (const race of races) {
    const myP = (participantsByRace.get(race.id) ?? []).find((p) => p.user_id === userId);
    const myPct = myP?.progress_percent ?? 0;
    if (isResultRace(race, myPct)) {
      resultRaces.push(race);
    } else {
      live.push(race);
    }
  }

  // Select focus board.
  const focusRace = selectFocusBoard(live, resultRaces, userId, participantsByRace);
  const focusIsResult = focusRace ? resultRaces.includes(focusRace) : false;
  const otherLive = live.filter((r) => r.id !== focusRace?.id);

  // Build boards.
  const focusBoard = focusRace
    ? buildRealBoard(focusRace, userId, participantsByRace, focusIsResult, true)
    : null;

  const liveBoards = otherLive
    .slice(0, 5)
    .map((r) => buildRealBoard(r, userId, participantsByRace, false, false));

  const results = resultRaces
    .slice(0, 3)
    .map((r) => buildRealBoard(r, userId, participantsByRace, true, false));

  // Header pulse.
  let headerPulse: string;
  if (live.length > 0) {
    const n = live.length;
    headerPulse = `${n} ${n === 1 ? 'board needs' : 'boards need'} proof`;
  } else if (resultRaces.length > 0) {
    headerPulse = 'Results are in';
  } else {
    headerPulse = 'Start a race with your crew';
  }

  return {
    mode: 'real',
    headerPulse,
    focusBoard,
    liveBoards,
    activity: [],
    results,
  };
}

function selectFocusBoard(
  live: LightRaceRow[],
  results: LightRaceRow[],
  userId: string,
  participantsByRace: Map<string, LightParticipantRow[]>,
): LightRaceRow | null {
  // Priority 1: live race I'm in with progress < 100%.
  for (const race of live) {
    const myP = (participantsByRace.get(race.id) ?? []).find((p) => p.user_id === userId);
    if (!myP) continue;
    if (myP.progress_percent < 100) return race;
  }
  // Priority 2: any live race I'm in.
  for (const race of live) {
    const myP = (participantsByRace.get(race.id) ?? []).find((p) => p.user_id === userId);
    if (myP) return race;
  }
  // Priority 3: any live race.
  if (live.length > 0) return live[0];
  // Priority 4: most recent result.
  if (results.length > 0) return results[0];
  return null;
}

function buildRealBoard(
  race: LightRaceRow,
  userId: string,
  participantsByRace: Map<string, LightParticipantRow[]>,
  forceResult: boolean,
  includeMiniLeaderboard: boolean,
): ArenaBoard {
  const participants = participantsByRace.get(race.id) ?? [];
  const myP = participants.find((p) => p.user_id === userId);
  const myPct = myP?.progress_percent ?? 0;
  const count = participants.length;
  const isResult = forceResult || isResultRace(race, myPct);

  const progressLabel = isResult
    ? 'Finished'
    : buildProgressLabel(race, myP, count);

  const rowSubtitle = buildRowSubtitle(race, myP, count);

  const isSolo = count === 1 && myP !== undefined;
  let boardContext: string;
  if (isResult) {
    boardContext = `${count} ${count === 1 ? 'racer' : 'racers'} finished`;
  } else if (isSolo) {
    boardContext = 'Solo · add crew from the race room';
  } else {
    boardContext = `${count} ${count === 1 ? 'racer' : 'racers'} on the board`;
  }

  const primaryActionType = isResult ? 'open_board' : 'submit_proof';
  const primaryActionLabel = isResult ? 'Open board' : 'Submit proof';

  let miniLeaderboard: ArenaMiniLeaderboardRow[] | undefined;
  if (includeMiniLeaderboard && participants.length > 0) {
    miniLeaderboard = participants.slice(0, 5).map((p) => ({
      label: p.user_id === userId ? 'You' : (p.display_name ?? 'Racer'),
      value: race.target_value
        ? `${p.progress_value} / ${race.target_value}`
        : `${p.progress_percent}%`,
      isCurrentUser: p.user_id === userId,
    }));
  }

  return {
    id: race.id,
    source: 'real',
    title: race.title,
    proofLabel: rowSubtitle,
    progressLabel,
    boardContext,
    primaryActionLabel,
    primaryActionType,
    progressPercent: myPct,
    racerCount: count,
    isResult,
    badgeLabel: buildBadge(race),
    miniLeaderboard,
  };
}
