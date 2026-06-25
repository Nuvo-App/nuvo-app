-- V2 person links for social graph and race invites.
-- Legacy user_id columns stay in place for compatibility.

ALTER TABLE crew_connections ADD COLUMN person_id TEXT;
ALTER TABLE crew_connections ADD COLUMN crew_person_id TEXT;

UPDATE crew_connections
SET
  person_id = COALESCE(person_id, (SELECT id FROM people WHERE people.user_id = crew_connections.user_id)),
  crew_person_id = COALESCE(crew_person_id, (SELECT id FROM people WHERE people.user_id = crew_connections.crew_user_id));

CREATE INDEX IF NOT EXISTS idx_crew_connections_person ON crew_connections(person_id, status);
CREATE INDEX IF NOT EXISTS idx_crew_connections_crew_person ON crew_connections(crew_person_id, status);

ALTER TABLE race_invites ADD COLUMN created_by_person_id TEXT;

UPDATE race_invites
SET created_by_person_id = COALESCE(
  created_by_person_id,
  (SELECT id FROM people WHERE people.user_id = race_invites.created_by)
);

CREATE INDEX IF NOT EXISTS idx_race_invites_created_by_person ON race_invites(created_by_person_id);
