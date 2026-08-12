# MOTION INTELLIGENCE — M1.1 REPORT

Generated: 2026-08-11T11:14:37.170179
Dataset: v1.0.0 (34 clips)
Git SHA: 6927d17
Production files changed: NONE

---

## 1. METRIC BUGS FOUND

- **Unbounded recall**: Old formula `totalDetected / totalExpected` allowed recall > 1.0 when detector overcounted. Example: ml_heuristic_v2 had recall=2.563.
- **Inflated precision**: Old formula counted all target detections as true positives, even overcounted reps. Precision was only penalized by confuser false accepts.
- **Gameable composite score**: Old score `recall*0.4 + precision*0.3 + (1-fa)*0.2 + exact*0.1` allowed high-recall/low-precision candidates to rank #1.
- **No catastrophic clip detection**: A detector predicting 20 reps on a 5-rep clip had no special penalty.
- **No false accept clip rate**: Only total false accept reps were tracked, not the fraction of confuser clips triggered.

## 2. EVENT MATCHING DEFINITION

**COUNT-BASED MATCHING** (current):
  TP = sum of min(detected, expected) per target clip
  FN = sum of max(0, expected - detected) per target clip
  FP = overcount on target clips + all detections on confuser clips

This is an upper bound on event-level TP. True temporal matching would
require per-rep timestamps which we do not have. Count-based metrics
are clearly labeled as such and not conflated with event-level precision.

**EVENT-LEVEL MATCHING** (future):
  Would use temporal alignment: each predicted event matches at most
  one ground-truth event within a temporal tolerance window.
  Requires annotated rep timestamps in fixtures.

## 3. CORRECTED METRIC DEFINITIONS

```
TP = matched reps (bounded by expected per clip)
FN = expected reps not matched
FP = unmatched predicted reps (overcount + confuser detections)
RECALL = TP / (TP + FN)  -- always in [0, 1]
PRECISION = TP / (TP + FP)  -- always in [0, 1]
F1 = 2 * P * R / (P + R)
FALSE_ACCEPT_CLIP_RATE = confuser clips triggered / total confuser clips
COUNT_MAE = mean(|detected - expected|) over target clips
CATASTROPHIC = clip where detected > 3x expected

PRODUCT_SCORE = F1 * (1 - false_accept_clip_rate) * count_quality_factor
  where count_quality_factor = 1 - (count_MAE / max_expected_reps)
```

## 4. BEFORE/AFTER LEADERBOARD

| Rank | M1 (Before) | M1.1 (After) | Gate | Product Score | Recall | Precision | F1 |
|------|-------------|--------------|------|---------------|--------|-----------|----|
| 1 | ml_heuristic_v1 | #15 ml_heuristic_v1 | REJECT | 0.1567 | 1.0000 | 0.3846 | 0.5556 |
| 2 | concept_v2 | #2 concept_v2 | RESEARCH | 0.2319 | 0.2000 | 0.3333 | 0.2500 |
| 3 | ml_heuristic_v2 | #24 ml_heuristic_v2 | REJECT | 0.0137 | 0.2000 | 0.0625 | 0.0952 |
| 4 | production_jsq | #14 production_jsq | REJECT | 0.1697 | 0.0000 | 0.0000 | 0.0000 |
| 5 | det_lowered_airborne | #16 det_lowered_airborne | REJECT | 0.1533 | 0.0000 | 0.0000 | 0.0000 |
| 6 | det_foot_guard | #13 det_foot_guard | RESEARCH | 0.1789 | 0.0000 | 0.0000 | 0.0000 |
| 7 | det_camera_comp | #25 det_camera_comp | REJECT | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| 8 | det_relaxed_temporal | #19 det_relaxed_temporal | REJECT | 0.1469 | 0.0000 | 0.0000 | 0.0000 |

## 5. CORRECTED BEST BASELINE

