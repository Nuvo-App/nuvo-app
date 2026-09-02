# NuvoMetricHead — few-shot motion discrimination on top of frozen MotionBERT

Status: DESIGN. Blocked on real `datasets/nuvo_motion/` fixtures from device
sessions (see `replay_session.py --to-fixture`). Do not wire into the app until
a real failed session replays correctly offline with the trained head.

## Architecture

    MotionBERT release_action backbone  (FROZEN)  -> per-frame reps (T, 17, 512)
        |
        v
    NuvoMetricHead                                -> compact motion embedding (D~128)
        - temporal model: pick by benchmark
            a) small temporal transformer (2-4 layers, D_model 256)
            b) 1D temporal conv stack
            c) attention pooling over frames
            d) temporal pyramid (0-25/25-50/50-75/75-100 pooled + concat)
        - also feed embedding velocity / delta channels
        - L2-normalised output

The head is trained OFFLINE for generic few-shot motion identity. It is never
trained on a user's 3 examples — those stay the support set at inference.

## Episodic training (simulates Teach Nuvo)

    episode:
      support  = A1 A2 A3        (3 demos of one movement)
      positive = A4              (held-out performance of A)
      negatives = B C D ...      (other movements, incl. HARD negatives)

    losses to benchmark (report measured separation, not vibes):
      - prototypical  (ProtoNet)
      - supervised contrastive (SupCon)
      - triplet / hard-negative mining

## Hard negatives (must be in every batch)

    arm raise vs wave
    squat vs lunge
    left-side vs right-side variants
    same pose set, different order

## Pipeline

    1. datasets/nuvo_motion/*  +  synthetic bank  -> episodes
    2. train_metric_head.py                       -> head.pt
    3. eval_metric_head.py                        -> per-fixture: positive accept,
                                                    negative reject, margin
    4. bench vs the current handcrafted matcher   -> must beat it on real fixtures
    5. export_head_onnx.py                        -> head.onnx (bundled asset)
    6. Dart: chain onnx encoder -> onnx head -> existing multi-reference matcher
       (matcher logic unchanged; only the embedding it consumes changes)

## Acceptance gate (before app wiring)

    my real failed session:
      3 supports -> learn
      my failed 4th attempt -> ACCEPT
      wrong movements from the same session -> REJECT
