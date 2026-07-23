export async function hasAcceptedTerms(db: D1Database, userId: string): Promise<boolean> {
  const user = await db
    .prepare('SELECT terms_accepted_at FROM users WHERE id = ?')
    .bind(userId)
    .first<{ terms_accepted_at: string | null }>();
  return Boolean(user?.terms_accepted_at);
}
