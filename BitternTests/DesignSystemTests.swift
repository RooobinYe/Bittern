import Foundation
import Testing
@testable import Bittern

@Suite
struct BubbleRingArrangementTests {
    private let radius = 140.0

    /// The gap, in radians, from each placement to the next around the ring.
    private func gaps(_ angles: [Double]) -> [Double] {
        let sorted = angles.sorted()
        return sorted.indices.map { index in
            index + 1 < sorted.count
                ? sorted[index + 1] - sorted[index]
                : sorted[0] + 2 * .pi - sorted[index]
        }
    }

    @Test func bubblesWithRoomStayAtTheirSlices() {
        let preferred = [0.0, 2.0, 4.0]
        let placements = BubbleRingArrangement.placements(
            preferredAngles: preferred,
            widths: [70, 70, 70],
            radius: radius
        )

        #expect(placements.map(\.angle) == preferred)
        #expect(placements.allSatisfy { !$0.isOuter })
    }

    @Test func crowdedNeighboursSpreadToTheirMinimumSeparation() {
        let preferred = [1.0, 1.05, 1.1, 4.0]
        let widths = [70.0, 70, 70, 70]
        let placements = BubbleRingArrangement.placements(
            preferredAngles: preferred,
            widths: widths,
            radius: radius
        )
        let minimum = BubbleRingArrangement.minimumSeparation(70, 70, radius: radius, padding: 4)

        #expect(gaps(placements.map(\.angle)).allSatisfy { $0 >= minimum - 1e-6 })
        // The cluster spreads around its own middle rather than drifting.
        #expect(abs(placements[1].angle - 1.05) < 1e-6)
        #expect(placements.allSatisfy { !$0.isOuter })
    }

    @Test func spreadingKeepsTheOrderAroundTheRing() {
        let preferred = [0.30, 0.32, 0.34, 0.36, 0.38]
        let placements = BubbleRingArrangement.placements(
            preferredAngles: preferred,
            widths: Array(repeating: 60, count: preferred.count),
            radius: radius
        )
        let angles = placements.map(\.angle)

        #expect(angles == angles.sorted())
    }

    @Test func tooManyForOneRingAlternateWithAnOuterRing() {
        let count = 16
        let preferred = (0..<count).map { Double($0) / Double(count) * 2 * .pi }
        let placements = BubbleRingArrangement.placements(
            preferredAngles: preferred,
            widths: Array(repeating: 70, count: count),
            radius: radius
        )

        #expect(placements.filter(\.isOuter).count == count / 2)
        for index in 0..<count {
            #expect(placements[index].isOuter == (index % 2 == 1))
        }
    }

    @Test func noBubblesNoPlacements() {
        #expect(BubbleRingArrangement.placements(preferredAngles: [], widths: [], radius: radius).isEmpty)
    }
}

@Suite
struct ContrastingForegroundTests {
    private func luminance(_ hex: Int) -> Double {
        func linear(_ component: Int) -> Double {
            let value = Double(component) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return ContrastingForeground.relativeLuminance(
            linearRed: linear(hex >> 16 & 0xFF),
            linearGreen: linear(hex >> 8 & 0xFF),
            linearBlue: linear(hex & 0xFF)
        )
    }

    @Test func lightBackgroundsGetBlackText() {
        #expect(ContrastingForeground.preferred(onLuminance: luminance(0xFFFFFF)) == .black)
        // A muted orange, where white text manages only about 2.7:1.
        #expect(ContrastingForeground.preferred(onLuminance: luminance(0xC99A6B)) == .black)
    }

    @Test func darkBackgroundsGetWhiteText() {
        #expect(ContrastingForeground.preferred(onLuminance: luminance(0x000000)) == .white)
        #expect(ContrastingForeground.preferred(onLuminance: luminance(0x3A3A8C)) == .white)
    }

    @Test func gainAndLossColorsReadOnWhite() {
        let white = luminance(0xFFFFFF)
        #expect(ContrastingForeground.contrastRatio(luminance(0x217F38), white) >= 4.5)
        #expect(ContrastingForeground.contrastRatio(luminance(0xD70015), white) >= 4.5)
        // The grouped list background is a little darker than white.
        let grouped = luminance(0xF2F2F7)
        #expect(ContrastingForeground.contrastRatio(luminance(0x217F38), grouped) >= 4.5)
        #expect(ContrastingForeground.contrastRatio(luminance(0xD70015), grouped) >= 4.5)
    }
}

@Suite
struct PerformanceChartRunsTests {
    @Test func oneStyleIsOneRun() {
        let runs = PerformanceChartRuns.runs(
            styles: [.primary, .primary, .primary],
            isPlotted: [true, true, true],
            selectedIndex: nil
        )

        #expect(runs == [PerformanceChartRun(indices: [0, 1, 2], style: .primary, isDimmed: false)])
    }

