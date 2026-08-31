# Nuvo agent documentation

This is the operational map for agents working on Nuvo, an app that turns real-life goals into leaderboard races with a crew. Read this before changing code.

## Start here

1. Read the repository rules in [`/AGENTS.md`](../../AGENTS.md).
2. Read the product source of truth in [`../NUVO_PRODUCT_MODEL.md`](../NUVO_PRODUCT_MODEL.md).
3. Read the known-good baseline and rollback notes in [`../BASELINE_BEFORE_PRODUCT_SKELETON.md`](../BASELINE_BEFORE_PRODUCT_SKELETON.md).
4. Read [`00-start-here.md`](00-start-here.md) for the current architecture and workflow.
5. Read the guide matching the work:
   - UI or navigation: [`01-app-architecture.md`](01-app-architecture.md) and [`02-ui-and-design-system.md`](02-ui-and-design-system.md)
   - auth or API integration: [`03-data-auth-and-backend.md`](03-data-auth-and-backend.md)
   - races, proof, movement, or camera: [`04-race-and-ai-motion.md`](04-race-and-ai-motion.md)
   - tests, builds, or release: [`05-testing-and-release.md`](05-testing-and-release.md)
   - agent change safety: [`06-change-safety-and-maintenance.md`](06-change-safety-and-maintenance.md)
   - camera-AI direction / non-negotiables: [`07-ui-refinement-and-camera-ai-migration.md`](07-ui-refinement-and-camera-ai-migration.md)

## Fast-onboarding set (read these to stop re-deriving context)

| Doc | Use it for |
|---|---|
| [`08-codebase-navigation.md`](08-codebase-navigation.md) | where any file/provider/flow lives; the 4-layer rule; file-naming glossary; "trace a feature in 3 greps" |
| [`09-widget-and-token-reference.md`](09-widget-and-token-reference.md) | how to use the shared widgets & tokens (buttons, empty/error states, podium, colours, shadows, responsive, clipped-corner fix) |
| [`10-pitfalls-and-fixes.md`](10-pitfalls-and-fixes.md) | **every issue this codebase has hit** — symptom → root cause → fix → the rule that stops it recurring. Read the relevant section before touching networking, auth, routing, layout scaling, or tests. |
| [`11-adding-a-feature.md`](11-adding-a-feature.md) | step-by-step recipes: tweak a screen, add a field / API call / screen / widget / proof type; the pre-commit checklist |
| [`12-screen-reference.md`](12-screen-reference.md) | every route/screen: file, primary action, states, shared widgets, data source |
| [`../NAVIGATION_MAP.md`](../NAVIGATION_MAP.md) | the route table, navigation graph, and which verb (`go` / `push` / `pushReplacement` / `safePopOrGo`) |

## Source-of-truth rule

The code wins over a snapshot document. Existing audits and maps are useful orientation, but they may describe an older branch. If a document conflicts with the current imports, route table, API implementation, or tests, verify the code and update the relevant documentation after the change.

## Current repository facts

- Client: Flutter/Dart, Riverpod, GoRouter, Material 3.
- Backend: Cloudflare Worker + Hono + D1 under `server/worker/`.
- Auth: email-code flow plus Google/Apple integrations in the current client/backend paths.
- AI Motion Proof: camera frames, ML Kit pose detection, movement-specific validators, and real verification. It must never be faked or bypassed.
- Current public API base is compile-time configurable with `NUVO_API_BASE_URL`; the default is the deployed Worker URL in the API clients.
- There is no permission to assume that mock/demo data represents production behavior.

## Before any edit

Declare the files you will read and edit, the behavior change, what will not change, and the risk level. Keep changes scoped. Do not casually touch auth, camera/ML, race state, backend contracts, native iOS files, or dependencies.

## Before release

Run the checks in [`05-testing-and-release.md`](05-testing-and-release.md), inspect the diff, confirm no secrets or local vars are staged, and verify the target environment explicitly. Documentation alone does not authorize a deploy.
