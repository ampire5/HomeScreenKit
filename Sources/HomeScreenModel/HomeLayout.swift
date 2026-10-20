import CoreGraphics

/// The grid's spacing in points: insets, gaps, headings and the two text lines under a picture.
public struct HomeMetrics: Equatable, Sendable {
    public var inset: CGFloat = 32
    public var spacing: CGFloat = 20
    public var rowSpacing: CGFloat = 24
    public var headingHeight: CGFloat = 28
    public var headingGap: CGFloat = 12
    public var sectionGap: CGFloat = 8
    public var textHeight: CGFloat = 40
    public var top: CGFloat = 16
    public var minWidth: CGFloat = 140
    public var maxColumns = 8

    public init() {}
}

/// How many columns, how wide a card, and whether the grid scrolls.
public struct HomeGridFit: Equatable, Sendable {
    public let columns: Int
    public let cardWidth: CGFloat
    public let scrolls: Bool

    public init(columns: Int, cardWidth: CGFloat, scrolls: Bool) {
        self.columns = columns
        self.cardWidth = cardWidth
        self.scrolls = scrolls
    }
}

/// The home screen's grid (`home-layout`). `sections` lists each non-empty section's card count and whether it has a
/// heading; `aspect` is a picture's height over its width.
public enum HomeLayout {
    public static func fit(mode: HomeLayoutMode, area: CGSize, cardSize: CGFloat, aspect: CGFloat,
                           sections: [(count: Int, heading: Bool)], metrics m: HomeMetrics = .init()) -> HomeGridFit {
        let usable = max(1, area.width - 2 * m.inset)
        /// As many columns of `width` as fit the width, at least one, at most `maxColumns`.
        func columns(at width: CGFloat) -> Int {
            max(1, min(m.maxColumns, Int(((usable + m.spacing) / (width + m.spacing)).rounded(.down))))
        }
        if mode == .scroll {
            let width = min(cardSize, usable)
            return HomeGridFit(columns: columns(at: width), cardWidth: width, scrolls: true)
        }
        // More columns than the longest section only shrink the cards (a tie keeps the same width).
        let longest = max(1, sections.map(\.count).max() ?? 1)
        var best: HomeGridFit?
        for c in 1...max(1, min(m.maxColumns, longest)) {
            let width = min(cardSize, ((usable - m.spacing * CGFloat(c - 1)) / CGFloat(c)).rounded(.down))
            guard width >= m.minWidth else { break }
            let candidate = HomeGridFit(columns: c, cardWidth: width, scrolls: false)
            guard contentHeight(candidate, aspect: aspect, sections: sections, metrics: m) <= area.height else { continue }
            if best == nil || width >= best!.cardWidth { best = candidate }   // a tie: more columns, fewer rows
        }
        if let best { return best }
        let width = min(m.minWidth, usable)
        return HomeGridFit(columns: columns(at: width), cardWidth: width, scrolls: mode == .fit)
    }

    /// The picture and the two lines under it.
    public static func cardHeight(width: CGFloat, aspect: CGFloat, metrics m: HomeMetrics = .init()) -> CGFloat {
        (width * aspect).rounded() + 8 + m.textHeight
    }

    /// The grid's whole height: top, each section's heading and rows, the gaps between sections, the bottom inset.
    public static func contentHeight(_ fit: HomeGridFit, aspect: CGFloat, sections: [(count: Int, heading: Bool)],
                                     metrics m: HomeMetrics = .init()) -> CGFloat {
        let card = cardHeight(width: fit.cardWidth, aspect: aspect, metrics: m)
        let shown = sections.filter { $0.count > 0 }
        var height = m.top + m.inset
        for (i, section) in shown.enumerated() {
            if section.heading { height += m.headingHeight + m.headingGap }
            let rows = (section.count + fit.columns - 1) / fit.columns
            height += CGFloat(rows) * card + CGFloat(rows - 1) * m.rowSpacing
            if i < shown.count - 1 { height += m.rowSpacing + m.sectionGap }
        }
        return height
    }
}
