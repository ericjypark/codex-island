import Foundation

/// Generic UserDefaults-backed store for picker preferences. Holds the
/// currently-selected style of any `RawRepresentable & CaseIterable` enum,
/// plus a one-shot `hasCycledStyle` bool that drives the "⌘-click to cycle"
/// onboarding hint.
///
/// Used by `StylePref` (chart visualization) and `CostStylePref` (cost
/// view layout). Subclasses pin the generic parameter to a concrete enum
/// and provide a `static let shared` singleton.
@MainActor
class StylePreferenceStore<S: RawRepresentable & CaseIterable & Hashable>: ObservableObject
where S.RawValue == String {
    private let styleKey: String
    private let cycledKey: String
    private let defaults: UserDefaults

    @Published var style: S {
        didSet { defaults.set(style.rawValue, forKey: styleKey) }
    }
    @Published var hasCycledStyle: Bool {
        didSet { defaults.set(hasCycledStyle, forKey: cycledKey) }
    }

    init(styleKey: String, cycledKey: String, defaultStyle: S,
         legacyStyles: [String: S] = [:], defaults: UserDefaults = .standard) {
        self.styleKey = styleKey
        self.cycledKey = cycledKey
        self.defaults = defaults
        let raw = defaults.string(forKey: styleKey) ?? ""
        self.style = S(rawValue: raw) ?? legacyStyles[raw] ?? defaultStyle
        // Demo mode keeps the ⌘-click hint visible regardless of prior session.
        self.hasCycledStyle = AppEnvironment.isDemo ? false : defaults.bool(forKey: cycledKey)
        if legacyStyles[raw] != nil { defaults.set(style.rawValue, forKey: styleKey) }
    }

    func cycle() {
        let all = Array(S.allCases)
        if let i = all.firstIndex(of: style) {
            style = all[(i + 1) % all.count]
        }
        if !hasCycledStyle { hasCycledStyle = true }
    }
}
