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
