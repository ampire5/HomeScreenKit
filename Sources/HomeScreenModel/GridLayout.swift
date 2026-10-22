import CoreGraphics

/// How a photo sits in its slot: filling a square, or whole inside it.
public enum GridStyle: String, CaseIterable, Sendable {
    case square, aspect
}

/// Where a card's name goes: nowhere, over the photo, or on a line under it.
public enum GridNames: String, CaseIterable, Sendable {
    case off, photo, below

    /// ⌥N: off → photo → below → off.
    public var next: GridNames {
        switch self {
        case .off: .photo
        case .photo: .below
        case .below: .off
        }
    }
}

/// How folders and archives are drawn: a big cover with a band of facts under it, a compact card with the cover at the
/// left, or a row of a list. Photo sections ignore it.
public enum CardStyle: String, CaseIterable, Sendable {
    case posters, cards, list
}

/// One run of the grid: the folders and archives (collections, fewer and wider) or the photos, with an optional heading.
public struct GridSection: Equatable, Sendable {
    public enum Kind: Sendable {
        case collections, photos
    }

    public var kind: Kind
    public var count: Int
    public var title: String?

    public init(kind: Kind, count: Int, title: String? = nil) {
        self.kind = kind
        self.count = count
        self.title = title
    }
}

/// The grid's spacing (Photos measurements).
public struct GridMetrics: Equatable, Sendable {
    public var photoGap: CGFloat = 2
    public var photoEdge: CGFloat = 0
    public var collectionGap: CGFloat = 16
    public var collectionEdge: CGFloat = 20
    /// A collection slot wants this much of the photo target.
    public var collectionScale: CGFloat = 1.6
    /// Above the first section: the view sets it to the toolbar's height.
    public var top: CGFloat = 0
    public var headerHeight: CGFloat = 36
    public var footerHeight: CGFloat = 72
    /// The name line under a slot in `.below` (collections always have it there).
    public var belowText: CGFloat = 22
    /// Names and badges only on slots at least this wide.
    public var minNamed: CGFloat = 90
    /// A poster's band, line by line. The heights are the caption's metrics from `CollectionCard` under a picture
    /// (`.below`): 3 pt, the name line 17 pt, the facts line 15 pt — so one line is 20 pt and two are 35 pt (the 35 that
    /// the caption draws and the grid used to reserve 22 for).
    public var bandInset: CGFloat = 3
    public var bandNameLine: CGFloat = 17
    public var bandFactsLine: CGFloat = 15
    /// A poster narrower than this has the name line only.
    public var bandTwoLinesFrom: CGFloat = 200
    /// A column narrower than this shows posters whatever the style.
    public var minStyled: CGFloat = 320
    /// A compact card: the cover is a square of `cardHeight` at its left. The columns are at least `cardWidth` wide
    /// and share what is left over; the gap is 10 so that three fit a 960 pt window.
    public var cardWidth: CGFloat = 300
    public var cardHeight: CGFloat = 92
    public var cardGap: CGFloat = 10
    /// A list row: one column over the whole width, the cover a square of `listCover` in the middle of the row's height.
    public var listRow: CGFloat = 44
    public var listCover: CGFloat = 36

    public init() {}
}

/// The grid as geometry only: sections top to bottom, each a heading (when titled) and rows at its own column count,
/// and a footer at the end. The columns always fill the width — the target is the wanted slot width, the count the
/// nearest to it, and the slots share the width with nothing left at the right. A folder can hold tens of thousands
/// of files, so the view makes cards only for `indices(in:margin:)`; this is a value type so the layout of a big
/// folder can be made off the main actor.
public struct GridLayout: Equatable, Sendable {
    public enum Direction: Sendable {
        case left, right, up, down
    }

    /// A section as laid out: where its heading and rows are.
    private struct Placed: Equatable, Sendable {
        var first: Int
        var count: Int
        var columns: Int
        var slot: CGFloat
        var slotHeight: CGFloat
        var gap: CGFloat
        var edge: CGFloat
        var header: CGRect?
        /// The first row's top.
        var rowsTop: CGFloat
        /// The cover's side and where it sits in the slot: the full width for a poster, a square at the left otherwise.
        var cover: CGFloat
        var coverInset: CGFloat
        var rows: Int { (count + columns - 1) / columns }
        var pitch: CGFloat { slotHeight + gap }
    }

