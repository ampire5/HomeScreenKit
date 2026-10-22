import Foundation

/// One cell of the filmstrip: `range` is the items it stands for and `item` the one it shows (the middle of the
/// range). `start` is its leading edge in points from the strip view's leading edge, `length` its extent along the
/// strip (the strip's thickness is the layout's).
public struct FilmstripCell: Equatable, Sendable {
    public let range: Range<Int>
    public let item: Int
    public let start: Double
    public let length: Double
}

/// The filmstrip as Photos' strip: one narrow cell per item on a line that moves under the strip's fixed centre,
/// the current item there in its own proportions. Pure arithmetic in points, no AppKit. Positions are `along` the
/// strip, its `thickness` is `across` it; nothing here depends on `axis`.
///
/// Every cell shares one length `cellLength` — the strip's length over the item count, kept between 9:16 of the
/// thickness (`narrowAspect`, many items) and `maxAspect` of it (few items) — but is never longer than its item
/// (`narrowLength(of:)`). The base line lays the narrow cells out with a `gapRatio` gap from 0; an offset is the base
/// position under the strip's centre. At rest the current cell expands (`expansion` 0 → 1) to its item's proportions
/// with `currentPaddingRatio` on each side, around its own centre, pushing its neighbours apart; the base line, and so
/// the item under a point, ignores that expansion.
///
/// While no known item is narrower than `cellLength` the base line is a formula; otherwise its cell starts are
/// prefix sums made once here (O(n)) and searched by bisection. A window of cells costs O(visible cells) either way.
public struct FilmstripLayout: Equatable, Sendable {
    /// The narrow cell's aspect (length : thickness) in a big list: 9:16, as Photos.
    public static let narrowAspect = 0.5625
    /// The gap between cells, as a share of the thickness.
    public static let gapRatio = 0.028
    /// The corner radius as a share of the thickness (3 pt ≈ 0.045 · 68).
    public static let radiusRatio = 0.045
    /// The expanded current cell's space on each side, as a share of the thickness.
    public static let currentPaddingRatio = 0.12
    /// The length of the fading edges, as a share of the thickness.
    public static let fadeRatio = 0.85
    /// The current cell's aspect while its item's is not known.
    public static let unknownCurrentAspect = 1.5

    public let axis: FilmstripAxis
    public let itemCount: Int
    public let length: Double
    public let thickness: Double
    /// The length every cell shares (0 for no items).
    public let cellLength: Double
    public let gap: Double
    /// The aspects by item (`nil`: not known); shorter than the list while they arrive.
    private let aspects: [Double?]
    /// The leading edge of each narrow cell on the base line, plus the end (`itemCount + 1` values); empty while
    /// every cell is `cellLength` long.
    private let starts: [Double]

    public init(axis: FilmstripAxis = .horizontal, itemCount: Int, length: Double, thickness: Double,
                maxAspect: Double, aspects: [Double?]) {
        self.axis = axis
        self.itemCount = max(0, itemCount)
        self.length = length
        self.thickness = thickness
        self.aspects = aspects
        gap = Self.gapRatio * thickness
        if self.itemCount == 0 {
            cellLength = 0
        } else {
            let lower = Self.narrowAspect * thickness, upper = max(lower, maxAspect * thickness)
            cellLength = min(max(length / Double(self.itemCount), lower), upper)
        }
        let cellLength = cellLength, thickness = thickness
        let narrower = aspects.prefix(self.itemCount).contains { $0.map { $0 * thickness < cellLength } ?? false }
        guard narrower else {
            starts = []
            return
        }
        var starts = [Double](repeating: 0, count: self.itemCount + 1)
        var position = 0.0
        for item in 0..<self.itemCount {
            starts[item] = position
            let aspect = item < aspects.count ? aspects[item] : nil
            position += (aspect.map { min(cellLength, $0 * thickness) } ?? cellLength) + gap
        }
        starts[self.itemCount] = position
        self.starts = starts
    }

    /// The item's cell length while it is not the expanded current one: `cellLength`, or its aspect's length at the
    /// thickness when that is shorter.
    public func narrowLength(of item: Int) -> Double {
        guard item >= 0, item < aspects.count, let aspect = aspects[item] else { return cellLength }
        return min(cellLength, aspect * thickness)
    }

