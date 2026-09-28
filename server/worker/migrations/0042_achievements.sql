-- 0040_achievements.sql
-- Progression v2: real achievement collection, stat-driven requirements,
-- capability unlock ladder, per-user canonical stats snapshot.
-- Additive only — existing rows/columns keep their meaning.

-- ── unlock_definitions: achievement metadata ─────────────────────────────────
-- required_level keeps its meaning for level-gated defs (requirement_kind
-- 'level'). 'stat' defs earn through canonical-history thresholds instead.
ALTER TABLE unlock_definitions ADD COLUMN category TEXT;
ALTER TABLE unlock_definitions ADD COLUMN icon_key TEXT;
ALTER TABLE unlock_definitions ADD COLUMN requirement_kind TEXT NOT NULL DEFAULT 'level';
ALTER TABLE unlock_definitions ADD COLUMN stat_key TEXT;
ALTER TABLE unlock_definitions ADD COLUMN threshold INTEGER;
ALTER TABLE unlock_definitions ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0;

-- ── user_progression: canonical stat snapshot ────────────────────────────────
-- Recomputed every reconcile from race_events/races/race_members — never a
-- client input, so collection progress can never be fabricated.
ALTER TABLE user_progression ADD COLUMN stats_json TEXT;

-- ── XP schedule v2 repair ────────────────────────────────────────────────────
-- Win bonus is +15 (was +10 in the v1 schedule). Fix already-projected rows so
-- historical and future wins price identically; xp_events stays the ledger.
UPDATE xp_events SET xp_amount = 15 WHERE source_type = 'winner_determined' AND xp_amount = 10;

-- ── legacy level badges retire ───────────────────────────────────────────────
-- The v1 seed was level-gated badges at 2/3/5/7/10/15/20/25. v2 replaces them
-- with the capability ladder + milestone achievements; deactivate rather than
-- delete so any rows already earned still resolve.
UPDATE unlock_definitions SET active = 0 WHERE id IN (
  'bdg-off-the-line', 'bdg-in-motion', 'bdg-five-deep', 'bdg-locked-in',
  'bdg-double-digits', 'bdg-built-different', 'bdg-veteran', 'bdg-unstoppable'
);

-- ── achievements: racing ─────────────────────────────────────────────────────
INSERT OR IGNORE INTO unlock_definitions
  (id, required_level, unlock_type, unlock_key, name, description, metadata_json, category, icon_key, requirement_kind, stat_key, threshold, sort_order)
VALUES
  ('ach-first-move',       0, 'achievement', 'first_move',       'First Move',       'Submit your first accepted progress.',  '{"rarity":"common"}',    'racing',      'arrow_forward', 'stat', 'progresses_accepted', 1,   10),
  ('ach-on-the-board',     0, 'achievement', 'on_the_board',     'On the Board',     'Finish your first race.',               '{"rarity":"common"}',    'racing',      'flag',          'stat', 'races_finished',      1,   20),
  ('ach-five-deep',        0, 'achievement', 'five_deep',        'Five Deep',        'Finish 5 races.',                       '{"rarity":"uncommon"}',  'racing',      'flags_5',       'stat', 'races_finished',      5,   30),
  ('ach-double-digits',    0, 'achievement', 'double_digits',    'Double Digits',    'Finish 10 races.',                      '{"rarity":"milestone"}', 'racing',      'num_10',        'stat', 'races_finished',      10,  40),
  ('ach-quarter-century',  0, 'achievement', 'quarter_century',  'Quarter Century',  'Finish 25 races.',                      '{"rarity":"milestone"}', 'racing',      'num_25',        'stat', 'races_finished',      25,  50),
  ('ach-fifty-strong',     0, 'achievement', 'fifty_strong',     'Fifty Strong',     'Finish 50 races.',                      '{"rarity":"milestone"}', 'racing',      'num_50',        'stat', 'races_finished',      50,  60),
  ('ach-century',          0, 'achievement', 'century',          'Century',          'Finish 100 races.',                     '{"rarity":"legendary"}', 'racing',      'num_100',       'stat', 'races_finished',      100, 70);

-- ── achievements: winning ────────────────────────────────────────────────────
INSERT OR IGNORE INTO unlock_definitions
  (id, required_level, unlock_type, unlock_key, name, description, metadata_json, category, icon_key, requirement_kind, stat_key, threshold, sort_order)
