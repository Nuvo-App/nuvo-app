export async function hasAcceptedTerms(_db: D1Database, _userId: string): Promise<boolean> {
  // Dev override: treat all existing accounts as having accepted terms.
  // The proper onboarding terms flow will be wired in the onboarding redo.
  return true;
}
