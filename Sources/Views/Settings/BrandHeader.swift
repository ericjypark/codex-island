import SwiftUI
import AppKit

/// The Settings window's brand row. Replaces the empty traffic-light
/// gutter and the duplicate "NOW" stats from the previous design.
///
/// Three elements left to right: the CodexIsland brand mark (the curly-
/// brace island glyph that ships in `Resources/codexisland_logo.png`,
/// rendered as a template image so it picks up the cobalt accent), the
/// app name + tagline, and a version pill on the right.
struct BrandHeader: View {
    let version: String

    private var logo: NSImage? {
        Bundle.main.url(forResource: "codexisland_logo", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            mark

            VStack(alignment: .leading, spacing: 2) {
                // 14pt semibold — brand wordmark, intentionally one step above providerTitle (13).
                Text("CodexIsland")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.15)
                    .foregroundStyle(.white.opacity(0.92))
                // 11pt regular — tagline reads quieter than label (11 medium).
                Text("Your AI usage limits, living in your notch.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer(minLength: 8)

            // 11pt medium mono — no token (bodyNumber is semibold); version pill keeps medium
            // weight to balance the wordmark without competing.
            Text("v\(version)")
                .font(.system(size: 11, weight: .medium).monospaced())
                .foregroundStyle(.white.opacity(0.34))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(.white.opacity(0.04))
                )
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 22)
    }

    @ViewBuilder
    private var mark: some View {
        if let logo {
            // The shipped PNG is opaque RGB (no alpha channel) — black
            // glyph on a white background. `.template` renders a solid
            // rectangle because there's nothing transparent to mask.
            // Invert so the glyph becomes white and the background black,
            // then blend `.lighten` over the dark settings surface so the
            // inverted-black background drops out and only the white glyph
            // remains.
            Image(nsImage: logo)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 26, height: 26)
                .colorInvert()
                .blendMode(.lighten)
                .opacity(0.92)
                .shadow(color: IslandColor.cobalt.opacity(0.35), radius: 6)
        } else {
            // Fallback if the resource is missing in the bundle: a plain
            // cobalt-glowing dot so the header layout doesn't collapse.
            Circle()
                .fill(IslandColor.cobalt)
                .frame(width: 10, height: 10)
                .shadow(color: IslandColor.cobalt.opacity(0.85), radius: 5)
                .frame(width: 26, height: 26)
        }
    }
}
