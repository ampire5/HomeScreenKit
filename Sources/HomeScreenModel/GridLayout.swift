import CoreGraphics

/// How a photo sits in its slot: filling a square, or whole inside it.
public enum GridStyle: String, CaseIterable, Codable, Sendable {
    case square, aspect
}

/// Where a card's name goes: nowhere, over the photo, or on a line under it.
/// File names on the grid: none, on the picture, under it, or `auto` (the owner's choice of 2026-10-27, board
/// «Эскизы файлов» D): under the picture with the facts line on tiles at least `GridMetrics.namesBelowFrom` wide, on
/// smaller tiles a band over the picture while the pointer is on it.
public enum GridNames: String, CaseIterable, Sendable {
    case off, photo, below, auto

    /// ⌥N: auto → off → photo → below → auto.
    public var next: GridNames {
        switch self {
        case .auto: .off
        case .off: .photo
        case .photo: .below
        case .below: .auto
        }
    }
}

/// How folders and archives are drawn: a big cover with a band of facts under it, a compact card with the cover at the
/// left, or a row of a list. Photo sections ignore it, except that the list also draws files as rows.
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
    /// On the line of the headings and the folders (board «Эскизы файлов» B, 2026-10-27), not edge to edge.
    public var photoEdge: CGFloat = 20
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
    /// A file's facts line under its name in `.below` (file-cards spec §2), when the app has one (`FileStyle.factsLine`).
    public var belowFacts: CGFloat = 15
    /// Names and badges only on slots at least this wide.
    public var minNamed: CGFloat = 90
    /// `GridNames.auto`: the names go under the pictures from this slot width.
    public var namesBelowFrom: CGFloat = 160
    /// A poster is one card: the square cover, a 3 pt seam (the progress track) under it, then the band of facts
    /// (`PosterBand`, by width). The band's lines change at these widths: under `bandTwoLinesFrom` the name line
    /// only; from `bandProgressFrom` a third line with the dates' span and the progress as text.
    public var seam: CGFloat = 3
    public var bandTwoLinesFrom: CGFloat = 200
    public var bandProgressFrom: CGFloat = 280
    /// A column narrower than this shows posters whatever the style.
    public var minStyled: CGFloat = 320
    /// A compact card (mockup B, 300 × 92): the columns are at least `cardWidth` wide and share what is left over;
    /// the gap is 10 so that three fit a 960 pt window. The cover is a `cardCover` square `cardPadding` in from the
    /// card's top left.
    public var cardWidth: CGFloat = 300
    public var cardHeight: CGFloat = 92
    public var cardGap: CGFloat = 10
    public var cardPadding: CGFloat = 8
    public var cardCover: CGFloat = 76
    /// The list (mockup C): rows of `listRow` (the 1 pt separator included) in one container `collectionEdge` in
    /// from the sides; a row's cover is a `listCover` square `listPadding` in from the row's left, in the middle of
    /// its height. The column heads (`listHeader` tall) sit at the container's top.
    public var listRow: CGFloat = 44
    public var listCover: CGFloat = 32
    public var listPadding: CGFloat = 12
    public var listHeader: CGFloat = 28

    /// The band under a poster's cover at slot width `width`, from the mockup's three sizes (⌘− 176 pt, the default
    /// 232 pt, ⌘+ 300 pt): its paddings, line heights and font sizes. Heights are whole points; each line is the
    /// height of its font's line in AppKit (12 / 13 / 14 pt semibold: 15 / 16 / 17), the facts lines the mockup's
    /// 13 and 14.
    public func posterBand(width: CGFloat) -> PosterBand {
        if width < bandTwoLinesFrom {
            return PosterBand(lines: 1, top: 6, bottom: 8, nameLine: 15, nameSize: 12, factsLine: 0, factsSize: 11.5)
        }
        if width < bandProgressFrom {
            return PosterBand(lines: 2, top: 7, bottom: 9, nameLine: 16, nameSize: 13, factsLine: 13, factsSize: 11.5)
        }
        return PosterBand(lines: 3, top: 6, bottom: 8, nameLine: 17, nameSize: 14, factsLine: 14, factsSize: 12)
    }

    public init() {}

    /// The Cards and List styles' three sizes, picked by the card size the slider and ⌘= / ⌘− set (the owner,
    /// 2026-10-27, over a slider that did nothing in them): under 200 pt small, from 300 pt large, between the
    /// mockups' own (the default 220 among them). ⌘= / ⌘− (`HomeResize.sizes`: 100, 160, 240, 360) go small,
    /// small, regular, large.
    public enum SizeStep: Sendable, CaseIterable {
        case small, regular, large

        public init(cardSize: CGFloat) {
            self = cardSize < 200 ? .small : cardSize < 300 ? .regular : .large
        }
    }

    /// These metrics with the compact card and the list row of `step`: the card 260 × 80, 300 × 92 or 360 × 110 (its
    /// cover the height less the padding), the row 34, 44 or 56 tall (its cover 24, 32 or 44).
    public func sized(_ step: SizeStep) -> GridMetrics {
        var m = self
        switch step {
        case .small: (m.cardWidth, m.cardHeight, m.listRow, m.listCover) = (260, 80, 34, 24)
        case .regular: break
        case .large: (m.cardWidth, m.cardHeight, m.listRow, m.listCover) = (360, 110, 56, 44)
        }
        m.cardCover = m.cardHeight - 2 * m.cardPadding
        return m
    }
}

