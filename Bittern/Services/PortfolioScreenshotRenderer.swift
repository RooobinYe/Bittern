//
//  PortfolioScreenshotRenderer.swift
//  Bittern
//

import SwiftUI
import UIKit

// MARK: - Screenshot Context

struct ScreenshotContextKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// When true, views should render in screenshot-friendly mode:
    /// - No interactive elements (Menus become static Labels)
    /// - VStack instead of LazyVStack (all rows materialized)
    /// - No NavigationLinks
    var isRenderingScreenshot: Bool {
        get { self[ScreenshotContextKey.self] }
        set { self[ScreenshotContextKey.self] = newValue }
    }
}

// MARK: - Renderer

/// Renders any SwiftUI View into a UIImage using **image generation**,
/// not screen capture.
///
/// ## Approach
///
/// This is a true "generate an image" pipeline — it does NOT screenshot
/// pixels from the window hierarchy. Instead it uses SwiftUI's own
/// software renderer (`ImageRenderer`, iOS 16+) to rasterise the view
/// tree directly into a bitmap.
///
/// Two steps:
/// 1. **Measure** — `UIHostingController.sizeThatFits` runs a layout-only
///    pass to determine the natural height of the content at the given width.
///    This is lightweight (no rendering, no window insertion) and correctly
///    handles `GeometryReader`-based views like the donut chart.
/// 2. **Render** — `ImageRenderer` draws the view tree into a `UIImage` at
///    the measured size and desired scale. This runs entirely off-screen
///    without touching `drawHierarchy`, `layer.render(in:)`, or any
///    UIWindow.
///
/// ## Why not pure ImageRenderer (without measurement)?
///
/// `ImageRenderer` with an `unspecified` proposed height breaks
/// `GeometryReader`-based views: the GeometryReader receives ~0 height
/// and collapses. Measuring first gives us a concrete height to feed
/// into `ImageRenderer.proposedSize`, which resolves this.
///
/// ## Memory
///
/// For very tall content (> 3000 pt) the scale is automatically reduced
/// to 1× to keep the uncompressed bitmap under ~20 MB.
enum ScreenshotRenderer {

    /// Renders a SwiftUI view into a shareable UIImage.
    ///
    /// - Parameters:
    ///   - content: The SwiftUI view to render.
    ///   - width: The target width in points.
    ///   - scale: The scale factor. Defaults to `UIScreen.main.scale`.
    ///     Auto-reduced to 1× for content taller than 3000 pt.
    /// - Returns: A `UIImage`, or `nil` if rendering fails.
    @MainActor
    static func render<Content: View>(
        _ content: Content,
        width: CGFloat,
        scale: CGFloat = UIScreen.main.scale,
        backgroundColor: UIColor = .systemBackground
    ) -> UIImage? {
        guard width > 0 else { return nil }

        // ---- 1. Measure ----
        // UIHostingController.sizeThatFits runs layout-only.
        // No window insertion needed — it works entirely in memory.
        let host = UIHostingController(rootView: content)
        let fitting = host.sizeThatFits(
            in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        )
        let renderSize = CGSize(
            width: width,
            height: ceil(fitting.height)
        )

        guard renderSize.height > 0, renderSize.height.isFinite else {
            return nil
        }

        // ---- 2. Pick effective scale ----
        // Tall content at 3× can exceed 45 MB uncompressed — drop to 1×.
        let effectiveScale: CGFloat = renderSize.height > 3000 ? min(scale, 1.0) : scale

        // ---- 3. Render ----
        // ImageRenderer generates the image directly from the SwiftUI view
        // tree via software rendering. proposedSize provides the concrete
        // dimensions so GeometryReader views receive a definite size.
        let renderer = ImageRenderer(content: content)
        renderer.scale = effectiveScale
        renderer.proposedSize = ProposedViewSize(renderSize)

        guard let rawImage = renderer.uiImage else { return nil }

        // ---- 4. Strip alpha channel ----
        // ImageRenderer always produces RGBA images even when the content is
        // fully opaque. That doubles the memory needed for decoding (RGB vs
        // RGBA) and inflates file size. Redraw into an opaque context to fix.
        let opaqueFormat = UIGraphicsImageRendererFormat()
        opaqueFormat.scale = effectiveScale
        opaqueFormat.opaque = true

        return UIGraphicsImageRenderer(
            size: renderSize,
            format: opaqueFormat
        ).image { ctx in
            backgroundColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: renderSize))
            rawImage.draw(at: .zero)
        }
    }

    // MARK: - Content Height Estimation

    /// Estimates the total content height for a given number of items.
    ///
    /// Useful for deciding whether to show a "this may take a moment" hint
    /// before invoking ``render(_:width:scale:)``.
    static func estimatedContentHeight(itemCount: Int, estimatedRowHeight: CGFloat) -> CGFloat {
        return CGFloat(itemCount) * estimatedRowHeight
    }
}
