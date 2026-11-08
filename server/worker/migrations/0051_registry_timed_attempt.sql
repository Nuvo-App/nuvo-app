-- Migration 0051 (race S7, gap 10): registry rep movements offer Timed battles.
--
-- Every preset row ships all four race formats, but registry-published rep
-- movements (remote releases, the hidden custom seed) only offered
-- first_to_goal / most_in_window / best_attempt — so registryConfigFromBody
-- refused a timed_attempt create even though the engines and the app fully
-- support the mode. This appends "timed_attempt" to every rep-measured
-- registry row that lacks it.
--
-- Idempotent: the NOT EXISTS guard makes a second run a no-op. Deliberately
-- excluded: duration rows (a plank hold is never a timed rep battle) and
-- basketball_shot (object-composition shots stay untimed).
UPDATE motion_activities
SET supported_formats_json = json_insert(supported_formats_json, '$[#]', 'timed_attempt'),
    updated_at = CURRENT_TIMESTAMP
WHERE measurement_type = 'repetitions'
  AND id != 'basketball_shot'
  AND NOT EXISTS (
    SELECT 1
    FROM json_each(motion_activities.supported_formats_json)
    WHERE json_each.value = 'timed_attempt'
  );

-- Migration 0051 (race S7, M1): treadmill_running is a distance movement.
--
-- The row was seeded as 'repetitions' with rep-scale targets, which is why a
-- real run was judged by rep rate (a 5 km proof looked like 5,000 "reps").
-- The measurement becomes 'distance' with metre goals (400 m … 5 km). The
-- wire metric deliberately stays 'reps' — assertSubmissionCompatible and
-- every stored treadmill race treat the value as an opaque cumulative
-- integer, now meaning metres. Idempotent: re-applying writes the same
-- values.
UPDATE motion_activities
SET measurement_type = 'distance',
    suggested_targets_json = '[400,800,1600,3200,5000]',
    updated_at = CURRENT_TIMESTAMP
WHERE id = 'treadmill_running';