VALUES
  ('ach-first-w',          0, 'achievement', 'first_w',          'First W',          'Win your first race.',                  '{"rarity":"common"}',    'winning',     'trophy_1',      'stat', 'races_won',           1,   10),
  ('ach-hat-trick',        0, 'achievement', 'hat_trick',        'Hat Trick',        'Win 3 races.',                          '{"rarity":"uncommon"}',  'winning',     'trophy_3',      'stat', 'races_won',           3,   20),
  ('ach-high-five',        0, 'achievement', 'high_five',        'High Five',        'Win 5 races.',                          '{"rarity":"uncommon"}',  'winning',     'trophy_5',      'stat', 'races_won',           5,   30),
  ('ach-ten-up',           0, 'achievement', 'ten_up',           'Ten Up',           'Win 10 races.',                         '{"rarity":"milestone"}', 'winning',     'trophy_10',     'stat', 'races_won',           10,  40),
  ('ach-twentyfive-wins',  0, 'achievement', 'twentyfive_wins',  'Twenty-Five W''s', 'Win 25 races.',                         '{"rarity":"milestone"}', 'winning',     'trophy_25',     'stat', 'races_won',           25,  50),
  ('ach-champion',         0, 'achievement', 'champion',         'Champion',         'Win 50 races.',                         '{"rarity":"legendary"}', 'winning',     'crown',         'stat', 'races_won',           50,  60);

-- ── achievements: creation ───────────────────────────────────────────────────
INSERT OR IGNORE INTO unlock_definitions
  (id, required_level, unlock_type, unlock_key, name, description, metadata_json, category, icon_key, requirement_kind, stat_key, threshold, sort_order)
VALUES
  ('ach-race-maker',       0, 'achievement', 'race_maker',       'Race Maker',       'Create 3 races.',                       '{"rarity":"uncommon"}',  'creation',    'flag_plus',     'stat', 'races_created',       3,   10),
  ('ach-starter-pack',     0, 'achievement', 'starter_pack',     'Starter Pack',     'Create 10 races.',                      '{"rarity":"milestone"}', 'creation',    'flags_stack',   'stat', 'races_created',       10,  20),
  ('ach-race-architect',   0, 'achievement', 'race_architect',   'Race Architect',   'Create 25 races.',                      '{"rarity":"legendary"}', 'creation',    'blueprint',     'stat', 'races_created',       25,  30);

-- ── achievements: performance ────────────────────────────────────────────────
INSERT OR IGNORE INTO unlock_definitions
  (id, required_level, unlock_type, unlock_key, name, description, metadata_json, category, icon_key, requirement_kind, stat_key, threshold, sort_order)
VALUES
  ('ach-personal-best',    0, 'achievement', 'personal_best',    'Personal Best',    'Set your first personal best.',         '{"rarity":"common"}',    'performance', 'spark_up',      'stat', 'pbs_set',             1,   10),
  ('ach-getting-better',   0, 'achievement', 'getting_better',   'Getting Better',   'Set 10 personal bests.',                '{"rarity":"milestone"}', 'performance', 'chart_up',      'stat', 'pbs_set',             10,  20),
  ('ach-comeback',         0, 'achievement', 'comeback',         'Comeback',         'Win a race after trailing.',            '{"rarity":"uncommon"}',  'performance', 'arrow_curve',   'stat', 'comebacks',           1,   30),
  ('ach-wire-to-wire',     0, 'achievement', 'wire_to_wire',     'Wire to Wire',     'Lead from first result to the finish.', '{"rarity":"milestone"}', 'performance', 'crown_line',    'stat', 'wire_to_wires',       1,   40);

-- ── achievements: social ─────────────────────────────────────────────────────
INSERT OR IGNORE INTO unlock_definitions
  (id, required_level, unlock_type, unlock_key, name, description, metadata_json, category, icon_key, requirement_kind, stat_key, threshold, sort_order)
VALUES
  ('ach-crewmate',         0, 'achievement', 'crewmate',         'Crewmate',         'Finish 5 races with other people.',     '{"rarity":"uncommon"}',  'social',      'people',        'stat', 'social_finished',     5,   10),
  ('ach-crowd-favorite',   0, 'achievement', 'crowd_favorite',   'Crowd Favorite',   'Finish a race with 10+ racers.',        '{"rarity":"milestone"}', 'social',      'people_flag',   'stat', 'big_race_finished',   1,   20),
  ('ach-rivalry',          0, 'achievement', 'rivalry',          'Rivalry',          'Finish 5 races against the same racer.','{"rarity":"milestone"}', 'social',      'crossed_flags', 'stat', 'rivalry_max',         5,   30);

-- ── achievements: variety ────────────────────────────────────────────────────
INSERT OR IGNORE INTO unlock_definitions
  (id, required_level, unlock_type, unlock_key, name, description, metadata_json, category, icon_key, requirement_kind, stat_key, threshold, sort_order)
VALUES
  ('ach-variety-pack',     0, 'achievement', 'variety_pack',     'Variety Pack',     'Finish races in 4 categories.',         '{"rarity":"uncommon"}',  'variety',     'tiles_4',       'stat', 'distinct_categories', 4,   10),
  ('ach-all-rounder',      0, 'achievement', 'all_rounder',      'All-Rounder',      'Finish races in 8 categories.',         '{"rarity":"milestone"}', 'variety',     'compass',       'stat', 'distinct_categories', 8,   20);

