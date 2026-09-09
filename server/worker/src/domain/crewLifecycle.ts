/**
 * Pure crew-connection lifecycle helpers. The route code (routes/crew.ts,
 * routes/users.ts) does the D1 I/O; the state logic lives here so it is
 * unit-tested and identical across every entry point (search, profile card,
 * invite accept — see docs/agents/19-social-platform-contract.md §8).
 *
 *   none              no row, or a removed/declined row
 *   connected         both directional rows are 'active' (or self)
 *   pending_outgoing  a 'pending' row this viewer created
 *   pending_incoming  a 'pending' row the other person created
 */
export type CrewConnectionStatus =
  | 'none'
  | 'connected'
  | 'pending_outgoing'
  | 'pending_incoming';

export function crewConnectionStatus(
  viewerId: string,
  targetId: string,
  row: { status: string; requested_by: string | null } | null | undefined,
): CrewConnectionStatus {
  if (viewerId === targetId) return 'connected';
  if (!row) return 'none';
  if (row.status === 'active') return 'connected';
  if (row.status === 'pending') {
    return row.requested_by === viewerId ? 'pending_outgoing' : 'pending_incoming';
  }
  return 'none'; // removed | declined
}

/** Whether the viewer may see the target's real name + photo. */
export function canSeeIdentity(
  viewerId: string,
  targetId: string,
  targetPrivate: boolean,
  status: CrewConnectionStatus,
): boolean {
  if (viewerId === targetId) return true;
  if (status === 'connected') return true;
  return !targetPrivate;
}

/**
 * The connection status to write when someone connects. Public target → an
 * immediate mutual 'active'; private target → a 'pending' request they accept.
 */
export function connectResult(targetPrivate: boolean): {
  mine: 'active' | 'pending';
  theirs: 'active' | 'pending';
  outcome: 'active' | 'pending';
} {
  return targetPrivate
    ? { mine: 'pending', theirs: 'pending', outcome: 'pending' }
    : { mine: 'active', theirs: 'active', outcome: 'active' };
}
