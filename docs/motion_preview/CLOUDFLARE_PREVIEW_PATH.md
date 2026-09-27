# Cloudflare / remote preview path

**Preview ≠ verifier.** Everything on this page decorates the setup card.
The AI Motion Proof camera pipeline is untouched by all of it — never touch
verifier code to make an animation look better.

## What exists today

```
D1 motion_activities.metadata_json.previewSequence   (per-activity JSON)
        │
        ▼
Worker  GET /races/activities            server/worker/src/index.ts ~line 150
        (public, unauthenticated, emits each activity's metadata
         including previewSequence verbatim)
        │
        ▼
Client  MotionCatalogSnapshot.previewSequenceFor(activityId)
        lib/features/races/data/motion_catalog.dart
        (fetched via motionCatalogProvider)
        │
        ▼
        RemotePreviewSpec.tryParse(json)          remote_movement_preview.dart
        validates: rig ∈ {front,side} · durationMs > 0 · ≥2 keyframes
        front frames → RivePoseFrame.fromJson
        side  frames → SideRigPose.fromJson
        │
        ▼
        RemoteFrontKeyframeSequence / RemoteSideKeyframeSequence
        — replaces the bundled sequence for that activity
        invalid/missing → bundled sequence (always safe fallback)
```

## What remote previews can do

- Replace the **keyframe list and duration** for any preset — no app release
  needed.
- Choose the rig per activity (`rig: "front"` or `"side"`).
- Give `MotionActivityType.remote` activities an animation they otherwise
  lack.

## What remote previews cannot do today

- Ship new `.riv` assets — rigs are bundled in `assets/animations/preverify/`.
- Change rig bindings, interpolation, or rendering — those are compiled in
  `RivePoseController` / `RiveMovementPreview`.
- Affect verification in any way.

## Release/package boundary (Agent 4 territory — do not touch)

`motion_package_store*.dart`, `motion_package_installer.dart`, the Worker
`/motion/releases/...` asset routes, and `server/worker/src/domain/
motionAssets.ts` deliver **verifier packages** (models, test vectors). They
are a separate system from `previewSequence`. Previews are catalog metadata;
packages are verifier payloads. A teammate fixing previews has no reason to
edit either side of that boundary, and must not "borrow" the package
installer to deliver animations.

## Editing preview metadata safely

The only Worker-adjacent change a preview task can ever need is the value of
`previewSequence` inside an activity's `metadata_json` — data, not schema.
Do not change routes, release semantics, checksums, or `motionAssets.ts`.
