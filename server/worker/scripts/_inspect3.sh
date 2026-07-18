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
}

run demo_races "SELECT * FROM races WHERE id LIKE 'd0000001%' OR title LIKE '%Demo%' OR visibility = 'public_demo' LIMIT 20;"
run demo_parts "SELECT * FROM race_participants WHERE race_id LIKE 'd0000001%';"
run demo_people "SELECT * FROM people;"
run demo_moves "SELECT * FROM moves LIMIT 20;"
run profiles_all "SELECT * FROM profiles;"
run users_schema2 "PRAGMA table_info(users);"
run passes_all "SELECT * FROM member_passes;"
run race_one "SELECT * FROM races WHERE id = '254b6d3a-b9f9-4979-945e-99e70819aeac';"
run parts_one "SELECT * FROM race_participants WHERE race_id = '254b6d3a-b9f9-4979-945e-99e70819aeac';"
run proofs_one "SELECT id, race_id, user_id, proof_type, value, verification_status, note, created_at FROM proofs WHERE race_id = '254b6d3a-b9f9-4979-945e-99e70819aeac';"
run ak_races_join "SELECT r.id, r.title, r.status, r.goal_type, r.target_value, r.unit, r.proof_requirement, r.ai_activity_type, rp.progress_value, rp.progress_percent FROM races r JOIN race_participants rp ON rp.race_id = r.id WHERE rp.user_id = 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4' AND r.deleted_at IS NULL ORDER BY r.created_at DESC;"

python3 - <<'PY'
import json
base='/tmp/nuvo_inspect'
for name in ['demo_races','demo_parts','demo_people','demo_moves','profiles_all','users_schema2','passes_all','race_one','parts_one','proofs_one','ak_races_join','pcounts','all_users','proofs_schema','race_participants_schema','people_schema','members_schema','moves_schema','crew_schema','invites_schema','passes_schema']:
    try:
        d=json.load(open(f'{base}/{name}.json'))
    except Exception as e:
        print(name,'MISSING',e); continue
    print('='*20,name,'='*20)
    res=d[0]['results']
    if 'schema' in name:
        print([r['name']+':'+r['type'] for r in res])
    else:
        print(json.dumps(res, indent=2)[:7000])
    print()
PY