-- ── achievements: motion proof ───────────────────────────────────────────────
INSERT OR IGNORE INTO unlock_definitions
  (id, required_level, unlock_type, unlock_key, name, description, metadata_json, category, icon_key, requirement_kind, stat_key, threshold, sort_order)
VALUES
  ('ach-motion-rookie',    0, 'achievement', 'motion_rookie',    'Movement Rookie',  'Finish your first motion race.',        '{"rarity":"common"}',    'motion',      'motion_figure', 'stat', 'motion_finished',     1,   10),
  ('ach-motion-regular',   0, 'achievement', 'motion_regular',   'Motion Regular',   'Finish 10 motion races.',               '{"rarity":"milestone"}', 'motion',      'motion_10',     'stat', 'motion_finished',     10,  20),
  ('ach-motion-machine',   0, 'achievement', 'motion_machine',   'Motion Machine',   'Finish 50 motion races.',               '{"rarity":"legendary"}', 'motion',      'motion_bolt',   'stat', 'motion_finished',     50,  30);

-- ── achievements: proof + format ─────────────────────────────────────────────
INSERT OR IGNORE INTO unlock_definitions
  (id, required_level, unlock_type, unlock_key, name, description, metadata_json, category, icon_key, requirement_kind, stat_key, threshold, sort_order)
VALUES
  ('ach-photo-finish',     0, 'achievement', 'photo_finish',     'Photo Finish',     'Finish your first photo-proof race.',   '{"rarity":"common"}',    'proof',       'camera',        'stat', 'photo_finished',      1,   10),
  ('ach-proof-collector',  0, 'achievement', 'proof_collector',  'Proof Collector',  'Get 10 accepted photo proofs.',         '{"rarity":"milestone"}', 'proof',       'camera_check',  'stat', 'photo_proofs',        10,  20),
  ('ach-time-trial',       0, 'achievement', 'time_trial',       'Time Trial',       'Finish your first timed race.',         '{"rarity":"common"}',    'proof',       'stopwatch',     'stat', 'timed_finished',      1,   30),
  ('ach-against-the-clock',0, 'achievement', 'against_the_clock','Against the Clock','Finish 10 timed races.',                '{"rarity":"milestone"}', 'proof',       'stopwatch_bolt','stat', 'timed_finished',      10,  40);

-- ── achievements: category families ──────────────────────────────────────────
-- stat_key 'category:<name>' reads the canonical custom-activity category, so
-- new families are data, not code — FlexiRace growth adds defs, not rewires.
INSERT OR IGNORE INTO unlock_definitions
  (id, required_level, unlock_type, unlock_key, name, description, metadata_json, category, icon_key, requirement_kind, stat_key, threshold, sort_order)
VALUES
  ('ach-book-it',          0, 'achievement', 'book_it',          'Book It',          'Finish your first reading race.',       '{"rarity":"uncommon"}',  'category',    'book',          'stat', 'category:reading',    1,   10),
  ('ach-page-turner',      0, 'achievement', 'page_turner',      'Page Turner',      'Finish 10 reading races.',              '{"rarity":"milestone"}', 'category',    'books_stack',   'stat', 'category:reading',    10,  20),
  ('ach-brain-race',       0, 'achievement', 'brain_race',       'Brain Race',       'Finish your first academic race.',      '{"rarity":"uncommon"}',  'category',    'paper_grade',   'stat', 'category:academic',   1,   30),
  ('ach-scholar',          0, 'achievement', 'scholar',          'Scholar',          'Finish 10 academic races.',             '{"rarity":"milestone"}', 'category',    'cap_grad',      'stat', 'category:academic',   10,  40),
  ('ach-on-the-green',     0, 'achievement', 'on_the_green',     'On the Green',     'Finish your first golf race.',          '{"rarity":"uncommon"}',  'category',    'flag_golf',     'stat', 'category:golf',       1,   50),
  ('ach-clubhouse-regular',0, 'achievement', 'clubhouse_regular','Clubhouse Regular','Finish 10 golf races.',                 '{"rarity":"milestone"}', 'category',    'flag_golf_10',  'stat', 'category:golf',       10,  60);

-- ── achievements: level milestones ───────────────────────────────────────────
-- Identity stays "Level N" — these mark the climb, not rank tiers.
INSERT OR IGNORE INTO unlock_definitions
  (id, required_level, unlock_type, unlock_key, name, description, metadata_json, category, icon_key, requirement_kind, stat_key, threshold, sort_order)