    public let count: Int
    public let footerFrame: CGRect
    private let placed: [Placed]
    private let metrics: GridMetrics

    /// `style` is for the collection sections (a narrow column falls back to posters); the photo sections do not use it.
    public init(sections: [GridSection], width: CGFloat, target: CGFloat, names: GridNames, style: CardStyle = .posters,
                metrics: GridMetrics = .init()) {
        self.metrics = metrics
        var y = metrics.top, first = 0, placed: [Placed] = []
        for section in sections {
            let isPhotos = section.kind == .photos
            var gap = isPhotos ? metrics.photoGap : metrics.collectionGap
            var edge = isPhotos ? metrics.photoEdge : metrics.collectionEdge
            let wanted = isPhotos ? target : target * metrics.collectionScale
            var columns = Self.columns(width: width, target: wanted, gap: gap, edge: edge)
            var slot = max(1, (width - 2 * edge - gap * CGFloat(columns - 1)) / CGFloat(columns))
            var slotHeight: CGFloat, cover = slot, coverInset: CGFloat = 0
            let used = isPhotos || width < metrics.minStyled ? CardStyle.posters : style
            if isPhotos {
                slotHeight = slot + (names == .below ? metrics.belowText : 0)
            } else {
                switch used {
                case .posters:
                    slotHeight = slot + Self.bandHeight(width: slot, metrics: metrics)
                case .cards:
                    gap = metrics.cardGap
                    columns = max(1, Int(((width - 2 * edge + gap) / (metrics.cardWidth + gap)).rounded(.down)))
                    slot = max(1, (width - 2 * edge - gap * CGFloat(columns - 1)) / CGFloat(columns))
                    slotHeight = metrics.cardHeight
                    cover = metrics.cardHeight
                case .list:
                    gap = 0
                    edge = 0
                    columns = 1
                    slot = max(1, width)
                    slotHeight = metrics.listRow
                    cover = metrics.listCover
                    coverInset = (metrics.listRow - metrics.listCover) / 2
                }
            }
            var header: CGRect?
            if section.count > 0, let title = section.title, !title.isEmpty {
                header = CGRect(x: 0, y: y, width: width, height: metrics.headerHeight)
                y += metrics.headerHeight
            }
            let p = Placed(first: first, count: section.count, columns: columns, slot: slot, slotHeight: slotHeight,
                           gap: gap, edge: edge, header: header, rowsTop: y, cover: cover, coverInset: coverInset)
            y += CGFloat(p.rows) * p.pitch
            first += section.count
            placed.append(p)
        }
        self.placed = placed
        count = first
        footerFrame = CGRect(x: 0, y: y, width: width, height: metrics.footerHeight)
    }

    /// A folder poster's band under the cover at slot width `width`: the name line, and under 200 pt wide nothing
    /// more; wider, the facts line too. The poster view draws exactly this.
    public static func bandHeight(width: CGFloat, metrics: GridMetrics = .init()) -> CGFloat {
        let lines = width < metrics.bandTwoLinesFrom ? metrics.bandNameLine : metrics.bandNameLine + metrics.bandFactsLine
        return metrics.bandInset + lines
    }

    /// The column count nearest to `target` at `width`, at least one.
    public static func columns(width: CGFloat, target: CGFloat, gap: CGFloat, edge: CGFloat) -> Int {
        max(1, Int(((width - 2 * edge + gap) / (max(1, target) + gap)).rounded()))
    }

    /// The slot width that `columns` columns have at `width` (at least 1 pt; callers clamp it to their range).
    public static func target(columns: Int, width: CGFloat, gap: CGFloat, edge: CGFloat) -> CGFloat {
        max(1, (width - 2 * edge + gap) / CGFloat(max(1, columns)) - gap)
    }

