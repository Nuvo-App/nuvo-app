# FEATURE SEPARABILITY REPORT

Generated: 2026-08-11T11:14:31.313495
Dataset: 7098 frames, 24 clips

## TOP 20 SEPARATING FEATURES (Jump Squat vs Confusers)

| Rank | Feature | JS Mean | Conf Mean | Effect Size | Deep Squat | Jump Jack | Vert Jump | Squat Jack |
|------|---------|---------|-----------|-------------|------------|-----------|-----------|-----------|
| 1 | normStanceWidth | 1.0399 | 0.3399 | 1.187 | 0.1705 | 0.4059 | 0.2715 | 0.5892 |
| 2 | footSepConf | 0.8658 | 0.4451 | 0.987 | 0.2400 | 0.3000 | 0.4542 | 0.4083 |
| 3 | leftKnee_relTorsoX | 0.1034 | 0.0391 | 0.981 | 0.0022 | 0.0298 | 0.0390 | 0.0523 |
| 4 | leftKnee_relLeftHipX | 0.0635 | 0.0111 | 0.963 | -0.0176 | 0.0012 | 0.0045 | 0.0234 |
| 5 | rightAnkle_relShldrX | -0.0970 | -0.0391 | 0.943 | -0.0020 | -0.0511 | -0.0352 | -0.0503 |
| 6 | leftKnee_relRightHipX | 0.1433 | 0.0671 | 0.933 | 0.0219 | 0.0585 | 0.0734 | 0.0811 |
| 7 | rightKnee_relShldrX | -0.0925 | -0.0358 | 0.923 | -0.0201 | -0.0460 | -0.0334 | -0.0545 |
| 8 | leftShoulder_relTorsoY | -0.1546 | -0.2353 | 0.907 | -0.2096 | -0.1860 | -0.2140 | -0.1789 |
| 9 | rightHip_relShldrY | 0.1559 | 0.2354 | 0.891 | 0.2119 | 0.1880 | 0.2123 | 0.1777 |
| 10 | leftHip_relShldrY | 0.1558 | 0.2344 | 0.873 | 0.2105 | 0.1880 | 0.2125 | 0.1767 |
| 11 | leftKnee_relShldrX | 0.0836 | 0.0377 | 0.859 | 0.0349 | 0.0303 | 0.0355 | 0.0533 |
| 12 | rightShoulder_relTorsoY | -0.1571 | -0.2344 | 0.853 | -0.2128 | -0.1900 | -0.2109 | -0.1755 |
| 13 | leftAnkle_relTorsoX | 0.0840 | 0.0335 | 0.792 | -0.0010 | 0.0287 | 0.0350 | 0.0563 |
| 14 | footSep | 0.1648 | 0.0823 | 0.780 | 0.0381 | 0.0866 | 0.0669 | 0.1087 |
| 15 | leftAnkle_relLeftHipX | 0.0441 | 0.0055 | 0.774 | -0.0207 | 0.0000 | 0.0006 | 0.0275 |
| 16 | leftAnkle_relRightHipX | 0.1239 | 0.0615 | 0.764 | 0.0188 | 0.0573 | 0.0695 | 0.0852 |
| 17 | leftHipAngle | 116.6128 | 147.7272 | 0.738 | 117.9066 | 163.5119 | 148.2671 | 166.0445 |
| 18 | rightKnee_y | 0.6397 | 0.7304 | 0.730 | 0.6386 | 0.7047 | 0.7344 | 0.6911 |
| 19 | rightAnkle_y | 0.7578 | 0.8510 | 0.722 | 0.7762 | 0.8563 | 0.8274 | 0.8314 |
| 20 | leftKnee_y | 0.6357 | 0.7242 | 0.719 | 0.6404 | 0.6955 | 0.7319 | 0.6950 |

## JUMP SQUAT vs DEEP SQUAT — Key Distinguishing Features

  1. torsoAngle: JS=-78.0430 DS=-92.6423 diff=14.5993
  2. rightHipAngle: JS=121.4407 DS=111.2233 diff=10.2174
  3. rightKneeAngle: JS=122.6196 DS=114.7226 diff=7.8970
  4. leftHipAngle: JS=116.6128 DS=117.9066 diff=1.2938
  5. leftKneeAngle: JS=121.2315 DS=122.2167 diff=0.9852
  6. normStanceWidth: JS=1.0399 DS=0.1705 diff=0.8694
  7. footSepConf: JS=0.8658 DS=0.2400 diff=0.6258
  8. missingLandmarks: JS=0.3541 DS=0.9000 diff=0.5459
  9. rightAnkle_conf: JS=0.8981 DS=0.6329 diff=0.2653
  10. rightKnee_conf: JS=0.9221 DS=0.6879 diff=0.2342

## JUMP SQUAT vs JUMPING JACK — Key Distinguishing Features

  1. leftKneeAngle: JS=121.2315 JJ=172.7635 diff=51.5320
  2. rightKneeAngle: JS=122.6196 JJ=172.2623 diff=49.6427
  3. leftHipAngle: JS=116.6128 JJ=163.5119 diff=46.8991
  4. rightHipAngle: JS=121.4407 JJ=157.6546 diff=36.2139
  5. torsoAngle: JS=-78.0430 JJ=-70.1151 diff=7.9279
  6. normStanceWidth: JS=1.0399 JJ=0.4059 diff=0.6340
  7. footSepConf: JS=0.8658 JJ=0.3000 diff=0.5658
  8. standingConf: JS=0.5351 JJ=0.9033 diff=0.3683
  9. compressionConf: JS=0.4360 JJ=0.0750 diff=0.3610
  10. hipYDirChanges10: JS=0.4510 JJ=0.7733 diff=0.3223
