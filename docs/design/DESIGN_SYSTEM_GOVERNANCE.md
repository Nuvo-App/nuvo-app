# Design system governance — keeping the Nuvo look from drifting again

The audit in [`DESIGN_GUIDE_AUDIT_2026-09.md`](DESIGN_GUIDE_AUDIT_2026-09.md)
didn't happen because the design system is bad — it's because a good system
(`NuvoColors`, `nuvo_button.dart`, `NuvoRadii`, `NuvoSpacing`) has no
enforcement, so every screen written under deadline reaches for
`Color(0xFF...)`, `TextButton(...)`, or `BorderRadius.circular(14)` instead.
This doc is the checklist and guardrails that keep the
[`SCREEN_REMEDIATION_PLAN.md`](SCREEN_REMEDIATION_PLAN.md) fix from being
undone the next time someone ships a screen fast.

---

## 1. The rules, restated as things you can check

Pulled directly from the design guide, made checkable:

1. **Color** — every color on screen is one of: `NuvoColors.{blue, green,
   red, tan, yellow, orange, navy, white}` (or their `*Shadow`/`*Bright`/
   `*Surface` variants), a text/icon color from the theme, or an explicitly
   documented exception (third-party brand mark, a technical requirement
   like QR contrast). No bare `Color(0x...)`, no `Colors.white`/
   `Colors.black` as a full-surface fill.
2. **Buttons** — every tappable action is `NuvoPrimaryButton`,
   `NuvoOutlineButton`, `NuvoTertiaryButton`, `NuvoSuccessButton`,
   `NuvoDangerButton`, `NuvoBackButton`, or `NuvoIconAction`. No
   `ElevatedButton`/`TextButton`/`OutlinedButton`/`FilledButton` in
   `lib/features/**`.
3. **Shapes** — radii come from `NuvoRadii.*`, spacing from
   `NuvoSpacing.*`/`NuvoTokens.space*`. A raw numeric literal in a
   `BorderRadius`, `EdgeInsets`, or `SizedBox` in screen code is a smell,
   not an automatic violation — flag it in review, don't auto-fail on it
   (some one-off pixel nudges are legitimate).
4. **Interactivity** — any screen with a list, a loading state, or a
   success/reward moment uses the shared entrance/loading treatment
   (`NuvoEntrance`, `NuvoLoadingIndicator` — see the remediation plan Batch
   2) rather than a bare `CircularProgressIndicator()` or a static list with
   no reveal.

## 2. Enforcement — cheapest first

Ordered by cost to build vs. how much drift it actually stops. Do 2.1
regardless of anything else; the rest are a judgment call on effort.

### 2.1 `analysis_options.yaml` custom lint (do this first)

Flutter's built-in analyzer can't natively ban "`Color(0x...)` outside
`lib/core/theme/`" — that needs a `custom_lint` plugin rule (a small Dart
package that runs as part of `flutter analyze`). This is the single highest-
leverage guardrail because it fails CI/local analyze, not just PR review:

- Rule 1: no `Color(0x...)` / `Colors.white` / `Colors.black` literal
  outside `lib/core/theme/**` and an explicit allow-list (third-party brand
  colors, get an `// nuvo-lint-ignore: brand-color` marker convention).
- Rule 2: no `ElevatedButton(`/`TextButton(`/`OutlinedButton(`/
  `FilledButton(` constructor calls outside `lib/core/widgets/` and
  `lib/core/theme/` (the theme file legitimately configures their default
  style; screens should never construct one directly).

If a custom lint package is more than you want to maintain, a **pre-commit
grep hook** (see 2.2) gets ~80% of the value for a fraction of the effort —
recommended as the pragmatic starting point, with the lint plugin as a later
upgrade once the team decides it's worth it.

### 2.2 Pre-commit / CI grep guard (pragmatic starting point)

