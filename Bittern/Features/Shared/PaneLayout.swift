//
//  PaneLayout.swift
//  Bittern
//
//  Screens with two parts, such as the allocation and the holdings, place
//  them by the space they measure, never by device: one column, side by
//  side, or on either side of the fold of a partially folded display.
//

import SwiftUI

/// Where the fold of a partially folded display crosses a view, in the
/// view's own coordinates, with the margins that keep content clear of it.
nonisolated struct FoldDivision: Equatable, Sendable {
    let frame: CGRect

    /// A fold running top to bottom divides the view into leading and
    /// trailing halves, as in a book; one running side to side, into top
    /// and bottom, as in a laptop.
    var runsTopToBottom: Bool {
        frame.height > frame.width
    }
}

/// How a screen places its two parts.
nonisolated enum PaneArrangement: Equatable, Sendable {
    /// One column, the first part above the second.
    case single
    /// Side by side: the leading part this wide, then the gap.
    case columns(leadingWidth: CGFloat, gap: CGFloat)
    /// Above and below a fold: the top part this tall, then the gap.
    case rows(topHeight: CGFloat, gap: CGFloat)

    var isRows: Bool {
        if case .rows = self { true } else { false }
    }
}

/// What a screen's two parts need, from which their arrangement follows.
nonisolated struct PaneRequirements: Equatable, Sendable {
    /// The width that the side-by-side parts take when there is no fold to
    /// meet: a fixed width for one of them, the other taking the rest.
    enum PreferredWidth: Equatable, Sendable {
        case leading(CGFloat)
        case trailing(CGFloat)
    }

    let minimumLeadingWidth: CGFloat
    let minimumTrailingWidth: CGFloat
    let preferredWidth: PreferredWidth
    let columnSpacing: CGFloat
    /// The least height in which the parts make sense side by side.
    let minimumColumnsHeight: CGFloat
    /// True when side by side is for giving a chart or a form its height
    /// back, which a view taller than wide already has.
    var columnsOnlyWhenWide = false
    /// The least height of each part above and below a fold.
    let minimumRowHeight: CGFloat

    /// The narrowest view that holds both parts side by side.
    var minimumColumnsWidth: CGFloat {
        minimumLeadingWidth + columnSpacing + minimumTrailingWidth
    }

    func arrangement(in size: CGSize, fold: FoldDivision?) -> PaneArrangement {
        if let fold, let arrangement = arrangement(in: size, meeting: fold) {
            return arrangement
        }

        guard size.width >= minimumColumnsWidth,
              size.height >= minimumColumnsHeight,
              !columnsOnlyWhenWide || size.width > size.height else {
            return .single
        }

        let leadingWidth = switch preferredWidth {
        case .leading(let width): width
        case .trailing(let width): size.width - columnSpacing - width
        }
        let widest = size.width - columnSpacing - minimumTrailingWidth
        return .columns(
            leadingWidth: min(max(leadingWidth, minimumLeadingWidth), widest),
            gap: columnSpacing
        )
    }

    /// The parts on either side of the fold, or nil when a side is too
    /// small for its part. Content then crosses the fold, which scrolling
    /// content may.
    private func arrangement(in size: CGSize, meeting fold: FoldDivision) -> PaneArrangement? {
        if fold.runsTopToBottom {
            let leadingWidth = fold.frame.minX
            let trailingWidth = size.width - fold.frame.maxX
            guard leadingWidth >= minimumLeadingWidth, trailingWidth >= minimumTrailingWidth else { return nil }
            return .columns(leadingWidth: leadingWidth, gap: fold.frame.width)
        } else {
            let topHeight = fold.frame.minY
            let bottomHeight = size.height - fold.frame.maxY
            guard topHeight >= minimumRowHeight, bottomHeight >= minimumRowHeight else { return nil }
            return .rows(topHeight: topHeight, gap: fold.frame.height)
        }
    }
}

/// Measures the space it is given and where a fold crosses it.
struct PaneGeometryReader<Content: View>: View {
    @ViewBuilder let content: (CGSize, FoldDivision?) -> Content

    var body: some View {
        GeometryReader { proxy in
            content(proxy.size, Self.fold(in: proxy))
        }
    }

    private static func fold(in proxy: GeometryProxy) -> FoldDivision? {
        guard #available(iOS 27.1, *) else { return nil }
        return proxy.reservedRegions(kind: .division)
            .first { $0.isActive }
            .map { FoldDivision(frame: $0.frame) }
    }
}

/// Two parts side by side or above and below, as an arrangement says.
/// `.single` has no second place, so screens lay that out themselves.
struct PaneSplit<First: View, Second: View>: View {
    let arrangement: PaneArrangement
    /// Space between the parts and the view's edges. It goes inside each
    /// part, so the parts still meet the fold where it is.
    var margins = EdgeInsets()
    @ViewBuilder let first: First
    @ViewBuilder let second: Second

    var body: some View {
        switch arrangement {
        case .single:
            VStack(spacing: 0) {
                first
                second
            }
            .padding(margins)
        case .columns(let leadingWidth, let gap):
            HStack(alignment: .top, spacing: gap) {
                first
                    .padding(.leading, margins.leading)
                    .padding(.top, margins.top)
                    .padding(.bottom, margins.bottom)
                    .frame(width: leadingWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
                second
                    .padding(.trailing, margins.trailing)
                    .padding(.top, margins.top)
                    .padding(.bottom, margins.bottom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        case .rows(let topHeight, let gap):
            VStack(spacing: gap) {
                first
                    .padding(.horizontal, margins.leading)
                    .padding(.top, margins.top)
                    .frame(height: topHeight)
                    .frame(maxWidth: .infinity, alignment: .top)
                second
                    .padding(.horizontal, margins.leading)
                    .padding(.bottom, margins.bottom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }
}
