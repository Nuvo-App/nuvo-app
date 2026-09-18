# Basketball object-interaction goal

The first Nuvo object-interaction goal is **shoot a basketball into a hoop**.
It is internal-only until the phone can produce object dots and the candidate
passes replay and physical-device gates.

## Dot-only contract

The phone keeps the camera frame local. The motion data plane emits:

- human pose landmarks for the wrists and body context;
- a `ball` object dot with normalized center, scale, and likelihood;
- a `hoop` object dot with normalized rim center and likelihood;
- timestamps for deterministic velocity and plane-crossing calculations.

No raw video is required by the release or the telemetry artifact.

## Composition graph

```text
ready -> released -> ascending -> descending -> made
   \                                         -> missed
    \---------------------------- timeout --/
```

The first release is `object_composition_v1`. Its bounded declarative fields
control hand proximity, release distance, vertical velocity, hoop-plane
tolerance, made radius, and timeout. The local runtime performs the event
decisions; the Worker only distributes the immutable release and records
versioned evidence.

## Acceptance boundary

Three demonstrations can initialize a candidate, but promotion also requires
held-out made shots and negative examples: airballs, rim/out shots, fake
releases, occluded ball, and a ball passing near the hoop without scoring.
The activity remains internal until those replay and physical-device gates
pass.
