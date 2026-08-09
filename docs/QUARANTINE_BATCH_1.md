# Quarantine Log — Batch 1 (8 candidates)

Date: 2026-08-09
Assessor: Devin (GLM-5.2 High)

## Methodology

Each candidate movement was assessed against the existing 7 preset movements
(pushups, squats, jumping jacks, lunges, plank, high knees, arm raises) to
determine whether it can **prove identity** — i.e., whether a validator can
distinguish it from all existing movements using only the available pose
signals (joint angles, landmark positions, body-width ratios).

The key question is NOT "can we count reps for this movement?" — it's
**"can we prove this movement is NOT one of the others?"**

A movement passes if it has at least one **categorical** signal differentiator
(a signal that is clearly present/absent vs. a threshold, not just a
continuous difference in degree). A movement is quarantined if its only
differentiators are continuous, ambiguous, or undetectable in 2D front view.

## Results

| # | Movement | Verdict | Reason |
|---|----------|---------|-------|
| 1 | Sumo Squats | **PASS** | Wide stance (ankleWidth/bodyWidth > 1.5) is categorical vs regular squats (~0.3-0.5) |
| 2 | Narrow Squats | QUARANTINE | Stance width is continuous, not categorical. Overlaps with regular squats. |
| 3 | Squat Pulses | QUARANTINE | Range of motion (~0.05-0.10 hipToKneeRatio delta) near pose estimation noise floor (~0.05-0.08). Cannot distinguish from partial squats or jitter. |
| 4 | Jump Squats | QUARANTINE | Cannot detect flight phase. Rep cycle identical to regular squats (squat-down → stand-up). No signal differentiates "stand" from "jump". |
| 5 | Reverse Lunges | QUARANTINE | Step direction is Z-axis (away from camera). In 2D front view, indistinguishable from forward lunges. Both produce same knee separation + knee angle pattern. |
| 6 | Side Lunges | **PASS** | Lateral knee separation (> 0.85 * hipWidth) is categorical vs forward lunges (~0.55-0.70). Side step produces direct X-separation; forward step produces Z-movement. |
| 7 | Split Squats | QUARANTINE | Active position identical to forward lunges (one knee bent, knees separated). No signal distinguishes "split squat" from "lunge" once in the split stance. |
| 8 | Star Jumps | QUARANTINE | Indistinguishable from jumping jacks. Both are arms-up + feet-wide. Only difference is degree of spread (continuous, not categorical). |

## Quarantine Details

### Narrow Squats
- **Candidate differentiator:** ankleWidth/bodyWidth < 0.4
- **Problem:** Regular squats already have ankleWidth/bodyWidth ~0.3-0.5.
  Narrow squats would be ~0.2-0.3. The overlap zone (0.3-0.4) is too wide
  for a reliable threshold. People with naturally narrow stances doing
  regular squats would trigger narrow squats, and vice versa.
- **Verdict:** Cannot prove identity. Quarantined.

### Squat Pulses
- **Candidate differentiator:** Small hipToKneeRatio oscillation (~0.05-0.10)
- **Problem:** ML Kit pose estimation has ~5-8% noise on landmark positions.
  This translates to ~0.05-0.08 noise on hipToKneeRatio. Squat pulses
  produce a signal of ~0.05-0.10, which is within the noise floor. The
  validator would either count noise as reps or miss real pulses.
- **Verdict:** Signal below noise floor. Quarantined.

### Jump Squats
- **Candidate differentiator:** Flight phase (feet off ground)
- **Problem:** ML Kit does not detect ground contact. The rep cycle is
  squat-down → stand-up, identical to regular squats. The "jump" portion
  is a brief upward acceleration that produces no distinguishable pose
  signal — the body is fully extended in both "standing" and "jumping".
- **Verdict:** No categorical differentiator. Quarantined.

### Reverse Lunges
- **Candidate differentiator:** Step direction (backward vs forward)
- **Problem:** Step direction is along the Z-axis (depth). In 2D front view,
  both forward and reverse lunges produce the same X-separation pattern:
  one knee moves away from center, one stays. The knee angle and separation
  signals are identical for both movements.
- **Verdict:** Z-axis information not available. Quarantined.

### Split Squats
- **Candidate differentiator:** Stationary split stance vs. stepping lunge
- **Problem:** Once in the split stance (one knee bent, knees separated),
  the pose is identical to the active phase of a forward lunge. The
  difference is in the transition (stepping vs. dropping), but the
  validator only sees the static pose, not the transition.
- **Verdict:** Active pose identical to lunges. Quarantined.

### Star Jumps
- **Candidate differentiator:** Larger arm/leg spread than jumping jacks
- **Problem:** Both jumping jacks and star jumps produce arms-up + feet-wide.
  The only difference is the degree of spread (star jumps ~1.6-1.8
  ankleWidth/bodyWidth vs. jumping jacks ~1.4-1.6). This is a continuous
  difference, not categorical. The overlap zone makes reliable
  differentiation impossible.
- **Verdict:** Continuous, not categorical. Quarantined.

## Pass Details

### Sumo Squats
- **Identity signal:** ankleWidthToBodyWidth > 1.5 (AND hipToKneeRatio for
  the squat descent)
- **Why it works:** Regular squats have ankleWidth/bodyWidth ~0.3-0.5.
  Sumo squats have ~1.5-2.0+. The 1.5 threshold is well above the regular
  squat range and well below the sumo squat range. There is no overlap.
- **Cheating resistance:** A sumo squat race cannot be cheated by doing
  regular squats — the narrow stance fails the ankleWidth condition.
  The regular squat race CAN be done with sumo squats (the hipToKneeRatio
  descent is the same), but this is acceptable: sumo squats are harder
  than regular squats, so there's no incentive to cheat a regular squat
  race by doing sumo squats.

### Side Lunges
- **Identity signal:** kneeSeparationToHipWidth > 0.85 (AND one knee < 118°)
- **Why it works:** Forward lunges produce kneeSeparation ~0.55-0.70
  (the forward step creates some X-separation due to 2D projection, but
  it's limited). Side lunges produce kneeSeparation ~2.5-3.0+ (the lateral
  step creates direct X-separation). The 0.85 threshold is above the
  forward lunge range and below the side lunge range.
- **Cheating resistance:** A side lunge race cannot be cheated by doing
  forward lunges — the forward step produces insufficient lateral
  separation to cross the 0.85 threshold.
- **Known limitation:** A forward lunge with an unusually wide lateral
  component (~0.85+) could trigger side lunges. This is a boundary case
  that may need tuning with real-world data.