A shell script, run in CI and optionally as a local pre-commit hook, that
`grep`s the diff (or the whole `lib/features` tree) for the same patterns as
the audit and fails the build if a *new* violation appears outside an
allow-list file. Doesn't need a Dart package — a five-line `bash` script
using `git diff --name-only` + `grep -n` is enough to catch 90% of what
caused this audit. Weaker than 2.1 (easy to bypass locally with
`--no-verify`, doesn't understand Dart syntax so needs some regex care around
strings/comments) but ships same-day.

### 2.3 PR checklist (cheapest, weakest on its own — pair with 2.1 or 2.2)

Add a section to the PR template:

```markdown
## Design system checklist
- [ ] No raw `Color(0x...)` / `Colors.white` / `Colors.black` outside `lib/core/theme/`
- [ ] No `ElevatedButton`/`TextButton`/`OutlinedButton`/`FilledButton` — used a `Nuvo*Button`
- [ ] Radii/spacing use `NuvoRadii`/`NuvoSpacing` tokens, not raw numbers
- [ ] Loading/empty/success states use the shared components, not bare defaults
- [ ] If this is a "reward" or first-impression moment: does it feel as significant as the guide asks for?
```

A checklist alone relies on the author remembering to check it honestly —
treat it as a review aid, not a substitute for 2.1/2.2.

### 2.4 Golden/widget tests for the shared components themselves

Not a guard against *new* screens drifting, but a guard against the shared
components (`nuvo_button.dart`, `NuvoAmbientGlow`, `NuvoLoadingIndicator`)
silently changing shape/color over time. One golden test per component
variant (Primary/Outline/Tertiary/Success/Danger × default/pressed) is
enough — this is what makes it safe to say "every screen inherits the fix"
in the remediation plan without re-checking every screen by hand later.

## 3. New-component checklist (for whoever builds Batch 2's shared components)

Before adding *any* new visual primitive to `lib/core/widgets/`:

- Does an existing component already do this? (Check `nuvo_button.dart`,
  `nuvo_board_components.dart`, `nuvo_avatar.dart`, `NuvoEmptyState` before
  writing a new one.)
- Does it take its colors exclusively from `NuvoColors`/`NuvoSemanticColors`
  — no locally-defined `Color(0x...)` constants, even "just for this
  component" (this is exactly how `bottom_nav.dart`'s `_kTrackNavy` and
  `_kTrackActiveBlue` happened)?
- Does it pick a 3D-vs-2D stance explicitly, rather than leaving it to the
  caller to guess? (A component that's "sometimes elevated, sometimes not"
  based on a boolean flag with no documented rule is how the original
  Ghost/Tertiary confusion started.)
- Is there a one-line doc comment stating which guide rule it implements
  (e.g. "3D button per NUVO_DESIGN_GUIDE — main color + shadow-color outline
  + offset shadow") so the *reason* survives the next refactor?

## 4. When the guide itself needs to change

The guide (colors, button rule, "fun and playful" mandate) is a product
decision, not an engineering one. If a screen seems to need an exception:

1. Write the specific conflict down (which rule, which screen, why it
   doesn't fit) — don't just add a one-off `Color(0x...)` and move on.
2. Get an explicit yes from whoever owns the design guide before shipping
   the exception.
3. If it's approved, add it to the allow-list in 2.1/2.2 *with a comment
   citing the decision*, so the next audit doesn't re-flag it as drift.

This is the same failure mode that produced the off-palette blues in
`splash_screen.dart`/`welcome_race_builder_screen.dart` — nobody decided
"we need a second blue," it just accumulated one gradient stop at a time.
The rule above exists to make that decision visible instead of silent.

## 5. Keeping `NUVO_DESIGN_SYSTEM.md` from going stale again

`NUVO_DESIGN_SYSTEM.md`'s hex table is what went stale and caused confusion
this round (it referenced colors that matched neither the pre- nor
post-guide palette). Going forward: **`app_colors.dart` is the source of
truth; docs quote it, never duplicate the literal hex values.** If a doc
needs to show a color for reference, link the constant name
(`NuvoColors.success`) instead of pasting `#2ECC40` — a renamed/re-hexed
token then makes the doc correct by construction instead of silently wrong.