    public func columns(inSection s: Int) -> Int { placed[s].columns }
    public func slotWidth(inSection s: Int) -> CGFloat { placed[s].slot }
    public func showsNames(inSection s: Int) -> Bool { placed[s].slot >= metrics.minNamed }

    public func section(of index: Int) -> Int {
        placed.lastIndex { $0.first <= index && $0.count > 0 } ?? 0
    }

    public var contentHeight: CGFloat { footerFrame.maxY }

    public func headerFrame(ofSection s: Int) -> CGRect? { placed[s].header }

    /// The slot, the name line included in `.below`.
    public func frame(of index: Int) -> CGRect {
        let p = placed[section(of: index)]
        let i = index - p.first, row = i / p.columns, column = i % p.columns
        return CGRect(x: (p.edge + CGFloat(column) * (p.slot + p.gap)).rounded(), y: p.rowsTop + CGFloat(row) * p.pitch,
                      width: p.slot, height: p.slotHeight)
    }

    /// The square cover: the slot's width at its top for a poster, the card's height at its left, a row's small one.
    public func pictureFrame(of index: Int) -> CGRect {
        let f = frame(of: index), p = placed[section(of: index)]
        return CGRect(x: f.minX + p.coverInset, y: f.minY + p.coverInset, width: p.cover, height: p.cover)
    }

    /// The cards whose rows meet `rect` grown by `margin` above and below, whole rows.
    public func indices(in rect: CGRect, margin: CGFloat) -> Range<Int> {
        let top = rect.minY - margin, bottom = rect.maxY + margin
        var lower: Int?, upper = 0
        for p in placed where p.count > 0 {
            let end = p.rowsTop + CGFloat(p.rows) * p.pitch
            guard bottom >= p.rowsTop, top < end else { continue }
            let first = max(0, Int(((top - p.rowsTop) / p.pitch).rounded(.down)))
            let last = min(p.rows - 1, Int(((bottom - p.rowsTop) / p.pitch).rounded(.down)))
            guard first <= last else { continue }
            if lower == nil { lower = p.first + first * p.columns }
            upper = p.first + min(p.count, (last + 1) * p.columns)
        }
        guard let lower else { return 0..<0 }
        return lower..<upper
    }

    /// The card under `point`; nil in a gap, a heading, an edge or past the last card.
    public func index(at point: CGPoint) -> Int? {
        for p in placed where p.count > 0 {
            let x = point.x - p.edge, y = point.y - p.rowsTop
            guard y >= 0, y < CGFloat(p.rows) * p.pitch else { continue }
            guard x >= 0 else { return nil }
            let column = Int(x / (p.slot + p.gap)), row = Int(y / p.pitch)
            guard column < p.columns, x - CGFloat(column) * (p.slot + p.gap) < p.slot,
                  y - CGFloat(row) * p.pitch < p.slotHeight else { return nil }
            let i = row * p.columns + column
            return i < p.count ? p.first + i : nil
        }
        return nil
    }

    /// The card an arrow key moves to: left and right in index order (across rows and sections), up and down to the
    /// card in the next row — which may be in the next section — whose middle is nearest, ties to the left.
    public func neighbour(of index: Int, _ d: Direction) -> Int? {
        guard index >= 0, index < count else { return nil }
        switch d {
        case .left: return index > 0 ? index - 1 : nil
        case .right: return index + 1 < count ? index + 1 : nil
        case .up, .down:
            let rows = rowRanges
            guard let r = rows.firstIndex(where: { $0.contains(index) }) else { return nil }
            let target = d == .up ? r - 1 : r + 1
            guard rows.indices.contains(target) else { return nil }
            let midX = frame(of: index).midX
            return rows[target].min { abs(frame(of: $0).midX - midX) < abs(frame(of: $1).midX - midX) }
        }
    }

    /// Every row's indices, top to bottom.
    private var rowRanges: [Range<Int>] {
        placed.flatMap { p in
            (0..<p.rows).map { row in (p.first + row * p.columns)..<(p.first + min(p.count, (row + 1) * p.columns)) }
        }
    }
}
