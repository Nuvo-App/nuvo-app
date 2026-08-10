# Air-Detection Gap Summary — Updated After Flight Primitive

> **Status:** The `AirborneStateTracker` flight primitive is now implemented
> and registered as `FactoryPrimitive.airDetection`. It is **not yet
> attached** to any production movement. This document re-evaluates the
> movements whose blocker included `airDetection` in the original
> 100-movement classification.

## Primitive Now Available

| Primitive | Implementation | Location |
|-----------|---------------|----------|
| `airDetection` | `AirborneStateTracker` class | `lib/features/races/ai/airborne_state_tracker.dart` |
| `FactoryPrimitive.airDetection` | Capability inventory enum | `lib/features/races/ai/preset_motion/factory_capabilities.dart` |

**Capabilities of the primitive:**
- Baseline-relative ankle Y detection (no raw threshold)
- Body-scale-relative via `torsoHeight`
- Both ankles must rise (rejects one-foot lifts)
- Frame-count-based (no wall-clock dependency)
- Baseline EMA adaptation when grounded
- Frozen baseline during airborne phase
- Fail-safe on missing/low-likelihood ankles

---

## Updated Air-Blocked Movement Table

| Movement | Old Status | New Status With Air Detection | Other Missing Primitives | Ready For Next Batch? |
|----------|-----------|-------------------------------|-------------------------|----------------------|
| **Tuck Jumps** | NEEDS_PRIMITIVE | NEEDS_PRIMITIVE (partial unlock) | `kneeToChestProximity` (both knees above hip level) | **NO** — needs knee-to-chest signal |
| **Skater Jumps** | NEEDS_PRIMITIVE | NEEDS_PRIMITIVE (partial unlock) | `lateralWeightShift` (hip X relative to landing ankle X), alternating-side state machine | **NO** — needs lateral weight shift |
| **Lateral Bounds** | NEEDS_PRIMITIVE | NEEDS_PRIMITIVE (partial unlock) | `lateralWeightShift` (hip X relative to landing ankle X), alternating-side state machine | **NO** — needs lateral weight shift |
| **Frog Jumps** | NEEDS_PRIMITIVE | NEEDS_PRIMITIVE (partial unlock) | `handToFootContact` (wrists near ankles during tuck) | **NO** — needs hand-to-foot proximity |
| **Simulated Jump Rope** | NEEDS_PRIMITIVE | NEEDS_PRIMITIVE (partial unlock) | `circularArmMotion` (circular pattern in wrist trajectory over time) | **NO** — needs circular arm trajectory |
| **Heisman Jumps** | NEEDS_PRIMITIVE | NEEDS_PRIMITIVE (partial unlock) | `lateralWeightShift` (hip X relative to landing ankle X), alternating-side state machine | **NO** — needs lateral weight shift |
| **Jump Squats** | CUSTOM | CUSTOM (airDetection now available) | `multiPhaseSequence` state machine (squat→jump→land, 3-phase beyond START→ACTIVE→START) | **NO** — needs multi-phase state machine |
| **Lunge Jumps** | CUSTOM | CUSTOM (airDetection now available) | `multiPhaseSequence` state machine (lunge→jump→switch→land) | **NO** — needs multi-phase state machine |

---

## Analysis

### Movements That Benefit Most From Air Detection

The `airDetection` primitive was a **hard blocker** for 6 movements
(tuck jumps, skater jumps, lateral bounds, frog jumps, simulated jump
rope, heisman jumps) and a **soft blocker** for 2 movements (jump
squats, lunge jumps). With air detection now available:

- **6 movements** have their air-detection blocker resolved but still
  require additional primitives (lateral weight shift, knee-to-chest,
  hand-to-foot, circular arm motion).
- **2 movements** (jump squats, lunge jumps) had airDetection listed as
  a missing signal but were classified as CUSTOM (not NEEDS_PRIMITIVE)
  because the primary blocker was the multi-phase state machine, not
  the air signal itself. Air detection improves their fidelity but
  does not unblock them alone.

### Remaining Primitive Gaps

| Primitive | Movements Waiting | Type |
|-----------|------------------|------|
| `lateralWeightShift` | Skater Jumps, Lateral Bounds, Heisman Jumps | Numeric (hip X relative to ankle X) |
| `kneeToChestProximity` | Tuck Jumps | Boolean (both knees above hip level) |
| `handToFootContact` | Frog Jumps | Boolean (wrists near ankles) |
| `circularArmMotion` | Simulated Jump Rope | Temporal trajectory |
| `multiPhaseSequence` | Jump Squats, Lunge Jumps | State machine (3+ phases) |
| `alternatingSideStateMachine` | Skater Jumps, Lateral Bounds, Heisman Jumps | State machine (alternating landings) |

### Next-Batch Readiness

**No movement is fully ready for the next batch based on airDetection
alone.** The closest candidates are:

1. **Jump Squats** — needs only `multiPhaseSequence` (airDetection now
   available). If a multi-phase state machine is built next, jump squats
   become implementable.
2. **Lunge Jumps** — same as jump squats (needs `multiPhaseSequence`).
3. **Tuck Jumps** — needs `kneeToChestProximity` (a per-side boolean
   signal). This is a smaller primitive than lateral weight shift.

### Recommended Next Primitive (Not Implemented)

Based on unlock count and implementation complexity:
1. `multiPhaseSequence` — unlocks 2 movements (jump squats, lunge jumps)
2. `kneeToChestProximity` — unlocks 1 movement (tuck jumps)
3. `lateralWeightShift` — unlocks 3 movements (skater, lateral bounds,
   heisman) but requires alternating-side state machine too

---

## Confirmations

- **No new movements were added** in this task.
- The `airDetection` primitive is registered in the factory inventory
  but **not attached** to any production movement.
- Existing movement behavior (all 11 preset movements) is unchanged.
- No Teach Nuvo, Arena, picker, or D1 schema changes.
