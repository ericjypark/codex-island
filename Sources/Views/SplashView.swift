import SwiftUI
import AppKit

/// Launch sequence: pure desktop blur ramps in, brand logos grow in at
/// center, a Continue button appears and waits for the user. On click,
/// the icons travel to the notch position (matching IslandRootView's
/// logo overlay coordinates exactly) and the splash hands off to the
/// island window.
///
/// "Pure blur, no frost" — the backdrop is CALayer backgroundFilters +
/// CIGaussianBlur, NOT NSVisualEffectView. NSVisualEffectView always
/// adds a tint of some kind; CALayer-level CIGaussianBlur on a
/// transparent layer in a transparent window is the only way to get a
/// truly tint-free, see-through-to-blurred-desktop effect on macOS.
struct SplashView: View {
    let screenSize: CGSize
    let notch: NotchInfo
    let onComplete: () -> Void

    @State private var blurRadius: CGFloat = 0
    @State private var iconsRevealed = false
    @State private var ctaVisible = false
    @State private var iconsAtNotch = false

    private var claudeLogo: NSImage? {
        Bundle.main.url(forResource: "claude_logo", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
    }

    private var openaiLogo: NSImage? {
        Bundle.main.url(forResource: "openai_logo", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
    }

    /// Where Claude's icon ends up — the screen-coord center of the island
    /// window's leading logo.
    private var claudeFinalCenter: CGPoint {
        let islandWidth = notch.width + IslandRootView.tabWidth * 2
        let leftEdge = screenSize.width / 2 - islandWidth / 2
        let x = leftEdge + 9 + 10
        let y = max(0, (notch.height - 20) / 2) + 10
        return CGPoint(x: x, y: y)
    }

    private var codexFinalCenter: CGPoint {
        let islandWidth = notch.width + IslandRootView.tabWidth * 2
        let rightEdge = screenSize.width / 2 + islandWidth / 2
        let x = rightEdge - 9 - 10
        let y = max(0, (notch.height - 20) / 2) + 10
        return CGPoint(x: x, y: y)
    }

    private var claudeStartCenter: CGPoint {
        CGPoint(x: screenSize.width / 2 - 140, y: screenSize.height / 2 - 50)
    }

    private var codexStartCenter: CGPoint {
        CGPoint(x: screenSize.width / 2 + 140, y: screenSize.height / 2 - 50)
    }

    /// Logo size: 160pt frame, scaled by iconScale.
    /// Start: 0.3 (never animate from scale(0) per Emil), grow to 1.0 (160pt).
    /// Move-to-notch: 20/160 ≈ 0.125 (matching the 20pt island logo size).
    private static let logoFrame: CGFloat = 160

    private var iconScale: CGFloat {
        if iconsAtNotch { return 20.0 / Self.logoFrame }
        return iconsRevealed ? 1.0 : 0.3
    }

    private var claudePosition: CGPoint {
        iconsAtNotch ? claudeFinalCenter : claudeStartCenter
    }

    private var codexPosition: CGPoint {
        iconsAtNotch ? codexFinalCenter : codexStartCenter
    }

    var body: some View {
        ZStack {
            WallpaperBlurBackground(radius: blurRadius)
                .ignoresSafeArea()

            if let claudeLogo {
                Image(nsImage: claudeLogo)
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(IslandColor.claude)
                    .frame(width: Self.logoFrame, height: Self.logoFrame)
                    .scaleEffect(iconScale)
                    .position(claudePosition)
                    .opacity(iconsRevealed ? 1 : 0)
            }

            if let openaiLogo {
                Image(nsImage: openaiLogo)
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(IslandColor.codex)
                    .frame(width: Self.logoFrame, height: Self.logoFrame)
                    .scaleEffect(iconScale)
                    .position(codexPosition)
                    .opacity(iconsRevealed ? 1 : 0)
            }

            if !iconsAtNotch {
                CTAButton(action: handleCTAClick)
                    .opacity(ctaVisible ? 1 : 0)
                    .offset(y: ctaVisible ? 0 : 8)
                    .position(
                        x: screenSize.width / 2,
                        y: screenSize.height / 2 + 200
                    )
            }
        }
        .onAppear { startSequence() }
    }

    private func startSequence() {
        // Phase 1: blur ramps in over 900ms — gradual enough to read
        // as the desktop "going out of focus" rather than a curtain
        // dropping. End radius 25pt is heavy but not absolute.
        withAnimation(.easeOut(duration: 0.90)) {
            blurRadius = 25
        }
        // Phase 2 (t=400): logos grow in. Spring response 0.7 with damping
        // 0.78 settles slightly under critical so the icons feel like they
        // emerge into focus rather than snap.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
            withAnimation(.spring(response: 0.70, dampingFraction: 0.78)) {
                iconsRevealed = true
            }
        }
        // Phase 3 (t=1200): Continue button slides up + fades in.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.20) {
            withAnimation(.strongEaseOut) {
                ctaVisible = true
            }
        }
    }

    private func handleCTAClick() {
        // Light haptic confirms the click registered.
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment, performanceTime: .now
        )
        // CTA fades out instantly so the user's eye follows the icons.
        withAnimation(.easeOut(duration: 0.18)) {
            ctaVisible = false
        }
        // Icons travel to the notch + shrink to 20pt. Same spring as the
        // earlier auto-driven version; user-initiated now.
        withAnimation(.spring(response: 0.65, dampingFraction: 0.85)) {
            iconsAtNotch = true
        }
        // Blur lifts mid-travel so by the time the icons settle the
        // desktop is sharp again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            withAnimation(.easeOut(duration: 0.45)) {
                blurRadius = 0
            }
        }
        // Hand off to the island window once everything is settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.80) {
            onComplete()
        }
    }
}

/// Loads the user's actual desktop wallpaper via NSWorkspace and blurs it
/// with SwiftUI's .blur(radius:) — a real CIGaussianBlur with zero tint
/// or frost. NSWorkspace.desktopImageURL works without any entitlements
/// or screen-recording permission, so the splash is "plug and play" on
/// first launch.
///
/// Trade-off vs NSVisualEffectView: this only shows the wallpaper, not
/// other open windows. For a launch splash that covers the whole screen
/// anyway, that's exactly the right framing — the user's attention is
/// on our app, not on whatever was behind the splash.
private struct WallpaperBlurBackground: View {
    var radius: CGFloat

    @State private var wallpaper: NSImage?

    var body: some View {
        ZStack {
            // Black fallback if the wallpaper can't load (rare — would
            // mean the user has no wallpaper set, or NSWorkspace is
            // refusing to vend the URL for some sandboxed reason).
            Color.black

            if let wallpaper {
                Image(nsImage: wallpaper)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: radius)
            }
        }
        .clipped()
        .onAppear { wallpaper = loadWallpaper() }
    }

    private func loadWallpaper() -> NSImage? {
        guard let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

private struct CTAButton: View {
    let action: () -> Void
    @State private var hovered = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("continue")
                    .font(.system(size: 14, weight: .medium))
                    .tracking(0.4)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(.black.opacity(hovered ? 0.65 : 0.45))
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                .white.opacity(hovered ? 0.25 : 0.12),
                                lineWidth: 0.5
                            )
                    )
            )
            .scaleEffect(pressed ? 0.97 : (hovered ? 1.04 : 1.0))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.strongEaseOut, value: hovered)
        .animation(.easeOut(duration: 0.12), value: pressed)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressed = $0 }, perform: {})
    }
}
