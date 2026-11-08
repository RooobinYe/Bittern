//
//  HoldingDetailModel.swift
//  Bittern
//

import Foundation
import Observation
import OSLog

/// Price history per chart range, loaded on demand and kept for the life of
/// the detail screen. Every loaded range follows the live price: its last
/// point is the bar in progress (`LiveChartTail`).
@MainActor
@Observable
final class HoldingDetailModel {
    var selectedRange: HoldingChartRange = .oneDay {
        didSet { frozen = nil }
    }
    /// The point the user is holding on the chart. While it is set the chart
    /// holds still; live updates show when it is let go.
    var selectedPoint: HoldingPricePoint? {
        didSet {
            if selectedPoint == nil {
                frozen = nil
            } else if frozen == nil, let series = seriesByRange[selectedRange] {
                frozen = FrozenChart(series: series, valueBounds: valueBoundsByRange[selectedRange])
            }
        }
    }
    var errorMessage: String?
    private(set) var seriesByRange: [HoldingChartRange: HoldingPriceSeries] = [:]
    /// What each range's value axis covers. It widens only when a live
    /// price leaves it, so the axis doesn't move with every tick.
    private(set) var valueBoundsByRange: [HoldingChartRange: ClosedRange<Double>] = [:]
    /// The range whose first load is in flight. A reload of a range that
    /// already has a series keeps showing it instead.
    private(set) var loadingRange: HoldingChartRange?
    /// Ranges that never loaded because there was no network. They load
    /// when it returns.
    private(set) var rangesUnavailableOffline: Set<HoldingChartRange> = []

    @ObservationIgnored private var frozen: FrozenChart?
    @ObservationIgnored private var lastReloads: [HoldingChartRange: Date] = [:]

    private struct FrozenChart {
        let series: HoldingPriceSeries
        let valueBounds: ClosedRange<Double>?
    }

    /// A range a live price no longer fits is loaded again at most this
    /// often.
    private static let minimumReloadInterval: TimeInterval = 60

    var isLoading: Bool {
        loadingRange == selectedRange
    }

    var visibleSeries: HoldingPriceSeries? {
        frozen?.series ?? seriesByRange[selectedRange]
    }

    var visibleValueBounds: ClosedRange<Double>? {
        frozen.map(\.valueBounds) ?? valueBoundsByRange[selectedRange]
    }

    var isVisibleRangeUnavailableOffline: Bool {
        seriesByRange[selectedRange] == nil && rangesUnavailableOffline.contains(selectedRange)
    }

    /// The ranges worth offering: every range until a loaded series says
    /// when the holding first traded.
    var availableRanges: [HoldingChartRange] {
        HoldingChartRange.available(
            firstTradeDate: seriesByRange.values.compactMap(\.firstTradeDate).min(),
            at: Date()
        )
    }

    /// Loads `range` unless it already has a series. A reload replaces it.
    /// Without a network a range that never loaded waits for one, with no
    /// message: the chart says so. The caller's task decides the lifetime:
    /// SwiftUI cancels a `.task(id:)` when the range changes, and a
    /// cancelled load changes nothing.
    func load(
        _ range: HoldingChartRange,
        for holding: PortfolioHolding,
        using repository: any PortfolioRepository,
        isOnline: Bool = true,
        reload: Bool = false,
        at now: Date = Date()
    ) async {
        guard reload || seriesByRange[range] == nil else { return }
        guard isOnline else {
            if seriesByRange[range] == nil {
                rangesUnavailableOffline.insert(range)
            }
            return
        }

        if seriesByRange[range] == nil {
            loadingRange = range
        }
        rangesUnavailableOffline.remove(range)
        errorMessage = nil
        defer {
            if loadingRange == range {
                loadingRange = nil
            }
        }

        do {
            let loaded = try await repository.priceHistory(for: holding, range: range)
            try Task.checkCancellation()
            if range == selectedRange {
                selectedPoint = nil
            }
            var series = loaded
            if let observation = holding.liveObservation(for: range, at: now),
               case .updated(let following) = LiveChartTail.applying(
                   observation,
                   to: loaded,
                   barLength: range.barLength
               ) {
                series = following
            }
            seriesByRange[range] = series
            valueBoundsByRange[range] = Self.valueBounds(of: series, range: range, holding: holding)
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
            if RefreshFailure(error) == .offline {
                if seriesByRange[range] == nil {
                    rangesUnavailableOffline.insert(range)
                }
                return
            }
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

    /// Moves every loaded range's last bar to `holding`'s live price, and
    /// starts a bar when a new one begins. Returns the ranges the price no
    /// longer fits, such as 1D once a session has closed, to load again.
    func follow(_ holding: PortfolioHolding, at now: Date = Date()) -> [HoldingChartRange] {
        var reloads: [HoldingChartRange] = []
        for (range, series) in seriesByRange where !series.points.isEmpty {
            guard let observation = holding.liveObservation(for: range, at: now) else { continue }
            switch LiveChartTail.applying(observation, to: series, barLength: range.barLength) {
            case .unchanged:
                break
            case .updated(let following):
                seriesByRange[range] = following
                if let bounds = valueBoundsByRange[range] {
                    valueBoundsByRange[range] = PerformanceChartGeometry.valueBounds(
                        bounds,
                        including: observation.price
                    )
                }
            case .needsReload:
                if lastReloads[range].map({ now.timeIntervalSince($0) >= Self.minimumReloadInterval }) ?? true {
                    lastReloads[range] = now
                    reloads.append(range)
                }
            }
        }
        return reloads
    }

    /// The values a freshly loaded series' axis covers: its points and the
    /// price its change is measured from.
    private static func valueBounds(
        of series: HoldingPriceSeries,
        range: HoldingChartRange,
        holding: PortfolioHolding
    ) -> ClosedRange<Double>? {
        var values = series.points.map(\.price)
        if let base = range.detailChangeBasePrice(
            previousClose: holding.previousClose,
            seriesBaseline: series.baselinePrice,
            seriesFirstPrice: series.points.first?.price
        ) {
            values.append(base)
        }
        guard let low = values.min(), let high = values.max() else { return nil }
        return low...high
    }
}