/// A poster's band of facts at one size: one line (the name, the `+N` pill or ✓), two (the facts with the dates'
/// bars and years) or three (the facts, then the bars with the dates' span and the progress as text).
public struct PosterBand: Equatable, Sendable {
    public var lines: Int
    public var top: CGFloat
    public var bottom: CGFloat
    public var nameLine: CGFloat
    public var nameSize: CGFloat
    /// The second and third lines' height; their gap to the line above is `gap`.
    public var factsLine: CGFloat
    public var factsSize: CGFloat
    public var gap: CGFloat = 3

    public init(lines: Int, top: CGFloat, bottom: CGFloat, nameLine: CGFloat, nameSize: CGFloat, factsLine: CGFloat,
                factsSize: CGFloat) {
        self.lines = lines
        self.top = top
        self.bottom = bottom
        self.nameLine = nameLine
        self.nameSize = nameSize
        self.factsLine = factsLine
        self.factsSize = factsSize
    }

    public var height: CGFloat { top + nameLine + CGFloat(lines - 1) * (gap + factsLine) + bottom }
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
        var coverInset: CGPoint
        /// A file card's picture is wider than tall by the files' aspect (a video's 135 × 76); nil: `cover` square.
        var coverWidth: CGFloat? = nil
        /// The files' names (and facts) under their pictures: `.below`, or `.auto` on slots wide enough.
        var namesBelow = false
        var rows: Int { (count + columns - 1) / columns }
        var pitch: CGFloat { slotHeight + gap }
    }

    public let count: Int
    public let footerFrame: CGRect
    private let placed: [Placed]
    public let metrics: GridMetrics

    /// `style` is for the collection sections (a narrow column falls back to posters); the photo sections do not use it.
    /// `fileAspect` is a photo slot's width over its picture's height (`FileStyle.aspect`: 1 for photos, 16:9 for video).
    /// `factsLine`: the files' facts under their names (`FileStyle.factsLine`); in the Cards style files take card
    /// slots too, their picture `fileAspect` × the cover's height.
    public init(sections: [GridSection], width: CGFloat, target: CGFloat, names: GridNames, style: CardStyle = .posters,
                fileAspect: CGFloat = 1, factsLine: Bool = false, metrics: GridMetrics = .init()) {
        self.metrics = metrics
        var y = metrics.top, first = 0, placed: [Placed] = []
        for section in sections {
            let isPhotos = section.kind == .photos
            var gap = isPhotos ? metrics.photoGap : metrics.collectionGap
            var edge = isPhotos ? metrics.photoEdge : metrics.collectionEdge
            let wanted = isPhotos ? target : target * metrics.collectionScale
            var columns = Self.columns(width: width, target: wanted, gap: gap, edge: edge)
            var slot = max(1, (width - 2 * edge - gap * CGFloat(columns - 1)) / CGFloat(columns))
            var slotHeight: CGFloat, cover = slot, coverInset = CGPoint.zero, coverWidth: CGFloat?, namesBelow = false
            // Files keep their tiles in Posters; in Cards they are cards and in the list rows, like the folders.
            let used = width < metrics.minStyled ? CardStyle.posters : style
            if isPhotos && used == .cards {
                gap = metrics.cardGap
                columns = max(1, Int(((width - 2 * edge + gap) / (metrics.cardWidth + gap)).rounded(.down)))
                slot = max(1, (width - 2 * edge - gap * CGFloat(columns - 1)) / CGFloat(columns))
                slotHeight = metrics.cardHeight
                cover = metrics.cardCover
                coverWidth = (metrics.cardCover * fileAspect).rounded()
                coverInset = CGPoint(x: metrics.cardPadding, y: metrics.cardPadding)
            } else if isPhotos && used != .list {
                cover = fileAspect == 1 ? slot : (slot / max(0.1, fileAspect)).rounded()
                namesBelow = names == .below || (names == .auto && slot >= metrics.namesBelowFrom)
                slotHeight = cover + (namesBelow ? metrics.belowText + (factsLine ? metrics.belowFacts : 0) : 0)
            } else {
                switch used {
                case .posters:
                    slotHeight = slot + Self.bandHeight(width: slot, metrics: metrics)
                case .cards:
                    gap = metrics.cardGap
                    columns = max(1, Int(((width - 2 * edge + gap) / (metrics.cardWidth + gap)).rounded(.down)))
                    slot = max(1, (width - 2 * edge - gap * CGFloat(columns - 1)) / CGFloat(columns))
                    slotHeight = metrics.cardHeight
                    cover = metrics.cardCover
                    coverInset = CGPoint(x: metrics.cardPadding, y: metrics.cardPadding)
                case .list:
                    gap = 0
                    edge = metrics.collectionEdge   // the files' rows too: one container
                    columns = 1
                    slot = max(1, width - 2 * edge)
                    slotHeight = metrics.listRow
                    cover = metrics.listCover
                    coverInset = CGPoint(x: metrics.listPadding, y: ((metrics.listRow - metrics.listCover) / 2).rounded(.down))
                }
            }
            var header: CGRect?
            if section.count > 0, let title = section.title, !title.isEmpty {
                header = CGRect(x: 0, y: y, width: width, height: metrics.headerHeight)
                y += metrics.headerHeight
            }
            let p = Placed(first: first, count: section.count, columns: columns, slot: slot, slotHeight: slotHeight,
                           gap: gap, edge: edge, header: header, rowsTop: y, cover: cover, coverInset: coverInset,
                           coverWidth: coverWidth, namesBelow: namesBelow)
            y += CGFloat(p.rows) * p.pitch
            first += section.count
            placed.append(p)
        }
        self.placed = placed
        count = first
        footerFrame = CGRect(x: 0, y: y, width: width, height: metrics.footerHeight)
    }

    /// What a folder poster has under its cover at slot width `width`: the seam and the band (`posterBand`). The
    /// grid reserves exactly this and the poster view draws exactly this.
    public static func bandHeight(width: CGFloat, metrics: GridMetrics = .init()) -> CGFloat {
        metrics.seam + metrics.posterBand(width: width).height
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
    /// The files' names under their pictures in section `s` (`.below`, or `.auto` on wide enough slots).
    public func namesBelow(inSection s: Int) -> Bool { placed[s].namesBelow }

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

    /// The cover: the slot's width at its top for a poster (a photo's at its `fileAspect`), a compact card's square
    /// inside its padding, a row's small one.
    public func pictureFrame(of index: Int) -> CGRect {
        let f = frame(of: index), p = placed[section(of: index)]
        let width = p.coverInset == .zero ? f.width : p.coverWidth ?? p.cover
        return CGRect(x: f.minX + p.coverInset.x, y: f.minY + p.coverInset.y, width: width, height: p.cover)
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
