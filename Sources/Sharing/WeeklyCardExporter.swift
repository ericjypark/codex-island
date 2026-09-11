import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum WeeklyCardExportError: LocalizedError {
    case renderingFailed
    case clipboardFailed

    var errorDescription: String? {
        switch self {
        case .renderingFailed: return L10n.tr("Could not create the image. Try again.")
        case .clipboardFailed: return L10n.tr("Could not copy the image. Try saving a PNG instead.")
        }
    }
}

@MainActor
enum WeeklyCardExporter {
    static func png(snapshot: WeeklyUsageSnapshot,
                    format: WeeklyCardFormat, signature: String,
                    metric: WeeklyCardMetric = .apiValue) throws -> Data {
        let renderer = ImageRenderer(content: WeeklyUsageCard(snapshot: snapshot,
                                                              format: format, signature: signature, metric: metric))
        renderer.proposedSize = ProposedViewSize(format.size)
        renderer.scale = 2
        renderer.isOpaque = true
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw WeeklyCardExportError.renderingFailed }
        return data
    }

    static func copyImage(_ data: Data, to pasteboard: NSPasteboard = .general) throws {
        let item = NSPasteboardItem()
        guard item.setData(data, forType: .png) else { throw WeeklyCardExportError.clipboardFailed }
        if let image = NSImage(data: data), let tiff = image.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { throw WeeklyCardExportError.clipboardFailed }
    }

    static func save(_ data: Data, filename: String, window: NSWindow?,
                     completion: @escaping (Result<URL?, Error>) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = filename
        panel.canCreateDirectories = true
        panel.title = L10n.tr("Save usage card")
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else {
                completion(.success(nil))
                return
            }
            do {
                try data.write(to: url, options: .atomic)
                completion(.success(url))
            } catch {
                completion(.failure(error))
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }
}
