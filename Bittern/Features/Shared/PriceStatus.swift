//
//  PriceStatus.swift
//  Bittern
//
//  Whether the figures on screen are current. There is no status text:
//  figures that aren't current turn gray, and VoiceOver says since when.
//

import SwiftUI

/// Whether the prices on screen are current.
enum PriceStatus: Equatable {
    case current
    /// The last data, shown in gray because current prices can't be had.
    /// `since` is when every price was last known.
    case stale(since: Date?)

    var isStale: Bool {
        self != .current
    }

    /// The color for a large figure, such as a total or a price: its own
    /// while current, gray otherwise.
    func keyFigureColor(_ current: Color) -> Color {
        isStale ? BitternTheme.staleKeyFigure : current
    }

    /// The color for a smaller figure, such as a change.
    func figureColor(_ current: Color) -> Color {
        isStale ? BitternTheme.staleFigure : current
    }

    /// `text` as VoiceOver should read it: with when it was last current,
    /// when it isn't.
    func accessibilityLabel(for text: String, now: Date = Date()) -> String {
        guard case .stale(let since) = self else { return text }
        return "\(text), \(PortfolioFormat.notUpdatedSince(since, relativeTo: now))"
    }
}

extension EnvironmentValues {
    /// Set where the data is shown: the dashboard, its shared image and a
    /// holding's detail.
    @Entry var priceStatus: PriceStatus = .current
}
