export interface RankableScore {
  user_id: string;
  progress_value: number;
  completed_at: string | null;
  joined_at: string;
}

export interface RankedScore extends RankableScore {
  rank: number;
}

export function computeCompetitionRanks(rows: RankableScore[]): RankedScore[] {
  const sorted = [...rows].sort((a, b) => {
    if (b.progress_value !== a.progress_value) return b.progress_value - a.progress_value;
    const aCompleted = a.completed_at ?? '9999-12-31T23:59:59.999Z';
    const bCompleted = b.completed_at ?? '9999-12-31T23:59:59.999Z';
    if (aCompleted !== bCompleted) return aCompleted < bCompleted ? -1 : 1;
    return a.joined_at < b.joined_at ? -1 : a.joined_at > b.joined_at ? 1 : 0;
  });

  let lastScore: number | null = null;
  let currentRank = 0;
  return sorted.map((row, index) => {
    if (lastScore === null || row.progress_value !== lastScore) {
      currentRank = index + 1;
      lastScore = row.progress_value;
    }
    return { ...row, rank: currentRank };
  });
}
