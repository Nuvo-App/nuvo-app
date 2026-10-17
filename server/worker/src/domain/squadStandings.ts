/**
 * Crew standings across every race linked to a squad.
 *
 * Each race awards placement points to the squad members who raced in it
 * (ranked with the same tie-aware rules as a race leaderboard); the squad table
 * is the sum. Pure — the route loads rows, this ranks them.
 */
import { computeCompetitionRanks, type RankableScore } from './raceRanking';

export interface SquadRaceInput {
  raceId: string;
  direction: 'higher' | 'lower';
  /** Squad members only. progress_value 0 means they have not logged proof. */
  scores: RankableScore[];
}

export interface SquadStanding {
  user_id: string;
  rank: number;
  points: number;
  wins: number;
  races: number;
}

const PLACE_POINTS = [5, 3, 2];
const PARTICIPATION_POINT = 1;

export function placementPoints(rank: number): number {
  return PLACE_POINTS[rank - 1] ?? PARTICIPATION_POINT;
}

export function computeSquadStandings(
  memberIds: string[],
  races: SquadRaceInput[],
): SquadStanding[] {
  const totals = new Map<string, Omit<SquadStanding, 'rank'>>();
  for (const id of memberIds) {
    totals.set(id, { user_id: id, points: 0, wins: 0, races: 0 });
  }

  for (const race of races) {
    const ranked = computeCompetitionRanks(race.scores, {
      direction: race.direction === 'lower' ? 'asc' : 'desc',
    });
    for (const row of ranked) {
      const total = totals.get(row.user_id);
      // No proof logged yet — in the race, but not on the board.
      if (!total || row.progress_value <= 0) continue;
      total.points += placementPoints(row.rank);
      total.races += 1;
      if (row.rank === 1) total.wins += 1;
    }
  }

  const sorted = [...totals.values()].sort(
    (a, b) => b.points - a.points || b.wins - a.wins || a.user_id.localeCompare(b.user_id),
  );
  let lastKey: string | null = null;
  let currentRank = 0;
  return sorted.map((row, index) => {
    const key = `${row.points}:${row.wins}`;
    if (key !== lastKey) {
      currentRank = index + 1;
      lastKey = key;
    }
    return { ...row, rank: currentRank };
  });
}
