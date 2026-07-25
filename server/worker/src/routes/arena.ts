import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireAuth } from '../lib/jwt';
import type { ArenaBoard, ArenaSnapshot, ArenaMiniLeaderboardRow } from '../lib/demoArenaWorld';
import { activityForId, normalizeMetric } from '../domain/raceActivities';
import { effectiveRaceStatus } from '../domain/raceLifecycle';

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
  target_unit: string | null;
  metric: string | null;
  activity_id: string | null;
  format: string | null;
  verification_type: string;
  verification_method: string | null;
  movement_type: string | null;
  creator_id: string;
  start_at: string | null;
  end_at: string | null;
}

interface LightParticipantRow {
  race_id: string;
  user_id: string;
  display_name: string | null;
  profile_photo_url: string | null;
  progress_value: number;
  progress_percent: number;
  rank_cache: number | null;
}

function raceEffectiveStatus(race: LightRaceRow): string {
  return effectiveRaceStatus(race.status, race.start_at, race.end_at);
}

function isResultRace(race: LightRaceRow): boolean {
  return RESULT_STATUSES.has(raceEffectiveStatus(race));
}

function buildBadge(race: LightRaceRow): string | undefined {
  if ((race.verification_method ?? race.verification_type) === 'camera_pose') return 'AI';
  return undefined;
}

function metricLabel(race: LightRaceRow): string {
  const activity = activityForId(race.activity_id ?? race.movement_type);
  return normalizeMetric(race.metric ?? race.target_unit, activity) ?? activity?.defaultMetric ?? 'reps';
}

function progressPercent(race: LightRaceRow, participant: LightParticipantRow | undefined): number {
  if (!participant) return 0;
  if (race.target_value && race.target_value > 0) {
    return Math.min(100, Math.floor((participant.progress_value / race.target_value) * 100));
  }
  return Math.min(100, Math.max(0, participant.progress_percent));
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
    return `${val} / ${race.target_value} ${metricLabel(race)}`;
  }
  if (pct > 0) return `${val} ${metricLabel(race)}`;
  return 'Submit your first proof';
}

function buildRowSubtitle(
  race: LightRaceRow,
  myParticipant: LightParticipantRow | undefined,
  participantCount: number,
): string {
  const racerLabel = `${participantCount} ${participantCount === 1 ? 'racer' : 'racers'}`;
  if (myParticipant && race.target_value) {
    return `${myParticipant.progress_value} / ${race.target_value} ${metricLabel(race)} · ${racerLabel}`;
  }
  if (myParticipant && myParticipant.progress_percent > 0) {
    return `${myParticipant.progress_value} ${metricLabel(race)} · ${racerLabel}`;
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

  const snapshot = await buildRealSnapshot(db, userId);
  return c.json({ ok: true, snapshot });
});

async function buildRealSnapshot(db: D1Database, userId: string): Promise<ArenaSnapshot> {
  // Fetch races this user created or joined (same criteria as GET /races).
  const raceRows = await db
    .prepare(
      `SELECT DISTINCT r.id, r.title, r.status, r.target_value, r.target_unit,
              r.metric, r.activity_id, r.format, r.verification_type,
              r.verification_method, r.movement_type, r.creator_id,
              r.start_at, r.end_at
       FROM races r
       LEFT JOIN race_members rm ON rm.race_id = r.id AND rm.user_id = ? AND rm.status = 'active'
       WHERE r.deleted_at IS NULL AND (r.creator_id = ? OR rm.user_id IS NOT NULL)
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
      `SELECT rm.race_id, rm.user_id,
              COALESCE(rm.cached_display_name, p.full_name, 'Unknown') as display_name,
              COALESCE(rm.cached_avatar_url, p.avatar_url) as profile_photo_url,
              COALESCE(rp.progress_value, 0) as progress_value,
              COALESCE(rp.progress_percent, 0) as progress_percent,
              rp.rank_cache
       FROM race_members rm
       LEFT JOIN profiles p ON p.user_id = rm.user_id
       LEFT JOIN race_progress rp ON rp.race_id = rm.race_id AND rp.user_id = rm.user_id
       WHERE rm.race_id IN (${placeholders}) AND rm.status = 'active'
       ORDER BY COALESCE(rp.rank_cache, 999999) ASC, rp.progress_value DESC, rm.joined_at ASC`,
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
    if (isResultRace(race)) {
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
    if (progressPercent(race, myP) < 100) return race;
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
  const myPct = progressPercent(race, myP);
  const count = participants.length;
  const isResult = forceResult || isResultRace(race);

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
        ? `${p.progress_value} / ${race.target_value} ${metricLabel(race)}`
        : `${p.progress_value} ${metricLabel(race)}`,
      isCurrentUser: p.user_id === userId,
      profilePhotoUrl: p.profile_photo_url,
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
