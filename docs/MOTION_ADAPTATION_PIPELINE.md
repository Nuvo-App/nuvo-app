# Nuvo motion adaptation pipeline

The app already records each verification attempt locally and uploads a
compressed motion-session artifact without blocking the camera UI. The Worker
now turns those uploads into release-scoped signals without changing a live
session.

```text
attempt -> R2 artifact + D1 index
        -> release-linked aggregate metrics
        -> failure-cluster signal
        -> deterministic replay runner creates a report
        -> Worker guardrails validate the report
        -> draft -> canary -> stable
        -> catalog pointer changes -> compatible apps refresh
```

## Safety boundary

The Worker does not infer or publish a verifier from one attempt. It may
identify a cluster and retain feedback, but a proposed spec must pass the
strict schema validator and a held-out deterministic replay report. Stable
promotion requires a passing evaluation. Every release is immutable; rollback
only moves the channel pointer.

The Worker distributes declarative verifier specifications only. It never
downloads or executes Dart, native code, arbitrary model binaries, or an LLM in
the live camera loop.

## Internal workflow

All of these routes require `X-Internal-Key`:

- `GET /internal/motion/adaptation/signals?activityId=...&releaseId=...`
- `POST /internal/motion/releases/drafts`
- `POST /internal/motion/evaluations`
- `POST /internal/motion/releases/:releaseId/promote`
- `POST /internal/motion/channels/:activityId/:channel/rollback`

The replay runner remains outside the live Worker request path. It reads
versioned artifacts, evaluates a candidate against the same held-out dataset as
the baseline, and submits the machine-readable report. A failing report is
stored as evidence and cannot validate a release.

## Cloud rollout

Apply migration `0017_motion_adaptation_pipeline.sql`, deploy the Worker, and
then operate the draft/evaluation/promotion workflow. Existing clients keep
their current behavior; compatible clients adopt a promoted release after the
normal catalog refresh. The Worker changes are not live until the migration and
Worker deployment are explicitly performed in the target Cloudflare account.
