#!/bin/bash
set -euo pipefail
export CLOUDFLARE_ACCOUNT_ID=d618e374fb4ffb44dbc770dd07431f79
OUT=/tmp/nuvo_inspect
cd "$(dirname "$0")/.."
run() {
  local name="$1"; local sql="$2"
  npx wrangler d1 execute nuvo_db --remote --json --command "$sql" > "$OUT/$name.json" 2>"$OUT/$name.err"
  echo OK "$name"
}
run dr2 "SELECT id, title, status, goal_type, target_value, unit, target_unit, proof_requirement, visibility, ai_activity_type, demo_priority, created_by_person_id, start_line_at, finish_line_at, race_type, proof_mode FROM races WHERE id LIKE 'd0000001%' ORDER BY id;"
run drm "SELECT rm.race_id, rm.person_id, rm.member_role, rm.score_value, rm.score_percent, rm.rank_override, rm.is_current_user_highlight, p.display_name FROM race_members rm JOIN people p ON p.id = rm.person_id WHERE rm.race_id LIKE 'd0000001%' ORDER BY rm.race_id, rm.score_value DESC;"
run drp "SELECT race_id, user_id, display_name, progress_value, progress_percent FROM race_participants WHERE race_id LIKE 'd0000001%' ORDER BY race_id, progress_value DESC;"
run dproof "SELECT id, race_id, user_id, proof_type, value, verification_status, note, created_at FROM proofs WHERE race_id LIKE 'd0000001%' LIMIT 50;"
run dmoves "SELECT id, race_id, person_id, amount_value, amount_unit, move_status, move_source, note, checked_at FROM moves WHERE race_id LIKE 'd0000001%' LIMIT 50;"
run crew_s "PRAGMA table_info(crew_connections);"
run empty_solo "SELECT r.id, r.title, r.target_value, r.unit, r.ai_activity_type, r.proof_requirement, COUNT(rp.id) AS racers FROM races r LEFT JOIN race_participants rp ON rp.race_id = r.id WHERE r.deleted_at IS NULL AND r.status = 'active' AND r.creator_id = 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4' GROUP BY r.id HAVING racers <= 1 ORDER BY r.created_at DESC LIMIT 25;"
python3 - <<'PY'
import json
base='/tmp/nuvo_inspect'
for n in ['dr2','drm','drp','dproof','dmoves','crew_s','empty_solo']:
    d=json.load(open(f'{base}/{n}.json'))
    print('====',n,'====')
    print(json.dumps(d[0]['results'], indent=2)[:8000])
    print()
PY