```
=== MOTION INTELLIGENCE LEADERBOARD ===
28 candidates registered

1. temp_adaptive_hyst (temporal/AdaptiveHysteresis) [REJECT]
   product_score: 0.2471
   dev: recall=0.5625 precision=0.5000 f1=0.5294
        exact=0.0000 mae=4.00 faClips=2/9 faClipRate=0.222
        TP=9 FN=7 FP=9 (overcount=5 confuser=4) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:1.00 vertical_jumps:0.00 jumping_jacks:0.00 squat_jacks:1.00 lunges:0.00
   val: recall=0.2500 precision=0.6667 f1=0.3636
   holdout: recall=0.2000 precision=0.5000 f1=0.2857

2. concept_v2 (deterministic/ConceptStateMachine) [RESEARCH]
   product_score: 0.2319
   dev: recall=0.3125 precision=0.7143 f1=0.4348
        exact=0.0000 mae=4.00 faClips=1/9 faClipRate=0.111
        TP=5 FN=11 FP=2 (overcount=1 confuser=1) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:1.00 squat_jacks:0.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.2000 precision=0.3333 f1=0.2500

3. cam_shoulder_hip_consensus (camera_relative/ShoulderHipConsensus) [REJECT]
   product_score: 0.2052
   dev: recall=0.3125 precision=0.6250 f1=0.4167
        exact=0.3333 mae=3.67 faClips=2/9 faClipRate=0.222
        TP=5 FN=11 FP=3 (overcount=0 confuser=3) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.0000 precision=0.0000 f1=0.0000

4. sq_median_filter (signal_quality/MedianFilterAirborne) [RESEARCH]
   product_score: 0.2032
   dev: recall=0.2500 precision=0.8000 f1=0.3810
        exact=0.3333 mae=4.00 faClips=1/9 faClipRate=0.111
        TP=4 FN=12 FP=1 (overcount=0 confuser=1) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:1.00 squat_jacks:0.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.0000 precision=0.0000 f1=0.0000

5. cam_torso_sub (camera_relative/TorsoSubtractedAirborne) [REJECT]
   product_score: 0.1944
   dev: recall=0.3125 precision=0.6250 f1=0.4167
        exact=0.0000 mae=4.00 faClips=2/9 faClipRate=0.222
        TP=5 FN=11 FP=3 (overcount=1 confuser=2) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.2000 precision=0.3333 f1=0.2500

6. temp_n_of_m (temporal/NofMTransitions) [REJECT]
   product_score: 0.1944
   dev: recall=0.3125 precision=0.6250 f1=0.4167
        exact=0.0000 mae=4.00 faClips=2/9 faClipRate=0.222
        TP=5 FN=11 FP=3 (overcount=1 confuser=2) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.2000 precision=0.3333 f1=0.2500

7. sq_conf_smooth (signal_quality/ConfidenceSmoothing) [REJECT]
   product_score: 0.1944
   dev: recall=0.3125 precision=0.6250 f1=0.4167
        exact=0.0000 mae=4.00 faClips=2/9 faClipRate=0.222
        TP=5 FN=11 FP=3 (overcount=1 confuser=2) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.2000 precision=0.3333 f1=0.2500

8. feat_accel (feature_engineering/AccelerationFeature) [REJECT]
   product_score: 0.1944
   dev: recall=0.3125 precision=0.6250 f1=0.4167
        exact=0.0000 mae=4.00 faClips=2/9 faClipRate=0.222
        TP=5 FN=11 FP=3 (overcount=1 confuser=2) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.2000 precision=0.3333 f1=0.2500

9. feat_joint_angular (feature_engineering/JointAngularVelocity) [REJECT]
   product_score: 0.1944
   dev: recall=0.3125 precision=0.6250 f1=0.4167
        exact=0.0000 mae=4.00 faClips=2/9 faClipRate=0.222
        TP=5 FN=11 FP=3 (overcount=1 confuser=2) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.2000 precision=0.3333 f1=0.2500

10. feat_stance_width (feature_engineering/StanceWidthDynamics) [REJECT]
   product_score: 0.1944
   dev: recall=0.3125 precision=0.6250 f1=0.4167
        exact=0.0000 mae=4.00 faClips=2/9 faClipRate=0.222
        TP=5 FN=11 FP=3 (overcount=1 confuser=2) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.2000 precision=0.3333 f1=0.2500

11. conf_deep_squat_reject (confuser_specialist/DeepSquatReject) [REJECT]
   product_score: 0.1944
   dev: recall=0.3125 precision=0.6250 f1=0.4167
        exact=0.0000 mae=4.00 faClips=2/9 faClipRate=0.222
        TP=5 FN=11 FP=3 (overcount=1 confuser=2) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.2000 precision=0.3333 f1=0.2500

12. conf_jumping_jack_reject (confuser_specialist/JumpingJackReject) [REJECT]
   product_score: 0.1944
   dev: recall=0.3125 precision=0.6250 f1=0.4167
        exact=0.0000 mae=4.00 faClips=2/9 faClipRate=0.222
        TP=5 FN=11 FP=3 (overcount=1 confuser=2) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.2000 precision=0.3333 f1=0.2500

13. det_foot_guard (deterministic/ConceptStateMachine_with_foot_guard) [RESEARCH]
   product_score: 0.1789
   dev: recall=0.1875 precision=1.0000 f1=0.3158
        exact=0.0000 mae=4.33 faClips=0/9 faClipRate=0.000
        TP=3 FN=13 FP=0 (overcount=0 confuser=0) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:0.00 squat_jacks:0.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.0000 precision=0.0000 f1=0.0000

14. production_jsq (deterministic/MultiPhaseSequenceValidator) [REJECT]
   product_score: 0.1697
   dev: recall=0.2500 precision=0.6667 f1=0.3636
        exact=0.3333 mae=4.00 faClips=2/9 faClipRate=0.222
        TP=4 FN=12 FP=2 (overcount=0 confuser=2) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.0000 precision=0.0000 f1=0.0000

15. ml_heuristic_v1 (ml/HeuristicScore_v1) [REJECT]
   product_score: 0.1567
   dev: recall=0.8125 precision=0.3023 f1=0.4407
        exact=0.0000 mae=2.00 faClips=5/9 faClipRate=0.556
        TP=13 FN=3 FP=30 (overcount=3 confuser=27) catastrophic=0
        confuser clip rates: normal_squats:0.33 deep_squats:1.00 vertical_jumps:0.50 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=0.7500 precision=0.7500 f1=0.7500
   holdout: recall=1.0000 precision=0.3846 f1=0.5556

16. det_lowered_airborne (deterministic/MultiPhaseSequenceValidator_tuned) [REJECT]
   product_score: 0.1533
   dev: recall=0.2500 precision=0.5714 f1=0.3478
        exact=0.0000 mae=4.33 faClips=2/9 faClipRate=0.222
        TP=4 FN=12 FP=3 (overcount=1 confuser=2) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.0000 precision=0.0000 f1=0.0000

17. conf_vertical_jump_reject (confuser_specialist/VerticalJumpReject) [REJECT]
   product_score: 0.1533
   dev: recall=0.2500 precision=0.5714 f1=0.3478
        exact=0.0000 mae=4.33 faClips=2/9 faClipRate=0.222
        TP=4 FN=12 FP=3 (overcount=1 confuser=2) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.2000 precision=0.3333 f1=0.2500

18. cam_hip_rel_ankle (camera_relative/HipRelativeAnkleAirborne) [REJECT]
   product_score: 0.1481
   dev: recall=0.3125 precision=0.4545 f1=0.3704
        exact=0.0000 mae=4.00 faClips=3/9 faClipRate=0.333
        TP=5 FN=11 FP=6 (overcount=1 confuser=5) catastrophic=0
        confuser clip rates: normal_squats:0.33 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.4000 precision=0.5000 f1=0.4444

19. det_relaxed_temporal (deterministic/MultiPhaseSequenceValidator_relaxed) [REJECT]
   product_score: 0.1469
   dev: recall=0.2500 precision=0.5000 f1=0.3333
        exact=0.0000 mae=4.33 faClips=2/9 faClipRate=0.222
        TP=4 FN=12 FP=4 (overcount=1 confuser=3) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.0000 precision=0.0000 f1=0.0000

20. ml_enhanced_v3 (ml/EnhancedHeuristic_v3_high_threshold) [REJECT]
   product_score: 0.1363
   dev: recall=0.5625 precision=0.3103 f1=0.4000
        exact=0.3333 mae=2.33 faClips=5/9 faClipRate=0.556
        TP=9 FN=7 FP=20 (overcount=0 confuser=20) catastrophic=0
        confuser clip rates: normal_squats:0.33 deep_squats:1.00 vertical_jumps:0.50 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=0.1250 precision=1.0000 f1=0.2222
   holdout: recall=0.6000 precision=0.3333 f1=0.4286

21. hybrid_ml_gate_det (hybrid/MLGate_DetCounter) [REJECT]
   product_score: 0.1259
   dev: recall=0.2500 precision=0.5000 f1=0.3333
        exact=0.0000 mae=4.33 faClips=3/9 faClipRate=0.333
        TP=4 FN=12 FP=4 (overcount=1 confuser=3) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:1.00 vertical_jumps:0.00 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.0000 precision=0.0000 f1=0.0000

22. combo_cam_foot_deepsquat (hybrid/Combo_Consensus+FootGuard+DeepSquatReject) [REJECT]
   product_score: 0.0790
   dev: recall=0.1250 precision=0.4000 f1=0.1905
        exact=0.0000 mae=4.67 faClips=2/9 faClipRate=0.222
        TP=2 FN=14 FP=3 (overcount=0 confuser=3) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.0000 precision=0.0000 f1=0.0000

23. ml_enhanced_v1 (ml/EnhancedHeuristic_v1) [REJECT]
   product_score: 0.0259
   dev: recall=1.0000 precision=0.1702 f1=0.2909
        exact=0.0000 mae=7.33 faClips=6/9 faClipRate=0.667
        TP=16 FN=0 FP=78 (overcount=22 confuser=56) catastrophic=1
        confuser clip rates: normal_squats:0.67 deep_squats:1.00 vertical_jumps:0.50 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=1.0000 precision=0.4444 f1=0.6154
   holdout: recall=1.0000 precision=0.2000 f1=0.3333

24. ml_heuristic_v2 (ml/HeuristicScore_v2_low_threshold) [REJECT]
   product_score: 0.0137
   dev: recall=1.0000 precision=0.1404 f1=0.2462
        exact=0.0000 mae=8.33 faClips=6/9 faClipRate=0.667
        TP=16 FN=0 FP=98 (overcount=25 confuser=73) catastrophic=2
        confuser clip rates: normal_squats:0.67 deep_squats:1.00 vertical_jumps:0.50 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=1.0000 precision=0.3077 f1=0.4706
   holdout: recall=0.2000 precision=0.0625 f1=0.0952

25. det_camera_comp (deterministic/ConceptStateMachine_with_camera_comp) [REJECT]
   product_score: 0.0000
   dev: recall=0.0000 precision=0.0000 f1=0.0000
        exact=0.0000 mae=5.33 faClips=0/9 faClipRate=0.000
        TP=0 FN=16 FP=0 (overcount=0 confuser=0) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:0.00 squat_jacks:0.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.0000 precision=0.0000 f1=0.0000

26. ml_enhanced_v2 (ml/EnhancedHeuristic_v2_low_threshold) [REJECT]
   product_score: 0.0000
   dev: recall=1.0000 precision=0.1159 f1=0.2078
        exact=0.0000 mae=13.67 faClips=6/9 faClipRate=0.667
        TP=16 FN=0 FP=122 (overcount=41 confuser=81) catastrophic=2
        confuser clip rates: normal_squats:0.67 deep_squats:1.00 vertical_jumps:0.50 jumping_jacks:1.00 squat_jacks:1.00 lunges:0.00
   val: recall=1.0000 precision=0.2581 f1=0.4103
   holdout: recall=1.0000 precision=0.1429 f1=0.2500

27. hybrid_det_ml (hybrid/DetProposal_MLVerifier) [REJECT]
   product_score: 0.0000
   dev: recall=0.0000 precision=0.0000 f1=0.0000
        exact=0.0000 mae=5.33 faClips=1/9 faClipRate=0.111
        TP=0 FN=16 FP=1 (overcount=0 confuser=1) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:1.00 squat_jacks:0.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.0000 precision=0.0000 f1=0.0000

28. combo_stance_ml (hybrid/Combo_StanceWidth+MLVerifier) [REJECT]
   product_score: 0.0000
   dev: recall=0.0000 precision=0.0000 f1=0.0000
        exact=0.0000 mae=5.33 faClips=1/9 faClipRate=0.111
        TP=0 FN=16 FP=1 (overcount=0 confuser=1) catastrophic=0
        confuser clip rates: normal_squats:0.00 deep_squats:0.00 vertical_jumps:0.00 jumping_jacks:1.00 squat_jacks:0.00 lunges:0.00
   val: recall=0.0000 precision=0.0000 f1=0.0000
   holdout: recall=0.0000 precision=0.0000 f1=0.0000


```

