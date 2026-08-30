# Change safety and documentation maintenance

## High-risk areas

Do not casually edit:

- auth API/repository/controller/gate/token store
- race API/repository/controller
- motion validators, pose detector, camera conversion, or AI Motion Proof screen
- iOS native project/permissions
- `pubspec.yaml` or `pubspec.lock`
- `server/worker/` and D1 migrations

The complete protected-file list is in `AGENTS.md`. A request to “make it work” does not authorize bypassing those boundaries.

## Safe agent workflow

1. Inspect `git status --short --branch` and preserve unrelated work.
2. Read the product model and baseline.
3. Search imports/usages before adding, deleting, or replacing a concept.
4. Declare files and risk before broad work.
5. Make the smallest coherent change.
6. Run focused checks, then the full required checks.
7. Review the diff and generated files.
8. Update the relevant docs if architecture, routes, contracts, or known issues changed.

Do not hide failures by weakening tests, making fake success states, swallowing API errors, or adding fallback mock data to production paths.

## Generated/snapshot files

Treat prior audits, maps, plans, golden images, build output, `.dart_tool`, and Worker temporary output as evidence, not source code. Do not edit generated output to fix a source problem. If generated code is introduced later, document the generator and command here before using it.

## Documentation maintenance rule

When a change affects routes, providers, API fields, migrations, proof semantics, protected files, or release commands:

- update the affected agent guide;
- add the new failure mode to the release checklist if it can break users;
- record whether the note is current behavior, a known defect, or a future plan;
- keep links relative and verify them after moves.

If this guide and `AGENTS.md` disagree, `AGENTS.md` wins. If either disagrees with code, stop and verify the implementation before editing.
