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
/// the item under a point, ignores that expansion. A run of current items (two pages shown side by side) expands
/// together: each to its own proportions, with the plain gap between them and the padding outside the run, around the
/// run's centre (`centre(of:)` of the range), the whole never longer than the strip.
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

    /// The base position of the middle of a run of items (`items` clamped to the list; empty: 0): from the first one's
    /// leading edge to the last one's trailing edge, every cell narrow. One item's is `centre(of:)` that item.
    public func centre(of items: Range<Int>) -> Double {
        let run = items.clamped(to: 0..<itemCount)
        guard let first = run.first, let last = run.last else { return 0 }
        return (start(of: first) + start(of: last) + narrowLength(of: last)) / 2
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
        fades(cells: cells, current: current..<(current + 1))
    }

    /// `fades(cells:current:)` for a run of current items: never over any of them.
    public func fades(cells: [FilmstripCell], current: Range<Int>) -> (start: Double, end: Double) {
        guard let first = cells.first, let last = cells.last else { return (0, 0) }
        var start = first.start < 0 ? fadeLength : 0
        var end = last.start + last.length > length ? fadeLength : 0
        if let lead = cells.first(where: { current.contains($0.item) }),
           let trail = cells.last(where: { current.contains($0.item) }) {
            start = min(start, max(0, lead.start))
            end = min(end, max(0, length - trail.start - trail.length))
        }
        return (start, end)
    }

    /// The cells on screen, plus one beyond each edge, in order, in view positions: base position `offset` at the
    /// strip's centre, `current` expanded by `expansion` (0 narrow … 1 its item's proportions, padded).
    public func cells(offset: Double, current: Int, expansion: Double) -> [FilmstripCell] {
        cells(offset: offset, current: current..<(current + 1), expansion: expansion)
    }

    /// `cells(offset:current:expansion:)` with a run of current items expanded together (two pages side by side):
    /// each grows to its own proportions, the run around its own centre (`centre(of:)` of `current`), with the plain gap
    /// inside and the current padding outside; scaled back so the run is never longer than the strip. Items of
    /// `current` outside the list are ignored; an empty run expands nothing.
    public func cells(offset: Double, current: Range<Int>, expansion: Double) -> [FilmstripCell] {
        guard itemCount > 0, let middle = item(atBase: offset) else { return [] }
        let e = min(max(expansion, 0), 1)
        let run = current.clamped(to: 0..<itemCount)
        // How much each item of the run grows, and the padding outside it.
        var grown: [Double] = []
        var padding = gap
        if e > 0, !run.isEmpty {
            let narrow = run.map(narrowLength(of:))
            let full = run.map { item in
                let aspect = (item < aspects.count ? aspects[item] : nil) ?? Self.unknownCurrentAspect
                return min(max(aspect * thickness, narrowLength(of: item)), length)
            }
            let gaps = gap * Double(run.count - 1)
            let narrowRun = narrow.reduce(0, +) + gaps, fullRun = full.reduce(0, +) + gaps
            // A run longer than the strip grows only as far as the strip allows.
            let fit = fullRun > length && fullRun > narrowRun ? max(0, length - narrowRun) / (fullRun - narrowRun) : 1
            grown = zip(full, narrow).map { ($0 - $1) * fit * e }
            padding = gap + (Self.currentPaddingRatio * thickness - gap) * e
        }
        let total = grown.reduce(0, +)
        // The run grows around its centre; every cell beyond it moves out by half of that and the padding's extra.
        let shift = total / 2 + (padding - gap)
        let origin = length / 2 - offset
        // The run's cells: their own growth, plus all that of the cells before them in the run.
        var grownBefore = [Double](repeating: 0, count: grown.count)
        for i in grown.indices.dropFirst() { grownBefore[i] = grownBefore[i - 1] + grown[i - 1] }
        let runStart = run.isEmpty ? 0 : origin + start(of: run.lowerBound) - total / 2
        func cell(_ item: Int) -> FilmstripCell {
            let narrow = narrowLength(of: item)
            let start: Double, extent: Double
            if !grown.isEmpty, run.contains(item) {
                let i = item - run.lowerBound
                extent = narrow + grown[i]
                start = runStart + (self.start(of: item) - self.start(of: run.lowerBound)) + grownBefore[i]
            } else {
                extent = narrow
                start = origin + self.start(of: item)
                    + (item < run.lowerBound ? -shift : item >= run.upperBound ? shift : 0)
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
