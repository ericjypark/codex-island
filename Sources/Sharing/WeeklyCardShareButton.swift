import AppKit
import SwiftUI

struct WeeklyCardShareContent {
    let image: NSImage
    let caption: String

    init(png: Data, caption: String) throws {
        guard let image = NSImage(data: png) else { throw WeeklyCardExportError.renderingFailed }
        self.image = image
        self.caption = caption
    }
}

struct WeeklyCardShareButton: NSViewRepresentable {
    let enabled: Bool
    let content: () throws -> WeeklyCardShareContent
    let onError: (Error) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: L10n.tr("Share…"), target: context.coordinator,
                              action: #selector(Coordinator.share(_:)))
        button.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.controlSize = .regular
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.sendAction(on: .leftMouseDown)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        button.isEnabled = enabled
    }

    @MainActor
    final class Coordinator: NSObject, NSSharingServicePickerDelegate {
        var parent: WeeklyCardShareButton
        private var picker: NSSharingServicePicker?

        init(_ parent: WeeklyCardShareButton) { self.parent = parent }

        @objc func share(_ sender: NSButton) {
            guard parent.enabled else { return }
            do {
                let content = try parent.content()
                let picker = NSSharingServicePicker(items: [content.image, content.caption])
                self.picker = picker
                picker.delegate = self
                picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            } catch {
                parent.onError(error)
            }
        }

        nonisolated func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                                              didChoose service: NSSharingService?) {
            Task { @MainActor [weak self] in self?.picker = nil }
        }
    }
}
