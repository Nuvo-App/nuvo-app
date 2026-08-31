# Custom-movement capture fixtures (Teach Nuvo)

Real device captures, for offline replay of the builder + runtime.

## How to add one

1. Run the app with `--dart-define=NUVO_DIAGNOSTICS=true`.
2. Teach a movement (Compete -> Start a race -> "Don't see your movement?" -> Teach Nuvo).
3. On the summary screen, open the debug panel, tap **Copy debug report**.
4. Save the JSON here as `<movement>_<n>.json`. The `calibrationFixture` key
   replays through `CustomPoseSequenceBuilder`; `learnedSpecFixture` +
   the demo frames replay through `CustomPoseSequenceRuntime`.

## Why

Threshold / normalization tuning must be driven by real captures, not synthetic
poses (see docs/agents/07 s9). These are that dataset. Also the seed for the
eventual learned-encoder training set (docs/agents/13).
