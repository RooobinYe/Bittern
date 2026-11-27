//
//  LogoSource.swift
//  Bittern
//

import SwiftUI
import UIKit

/// Loads one logo bitmap. `name` is only for logs.
struct LogoImageLoader: Sendable {
    let cached: @Sendable (_ url: URL) -> UIImage?
    let warmFromDisk: @Sendable (_ urls: [URL]) async -> Void
    let image: @Sendable (_ name: String, _ url: URL) async throws -> UIImage

    init(
        cached: @escaping @Sendable (_ url: URL) -> UIImage? = { _ in nil },
        warmFromDisk: @escaping @Sendable (_ urls: [URL]) async -> Void = { _ in },
        image: @escaping @Sendable (_ name: String, _ url: URL) async throws -> UIImage
    ) {
        self.cached = cached
        self.warmFromDisk = warmFromDisk
        self.image = image
    }
}

/// Where holding and provider logos come from. Views read it from the
/// environment instead of creating a client.
enum LogoSource: Sendable {
    /// No logos: every icon shows its fallback. The default, so previews and
    /// anything the app didn't set up never reach the network.
    case none
    /// Each logo loads when its view appears.
    case remote(LogoImageLoader)
    /// Bitmaps loaded beforehand, for rendering an image in a single pass
    /// where an asynchronous load could never finish in time.
    case preloaded([URL: UIImage])

    func cachedImage(for url: URL) -> UIImage? {
        switch self {
        case .none:
            return nil
        case .remote(let loader):
            return loader.cached(url)
        case .preloaded(let images):
            return images[url]
        }
    }

    func warmCachedLogos(for snapshot: PortfolioSnapshot) async {
        guard case .remote(let loader) = self else { return }
        await loader.warmFromDisk(snapshot.holdings.compactMap(\.logoURL))
    }
}

extension EnvironmentValues {
    @Entry var logoSource: LogoSource = .none
}

/// A logo from the environment's `LogoSource`, or `placeholder` while it
/// loads, when it fails, or when there is none.
struct LogoImage<Content: View, Placeholder: View>: View {
    let name: String
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @Environment(\.logoSource) private var source
    @State private var loaded: (url: URL, image: UIImage)?

    var body: some View {
        ZStack {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private var image: UIImage? {
        guard let url else { return nil }
        if let loaded, loaded.url == url {
            return loaded.image
        }
        return source.cachedImage(for: url)
    }

    private func load() async {
        guard case .remote(let loader) = source, let url, loaded?.url != url else { return }
        if let cached = loader.cached(url) {
            loaded = (url, cached)
            return
        }
        // A missing logo only leaves the placeholder; the loader logs why.
        guard let image = try? await loader.image(name, url) else { return }
        loaded = (url, image)
    }
}
