#!/bin/bash
set -euo pipefail
export CLOUDFLARE_ACCOUNT_ID=d618e374fb4ffb44dbc770dd07431f79
OUT=/tmp/nuvo_inspect
mkdir -p "$OUT"
cd "$(dirname "$0")/.."

run() {
  local name="$1"
  local sql="$2"
  echo "Running $name..."
  npx wrangler d1 execute nuvo_db --remote --json --command "$sql" > "$OUT/$name.json" 2>"$OUT/$name.err" || {
    echo "FAILED $name"
    cat "$OUT/$name.err"
    return 1
  }
  echo "OK $name ($(wc -c < "$OUT/$name.json") bytes)"
}

run tables "SELECT name FROM sqlite_master WHERE type='table' ORDER BY 1;"
run race_participants_schema "PRAGMA table_info(race_participants);"
run proofs_schema "PRAGMA table_info(proofs);"
run profiles_schema "PRAGMA table_info(profiles);"
run users_schema "PRAGMA table_info(users);"
run crew_schema "PRAGMA table_info(crew_connections);"
run invites_schema "PRAGMA table_info(race_invites);"
run passes_schema "PRAGMA table_info(member_passes);"
run members_schema "PRAGMA table_info(race_members);"
run moves_schema "PRAGMA table_info(moves);"
run people_schema "PRAGMA table_info(people);"
run races "SELECT id, creator_id, title, status, goal_type, target_value, unit, target_unit, proof_requirement, visibility, ai_activity_type, start_line_at, finish_line_at FROM races WHERE deleted_at IS NULL ORDER BY created_at DESC LIMIT 30;"
run users "SELECT u.id, u.primary_email, p.full_name, p.username FROM users u LEFT JOIN profiles p ON p.user_id = u.id LIMIT 50;"
run ak_part "SELECT * FROM race_participants WHERE user_id = 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4' LIMIT 30;"
run counts "SELECT (SELECT COUNT(*) FROM users) AS users, (SELECT COUNT(*) FROM races) AS races, (SELECT COUNT(*) FROM race_participants) AS participants, (SELECT COUNT(*) FROM proofs) AS proofs;"
run sample_part "SELECT * FROM race_participants LIMIT 10;"
run sample_proof "SELECT * FROM proofs LIMIT 10;"
run members_sql "SELECT sql FROM sqlite_master WHERE name = 'race_members';"
run moves_sql "SELECT sql FROM sqlite_master WHERE name IN ('moves','people','media_assets','race_members');"

echo "DONE. Files in $OUT"
ls -la "$OUT"