## 6. PARALLEL EXPERIMENTS RUN

Count: 28 candidates
Families:
  - deterministic: 6 candidates
  - ml: 5 candidates
  - camera_relative: 3 candidates
  - temporal: 2 candidates
  - signal_quality: 2 candidates
  - feature_engineering: 3 candidates
  - confuser_specialist: 3 candidates
  - hybrid: 4 candidates

Specialist groups:
  1. CAMERA_RELATIVE: 3 candidates (torso subtraction, hip-relative ankle, shoulder-hip consensus)
  2. TEMPORAL: 2 candidates (N-of-M transitions, adaptive hysteresis)
  3. SIGNAL_QUALITY: 2 candidates (median filter, confidence smoothing)
  4. FEATURE_ENGINEERING: 3 candidates (acceleration, joint angular velocity, stance width)
  5. CONFUSER_SPECIALISTS: 3 candidates (deep squat, jumping jack, vertical jump reject)
  6. LEARNED_MODELS: 3 candidates (enhanced heuristic v1/v2/v3)
  7. HYBRIDS: 4 candidates (det+ML verify, ML gate+det, combo camera+foot+deepsquat, combo stance+ML)

## 7. TOP 10 CANDIDATES

| Rank | Candidate | Family | Recall | Precision | F1 | FA Clip Rate | Count MAE | Exact Rate | Runtime (ms) | Product Score | Gate |
|------|-----------|--------|--------|-----------|----|-------------|-----------|------------|-------------|--------------|------|
| 1 | temp_adaptive_hyst | temporal | 0.5625 | 0.5000 | 0.5294 | 0.222 | 4.00 | 0.0000 | 0 | 0.2471 | REJECT |
| 2 | concept_v2 | deterministic | 0.3125 | 0.7143 | 0.4348 | 0.111 | 4.00 | 0.0000 | 0 | 0.2319 | RESEARCH |
| 3 | cam_shoulder_hip_consensus | camera_relative | 0.3125 | 0.6250 | 0.4167 | 0.222 | 3.67 | 0.3333 | 0 | 0.2052 | REJECT |
| 4 | sq_median_filter | signal_quality | 0.2500 | 0.8000 | 0.3810 | 0.111 | 4.00 | 0.3333 | 0 | 0.2032 | RESEARCH |
| 5 | cam_torso_sub | camera_relative | 0.3125 | 0.6250 | 0.4167 | 0.222 | 4.00 | 0.0000 | 0 | 0.1944 | REJECT |
| 6 | temp_n_of_m | temporal | 0.3125 | 0.6250 | 0.4167 | 0.222 | 4.00 | 0.0000 | 0 | 0.1944 | REJECT |
| 7 | sq_conf_smooth | signal_quality | 0.3125 | 0.6250 | 0.4167 | 0.222 | 4.00 | 0.0000 | 0 | 0.1944 | REJECT |
| 8 | feat_accel | feature_engineering | 0.3125 | 0.6250 | 0.4167 | 0.222 | 4.00 | 0.0000 | 0 | 0.1944 | REJECT |
| 9 | feat_joint_angular | feature_engineering | 0.3125 | 0.6250 | 0.4167 | 0.222 | 4.00 | 0.0000 | 0 | 0.1944 | REJECT |
| 10 | feat_stance_width | feature_engineering | 0.3125 | 0.6250 | 0.4167 | 0.222 | 4.00 | 0.0000 | 0 | 0.1944 | REJECT |

