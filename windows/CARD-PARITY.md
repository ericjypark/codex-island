# Share-card design corrections

The Windows card now has dedicated embedded text and display fonts, rounded numeric outlines,
explicit headline weight, and layout values measured from the existing SwiftUI card. This removes
the previous dependence on Segoe UI and the accidental regular-weight headline. The Mac production
card is the reference and was not edited for this work.

The feed, square, and story cards use the Mac's text baselines and section heights. The square API
amount now fits the source's 82-point line box. Legend rows are 15 points with 10-point spacing;
the footer is 44.5 points tall; the chart header and canvas are separated by the source's measured
24-point offset. The footer uses a drawn arrow. Long signatures retain their font size and truncate
at the trailing edge, sharing the date row's available width.

The portable faces are static Inter instances. Large numeric glyphs use the source card's measured
advances and cap height. Convex-corner cuts round terminals without eroding strokes or changing
counters. Cached outlines are reused across preview redraws and exports. Details, licenses, and
reproduction instructions are in [Assets/Fonts/README.md](IslandPrototype/Assets/Fonts/README.md).
Apple font files and glyph outlines are not embedded. Inter's glyph shapes and Windows rasterization
still differ from SF; these changes do not establish pixel-identical typography.

## Verification

On Windows 11 ARM in Parallels:

- `tests/run-card-render.ps1`: 30 checks passed across the six format/metric combinations and seven
  additional cases. The embedded font faces resolve from the application resources. Full-resolution
  dimensions and card margins hold for White/Black/Blue, sub-cent amounts, very large amounts,
  partial pricing, unpriced usage, Korean signatures, and long signatures.
- `tests/check-card-preserved.ps1`: all 12 installed-app interaction checks passed on build
  `077a0186-8459-4d0c-873e-ba8a5a58da2a`. These cover opening the studio, all six PNG exports,
  Fit/Actual size, signature length, copying the caption and image, and disabling export when no
  providers are selected. The wrapper restores the prior preferences and live/demo mode.
- Fixed-fixture renders are under `artifacts/card-after/`. For all six formats, the background,
  final chart marker, and first legend-dot position agree with the Mac reference to within two
  sRGB channel levels at the measured coordinates. Color profiles are honored before comparing
  the Mac and Windows PNGs. These anchor checks are not a visual similarity percentage.

`reference/measure-cards.py` instruments a separate copy of `WeeklyUsageCard.swift` to record actual
SwiftUI layout frames. It writes only the Windows reference artifacts. The fixed fixture retains
September 5-11 so typography and layout comparisons remain stable across midnight. Installed-app
exports use the card studio's current calendar period and can therefore contain different dates.

Rendered results were inspected for all six combinations and the edge cases. Exact font identity,
all possible personal signatures, and differences in system color-management/rasterization remain
outside the verified equivalence above.
