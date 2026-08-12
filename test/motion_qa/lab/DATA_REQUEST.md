# DATA REQUEST — Additional Real-World Clips for Motion Lab

**Generated:** 2026-08-11
**Requestor:** Motion Lab Agent 1 (automated, post-forensic-audit)
**Priority:** HIGH — current dataset is insufficient for generalizable model

---

## WHY MORE DATA IS NEEDED

### Current Dataset
- **Total clips:** 31
- **Dev split:** 16 clips (9 target, 7 confuser)
- **Validation split:** 8 clips
- **Holdout split:** 6 clips (1 target, 5 confuser)

### Evidence of Insufficiency
1. **Overfitting gap:** 0.3500 (dev F1=0.6000, holdout F1=0.2500)
2. **All 10 families plateaued** within ~500 experiments — no improvement in remaining 307,561
3. **Holdout has only 1 target clip** — holdout F1 is essentially binary (detect or miss)
4. **Deep squat confuser** has only 3 clips total (2 dev, 1 holdout) — insufficient for learning the distinction

---

## REQUESTED CLIPS

### Priority 1: Jump Squat Variety (target movement)
Need diverse jump squat clips to prevent overfitting to specific athletes/angles:

| # | Description | Reps | Source | Notes |
|---|-------------|------|--------|-------|
| 1 | Jump squats — side angle, athletic male | 5 | YouTube | Different camera angle from current clips |
| 2 | Jump squats — front angle, athletic female | 5 | YouTube | Gender diversity |
| 3 | Jump squats — 45-degree angle | 5 | YouTube | Oblique camera |
| 4 | Jump squats — wide stance | 5 | YouTube | Variation in form |
| 5 | Jump squats — fast tempo (minimal squat) | 5 | YouTube | Edge case: minimal compression |
| 6 | Jump squats — slow tempo (deep squat) | 5 | YouTube | Edge case: deep compression |
| 7 | Jump squats — beginner form | 3 | YouTube | Imperfect form |
| 8 | Jump squats — advanced form | 8 | YouTube | Explosive, high rep count |

**Total Priority 1:** 8 clips, ~46 reps

### Priority 2: Deep Squat Hard Negatives (primary confuser)
Deep squats are the main false-accept source. Need more examples:

| # | Description | Reps | Source | Notes |
|---|-------------|------|--------|-------|
| 1 | Deep squats — bodyweight, slow | 5 | YouTube | Clear deep squat pattern |
| 2 | Deep squats — weighted (barbell) | 5 | YouTube | Different movement profile |
| 3 | Deep squats — sumo stance | 5 | YouTube | Wide stance variation |
| 4 | Deep squats — close to jump squat (minimal jump) | 3 | YouTube | Hard negative: barely leaves ground |

**Total Priority 2:** 4 clips, ~18 reps

### Priority 3: Other Confuser Variety
Current confuser coverage is thin (1-2 clips each):

| # | Description | Reps | Source | Notes |
|---|-------------|------|--------|-------|
| 1 | Jumping jacks — standard | 8 | YouTube | |
| 2 | Jumping jacks — cross jacks variant | 5 | YouTube | |
| 3 | Squat jacks — standard | 5 | YouTube | |
| 4 | Lunges — forward, alternating | 5 | YouTube | |
| 5 | Lunges — reverse | 5 | YouTube | |
| 6 | Vertical jumps — tuck jumps | 5 | YouTube | |
| 7 | Normal squats — fast tempo | 5 | YouTube | |

**Total Priority 3:** 7 clips, ~43 reps

---

## SPLIT ASSIGNMENT

New clips should be distributed as follows:

| Split | Target Clips | Confuser Clips | Total |
|-------|-------------|----------------|-------|
| dev | 4 | 4 | 8 |
| validation | 2 | 3 | 5 |
| holdout | 2 | 3 | 5 |
| **Total** | **8** | **10** | **18** |

This would bring the dataset to:
- **Dev:** 24 clips (13 target, 11 confuser)
- **Validation:** 13 clips
- **Holdout:** 11 clips (3 target, 8 confuser)

---

## CLIP SPECIFICATIONS

- **Format:** MP4 or MOV
- **Resolution:** 720p or higher
- **Duration:** 10-30 seconds per clip
- **Framerate:** 30fps preferred
- **Camera:** Static (no tracking shots)
- **Subject:** Full body visible throughout movement
- **Lighting:** Indoor or outdoor, well-lit
- **Ground truth:** Rep count verified by human review

---

## EXPECTED IMPACT

With 18 additional clips:
1. **Holdout target clips:** 1 → 3 (reduces holdout F1 variance)
2. **Deep squat hard negatives:** 3 → 7 (improves confuser discrimination)
3. **Jump squat variety:** 9 → 13 dev clips (reduces overfitting to specific clips)
4. **Expected overfitting gap reduction:** 0.35 → ~0.15 (estimate)
5. **Expected holdout F1 improvement:** 0.25 → ~0.45 (estimate)