## 8. BEST DETERMINISTIC

concept_v2 (ConceptStateMachine)
  recall=0.3125 precision=0.7143 f1=0.4348
  product_score=0.2319 gate=RESEARCH

## 9. BEST ML

ml_heuristic_v1 (HeuristicScore_v1)
  recall=0.8125 precision=0.3023 f1=0.4407
  product_score=0.1567 gate=REJECT

## 10. BEST HYBRID

hybrid_ml_gate_det (MLGate_DetCounter)
  recall=0.2500 precision=0.5000 f1=0.3333
  product_score=0.1259 gate=REJECT

## 11. BEST OVERALL

temp_adaptive_hyst (temporal/AdaptiveHysteresis)
  recall=0.5625 precision=0.5000 f1=0.5294
  product_score=0.2471 gate=REJECT
  TP=9 FN=7 FP=9 (overcount=5 confuser=4)
  false_accept_clip_rate=0.222 catastrophic=0

## 12. FAILURE CLUSTERS

  deep_squats: 3 false accept reps
  squat_jacks: 1 false accept reps

## 13. DATASET LIMITATIONS

- Only 34 clips total (12 dev, 6 val, 6 holdout)
- Count-based labels only (no per-rep timestamps for event-level matching)
- Limited confuser diversity: 6 confuser types
- No camera motion metadata per clip
- No pose quality buckets assigned
- Holdout set too small for robust generalization claims

## 14. AUTOMATION SPEED

- 28 candidates evaluated in < 60 seconds
- 5 parameter searches with 34 total configurations
- Estimated throughput: ~30 experiments/minute

## 15. NEXT BOTTLENECK

Choose: **FEATURES**

Rationale: The best candidates still fail on deep squats and jumping jacks.
The signal extraction layer (hip-knee ratio + ankle rise) does not sufficiently
distinguish jump squats from visually similar movements. New features
(knee travel, stance width dynamics, acceleration profiles) are needed
before model complexity can help.

## 16. READINESS

```
BEST_RECALL: 1.0000
BEST_PRECISION: 1.0000
BEST_F1: 0.5294

ABOVE_75_90_GATE = NO
ABOVE_85_95_GATE = NO
ABOVE_90_95_GATE = NO
```

## 17. PRODUCTION FILES CHANGED

Expected: NONE
Actual: NONE

All work is in test/motion_qa/ only. No production motion code was modified.
