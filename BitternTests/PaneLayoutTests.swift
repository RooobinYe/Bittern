import CoreGraphics
import Testing
@testable import Bittern

@Suite
struct PaneArrangementTests {
    /// iPhone Duo's inner display, less its bars: the bars run down the
    /// side in landscape, as measured, and stay at the top and bottom in
    /// portrait.
    private let innerLandscape = CGSize(width: 867, height: 553)
    private let innerPortrait = CGSize(width: 669, height: 790)

    /// Partially folded like a book: the fold runs top to bottom.
    private let bookFold = FoldDivision(frame: CGRect(x: 455, y: -40, width: 40, height: 700))
    /// Partially folded like a laptop: the fold runs side to side.
    private let laptopFold = FoldDivision(frame: CGRect(x: -20, y: 345, width: 710, height: 40))

    @Test func dashboardStaysOneColumnOnPhones() {
        let panes = DashboardLayoutMetrics.panes
        #expect(panes.arrangement(in: CGSize(width: 402, height: 760), fold: nil) == .single)
        #expect(panes.arrangement(in: innerPortrait, fold: nil) == .single)
    }

    @Test func dashboardSplitsOnceBothColumnsFit() {
        let panes = DashboardLayoutMetrics.panes
        // 320 + 28 + 360: the threshold follows from the columns.
        #expect(panes.minimumColumnsWidth == 708)
        #expect(panes.arrangement(in: CGSize(width: 708, height: 600), fold: nil) == .columns(leadingWidth: 320, gap: 28))
        #expect(panes.arrangement(in: CGSize(width: 707, height: 600), fold: nil) == .single)
        #expect(panes.arrangement(in: CGSize(width: 900, height: 459), fold: nil) == .single)
        #expect(panes.arrangement(in: innerLandscape, fold: nil) == .columns(leadingWidth: 440, gap: 28))
        // Tall is fine for the dashboard: an iPad in portrait splits, its
        // allocation narrower so the holdings keep their minimum.
        #expect(panes.arrangement(in: CGSize(width: 820, height: 1_100), fold: nil) == .columns(leadingWidth: 432, gap: 28))
    }

    @Test func partsMeetAtTheFold() {
        let panes = DashboardLayoutMetrics.panes
        #expect(panes.arrangement(in: innerLandscape, fold: bookFold) == .columns(leadingWidth: 455, gap: 40))
        #expect(panes.arrangement(in: innerPortrait, fold: laptopFold) == .rows(topHeight: 345, gap: 40))
    }

    @Test func aFoldThatLeavesTooLittleRoomIsCrossed() {
        let panes = DashboardLayoutMetrics.panes
        // 760 - 435 - 40 = 285 is too narrow for the holdings.
        let narrowTrailing = FoldDivision(frame: CGRect(x: 435, y: 0, width: 40, height: 620))
        #expect(panes.arrangement(in: CGSize(width: 760, height: 620), fold: narrowTrailing) == .columns(leadingWidth: 372, gap: 28))
        // 669 - 600 - 40 = 29 is too short for the holdings.
        let lowFold = FoldDivision(frame: CGRect(x: 0, y: 600, width: 669, height: 40))
        #expect(panes.arrangement(in: innerPortrait, fold: lowFold) == .single)
    }

    @Test func chartScreensGoSideBySideOnlyWhenWide() {
        let history = PortfolioHistoryView.panes
        #expect(history.arrangement(in: innerPortrait, fold: nil) == .single)
        #expect(history.arrangement(in: innerLandscape, fold: nil) == .columns(leadingWidth: 260, gap: 24))
        #expect(history.arrangement(in: CGSize(width: 820, height: 1_100), fold: nil) == .single)
        #expect(history.arrangement(in: innerPortrait, fold: laptopFold) == .rows(topHeight: 345, gap: 40))
    }

    @Test func aPreferredTrailingWidthLeavesTheRestToTheLeadingPart() {
        let detail = HoldingDetailView.panes
        #expect(detail.arrangement(in: innerLandscape, fold: nil) == .columns(leadingWidth: 517, gap: 20))
        // 680 - 20 - 330 = 330 is under the chart's minimum of 360.
        #expect(detail.arrangement(in: CGSize(width: 680, height: 400), fold: nil) == .columns(leadingWidth: 360, gap: 20))
        #expect(detail.arrangement(in: innerLandscape, fold: bookFold) == .columns(leadingWidth: 455, gap: 40))
    }
}

@Suite
struct RangeRowLayoutTests {
    @Test func aNarrowRowSpreadsItsRangesAcross() {
        let slots = RangeRowLayout.slots(widths: Array(repeating: 44, count: 8), in: 362, maximumSpare: 32)
        #expect(slots.first?.minX == 0)
        let last = slots.last.map { $0.minX + $0.width }
        #expect(last == 362)
    }

    @Test func aWideRowGathersItsRangesInTheMiddle() {
        let slots = RangeRowLayout.slots(widths: [40, 40, 40, 40], in: 600, maximumSpare: 32)
        // Each range gets 40 + 32; the 312 left over splits between the ends.
        #expect(slots.map(\.width) == [72, 72, 72, 72])
        #expect(slots.map(\.minX) == [156, 228, 300, 372])
    }

    @Test func aRowTooNarrowForItsRangesStartsAtTheEdge() {
        let slots = RangeRowLayout.slots(widths: [60, 60, 60], in: 150, maximumSpare: 32)
        #expect(slots.map(\.minX) == [0, 60, 120])
        #expect(slots.map(\.width) == [60, 60, 60])
    }
}
