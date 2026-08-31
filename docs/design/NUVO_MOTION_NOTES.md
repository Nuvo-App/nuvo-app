# Nuvo Motion Notes

## Navigation

Pushed pages support an app-wide back gesture: begin a horizontal drag within
28 logical pixels of the left edge and release after the page has moved 76
pixels, or with a strong rightward velocity. The gesture calls the existing
router pop path, so it preserves the same route stack and auth behavior as a
back button.

Horizontal gestures that begin inside the page remain owned by that page. This
keeps Arena board paging and other content interactions independent from back
navigation.

## Page transitions

Standalone pages use a short slide/fade transition with a small scale change
for depth. The motion is intentionally quick and tactile; tab changes remain
instant so the bottom navigation does not feel delayed.

## Selection motion

Movement choices use animated selection state and a navy structural outline.
Grey remains reserved for quiet separators and non-structural dividers.
