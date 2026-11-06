//
//  BubbleRingLayout.swift
//  Bittern
//
//  Places the donut's allocation bubbles around the ring without letting
//  neighbours overlap.
//

import SwiftUI

/// Where each bubble goes on the ring: its angle, and whether it moved to the
/// outer of two staggered rings because one ring couldn't hold them all.
nonisolated struct BubblePlacement: Equatable {
    /// Radians, clockwise from three o'clock, as `cos` and `sin` expect.
    var angle: Double
    var isOuter: Bool
}

nonisolated enum BubbleRingArrangement {
    /// Spreads bubbles that sit too close together along the circle.
    ///
    /// - Parameters:
    ///   - preferredAngles: Each bubble's slice midpoint, in radians.
    ///   - widths: Each bubble's width, in points.
    ///   - radius: The radius of the circle the bubbles' centres sit on.
    ///   - padding: The space to keep between neighbours, in points.
    /// - Returns: One placement per bubble, in the order given. When the
    ///   bubbles need more than a full turn, alternate ones move to an outer
    ///   ring and each ring is spread on its own.
    static func placements(
        preferredAngles: [Double],
        widths: [Double],
        radius: Double,
        padding: Double = 4
    ) -> [BubblePlacement] {
        precondition(preferredAngles.count == widths.count)
        guard !preferredAngles.isEmpty else { return [] }
        guard radius > 0 else {
            return preferredAngles.map { BubblePlacement(angle: $0, isOuter: false) }
        }

        let order = preferredAngles.indices.sorted { preferredAngles[$0] < preferredAngles[$1] }
        let required = totalSeparation(widths: order.map { widths[$0] }, radius: radius, padding: padding)

        guard required > 2 * .pi, order.count > 1 else {
            let angles = spread(
                angles: order.map { preferredAngles[$0] },
                widths: order.map { widths[$0] },
                radius: radius,
                padding: padding
            )
            return arranged(angles: angles, order: order, isOuter: { _ in false }, count: preferredAngles.count)
        }

        // Alternate bubbles, in ring order, between the inner and outer ring.
        var placements = Array(repeating: BubblePlacement(angle: 0, isOuter: false), count: preferredAngles.count)
        for isOuter in [false, true] {
            let ring = order.enumerated().filter { ($0.offset % 2 == 1) == isOuter }.map(\.element)
            let angles = spread(
                angles: ring.map { preferredAngles[$0] },
                widths: ring.map { widths[$0] },
                radius: radius,
                padding: padding
            )
            for (index, angle) in zip(ring, angles) {
                placements[index] = BubblePlacement(angle: angle, isOuter: isOuter)
            }
        }
        return placements
    }

    /// The smallest angle between the centres of two bubbles on the circle
    /// that keeps them `padding` apart.
    static func minimumSeparation(
        _ lhsWidth: Double,
        _ rhsWidth: Double,
        radius: Double,
        padding: Double
    ) -> Double {
        let chord = (lhsWidth + rhsWidth) / 2 + padding
        return 2 * asin(min(chord / (2 * radius), 1))
    }

    private static func totalSeparation(widths: [Double], radius: Double, padding: Double) -> Double {
        guard widths.count > 1 else { return 0 }
        return widths.indices.reduce(0) { total, index in
            total + minimumSeparation(
                widths[index],
                widths[(index + 1) % widths.count],
                radius: radius,
                padding: padding
            )
        }
    }

    /// Relaxes sorted angles until every neighbour pair, including the last
    /// and the first across the full turn, is at least its minimum apart.
    /// Each pass pushes both bubbles of a crowded pair away from each other
    /// by half the shortfall, so a cluster spreads around its own centre.
    private static func spread(
        angles: [Double],
        widths: [Double],
        radius: Double,
        padding: Double
    ) -> [Double] {
        var angles = angles
        let count = angles.count
        guard count > 1 else { return angles }

        let separations = (0..<count).map { index in
            minimumSeparation(widths[index], widths[(index + 1) % count], radius: radius, padding: padding)
        }
        // A single ring that can't hold its bubbles shares the shortfall
        // evenly instead of pushing forever.
        let total = separations.reduce(0, +)
        let scale = total > 2 * .pi ? 2 * .pi / total : 1

        for _ in 0..<200 {
            var moved = false
            for index in 0..<count {
                let next = (index + 1) % count
                let nextAngle = next == 0 ? angles[0] + 2 * .pi : angles[next]
                let gap = nextAngle - angles[index]
                let shortfall = separations[index] * scale - gap
                guard shortfall > 1e-6 else { continue }

                angles[index] -= shortfall / 2
                if next == 0 {
                    angles[0] += shortfall / 2
                } else {
                    angles[next] += shortfall / 2
                }
                moved = true
            }
            if !moved { break }
        }
        return angles
    }

    private static func arranged(
        angles: [Double],
        order: [Int],
        isOuter: (Int) -> Bool,
        count: Int
    ) -> [BubblePlacement] {
        var placements = Array(repeating: BubblePlacement(angle: 0, isOuter: false), count: count)
        for (index, angle) in zip(order, angles) {
            placements[index] = BubblePlacement(angle: angle, isOuter: isOuter(index))
        }
        return placements
    }
}

/// Lays bubbles out on a circle around the centre of its bounds, each near
/// its preferred angle, measured at its real size so text size changes are
/// accounted for.
struct BubbleRingLayout: Layout {
    /// The radius of the ring of bubble centres.
    let radius: CGFloat
    /// How far an outer-ring bubble sits beyond `radius`.
    let outerRingOffset: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let placements = BubbleRingArrangement.placements(
            preferredAngles: subviews.map { $0[PreferredBubbleAngle.self] },
            widths: sizes.map { Double($0.width) },
            radius: Double(radius)
        )

        for (index, subview) in subviews.enumerated() {
            let placement = placements[index]
            let ringRadius = radius + (placement.isOuter ? outerRingOffset : 0)
            let size = sizes[index]
            // Large text can make a bubble wider than the margin left for it;
            // it slides inward rather than off the edge.
            let x = bounds.midX + cos(placement.angle) * ringRadius
            let y = bounds.midY + sin(placement.angle) * ringRadius
            subview.place(
                at: CGPoint(
                    x: min(max(x, bounds.minX + size.width / 2), bounds.maxX - size.width / 2),
                    y: min(max(y, bounds.minY + size.height / 2), bounds.maxY - size.height / 2)
                ),
                anchor: .center,
                proposal: ProposedViewSize(sizes[index])
            )
        }
    }
}

nonisolated private struct PreferredBubbleAngle: LayoutValueKey {
    static let defaultValue: Double = 0
}

extension View {
    /// The angle, in radians, a bubble in a `BubbleRingLayout` would sit at
    /// if nothing were in its way.
    func preferredBubbleAngle(_ angle: Double) -> some View {
        layoutValue(key: PreferredBubbleAngle.self, value: angle)
    }
}
