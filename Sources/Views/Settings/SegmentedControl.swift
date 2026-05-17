import SwiftUI

/// Pill-shaped segmented control used by Refresh interval, Token counting,
/// and Island width pickers in Settings. Items can be any `Hashable`; the
/// caller supplies a label closure so an enum can render its `.label` and
/// an Int can render `"5m"`.
struct SegmentedControl<Value: Hashable>: View {
    let items: [Value]
    @Binding var selected: Value
    let label: (Value) -> String
    var accessibilityPrefix: String = ""

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                let isOn = (item == selected)
                let itemLabel = L10n.tr(label(item))
                Button {
                    selected = item
                } label: {
                    Text(itemLabel)
                        .font(Typography.bodyNumber)
                        .foregroundStyle(isOn
                            ? Color.white.opacity(0.95)
                            : .white.opacity(0.55))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isOn ? .white.opacity(0.10) : .clear)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5)
                                        .strokeBorder(.white.opacity(isOn ? 0.08 : 0), lineWidth: 0.5)
                                }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityPrefix.isEmpty
                    ? itemLabel
                    : L10n.tr("%@, %@", L10n.tr(accessibilityPrefix), itemLabel))
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(.white.opacity(0.04))
        }
    }
}

/// Plain pill-shaped action button — white-tinted background, used by
/// "Refresh" (Cost section) and "Check" (Updates section). Quit button in
/// the footer uses a different hover-aware variant.
struct PillButton: View {
    let label: String
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(L10n.tr(label))
                .font(Typography.button)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white.opacity(0.10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                        }
                }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .opacity(isLoading ? 0.55 : 1)
    }
}
