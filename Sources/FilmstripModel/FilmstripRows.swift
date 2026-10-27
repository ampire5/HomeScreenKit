import CoreGraphics
import Foundation

/// One row of the vertical strip: `start` is its top in points from the strip view's top, `length` its height;
/// `picture` is where the picture goes inside the row (x across from the row's leading edge, y down from its top).
public struct FilmstripRow: Equatable, Sendable {
    public let item: Int
    public let start: Double
    public let length: Double
    public let picture: CGRect
}

/// The strip as a column of rows (FrameScrub's playlist, Loupe's folders): each item a whole picture in its own
/// proportions, `rowPicture` wide, on a line that moves under the strip's fixed centre; the browsed item there larger,
/// `currentPicture` wide, with the owner's card (`cardHeight`) under it. Pure arithmetic in points, no AppKit.
///
/// A portrait picture fits a square (`portraitCap`), so one tall file does not take the screen. The base line lays
/// the plain rows out from 0 with a `gapRatio` gap (prefix sums made once here, searched by bisection); an offset is
/// the base position under the strip's centre. The browsed row grows (`expansion` 0 → 1) around its own centre,
/// pushing the others apart; the base line, and so the item under a point, ignores that growth, as
/// `FilmstripLayout`'s does.
public struct FilmstripRows: FilmstripTrack, Equatable, Sendable {
    /// A picture is never taller than wide.
    public static let portraitCap = 1.0
    /// The gap between rows, of `rowPicture`.
    public static let gapRatio = 0.08
    /// The fading edges, of `rowPicture`.
    public static let fadeRatio = 0.85
    /// An item whose proportions are not known yet.
    public static let unknownAspect = 16.0 / 9

    public let itemCount: Int
    public let length: Double
    public let width: Double
    public let rowPicture: Double
    public let currentPicture: Double
    public let cardHeight: Double
    public let gap: Double
    private let aspects: [Double?]
    /// The top of each plain row on the base line, plus the end (`itemCount + 1` values).
    private let starts: [Double]

    public init(itemCount: Int, aspects: [Double?], length: Double, width: Double, rowPicture: Double,
                currentPicture: Double, cardHeight: Double) {
        self.itemCount = max(0, itemCount)
        self.aspects = aspects
        self.length = length
        self.width = width
        self.rowPicture = rowPicture
        self.currentPicture = currentPicture
        self.cardHeight = cardHeight
        gap = Self.gapRatio * rowPicture
        var starts = [Double](repeating: 0, count: self.itemCount + 1)
        var position = 0.0
        for item in 0..<self.itemCount {
            starts[item] = position
            position += Self.pictureSize(aspect: aspects.indices.contains(item) ? aspects[item] : nil, width: rowPicture).height + gap
        }
        starts[self.itemCount] = position
        self.starts = starts
    }

    /// A whole picture `width` wide, or as tall as that when it is portrait.
    private static func pictureSize(aspect: Double?, width: Double) -> CGSize {
        let aspect = aspect.flatMap { $0 > 0 ? $0 : nil } ?? unknownAspect
        let height = width / max(aspect, portraitCap)
        return CGSize(width: height * aspect, height: height)
    }

    private func aspect(of item: Int) -> Double? { aspects.indices.contains(item) ? aspects[item] : nil }

    /// A plain row's height: its picture's.
    public func plainLength(of item: Int) -> Double {
        Self.pictureSize(aspect: aspect(of: item), width: rowPicture).height
    }

    public func centre(of item: Int) -> Double {
        starts[item] + plainLength(of: item) / 2
    }

    /// The item whose row, with half a gap on each side, holds base position `position`; the first or last beyond
    /// the ends; nil for no items.
    public func item(atBase position: Double) -> Int? {
        guard itemCount > 0 else { return nil }
        let shifted = position + gap / 2
        var low = 0, high = itemCount - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= shifted { low = middle } else { high = middle - 1 }
        }
        return low
    }

    public var offsetRange: ClosedRange<Double> {
        guard itemCount > 0 else { return 0...0 }
        return centre(of: 0)...centre(of: itemCount - 1)
    }

    public var fadeLength: Double { Self.fadeRatio * rowPicture }

    /// The rows on screen, plus one beyond each edge, top to bottom, in view positions: base position `offset` at the
    /// strip's centre, `current` grown by `expansion` (0 plain … 1 its larger picture and the card).
    public func rows(offset: Double, current: Int, expansion: Double) -> [FilmstripRow] {
        guard itemCount > 0, let middle = item(atBase: offset) else { return [] }
        let e = min(max(expansion, 0), 1)
        let hasCurrent = (0..<itemCount).contains(current)
        let plainCurrent = hasCurrent ? Self.pictureSize(aspect: aspect(of: current), width: rowPicture) : .zero
        let fullCurrent = hasCurrent ? Self.pictureSize(aspect: aspect(of: current), width: currentPicture) : .zero
        let grown = hasCurrent ? (fullCurrent.height + cardHeight - plainCurrent.height) * e : 0
        let origin = length / 2 - offset
        func row(_ item: Int) -> FilmstripRow {
            if hasCurrent, item == current {
                let picture = CGSize(width: plainCurrent.width + (fullCurrent.width - plainCurrent.width) * e,
                                     height: plainCurrent.height + (fullCurrent.height - plainCurrent.height) * e)
                return FilmstripRow(item: item, start: origin + starts[item] - grown / 2,
                                    length: plainCurrent.height + grown, picture: CGRect(origin: .zero, size: picture))
            }
            let picture = Self.pictureSize(aspect: aspect(of: item), width: rowPicture)
            let shift = !hasCurrent ? 0 : item < current ? -grown / 2 : grown / 2
            return FilmstripRow(item: item, start: origin + starts[item] + shift, length: picture.height,
                                picture: CGRect(origin: .zero, size: picture))
        }
        var before: [FilmstripRow] = [], after: [FilmstripRow] = []
        var item = middle - 1
        while item >= 0 {
            let r = row(item)
            before.append(r)
            if r.start + r.length < 0 { break }
            item -= 1
        }
        item = middle + 1
        while item < itemCount {
            let r = row(item)
            after.append(r)
            if r.start > length { break }
            item += 1
        }
        return before.reversed() + [row(middle)] + after
    }

    /// How far each edge of `rows` fades: `fadeLength` where the strip goes on past that edge, 0 where it ends inside
    /// the view; never over the browsed row.
    public func fades(rows: [FilmstripRow], current: Int) -> (start: Double, end: Double) {
        guard let first = rows.first, let last = rows.last else { return (0, 0) }
        var start = first.start < 0 ? fadeLength : 0
        var end = last.start + last.length > length ? fadeLength : 0
        if let row = rows.first(where: { $0.item == current }) {
            start = min(start, max(0, row.start))
            end = min(end, max(0, length - row.start - row.length))
        }
        return (start, end)
    }
}
