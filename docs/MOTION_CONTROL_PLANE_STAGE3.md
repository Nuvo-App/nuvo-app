# Motion Control Plane — Stage 3 Evidence

Date: 2026-09-17

## Production contract

The Flutter client now consumes `GET /races/activities` as a public,
ETag-revalidated catalog. The bundled `motion_activity_catalog.dart` remains
the first-launch and offline fallback. Unknown engines are not inferred or
mapped to a local verifier.

Remote catalog entries are converted to display/create metadata only when the
release is supported, has an immutable release ID and checksum, declares the
known `native_v1` engine, and all required client capabilities are present.
The local pose/runtime implementation remains the executable trust boundary.

## Cache behavior

- Native: atomic last-known-good file in the application support directory.
- Web: last-known-good local storage entry.
- Refresh: one repository request with `If-None-Match`; no per-frame or
  per-build fetch loop.
- Failure: retain valid cache; corrupted cache falls back to the bundled
  catalog; no valid catalog is erased.

## Evidence

`test/motion_catalog_test.dart` covers:

1. Dynamic remote IDs preserve their stable server identity.
2. Unknown engines remain hidden instead of selecting a guessed verifier.
3. A failed refresh retains last-known-good catalog data.
4. Corrupt cache data falls back to the bundled catalog.

Worker ETag support is covered by the existing catalog endpoint contract and
the Worker typecheck/full suite. No simulator or real-device action was used.
