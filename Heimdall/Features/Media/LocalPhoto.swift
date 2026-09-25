import SwiftUI

/// A view-owned, display-sized image. No shared cache of sensitive media.
struct LocalPhoto: View {
    let url: URL
    let maximumPixelSize: Int
    var contentMode: ContentMode = .fit
    @State private var image: CGImage?
    @State private var failed = false

    private struct Request: Equatable {
        let url: URL
        let maximumPixelSize: Int
    }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: contentMode)
            } else if failed {
                if contentMode == .fit {
                    ContentUnavailableView("File unavailable", systemImage: "photo.badge.exclamationmark")
                } else {
                    Rectangle().fill(Theme.panel).overlay { Image(systemName: "photo.badge.exclamationmark") }
                        .accessibilityLabel("File unavailable")
                }
            } else {
                Rectangle().fill(Theme.panel).overlay { ProgressView() }
            }
        }
        .task(id: Request(url: url, maximumPixelSize: maximumPixelSize)) {
            image = nil
            failed = false
            do {
                let loaded = try await LocalImageLoader.shared.image(at: url, maximumPixelSize: maximumPixelSize)
                try Task.checkCancellation()
                image = loaded
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
        .onDisappear { image = nil }
    }
}
