=== MOTION INTELLIGENCE — MILESTONE 1 REPORT ===
Generated: 2026-08-11T11:14:29.956550
Dataset: v1.0.0 (34 clips)
Git SHA: 6927d17

--- SYSTEM COMPONENTS ---
1. Canonical Detector Interface: MotionCandidate
   - 8 candidates registered
   - Families: deterministic, ml
   - Architectures: MultiPhaseSequenceValidator, ConceptStateMachine, MultiPhaseSequenceValidator_tuned, ConceptStateMachine_with_foot_guard, ConceptStateMachine_with_camera_comp, MultiPhaseSequenceValidator_relaxed, HeuristicScore_v1, HeuristicScore_v2_low_threshold

2. Canonical Evaluator: CanonicalEvaluator
   - Metrics: recall, precision, count MAE, exact count rate,
     overcount/undercount rates, false accept rate, confuser clusters
   - Splits: dev (12), val (6), holdout (6)

3. Dataset Manifest: vv1.0.0
   - Target: jump_squats (10 clips)
   - Confusers: 24 clips
   - Hard negatives: 4 clips

4. Leaderboard: 8 entries

--- LEADERBOARD SUMMARY ---
=== MOTION INTELLIGENCE LEADERBOARD ===
8 candidates registered

1. concept_v2 (deterministic/ConceptStateMachine) [RESEARCH]
   product_score: 0.2319
   dev: recall=0.3125 precision=0.7143 f1=0.4348
        exact=0.0000 mae=4.00 faClips=1/9 faClipRate=0.111
        TP=5 FN=11 FP=2 (overcount=1 confuser=1) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:1.00 squat_jacks:0.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.2000 precision=0.3333 f1=0.2500

2. det_foot_guard (deterministic/ConceptStateMachine_with_foot_guard) [RESEARCH]
   product_score: 0.1789
   dev: recall=0.1875 precision=1.0000 f1=0.3158
        exact=0.0000 mae=4.33 faClips=0/9 faClipRate=0.000
        TP=3 FN=13 FP=0 (overcount=0 confuser=0) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:0.00 squat_jacks:0.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.0000 precision=0.0000 f1=0.0000

3. production_jsq (deterministic/MultiPhaseSequenceValidator) [REJECT]
   product_score: 0.1697
   dev: recall=0.2500 precision=0.6667 f1=0.3636
        exact=0.3333 mae=4.00 faClips=2/9 faClipRate=0.222
        TP=4 FN=12 FP=2 (overcount=0 confuser=2) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.0000 precision=0.0000 f1=0.0000

4. ml_heuristic_v1 (ml/HeuristicScore_v1) [REJECT]
   product_score: 0.1567
   dev: recall=0.8125 precision=0.3023 f1=0.4407
        exact=0.0000 mae=2.00 faClips=5/9 faClipRate=0.556
        TP=13 FN=3 FP=30 (overcount=3 confuser=27) catastrophic=0
        confuser clip rates: normal_squats:0.33 deep_squats:1.00 vertical_jumps:0.50 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=0.7500 precision=0.7500 f1=0.7500
   holdout: recall=1.0000 precision=0.3846 f1=0.5556

5. det_lowered_airborne (deterministic/MultiPhaseSequenceValidator_tuned) [REJECT]
   product_score: 0.1533
   dev: recall=0.2500 precision=0.5714 f1=0.3478
        exact=0.0000 mae=4.33 faClips=2/9 faClipRate=0.222
        TP=4 FN=12 FP=3 (overcount=1 confuser=2) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.0000 precision=0.0000 f1=0.0000

6. det_relaxed_temporal (deterministic/MultiPhaseSequenceValidator_relaxed) [REJECT]
   product_score: 0.1469
   dev: recall=0.2500 precision=0.5000 f1=0.3333
        exact=0.0000 mae=4.33 faClips=2/9 faClipRate=0.222
        TP=4 FN=12 FP=4 (overcount=1 confuser=3) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.0000 precision=0.0000 f1=0.0000

7. ml_heuristic_v2 (ml/HeuristicScore_v2_low_threshold) [REJECT]
   product_score: 0.0137
   dev: recall=1.0000 precision=0.1404 f1=0.2462
        exact=0.0000 mae=8.33 faClips=6/9 faClipRate=0.667
        TP=16 FN=0 FP=98 (overcount=25 confuser=73) catastrophic=2
        confuser clip rates: normal_squats:0.67 deep_squats:1.00 vertical_jumps:0.50 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=1.0000 precision=0.3077 f1=0.4706
   holdout: recall=0.2000 precision=0.0625 f1=0.0952

8. det_camera_comp (deterministic/ConceptStateMachine_with_camera_comp) [REJECT]
   product_score: 0.0000
   dev: recall=0.0000 precision=0.0000 f1=0.0000
        exact=0.0000 mae=5.33 faClips=0/9 faClipRate=0.000
        TP=0 FN=16 FP=0 (overcount=0 confuser=0) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:0.00 squat_jacks:0.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.0000 precision=0.0000 f1=0.0000



--- BOTTLENECK ANALYSIS ---
Top candidate: concept_v2
  Recall: 0.313
  Precision: 0.714
  False accepts: 1 reps from 1 clips
  Confuser breakdown: {jumping_jacks: 1}

=== FAILURE MINING REPORT ===

TOP FAILURE CAUSES:
  28x airborne_not_detected
  12x ascent_timeout
  11x airborne_too_long
  2x compression_timeout

CONFUSER FALSE ACCEPT CLUSTERS:
  1 reps from jumping_jacks


--- RECOMMENDATIONS ---
1. Focus on confuser rejection (precision is the bottleneck)
2. Add camera motion compensation to all candidates
3. Expand holdout set for more robust evaluation
4. Train tiny MLP on pose features as ML baseline
5. Explore hybrid: deterministic + ML score fusion

--- NEXT STEPS (Phase 27+) ---
- Subagent orchestration for parallel research
- Automated parameter search across more dimensions
- Movement expansion beyond jump squats
- Production promotion gate: recall > 0.80 AND precision > 0.90
