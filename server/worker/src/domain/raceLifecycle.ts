export type StoredRaceStatus = 'draft' | 'scheduled' | 'active' | 'completed' | 'cancelled' | 'archived';

export function effectiveRaceStatus(status: string, startsAt: string | null, endsAt: string | null, now = new Date()): StoredRaceStatus {
  if (status === 'completed' || status === 'cancelled' || status === 'archived' || status === 'draft') {
    return status as StoredRaceStatus;
  }
  if (startsAt && new Date(startsAt).getTime() > now.getTime()) return 'scheduled';
  if (endsAt && new Date(endsAt).getTime() <= now.getTime()) return 'completed';
  return 'active';
}
