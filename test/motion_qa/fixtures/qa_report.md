# QA Report: Jump Squat

## POSITIVE
- Total sequences: 44
- Accepted: 27
- Rejected: 17
- Accept rate: 61.4%

## CONFUSERS
- normal_squat → false accepts: 0
- plain_jump → false accepts: 0
- jumping_jack → false accepts: 0
- partial_squat → false accepts: 0

## FAILURE REASONS
- undercounted: 17
- airborne_never_detected: 1

## ROBUSTNESS
- drop_frames: 6/8 (75.0%)
- duplicate_frames: 7/8 (87.5%)
- time_stretch: 7/8 (87.5%)
- time_compress: 4/8 (50.0%)
- coordinate_jitter: 7/8 (87.5%)
- confidence_degradation: 7/8 (87.5%)
- ankle_dropout: 5/8 (62.5%)
- body_translation: 7/8 (87.5%)
- scale_change: 7/8 (87.5%)
- mirror: 7/8 (87.5%)


---

# QA Report: Lunge Jump

## POSITIVE
- Total sequences: 22
- Accepted: 10
- Rejected: 12
- Accept rate: 45.5%

## CONFUSERS

## FAILURE REASONS
- undercounted: 12
- stuck_in_idle: 3

## ROBUSTNESS
- drop_frames: 1/2 (50.0%)
- duplicate_frames: 1/2 (50.0%)
- time_stretch: 1/2 (50.0%)
- time_compress: 0/2 (0.0%)
- coordinate_jitter: 1/2 (50.0%)
- confidence_degradation: 1/2 (50.0%)
- ankle_dropout: 1/2 (50.0%)
- body_translation: 1/2 (50.0%)
- scale_change: 1/2 (50.0%)
- mirror: 1/2 (50.0%)

