import SwiftUI
import AppKit

/// One-shot launch sequence: frost fades in, icons fade in at center, icons
/// move to the notch position (matching where the island window's logo
/// overlays will land), frost fades out, sequence calls `onComplete`.
///
/// The trick to seamless handoff: claudeFinalCenter / codexFinalCenter
/// here compute the EXACT same screen coordinates as IslandRootView's
/// .overlay(alignment: .topLeading/.topTrailing) logo positioning. When
/// the island window opens behind this splash and the splash closes, the
/// two icons are at identical positions and sizes — the user reads it as
/// one continuous animation across two windows.
struct SplashView: View {
    let screenSize: CGSize
    let notch: NotchInfo
    let onComplete: () -> Void

    @State private var blurOpacity: Double = 0
    @State private var iconsVisible = false
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
    /// window's leading logo. islandWidth = notch.width + 2 × 38pt tabs.
    /// Logo center sits at (window leading edge + 9pt padding + 10pt half
    /// logo width) horizontally, and at (notch.height − 20)/2 + 10 vertically.
    private var claudeFinalCenter: CGPoint {
        let islandWidth = notch.width + IslandRootView.tabWidth * 2
        let leftEdge = screenSize.width / 2 - islandWidth / 2
        let x = leftEdge + 9 + 10
        let y = max(0, (notch.height - 20) / 2) + 10
        return CGPoint(x: x, y: y)
    }

    /// Mirror image for Codex on the trailing edge.
    private var codexFinalCenter: CGPoint {
        let islandWidth = notch.width + IslandRootView.tabWidth * 2
        let rightEdge = screenSize.width / 2 + islandWidth / 2
        let x = rightEdge - 9 - 10
        let y = max(0, (notch.height - 20) / 2) + 10
        return CGPoint(x: x, y: y)
    }

    private var claudeStartCenter: CGPoint {
        CGPoint(x: screenSize.width / 2 - 90, y: screenSize.height / 2)
    }

    private var codexStartCenter: CGPoint {
        CGPoint(x: screenSize.width / 2 + 90, y: screenSize.height / 2)
    }

    private var iconSize: CGFloat { iconsAtNotch ? 20 : 80 }
    private var claudePosition: CGPoint { iconsAtNotch ? claudeFinalCenter : claudeStartCenter }
    private var codexPosition: CGPoint { iconsAtNotch ? codexFinalCenter : codexStartCenter }

    var body: some View {
        ZStack {
            // Full-screen frosted backdrop.
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(blurOpacity)
                .ignoresSafeArea()

            if let claudeLogo {
                Image(nsImage: claudeLogo)
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(IslandColor.claude)
                    .frame(width: iconSize, height: iconSize)
                    .position(claudePosition)
                    .opacity(iconsVisible ? 1 : 0)
                    .scaleEffect(iconsVisible ? 1 : 0.7)
            }

            if let openaiLogo {
                Image(nsImage: openaiLogo)
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(IslandColor.codex)
                    .frame(width: iconSize, height: iconSize)
                    .position(codexPosition)
                    .opacity(iconsVisible ? 1 : 0)
                    .scaleEffect(iconsVisible ? 1 : 0.7)
            }
        }
        .onAppear { runSequence() }
    }

    private func runSequence() {
        // t=0: frost fades in over 300ms.
        withAnimation(.easeOut(duration: 0.30)) {
            blurOpacity = 1
        }
        // t=350: icons fade + scale in at center via spring.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                iconsVisible = true
            }
        }
        // t=900: brief 200ms beat at center, then icons travel + shrink to
        // the notch position. Spring response 0.65 / damping 0.85 makes the
        // travel feel deliberate without overshoot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.90) {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.85)) {
                iconsAtNotch = true
            }
        }
        // t=1500: frost fades out (icons stay at notch).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.50) {
            withAnimation(.easeOut(duration: 0.40)) {
                blurOpacity = 0
            }
        }
        // t=1950: handoff to the island window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.95) {
            onComplete()
        }
    }
}