    @Test func theSegmentBetweenSessionsIsNeutralAndSharesItsEnds() {
        let runs = PerformanceChartRuns.runs(
            styles: [.primary, .primary, .neutral, .neutral],
            isPlotted: [true, true, true, true],
            selectedIndex: nil
        )

        #expect(runs == [
            PerformanceChartRun(indices: [0, 1], style: .primary, isDimmed: false),
            PerformanceChartRun(indices: [1, 2, 3], style: .neutral, isDimmed: false)
        ])
    }

    @Test func theLineAfterTheSelectionIsDimmed() {
        let runs = PerformanceChartRuns.runs(
            styles: [.primary, .primary, .primary, .primary],
            isPlotted: [true, true, true, true],
            selectedIndex: 1
        )

        #expect(runs == [
            PerformanceChartRun(indices: [0, 1], style: .primary, isDimmed: false),
            PerformanceChartRun(indices: [1, 2, 3], style: .primary, isDimmed: true)
        ])
    }

    @Test func anUnplottedPointBreaksTheLine() {
        let runs = PerformanceChartRuns.runs(
            styles: [.primary, .primary, .primary, .primary, .primary],
            isPlotted: [true, true, false, true, true],
            selectedIndex: nil
        )

        #expect(runs == [
            PerformanceChartRun(indices: [0, 1], style: .primary, isDimmed: false),
            PerformanceChartRun(indices: [3, 4], style: .primary, isDimmed: false)
        ])
    }

    @Test func fewerThanTwoPointsDrawNothing() {
        #expect(PerformanceChartRuns.runs(styles: [.primary], isPlotted: [true], selectedIndex: nil).isEmpty)
    }
}

@Suite
struct PerformanceChartGeometryTests {
    @Test func nearestIndexSkipsUnplottedPoints() {
        let geometry = PerformanceChartGeometry(
            values: [1, 2, 3, 4],
            positions: [0, 10, nil, 30],
            baseValue: nil
        )

        #expect(geometry.nearestIndex(to: 19) == 1)
        #expect(geometry.nearestIndex(to: 21) == 3)
        #expect(geometry.lastPlottedIndex == 3)
    }

    @Test func theValueRangeIncludesTheBaseline() {
        let geometry = PerformanceChartGeometry(
            values: [100, 110],
            positions: [0, 1],
            baseValue: 90
        )

        #expect(geometry.yDomain.lowerBound <= 90)
        #expect(geometry.yDomain.upperBound > 110)
    }

    @Test func axisTicksAreDistinctAndInsideTheEdges() {
        let geometry = PerformanceChartGeometry(
            values: Array(repeating: 1, count: 100),
            positions: (0..<100).map(Double.init),
            baseValue: nil
        )
        let ticks = geometry.axisTickIndices

        #expect(ticks.count == 4)
        #expect(Set(ticks).count == ticks.count)
        #expect(ticks.allSatisfy { $0 > 0 && $0 < 99 })
    }
}

@Suite
struct PortfolioFormatTests {
    private let us = Locale(identifier: "en_US")
    private let uk = Locale(identifier: "en_GB")

    @Test func signedMoneyShowsItsDirectionButNotOnZero() {
        #expect(PortfolioFormat.money(12.5, signed: true, locale: us) == "+$12.50")
        #expect(PortfolioFormat.money(-12.5, signed: true, locale: us) == "-$12.50")
        #expect(PortfolioFormat.money(0, signed: true, locale: us) == "$0.00")
        #expect(PortfolioFormat.money(-12.5, locale: us) == "-$12.50")
    }

    @Test func pricesBelowAHundredKeepATenthOfACent() {
        #expect(PortfolioFormat.price(12.345, locale: us) == "$12.345")
        #expect(PortfolioFormat.price(12.3, locale: us) == "$12.30")
        #expect(PortfolioFormat.price(123.456, locale: us) == "$123.46")
    }

    @Test func percentagesAndChanges() {
        #expect(PortfolioFormat.percent(0.1234, locale: us) == "12.34%")
        #expect(PortfolioFormat.percent(0.012, signed: true, locale: us) == "+1.20%")
        #expect(PortfolioFormat.percent(-0.012, signed: true, locale: us) == "-1.20%")
        #expect(PortfolioFormat.change(1_234.4, percent: 0.012, locale: us) == "+$1,234 (+1.20%)")
    }

    @Test func quantities() {
        #expect(PortfolioFormat.shares(84, locale: us) == "84")
        #expect(PortfolioFormat.shares(1.5, locale: us) == "1.50")
        #expect(PortfolioFormat.tokens(0.070001, locale: us) == "0.07")
        #expect(PortfolioFormat.preciseQuantity(1234.000000123, locale: us) == "1234.000000123")
    }

    @Test func timesFollowTheRegionsClock() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date()
        let afternoon = calendar.date(bySettingHour: 14, minute: 30, second: 5, of: now)!

        #expect(PortfolioFormat.lastUpdated(afternoon, relativeTo: afternoon, calendar: calendar, locale: uk) == "14:30:05")
        #expect(PortfolioFormat.lastUpdated(afternoon, relativeTo: afternoon, calendar: calendar, locale: us).contains("2:30:05"))
    }

    @Test func anOlderSnapshotStatesItsDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 9))!
        let earlier = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 16, minute: 5))!
        let lastYear = calendar.date(from: DateComponents(year: 2025, month: 11, day: 3, hour: 16, minute: 5))!

        let thisYear = PortfolioFormat.lastUpdated(earlier, relativeTo: now, calendar: calendar, locale: uk)
        #expect(thisYear.contains("3 Nov") && thisYear.contains("16:05") && !thisYear.contains("2026"))
        #expect(PortfolioFormat.lastUpdated(lastYear, relativeTo: now, calendar: calendar, locale: uk).contains("2025"))
    }
}
