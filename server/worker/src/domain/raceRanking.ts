export interface RankableScore {
  user_id: string;
  progress_value: number;
  completed_at: string | null;
  joined_at: string;
}

export interface RankedScore extends RankableScore {
  rank: number;
}

export interface RankOptions {
  /**
   * 'desc' — most/best wins (default, all cumulative formats).
   * 'asc'  — fastest/lowest wins (timed-effort metrics where the score is a
   *          duration: lowest value takes rank 1).
   */
  direction?: 'asc' | 'desc';
}

export function computeCompetitionRanks(rows: RankableScore[], options: RankOptions = {}): RankedScore[] {
  const asc = options.direction === 'asc';
  // In 'asc' (lowest wins) a zero score means "no attempt yet" — it must
  // rank below every recorded score, never as the leader.
  const key = (row: RankableScore) =>
    asc && row.progress_value <= 0 ? Number.MAX_SAFE_INTEGER : row.progress_value;
  const sorted = [...rows].sort((a, b) => {
    const ka = key(a);
    const kb = key(b);
    if (ka !== kb) return asc ? ka - kb : kb - ka;
    const aCompleted = a.completed_at ?? '9999-12-31T23:59:59.999Z';
    const bCompleted = b.completed_at ?? '9999-12-31T23:59:59.999Z';
    if (aCompleted !== bCompleted) return aCompleted < bCompleted ? -1 : 1;
    return a.joined_at < b.joined_at ? -1 : a.joined_at > b.joined_at ? 1 : 0;
  });

  let lastScore: number | null = null;
  let currentRank = 0;
  return sorted.map((row, index) => {
    const k = key(row);
    if (lastScore === null || k !== lastScore) {
      currentRank = index + 1;
      lastScore = k;
    }
    return { ...row, rank: currentRank };
  });
}
