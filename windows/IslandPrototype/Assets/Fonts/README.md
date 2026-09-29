# Portable fonts

The island uses static `Island Text` faces at weights 500/600 and a separate `Island Status` face at 650, all at text optical size 14.
The 650 face is used for the footer status: native captures at 11 points showed that 600 rendered
its strokes lighter than the Mac reference. Footer numerals use Cascadia Bold with an optical
height and baseline adjustment, and opaque text colors avoid WPF's translucent-glyph brightening.
`windows/reference/prepare-island-fonts.py` reproduces them from the same verified Inter source below.
They are separately named and embedded so island text does not inherit the card's display treatment.
Settings uses the same Island Text family, grayscale text rendering, and opaque text colors matched to its dark surfaces.
Its layout follows the Mac provider-selection view; the font outlines are still Inter, not SF Pro.
The island's numeric face remains Cascadia Mono with Consolas fallback; advance calibration happens
when drawing, without modifying or copying either system font. The resolved face still determines
the glyph shapes.

## Share-card faces

These four static faces are derived from [Inter](https://rsms.me/inter/), copyright the Inter Project
Authors, under the bundled [SIL Open Font License](Inter-OFL.txt). Font binaries retain the original
copyright and license metadata. The license is also copied beside the published app's font resources.
They are embedded resources, so users do not need to install fonts and exports work offline.

`Card Text` uses Inter's text optical size and weight 600. `Card Display` uses its display optical size
at weights 400, 500, and 600. The internal family names distinguish the app's static instances from a
user-installed Inter. `windows/reference/prepare-card-fonts.py` reproduces them from a SHA-256-verified
upstream source using fontTools. It stops if that source changes.

`CardTypography` adjusts cap height, baseline, and numeric advances to the Mac card's measured layout.
For the large numbers and milestone text, the renderer rounds convex outline corners; it preserves
curves, counters, and thin joins. These outlines come from Inter, not Apple font files. The existing
Mac card's font files and implementation are unchanged. This improves visual agreement without
claiming that Inter glyphs or Windows rasterization are identical to SF.
