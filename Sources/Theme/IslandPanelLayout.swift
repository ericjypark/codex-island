import Foundation

enum IslandPanelLayout {
    static let horizontalInset: CGFloat = 24
    static let columnInset: CGFloat = 12
    static let tileHeight: CGFloat = 120
    static let dataVerticalInset: CGFloat = 8
    static let footerHeight: CGFloat = 44

    static func headerHeight(notch: NotchInfo) -> CGFloat { max(32, notch.height) }
}
