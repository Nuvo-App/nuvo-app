#!/bin/bash
set -euo pipefail
export CLOUDFLARE_ACCOUNT_ID=d618e374fb4ffb44dbc770dd07431f79
OUT=/tmp/nuvo_inspect
cd "$(dirname "$0")/.."

run() {
  local name="$1"
  local sql="$2"
  echo "Running $name..."
  npx wrangler d1 execute nuvo_db --remote --json --command "$sql" > "$OUT/$name.json" 2>"$OUT/$name.err" || {
    echo "FAILED $name"; cat "$OUT/$name.err"; return 1;
  }
  echo "OK $name"
}

run people "SELECT id, person_key, user_id, display_name, username, is_demo, status FROM people LIMIT 80;"
run pcounts "SELECT (SELECT COUNT(*) FROM people) AS people, (SELECT COUNT(*) FROM race_members) AS race_members, (SELECT COUNT(*) FROM moves) AS moves, (SELECT COUNT(*) FROM crew_connections) AS crew;"
run rm_rows "SELECT rm.race_id, rm.person_id, rm.member_role, rm.member_status, rm.score_value, rm.score_percent, p.display_name, p.user_id FROM race_members rm JOIN people p ON p.id = rm.person_id LIMIT 40;"
run crew "SELECT * FROM crew_connections LIMIT 40;"
run ak_person "SELECT * FROM people WHERE user_id = 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4' OR lower(display_name) LIKE '%akshay%' OR lower(username) LIKE '%akshay%';"
run all_users "SELECT u.id, u.primary_email, u.status, p.full_name, p.username, p.onboarding_complete FROM users u LEFT JOIN profiles p ON p.user_id = u.id;"
run part_per_race "SELECT race_id, COUNT(*) c FROM race_participants GROUP BY race_id ORDER BY c DESC LIMIT 20;"
run races_full "SELECT id, creator_id, title, status, goal_type, target_value, unit, target_unit, proof_requirement, visibility, ai_activity_type, start_line_at, finish_line_at, created_at FROM races WHERE deleted_at IS NULL ORDER BY created_at DESC;"

python3 - <<'PY'
import json
base='/tmp/nuvo_inspect'
for name in ['pcounts','people','ak_person','all_users','crew','rm_rows','part_per_race','races_full','counts','race_participants_schema','proofs_schema','profiles_schema','crew_schema']:
    path=f'{base}/{name}.json'
    try:
        d=json.load(open(path))
    except Exception as e:
        print(name, 'missing', e); continue
    print('='*20, name, '='*20)
    res = d if name=='pcounts' else d[0]['results']
    if name.endswith('_schema'):
        print([r['name'] for r in d[0]['results']])
    else:
        print(json.dumps(res if name!='pcounts' else d[0]['results'] if isinstance(d,list) else d, indent=2)[:6000])
    print()
PY
