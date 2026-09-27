/// Server-side Terms acceptance — the enforcement point for every UGC route.
/// Acceptance is recorded on the users row (terms_accepted_at +
/// terms_version) via POST /auth/terms; a missing timestamp means the user has
/// never accepted and UGC mutations must be refused.

/// Bump when the public Terms text changes so previously-accepted users can be
/// re-gated if product/legal decide a version match is required.
export const CURRENT_TERMS_VERSION = '2026-09-27';

export async function hasAcceptedTerms(db: D1Database, userId: string): Promise<boolean> {
  const row = await db
    .prepare('SELECT terms_accepted_at FROM users WHERE id = ?')
    .bind(userId)
    .first<{ terms_accepted_at: string | null }>();
  return Boolean(row?.terms_accepted_at);
}
