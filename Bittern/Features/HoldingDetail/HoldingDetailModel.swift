//
//  HoldingDetailModel.swift
//  Bittern
//

import Foundation
import Observation
import OSLog

/// Price history per chart range, loaded on demand and kept for the life of
/// the detail screen.
@MainActor
@Observable
final class HoldingDetailModel {
    var selectedRange: HoldingChartRange = .oneDay
    var selectedPoint: HoldingPricePoint?
    var errorMessage: String?
    private(set) var seriesByRange: [HoldingChartRange: HoldingPriceSeries] = [:]
    /// The range whose first load is in flight. A reload of a range that
    /// already has a series keeps showing it instead.
    private(set) var loadingRange: HoldingChartRange?

    var isLoading: Bool {
        loadingRange == selectedRange
    }

    var visibleSeries: HoldingPriceSeries? {
        seriesByRange[selectedRange]
    }

    /// Loads `range` unless it already has a series. A reload replaces it.
    /// The caller's task decides the lifetime: SwiftUI cancels a `.task(id:)`
    /// when the range changes, and a cancelled load changes nothing.
    func load(
        _ range: HoldingChartRange,
        for holding: PortfolioHolding,
        using repository: any PortfolioRepository,
        reload: Bool = false
    ) async {
        guard reload || seriesByRange[range] == nil else { return }

        if seriesByRange[range] == nil {
            loadingRange = range
        }
        errorMessage = nil
        defer {
            if loadingRange == range {
                loadingRange = nil
            }
        }

        do {
            let series = try await repository.priceHistory(for: holding, range: range)
            try Task.checkCancellation()
            if range == selectedRange {
                selectedPoint = nil
            }
            seriesByRange[range] = series
        } catch {
            guard !Task.isCancelled,
                  !(error is CancellationError),
                  (error as? URLError)?.code != .cancelled
            else {
                return
            }
            AppLog.marketData.warning(
                "Chart load failed range=\(range.title, privacy: .public) symbol=\(holding.symbol): \(AppLog.describe(error))"
            )
            if seriesByRange[range] == nil {
                seriesByRange[range] = .empty
            }
            if range == selectedRange {
                errorMessage = UserFacingError.message(
                    for: error,
                    fallback: "Price history for \(holding.symbol) couldn’t be loaded. Please try again."
                )
            }
        }
    }
}
