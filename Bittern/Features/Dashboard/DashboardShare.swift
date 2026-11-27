//
//  DashboardShare.swift
//  Bittern
//
//  The dashboard as a shareable PNG, drawn by the same views as the live
//  dashboard without their controls.
//

import CoreTransferable
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PortfolioShareItem: Transferable, Sendable {
    let renderPNG: @MainActor @Sendable () async throws -> Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            try await item.renderPNG()
        }
        .suggestedFileName("Bittern Portfolio.png")
    }
}

enum PortfolioShareError: Error {
    case renderingFailed
}

struct DashboardShareSnapshot: Sendable {
    /// The dashboard's title: "Portfolio", or the provider it shows.
    let title: String
    let portfolio: PortfolioSnapshot
    let sortedHoldings: [PortfolioHolding]
    let performanceMode: PerformanceMode
    let sortOption: HoldingSortOption
    let minimumMarketValue: Double
    let hiddenHoldingCount: Int
    var isPrivacyEnabled: Bool
    /// Gray in the image as on screen when prices aren't current.
    let priceStatus: PriceStatus
    let viewportSize: CGSize
    let layoutMode: PaneArrangement

    /// Renders the dashboard as a PNG at the width it occupies on screen,
    /// capped at the export maximum. Shared by the share sheet and the debug
    /// launch export.
    func renderPNG(
        colorScheme: ColorScheme,
        scale: CGFloat,
        dynamicTypeSize: DynamicTypeSize,
        logoSource: LogoSource
    ) async -> Data? {
        let width = min(
            max(viewportSize.width, 1),
            DashboardLayoutMetrics.maximumExportWidth
        )
        // ImageRenderer draws in one pass, so every logo must be in hand first.
        let logos = await preloadedLogos(from: logoSource)
        let content = PortfolioShareScreenshotContent(snapshot: self, width: width)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.colorScheme, colorScheme)
            .environment(\.logoSource, .preloaded(logos))

        return ScreenshotRenderer.render(
            content,
            width: width,
            scale: scale,
            backgroundColor: colorScheme.systemBackgroundColor
        )?.pngData()
    }

    private func preloadedLogos(from source: LogoSource) async -> [URL: UIImage] {
        switch source {
        case .none:
            return [:]
        case .preloaded(let images):
            return images
        case .remote(let loader):
            var requests: [URL: String] = [:]
            for holding in portfolio.holdings {
                guard let logoURL = holding.logoURL else { continue }
                requests[logoURL] = requests[logoURL] ?? holding.symbol
            }

            return await withTaskGroup(
                of: (URL, UIImage?).self,
                returning: [URL: UIImage].self
            ) { group in
                for (url, symbol) in requests {
                    group.addTask {
                        (url, try? await loader.image(symbol, url))
                    }
                }

                var images: [URL: UIImage] = [:]
                for await (url, image) in group {
                    images[url] = image
                }
                return images
            }
        }
    }
}

private struct PortfolioShareScreenshotContent: View {
    let snapshot: DashboardShareSnapshot
    let width: CGFloat

    var body: some View {
        DashboardVisualContent(
            portfolio: snapshot.portfolio,
            scopeTitle: snapshot.title,
            sortedHoldings: snapshot.sortedHoldings,
            performanceMode: snapshot.performanceMode,
            sortOption: snapshot.sortOption,
            minimumMarketValue: snapshot.minimumMarketValue,
            hiddenHoldingCount: snapshot.hiddenHoldingCount,
            isPrivacyEnabled: snapshot.isPrivacyEnabled,
            layoutMode: snapshot.layoutMode,
            controls: nil
        )
        .environment(\.priceStatus, snapshot.priceStatus)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(width: width, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(BitternTheme.background)
    }
}

private extension ColorScheme {
    var systemBackgroundColor: UIColor {
        UIColor.systemBackground.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: self == .dark ? .dark : .light)
        )
    }
}