VALUES
  ('ach-level-5',          5, 'achievement', 'level_5',          'Level 5',          'Reach Level 5.',                        '{"rarity":"uncommon"}',  'level',       'num_5',         'level', NULL, 5,   10),
  ('ach-level-10',        10, 'achievement', 'level_10',         'Level 10',         'Reach Level 10.',                       '{"rarity":"milestone"}', 'level',       'num_10',        'level', NULL, 10,  20),
  ('ach-level-25',        25, 'achievement', 'level_25',         'Level 25',         'Reach Level 25.',                       '{"rarity":"milestone"}', 'level',       'num_25',        'level', NULL, 25,  30),
  ('ach-level-50',        50, 'achievement', 'level_50',         'Level 50',         'Reach Level 50.',                       '{"rarity":"legendary"}', 'level',       'num_50',        'level', NULL, 50,  40),
  ('ach-level-100',      100, 'achievement', 'level_100',        'Level 100',        'Reach Level 100.',                      '{"rarity":"legendary"}', 'level',       'num_100',       'level', NULL, 100, 50);

-- ── capability ladder ────────────────────────────────────────────────────────
-- Levels visibly change the product: featured slots, accents, reactions,
-- frames, celebrations. Widgets read capabilities, never level literals.
INSERT OR IGNORE INTO unlock_definitions
  (id, required_level, unlock_type, unlock_key, name, description, metadata_json, category, icon_key, requirement_kind, stat_key, threshold, sort_order)
VALUES
  ('cap-badge-slot-2',      2, 'badge_slot',   'slot_2',       'Second badge slot', 'Feature a second achievement on your profile.',   '{"rarity":"common"}',   NULL, 'slot',    'level', NULL, 2,   10),
  ('cap-accent-ember',      3, 'accent',       'ember',        'Ember accent',      'A warm accent for your profile.',                 '{"rarity":"common"}',   NULL, 'accent',  'level', NULL, 3,   20),
  ('cap-reaction-flex',     4, 'reaction',     'flex',         'Flex reaction',     'A new reaction for race finishes.',               '{"rarity":"common"}',   NULL, 'reaction','level', NULL, 4,   30),
  ('cap-frame-racer',       5, 'frame',        'racer',        'Racer frame',       'A profile frame for finishing your climb to 5.',  '{"rarity":"uncommon"}', NULL, 'frame',   'level', NULL, 5,   40),
  ('cap-celebration-flare', 6, 'celebration',  'flare',        'Finish flare',      'A new finish-line celebration.',                  '{"rarity":"uncommon"}', NULL, 'spark',   'level', NULL, 6,   50),
  ('cap-badge-slot-3',      7, 'badge_slot',   'slot_3',       'Third badge slot',  'Feature a third achievement on your profile.',    '{"rarity":"uncommon"}', NULL, 'slot',    'level', NULL, 7,   60),
  ('cap-accent-ice',        8, 'accent',       'ice',          'Ice accent',        'A cool accent for your profile.',                 '{"rarity":"common"}',   NULL, 'accent',  'level', NULL, 8,   70),
  ('cap-reaction-clap',     9, 'reaction',     'clap',         'Clap reaction',     'A new reaction for race finishes.',               '{"rarity":"common"}',   NULL, 'reaction','level', NULL, 9,   80),
  ('cap-frame-champion',   10, 'frame',        'champion',     'Champion frame',    'A profile frame for reaching double digits.',     '{"rarity":"milestone"}',NULL, 'frame',   'level', NULL, 10,  90),
  ('cap-accent-royal',     15, 'accent',       'royal',        'Royal accent',      'A deep accent for your profile.',                 '{"rarity":"milestone"}',NULL, 'accent',  'level', NULL, 15, 100),
  ('cap-reaction-rocket',  20, 'reaction',     'rocket',       'Rocket reaction',   'A new reaction for race finishes.',               '{"rarity":"milestone"}',NULL, 'reaction','level', NULL, 20, 110),
  ('cap-frame-legend',     25, 'frame',        'legend',       'Legend frame',      'A profile frame for the long racers.',            '{"rarity":"milestone"}',NULL, 'frame',   'level', NULL, 25, 120),
  ('cap-accent-gold',      30, 'accent',       'gold',         'Gold accent',       'A bright accent for your profile.',               '{"rarity":"milestone"}',NULL, 'accent',  'level', NULL, 30, 130),
  ('cap-celebration-storm',40, 'celebration',  'storm',        'Storm finish',      'A new finish-line celebration.',                  '{"rarity":"legendary"}',NULL, 'spark',   'level', NULL, 40, 140),
  ('cap-frame-mythic',     50, 'frame',        'mythic',       'Mythic frame',      'A profile frame almost nobody has earned.',       '{"rarity":"legendary"}',NULL, 'frame',   'level', NULL, 50, 150);
