/**
 * Demo Arena World — deterministic synthetic snapshot generator.
 *
 * Only called for users with demo_world_enabled = 1.
 * Normal users never see this output.
 *
 * Design principles:
 * - Deterministic within a 5-minute time bucket so quick refreshes return
 *   identical data, but the world shifts believably every 5 minutes.
 * - Pure functions, zero external dependencies.
 * - No real D1 reads or writes inside this module.
 */

// ── Types ─────────────────────────────────────────────────────────────────────

export interface ArenaMiniLeaderboardRow {
  label: string;
  value: string;
  isCurrentUser?: boolean;
  profilePhotoUrl?: string | null;
}

export interface ArenaBoard {
  id: string;
  source: 'real' | 'demo';
  title: string;
  proofLabel?: string;
  progressLabel: string;
  boardContext: string;
  primaryActionLabel: string;
  primaryActionType: 'submit_proof' | 'open_board' | 'start_race' | 'none';
  progressPercent?: number;
  racerCount?: number;
  isResult: boolean;
  badgeLabel?: string;
  miniLeaderboard?: ArenaMiniLeaderboardRow[];
}

export interface ArenaActivity {
  id: string;
  actorName: string;
  text: string;
  raceTitle?: string;
  timeLabel: string;
  type: 'proof_submitted' | 'joined' | 'leader_changed' | 'finished' | 'waiting';
}

export interface ArenaSnapshot {
  mode: 'real' | 'demo';
  headerPulse: string;
  focusBoard: ArenaBoard | null;
  liveBoards: ArenaBoard[];
  activity: ArenaActivity[];
  results: ArenaBoard[];
}

// ── Seeded PRNG (xorshift32 — no dependencies) ────────────────────────────────

function djb2Hash(s: string): number {
  let h = 5381;
  for (let i = 0; i < s.length; i++) {
    h = (((h << 5) + h) ^ s.charCodeAt(i)) >>> 0;
  }
  return h >>> 0;
}

function makeRand(seed: number): () => number {
  let s = (seed || 1) >>> 0;
  return () => {
    s ^= s << 13;
    s ^= s >> 17;
    s ^= s << 5;
    s = s >>> 0;
    return s / 4294967296;
  };
}

