# Island typography, effects, and motion

The Mac implementation remains the visual reference. This pass refines the existing Windows island;
it does not establish identical platform rendering or change the Mac app.

## Typography

The island embeds static Inter text faces at weights 500 and 600, plus a separate 650 status face. Provider titles, labels,
and supporting copy have consistent metrics without requiring a user-installed proportional font.
Settings retain their native Windows font; the share card keeps its separately tuned typography.
The font source, license, and reproducible build are documented in
[Assets/Fonts/README.md](IslandPrototype/Assets/Fonts/README.md).

Numeric and caption text retains Cascadia Mono with Consolas fallback. Its horizontal advance is
calibrated from the resolved font to the reference's measured 0.6181640625 em. Cost amounts and their
currency/unit labels share a baseline. Plan chips use bold, and proportional section labels have the
reference's tracking. Model names truncate at text-element boundaries. Large cost digits fit their
tile down to half size before ellipsis; day-detail values fit their 82-DIP column down to 0.72 scale.
Accessible descriptions retain the full values.

In four controlled 2x Cost samples, the strong colored digit widths changed from 124/211/170/125 pixels
to 130/223/179/132. The Mac widths are 130/224/180/131. These horizontal measurements describe
those four fixtures only; glyph shapes still differ.

## Vertical alignment

Text drawn from an arbitrary font-box top did not align consistently across the proportional and
monospaced faces. The island now uses explicit baselines for mixed-size rows and measured line-box
centers for chips, reset details, model rows, and footer controls. Width fitting preserves the baseline.
Both text families use the reference cap-height scale, including retained glowing cost text.

The reference measurements come from the existing SwiftUI views through a temporary layout wrapper
that preserves each child's size and first-text-baseline alignment. For the 800-point panel, the
Bar, Stepped, and Spark chart heads have baselines at 98, 94, and 79 points from the panel top.
Numeric values and percent signs share 129.5; Cost values and units share 140. Chart captions and
meter positions follow the source stack's line heights and spacing.

The overview value and unit share a baseline, and the activity caption keeps the source bottom
alignment. Calendar month captions use the monospaced caption role. The day-detail strip aligns
its label and value rows separately. Footer share text uses the source's 11-point button role,
and the drawn share icon fits the same row. Reset details use 26-point rows with 4-point gaps.

`python3 reference/measure-island.py` records reference frames in the isolated Mac measurement bundle.
`python3 tests/compare-island-refinement.py --alignment` builds an 11-panel comparison against the
previous Windows pass and Mac reference. Small glyph-edge and antialiasing differences remain.

## Effects and motion

The footer uses the Mac status control's structure: a six-point teal dot, six-point gaps, a muted
`Synced` label, and a brighter monospaced elapsed time. Idle, syncing, connection, local-record-error,
and demo states retain a dim dot. The label and age are separately styled; native captures exposed
WPF's brightening of translucent glyph brushes, so their resting ink colors are explicitly 140 and
184 on the black surface. The status font and small numeral metrics are calibrated independently.

Only selected providers affect the status, and all selected timestamps must exist before the footer
can say `Synced`. The oldest selected timestamp determines the age. Usage refreshes quota data;
Cost and Overview refresh history. Syncing disables pointer, keyboard, and retained automation
actions. The whole group has hover, focus, and press feedback.

The dot breathes through retained opacity and scale animations. Its one-second clock redraws only
the status when its text changes, without rebuilding the island. Both stop when the panel is hidden
or collapsed; Reduce Motion and Low Power stop the pulse while allowing the visible age to advance.
The black panel shadow is behind the blue halo, matching the Mac's nested shadow order.

Numeric meter fills now carry the Mac's provider-colored glow. The actual-value bars in Cost also
carry their source glow. Retained effect labels carry their own page transforms, keeping Usage and
Cost attached to their respective pages while both are visible during a swipe. Text is still drawn
natively, with no whole-panel bitmap cache. The expanded panel's black shadow uses a downward offset
and the source's 0.5 opacity.

Chart changes use the same strong easing as the Mac's 220 ms transition. Reversing a day-detail reveal
starts from its displayed progress. Closing uses the source's 200 ms curve and releases its animation
clock. Enabling Reduce Motion settles active page, style, counter, detail, and reveal motion; changing
the Windows client-area-animation setting follows the same path. Re-entering during a partially
completed hide retains the displayed silhouette instead of resetting to the compact dimensions.

The native Mac backdrop material, exact blur/shadow kernels, symbol shapes, and physical presentation
timing remain separate gaps. This pass does not substitute a flat translucent outline for backdrop blur.

## Verification

`reference/render.sh` generates current Mac views from the actual SwiftUI source in a separate bundle.
`tests/run-visual-render.ps1` captures all 11 island views using the same freshly exported fixture in
an isolated WPF window. It does not change the installed application's data or preferences. Its
additional checks cover embedded font weights, interrupted detail animation, reduced motion during
active transitions, meter placement during page movement, and large USD/CHF/KRW values.

The existing live-render suite covers account/error states, recorded history, reset credits, and the
copied Mac quota trajectory. Counter-render checks cover active Low Power changes and native text
retention; swipe-render checks cover retained calendar drawing, selection, targets, and settled pixels.
Raw results and build identifiers are written under ignored `artifacts/`.

`tests/run-live-render.ps1 -FooterOnly` checks native footer rendering, font resolution, relative-time
updates without island redraws, input/loading states, localization, and timer lifetimes.
`tests/check-footer-ui.ps1 -Snapshot <history snapshot>` verifies the installed history profile,
refresh routing, and age progression, then captures normal and hovered footer states.

All measurements in this pass are from Windows 11 ARM in Parallels at 200% scaling. Other scales,
physical Windows hardware, and complete intermediate-frame parity are not established by these checks.