    /// The base position of the item's leading edge.
    private func start(of item: Int) -> Double {
        starts.isEmpty ? Double(item) * (cellLength + gap) : starts[item]
    }

    /// The base position of the item's centre: every cell narrow, gaps only.
    public func centre(of item: Int) -> Double {
        start(of: item) + narrowLength(of: item) / 2
    }

    /// The item whose cell, with half a gap on each side, holds base position `position`; the first or last beyond
    /// the ends; nil for no items.
    public func item(atBase position: Double) -> Int? {
        guard itemCount > 0 else { return nil }
        let shifted = position + gap / 2
        if starts.isEmpty {
            let item = Int((shifted / (cellLength + gap)).rounded(.down).clamped(to: -1...Double(itemCount)))
            return min(max(item, 0), itemCount - 1)
        }
        // The last item whose start is at or before `shifted`.
        var low = 0, high = itemCount - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= shifted { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// The offsets that put an item under the centre: the first item's to the last's.
    public var offsetRange: ClosedRange<Double> {
        guard itemCount > 0 else { return 0...0 }
        return centre(of: 0)...centre(of: itemCount - 1)
    }

    /// The length of the fading edges.
    public var fadeLength: Double { Self.fadeRatio * thickness }

    /// How far each edge of `cells` (as `cells(offset:current:expansion:)` gives them) fades: `fadeLength` where the
    /// strip goes on past that edge, so it shows there is more, 0 where it ends inside the view; never over the
    /// current cell.
    public func fades(cells: [FilmstripCell], current: Int) -> (start: Double, end: Double) {
        guard let first = cells.first, let last = cells.last else { return (0, 0) }
        var start = first.start < 0 ? fadeLength : 0
        var end = last.start + last.length > length ? fadeLength : 0
        if let shown = cells.first(where: { $0.item == current }) {
            start = min(start, max(0, shown.start))
            end = min(end, max(0, length - shown.start - shown.length))
        }
        return (start, end)
    }

    /// The cells on screen, plus one beyond each edge, in order, in view positions: base position `offset` at the
    /// strip's centre, `current` expanded by `expansion` (0 narrow … 1 its item's proportions, padded).
    public func cells(offset: Double, current: Int, expansion: Double) -> [FilmstripCell] {
        guard itemCount > 0, let middle = item(atBase: offset) else { return [] }
        let e = min(max(expansion, 0), 1)
        var grown = 0.0, padding = gap
        if e > 0, current >= 0, current < itemCount {
            let narrow = narrowLength(of: current)
            let aspect = (current < aspects.count ? aspects[current] : nil) ?? Self.unknownCurrentAspect
            let full = min(max(aspect * thickness, narrow), length)
            grown = (full - narrow) * e
            padding = gap + (Self.currentPaddingRatio * thickness - gap) * e
        }
        // The current cell grows around its centre; every cell beyond it moves out by half of that and the
        // padding's extra.
        let shift = grown / 2 + (padding - gap)
        let origin = length / 2 - offset
        func cell(_ item: Int) -> FilmstripCell {
            let narrow = narrowLength(of: item)
            let start: Double, extent: Double
            if item == current && grown > 0 {
                extent = narrow + grown
                start = origin + centre(of: item) - extent / 2
            } else {
                extent = narrow
                start = origin + self.start(of: item) + (item < current ? -shift : item > current ? shift : 0)
            }
            return FilmstripCell(range: item..<(item + 1), item: item, start: start, length: extent)
        }
        var before: [FilmstripCell] = [], after: [FilmstripCell] = []
        var item = middle - 1
        while item >= 0 {
            let c = cell(item)
            before.append(c)
            if c.start + c.length < 0 { break }
            item -= 1
        }
        item = middle + 1
        while item < itemCount {
            let c = cell(item)
            after.append(c)
            if c.start > length { break }
            item += 1
        }
        return before.reversed() + [cell(middle)] + after
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double { min(max(self, range.lowerBound), range.upperBound) }
}
