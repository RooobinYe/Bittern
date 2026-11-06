//
//  HoldingPriceSeries.swift
//  Bittern
//

import Foundation

enum HoldingChartRange: String, CaseIterable, Identifiable, Codable {
    case oneDay = "1D"
    case fiveDays = "5D"
    case threeMonths = "3M"
    case oneYear = "1Y"
    case fiveYears = "5Y"
    case max = "MAX"

    var id: String { rawValue }

    var title: String { rawValue }

    var summaryLabel: String {
        switch self {
        case .oneDay:
            "Today"
        case .fiveDays:
            "Last week"
        case .threeMonths:
            "3 months"
        case .oneYear:
            "1 year"
        case .fiveYears:
            "5 years"
        case .max:
            "Max"
        }
    }

    func detailChangeBasePrice(previousClose: Double?, seriesFirstPrice: Double?) -> Double? {
        switch self {
        case .oneDay:
            return previousClose
        case .fiveDays, .threeMonths, .oneYear, .fiveYears, .max:
            return seriesFirstPrice
        }
    }
}

enum PriceChartSession: Hashable {
    case regular
    case preMarket
    case postMarket

    var isExtendedHours: Bool {
        self != .regular
    }
}

struct HoldingPricePoint: Identifiable, Hashable {
    let date: Date
    let price: Double
    let session: PriceChartSession

    init(
        date: Date,
        price: Double,
        session: PriceChartSession = .regular
    ) {
        self.date = date
        self.price = price
        self.session = session
    }

    var id: TimeInterval {
        date.timeIntervalSince1970
    }

    func inSession(_ session: PriceChartSession) -> HoldingPricePoint {
        HoldingPricePoint(date: date, price: price, session: session)
    }
}

struct PriceChartTimeSegment: Hashable {
    let start: Date
    let end: Date
    let spacingBefore: TimeInterval

    init(
        start: Date,
        end: Date,
        spacingBefore: TimeInterval = 0
    ) {
        self.start = start
        self.end = end
        self.spacingBefore = spacingBefore
    }

    /// Half-open: the closing instant belongs to whatever follows.
    func contains(_ date: Date) -> Bool {
        start <= date && date < end
    }
}

struct PriceChartTimeDomain: Hashable {
    let segments: [PriceChartTimeSegment]

    init(start: Date, end: Date) {
        segments = [PriceChartTimeSegment(start: start, end: end)]
    }

    init(segments: [PriceChartTimeSegment]) {
        self.segments = segments
    }

    var start: Date {
        segments.first?.start ?? .distantFuture
    }

    var end: Date {
        segments.last?.end ?? .distantPast
    }

    var duration: TimeInterval {
        segments.reduce(0) { total, segment in
            total
                + max(0, segment.spacingBefore)
                + max(0, segment.end.timeIntervalSince(segment.start))
        }
    }

    func elapsedTime(for date: Date) -> TimeInterval? {
        var elapsed: TimeInterval = 0

        for segment in segments {
            elapsed += max(0, segment.spacingBefore)
            if segment.start <= date, date <= segment.end {
                return elapsed + date.timeIntervalSince(segment.start)
            }
            elapsed += max(0, segment.end.timeIntervalSince(segment.start))
        }

        return nil
    }
}

struct HoldingPriceSeries {
    let points: [HoldingPricePoint]
    let timeDomain: PriceChartTimeDomain?
    let baselinePrice: Double?

    init(
        points: [HoldingPricePoint],
        timeDomain: PriceChartTimeDomain?,
        baselinePrice: Double? = nil
    ) {
        self.points = points
        self.timeDomain = timeDomain
        self.baselinePrice = baselinePrice
    }

    static let empty = HoldingPriceSeries(
        points: [],
        timeDomain: nil,
        baselinePrice: nil
    )
}
