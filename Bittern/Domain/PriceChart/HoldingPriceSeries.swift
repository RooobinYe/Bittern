//
//  HoldingPriceSeries.swift
//  Bittern
//

import Foundation

enum HoldingChartRange: String, CaseIterable, Identifiable, Codable {
    case oneDay = "1D"
    case fiveDays = "5D"
    case oneMonth = "1M"
    case threeMonths = "3M"
    case yearToDate = "YTD"
    case oneYear = "1Y"
    case fiveYears = "5Y"
    case max = "MAX"

    var id: String { rawValue }

    var title: String { rawValue }

    /// How long into the year YTD waits before it shows: a week holds a few
    /// closes, so YTD is a chart of its own rather than a sparse 5D.
    static let yearToDateMinimumAge = DateComponents(day: 7)

    /// The ranges a holding has a full stretch of history for. 1D, 5D and
    /// MAX always show; 1M, 3M, 1Y and 5Y only once the holding has traded
    /// that long, and YTD only when it traded before this year began (or
    /// YTD would just be MAX) and the year is a week old. With no first
    /// trade date only the week rule applies.
    static func available(
        firstTradeDate: Date?,
        at now: Date,
        calendar: Calendar = .current
    ) -> [HoldingChartRange] {
        allCases.filter { range in
            let start: Date?
            switch range {
            case .oneDay, .fiveDays, .max:
                return true
            case .oneMonth:
                start = calendar.date(byAdding: .month, value: -1, to: now)
            case .threeMonths:
                start = calendar.date(byAdding: .month, value: -3, to: now)
            case .yearToDate:
                guard let yearStart = calendar.dateInterval(of: .year, for: now)?.start,
                      let shownFrom = calendar.date(byAdding: yearToDateMinimumAge, to: yearStart),
                      shownFrom <= now
                else {
                    return false
                }
                start = yearStart
            case .oneYear:
                start = calendar.date(byAdding: .year, value: -1, to: now)
            case .fiveYears:
                start = calendar.date(byAdding: .year, value: -5, to: now)
            }
            guard let firstTradeDate, let start else { return true }
            return firstTradeDate <= start
        }
    }

    var summaryLabel: String {
        switch self {
        case .oneDay:
            "Today"
        case .fiveDays:
            "Last week"
        case .oneMonth:
            "1 month"
        case .threeMonths:
            "3 months"
        case .yearToDate:
            "Year to date"
        case .oneYear:
            "1 year"
        case .fiveYears:
            "5 years"
        case .max:
            "Max"
        }
    }

    /// The price a range's change is measured from. 1D starts from the
    /// close before its trading day and YTD from the close before the
    /// year, both carried by the series; YTD has no fallback, so a missing
    /// close shows no change rather than one measured from the wrong day.
    /// Every other range starts from its own first point.
    func detailChangeBasePrice(
        previousClose: Double?,
        seriesBaseline: Double?,
        seriesFirstPrice: Double?
    ) -> Double? {
        switch self {
        case .oneDay:
            return seriesBaseline ?? previousClose
        case .yearToDate:
            return seriesBaseline
        case .fiveDays, .oneMonth, .threeMonths, .oneYear, .fiveYears, .max:
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
    /// The close the change is measured from, where it isn't the first
    /// point: the previous session's for 1D, last year's final one for YTD.
    let baselinePrice: Double?
    /// When the holding first traded, if the source says.
    var firstTradeDate: Date? = nil

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
