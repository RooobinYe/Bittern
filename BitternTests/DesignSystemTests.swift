import Foundation
import Testing
@testable import Bittern

@Suite
struct AllocationBandColorTests {
    @Test func oneColorPerBand() {
        #expect(BitternTheme.allocationBandColors(count: 0).isEmpty)
        #expect(BitternTheme.allocationBandColors(count: 1).count == 1)
        #expect(BitternTheme.allocationBandColors(count: 7).count == 7)
    }

    @Test func holdingsWearTheirBandsColors() {
        let large = makeHolding(symbol: "LRG", quantity: 60, currentPrice: 100)
        let medium = makeHolding(symbol: "MED", quantity: 30, currentPrice: 100)
        // Each under 5% of the total, so they share the small-holdings band.
        let small = makeHolding(symbol: "SML", quantity: 4, currentPrice: 100)
        let smaller = makeHolding(symbol: "SMR", quantity: 3, currentPrice: 100)
        let unpriced = makeHolding(symbol: "UNP", currentPrice: nil)
        let holdings = [small, unpriced, large, smaller, medium]

        let colors = BitternTheme.holdingAllocationColors(for: holdings)
        let bands = BitternTheme.allocationBandColors(count: 3)

        #expect(colors[large.id] == bands[0])
        #expect(colors[medium.id] == bands[1])
        #expect(colors[small.id] == bands[2])
        #expect(colors[smaller.id] == bands[2])
        #expect(colors[unpriced.id] == nil)
        #expect(
            BitternTheme.holdingAllocationColor(for: unpriced, in: holdings)
                == BitternTheme.unallocatedHoldingColor
        )
    }
}

@Suite
struct PerformanceModeTests {
    @Test func nextSwitchesBetweenTheTwoModes() {
        #expect(PerformanceMode.today.next == .allTime)
        #expect(PerformanceMode.allTime.next == .today)
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

    @Test func valueTicksAreRoundAndInsideTheRange() {
        let geometry = PerformanceChartGeometry(
            values: [40.21, 40.63],
            positions: [0, 1],
            baseValue: nil
        )
        let ticks = geometry.valueTicks(avoiding: nil)

        #expect((2...4).contains(ticks.count))
        #expect(ticks.allSatisfy { geometry.yDomain.contains($0) })
        // Evenly spaced on round cents.
        let steps = zip(ticks, ticks.dropFirst()).map { $1 - $0 }
        #expect(steps.allSatisfy { abs($0 - steps[0]) < 1e-9 })
        #expect(ticks.allSatisfy { abs(($0 * 100).rounded() - $0 * 100) < 1e-6 })
    }

    @Test func valueTicksMakeRoomForTheBaselinesLabel() {
        let geometry = PerformanceChartGeometry(
            values: [17.9, 52.4],
            positions: [0, 1],
            baseValue: 17.88
        )
        let span = geometry.yDomain.upperBound - geometry.yDomain.lowerBound
        let ticks = geometry.valueTicks(avoiding: 17.88)

        #expect(!ticks.isEmpty)
        #expect(ticks.allSatisfy { abs($0 - 17.88) >= span * 0.1 })
        #expect(ticks.allSatisfy { $0 == $0.rounded() })
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

    @Test func aUnitIsSingularOnlyForExactlyOne() {
        #expect(PortfolioFormat.quantityWithUnit(1, unit: .shares, locale: us) == "1 share")
        #expect(PortfolioFormat.quantityWithUnit(84, unit: .shares, locale: us) == "84 shares")
        #expect(PortfolioFormat.quantityWithUnit(0.1, unit: .shares, locale: us) == "0.10 shares")
        #expect(PortfolioFormat.quantityWithUnit(1.000001, unit: .shares, locale: us) == "1.00 shares")
        #expect(PortfolioFormat.quantityWithUnit(0, unit: .shares, locale: us) == "0 shares")
        #expect(PortfolioFormat.quantityWithUnit(1, unit: .tokens, locale: us) == "1 token")
        #expect(PortfolioFormat.quantityWithUnit(0.07, unit: .tokens, locale: us) == "0.07 tokens")
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