function shuffle<T>(arr: T[], rand: () => number): T[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

function pick<T>(arr: T[], rand: () => number): T {
  return arr[Math.floor(rand() * arr.length)];
}

function randInt(min: number, max: number, rand: () => number): number {
  return min + Math.floor(rand() * (max - min + 1));
}

// ── Demo world data ───────────────────────────────────────────────────────────

const DEMO_PEOPLE = ['Marcus', 'Jamie', 'Noah', 'Anaya', 'Maya', 'Leo'];

const DEMO_RACES = [
  { id: 'demo-jumping-jacks', title: 'Most Jumping Jacks', target: 10, unit: 'reps', badge: 'AI' },
  { id: 'demo-pushups', title: 'First to 100 Pushups', target: 100, unit: 'reps', badge: null },
  { id: 'demo-summer-fit', title: 'Summer Fit Race', target: 50, unit: 'reps', badge: null },
  { id: 'demo-study-sprint', title: 'Study Sprint', target: 20, unit: 'sessions', badge: null },
  { id: 'demo-side-project', title: 'Ship a Side Project', target: 5, unit: 'milestones', badge: null },
  { id: 'demo-no-scrolling', title: '30 Days No Scrolling', target: 30, unit: 'days', badge: null },
  { id: 'demo-touch-grass', title: 'Touch Grass 20', target: 20, unit: 'sessions', badge: null },
] as const;

const TIME_LABELS = ['just now', '2m ago', '4m ago', '8m ago', '12m ago', '25m ago', '1h ago', '2h ago'];

// ── Snapshot generation ───────────────────────────────────────────────────────

export function generateDemoSnapshot(
  userId: string,
  demoSeed: string | null,
  variant: string,
): ArenaSnapshot {
  const BUCKET_MS = 5 * 60 * 1000;
  const bucket = Math.floor(Date.now() / BUCKET_MS);
  const rawSeed = demoSeed ?? userId;
  const fullSeed = `${rawSeed}:${bucket}:${variant}`;
  const rand = makeRand(djb2Hash(fullSeed));

  // Shuffle people so leader varies per bucket.
  const people = shuffle([...DEMO_PEOPLE], rand);

  // Shuffle races to determine which appear in which slot.
  const races = shuffle([...DEMO_RACES], rand);

  // Slots: focus=0, live=1..3, results=4..5
  const focusRace = races[0];
  const liveRaces = races.slice(1, 4);
  const resultRaces = races.slice(4, 6);

  // ── Focus board ───────────────────────────────────────────────────────────

  // Assign progress to top two demo people (non-user), plus user at some value.
  const leader = people[0];
  const second = people[1];
  const leaderVal = randInt(Math.ceil(focusRace.target * 0.5), focusRace.target - 1, rand);
  const secondVal = randInt(Math.ceil(focusRace.target * 0.2), leaderVal - 1, rand);
  const userVal = 0; // user starts at the bottom — most motivating

  const miniLeaderboard: ArenaMiniLeaderboardRow[] = [
    { label: leader, value: `${leaderVal} / ${focusRace.target}` },
    { label: second, value: `${secondVal} / ${focusRace.target}` },
    { label: 'You', value: `${userVal} / ${focusRace.target}`, isCurrentUser: true },
  ];

  const aheadBy = leaderVal - userVal;
  const focusBoard: ArenaBoard = {
    id: focusRace.id,
    source: 'demo',
    title: focusRace.title,
    proofLabel: focusRace.badge === 'AI' ? 'AI Motion' : 'Manual',
    progressLabel: `You ${userVal} / ${focusRace.target}`,
    boardContext: `${leader} is ${aheadBy} ${focusRace.unit} ahead`,
    primaryActionLabel: 'Submit proof',
    primaryActionType: 'submit_proof',
    progressPercent: 0,
    racerCount: 3,
    isResult: false,
    badgeLabel: focusRace.badge ?? undefined,
    miniLeaderboard,
  };

  // ── Live boards ───────────────────────────────────────────────────────────

  const liveBoards: ArenaBoard[] = liveRaces.map((race) => {
    const personA = pick(people.slice(0, 4), rand);
    const val = randInt(1, race.target - 1, rand);
    const pct = Math.round((val / race.target) * 100);
    const racer2 = pick(people.filter((p) => p !== personA), rand);
    const isSolo = rand() < 0.2;
    const racerCount = isSolo ? 1 : 2;
    const subtitle =
      racerCount === 1
        ? `Solo · ${val} / ${race.target} ${race.unit}`
        : `${val} / ${race.target} ${race.unit} · ${racerCount} racers`;

    return {
      id: race.id,
      source: 'demo' as const,
      title: race.title,
      progressLabel: subtitle,
      boardContext: isSolo
        ? 'Add crew to make it a race'
        : `${personA} and ${racer2} racing`,
      primaryActionLabel: 'Submit proof',
      primaryActionType: 'submit_proof' as const,
      progressPercent: pct,
      racerCount,
      isResult: false,
      badgeLabel: race.badge ?? undefined,
    };
  });

  // ── Results ───────────────────────────────────────────────────────────────

  const results: ArenaBoard[] = resultRaces.map((race) => {
    const winner = pick(people.slice(0, 3), rand);
    const n = randInt(2, 4, rand);
    return {
      id: race.id,
      source: 'demo' as const,
      title: race.title,
      progressLabel: `${winner} finished first`,
      boardContext: `${n} racers · race over`,
      primaryActionLabel: 'Open board',
      primaryActionType: 'open_board' as const,
      progressPercent: 100,
      racerCount: n,
      isResult: true,
    };
  });

  // ── Activity ──────────────────────────────────────────────────────────────

  const allLiveRaces = [focusRace, ...liveRaces];
  const activityCount = randInt(2, 4, rand);
  const timeLabelPool = shuffle([...TIME_LABELS], rand);

  const activity: ArenaActivity[] = Array.from({ length: activityCount }, (_, i) => {
    const actor = pick(people.slice(0, 4), rand);
    const race = pick(allLiveRaces, rand);
    const typeRoll = rand();
    const type =
      typeRoll < 0.6
        ? ('proof_submitted' as const)
        : typeRoll < 0.8
          ? ('joined' as const)
          : ('leader_changed' as const);
    const text =
      type === 'proof_submitted'
        ? 'submitted proof'
        : type === 'joined'
          ? 'joined the board'
          : 'moved to the lead';

    return {
      id: `demo-activity-${i + 1}`,
      actorName: actor,
      text,
      raceTitle: race.title,
      timeLabel: timeLabelPool[i % timeLabelPool.length],
      type,
    };
  });

  // ── Header pulse ──────────────────────────────────────────────────────────

  const pulseOptions = [
    `${leader} is ahead on ${randInt(1, 2, rand)} board${rand() < 0.5 ? 's' : ''}`,
    `You can take the lead on ${liveBoards.length + 1} board${liveBoards.length > 0 ? 's' : ''}`,
    `${randInt(2, 4, rand)} crews are racing right now`,
    `${second} just moved on ${pick(allLiveRaces, rand).title}`,
  ];
  const headerPulse = pick(pulseOptions, rand);

  return {
    mode: 'demo',
    headerPulse,
    focusBoard,
    liveBoards,
    activity,
    results,
  };
}
