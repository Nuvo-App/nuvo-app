// Pure decision logic for binding a proof submission to its verification
// session. Kept free of I/O so every branch is unit-testable.

export type InlineSessionResult = {
  releaseId: string;
  releaseChecksum: string;
  resultValue: number;
  confidence: number | null;
  motionSessionId: string | null;
};

export type SessionAction =
  | 'ok'
  | 'complete_inline'
  | 'replay'
  | 'mismatch'
  | 'reused'
  | 'not_found';

export type DecideSessionActionInput = {
  /** null when no session row exists for this user + race. */
  sessionStatus: string | null;
  sessionResultValue: number | null;
  increment: number;
  /** Set when a move_log already references this session. */
  existingLogFound: boolean;
  existingLogClientSubmissionId: string | null;
  requestClientSubmissionId: string | null;
  inlineResult: InlineSessionResult | null;
  sessionRelease: { releaseId: string; releaseChecksum: string };
};

/** Parses the optional `sessionResult` request object. Returns null if absent or malformed. */
export function parseInlineSessionResult(raw: unknown): InlineSessionResult | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const o = raw as Record<string, unknown>;
  const releaseId = typeof o.releaseId === 'string' ? o.releaseId.trim() : '';
  const releaseChecksum = typeof o.releaseChecksum === 'string' ? o.releaseChecksum.trim() : '';
  if (!releaseId || !releaseChecksum) return null;
  if (typeof o.resultValue !== 'number' || !Number.isFinite(o.resultValue)) return null;
  const confidence = typeof o.confidence === 'number' && Number.isFinite(o.confidence)
    ? Math.max(0, Math.min(1, o.confidence))
    : null;
  const motionSessionId = typeof o.motionSessionId === 'string' && o.motionSessionId.trim()
    ? o.motionSessionId.trim()
    : null;
  return { releaseId, releaseChecksum, resultValue: o.resultValue, confidence, motionSessionId };
}

export function inlineResultIsValid(
  inline: InlineSessionResult | null,
  release: { releaseId: string; releaseChecksum: string },
  increment: number,
): boolean {
  if (!inline) return false;
  return inline.releaseId === release.releaseId &&
    inline.releaseChecksum === release.releaseChecksum &&
    Number.isInteger(inline.resultValue) &&
    inline.resultValue >= increment;
}

export function decideSessionAction(input: DecideSessionActionInput): SessionAction {
  const { sessionStatus } = input;
  if (sessionStatus === null) return 'not_found';
  if (
    (sessionStatus === 'created' || sessionStatus === 'running') &&
    inlineResultIsValid(input.inlineResult, input.sessionRelease, input.increment)
  ) {
    return 'complete_inline';
  }
  // A completed session's result is never overwritten; anything else that is
  // not a completed session covering the claim is a mismatch, as before.
  if (sessionStatus !== 'completed' || (input.sessionResultValue ?? 0) < input.increment) return 'mismatch';
  if (input.existingLogFound) {
    const same = input.requestClientSubmissionId !== null &&
      input.existingLogClientSubmissionId !== null &&
      input.existingLogClientSubmissionId === input.requestClientSubmissionId;
    return same ? 'replay' : 'reused';
  }
  return 'ok';
}
