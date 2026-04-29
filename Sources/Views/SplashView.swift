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
        CGPoint(x: screenSize.width / 2 - 110, y: screenSize.height / 2 - 30)
    }

    private var codexStartCenter: CGPoint {
        CGPoint(x: screenSize.width / 2 + 110, y: screenSize.height / 2 - 30)
    }

    /// Logo size: 100pt frame, scaled by iconScale.
    /// Start: 0.3 (never animate from scale(0) per Emil), grow to 1.0 (100pt).
    /// Move-to-notch: 0.20 (20pt, matching island logo size).
    private var iconScale: CGFloat {
        if iconsAtNotch { return 20.0 / 100.0 }
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
            PureBlurBackground(radius: blurRadius)
                .ignoresSafeArea()

            if let claudeLogo {
                Image(nsImage: claudeLogo)
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(IslandColor.claude)
                    .frame(width: 100, height: 100)
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
                    .frame(width: 100, height: 100)
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
                        y: screenSize.height / 2 + 100
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

/// Pure CIGaussianBlur via CALayer.backgroundFilters. The window must be
/// transparent (isOpaque=false, backgroundColor=.clear) for the layer's
/// background filters to read the desktop content underneath. Animatable
/// via SwiftUI by re-instantiating with a new `radius` each frame —
/// updateNSView pokes the CIFilter's input.
private struct PureBlurBackground: NSViewRepresentable {
    var radius: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        applyBlur(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        applyBlur(to: nsView)
    }

    private func applyBlur(to view: NSView) {
        guard let layer = view.layer else { return }
        if let filter = CIFilter(name: "CIGaussianBlur") {
            filter.setValue(radius, forKey: kCIInputRadiusKey)
            layer.backgroundFilters = [filter]
        }
        layer.setNeedsDisplay()
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
