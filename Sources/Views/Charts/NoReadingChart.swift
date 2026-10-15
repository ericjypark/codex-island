import SwiftUI

/// Tile shown when a window carries no reading — a failed fetch with nothing
/// to carry forward and no recorded history to seed from.
///
/// Every other chart takes a `Double` and draws it. A window without a
/// reading still has `usedPercent == 0`, so handing it to one of them draws a
/// confident "0% used", and under the `remaining` toggle a completely full
/// ring. Both are the most reassuring possible rendering of "we don't know",
/// which is exactly backwards. This draws the empty track and an em dash
/// instead, so the tile reads as absent rather than measured.
///
/// Geometry matches the stepped tile so the
/// swap in and out doesn't shift the panel's fixed 188pt height.
struct NoReadingChart: View {
    let label: String
    let sub: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(Typography.label)
                    .foregroundStyle(.white.opacity(0.6))
                    .textCase(.lowercase)
                Spacer()
                QuotaValue(reading: QuotaChartReading(id: label, label: label, value: nil, caption: sub),
                           mode: UsageDisplayModeStore.shared.mode, size: 32, weight: .semibold)
            }
            // Empty track, no fill: the scale is still there, we just have
            // nothing to put on it.
            RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(0.12))
                .frame(height: 16)
            ChartFoot(caption: sub)
        }
    }
}
