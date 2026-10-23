import SwiftUI
import UIKit

/// Load state handed to an `AuthenticatedImage`'s content, like `AsyncImagePhase`.
enum AuthenticatedImagePhase {
    case empty
    case success(Image)
    case failure

    var image: Image? {
        if case .success(let image) = self { return image }
        return nil
    }
}

/// `AsyncImage` for Matrix media: downloads through `MediaLoader` with the session's Bearer token
/// (Continuwuity only serves authenticated media) and reuses its memory and disk caches.
/// The content closure lays out exactly like AsyncImage's phase closure, so call sites keep their frames.
struct AuthenticatedImage<Content: View>: View {
    private let url: URL?
    private let maxPixelSize: CGFloat
    private let content: (AuthenticatedImagePhase) -> Content

    @State private var loaded: (url: URL, image: UIImage)?
    @State private var failedURL: URL?

    init(url: URL?, maxPixelSize: CGFloat = MediaLoader.defaultMaxPixelSize,
         @ViewBuilder content: @escaping (AuthenticatedImagePhase) -> Content) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.content = content
    }

    var body: some View {
        ZStack {
            if let loaded, loaded.url == url, let firstFrame = loaded.image.images?.first {
                AnimatedMediaImage(image: loaded.image)
                    .aspectRatio(firstFrame.size.width / max(1, firstFrame.size.height), contentMode: .fit)
            } else { content(phase) }
        }.task(id: url) { await load() }
    }

    private var phase: AuthenticatedImagePhase {
        guard let url else { return .empty }
        if let loaded, loaded.url == url { return .success(Image(uiImage: loaded.image)) }
        // Memory hit: no placeholder frame when a recycled row comes back on screen.
        if let cached = MediaLoader.shared.cachedImage(for: url, maxPixelSize: maxPixelSize) {
            return .success(Image(uiImage: cached))
        }
        return failedURL == url ? .failure : .empty
    }

    private func load() async {
        guard let url else { return }
        if let cached = MediaLoader.shared.cachedImage(for: url, maxPixelSize: maxPixelSize) {
            loaded = (url, cached)
            return
        }
        do {
            let image = try await MediaLoader.shared.image(for: url, maxPixelSize: maxPixelSize)
            guard !Task.isCancelled else { return }
            loaded = (url, image)
            failedURL = nil
        } catch is CancellationError {
            // The row scrolled away; the download itself finishes and lands in the cache.
        } catch {
            guard !Task.isCancelled else { return }
            failedURL = url
        }
    }
}

/// UIKit advances GIF frames; SwiftUI.Image alone displays only the poster frame.
private struct AnimatedMediaImage: UIViewRepresentable {
    let image: UIImage
    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }
    func updateUIView(_ view: UIImageView, context: Context) {
        if view.image !== image { view.image = image; view.startAnimating() }
    }
    static func dismantleUIView(_ view: UIImageView, coordinator: ()) { view.stopAnimating(); view.image = nil }
}
