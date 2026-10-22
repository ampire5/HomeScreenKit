import AppKit
import HomeChrome
import HomeScreenModel

/// What the poster's facts line holds in the room it has. Short of room it gives up, in this order: (a) the folders part
/// of the count (`248 · 3 folders` becomes `248`), (b) the size, (c) the years' text (the bars stay), (d) the bars.
/// The progress text, the lowest priority, goes before any of these. A width of nil: there is no such item.
struct PosterFacts: Equatable {
    var shortInside = false, size = true, years = true, bars = true, viewed = true

    static let gap: CGFloat = 8, tight: CGFloat = 5

    static func pick(room: CGFloat, full: CGFloat?, short: CGFloat?, size: CGFloat?, years: CGFloat?, bars: CGFloat?,
                     viewed: CGFloat?) -> PosterFacts {
        let configs = [PosterFacts(shortInside: false), PosterFacts(shortInside: true),
                       PosterFacts(shortInside: true, size: false), PosterFacts(shortInside: true, size: false, years: false),
                       PosterFacts(shortInside: true, size: false, years: false, bars: false)]
        func need(_ c: PosterFacts, withViewed: Bool) -> CGFloat {
            var blocks: [CGFloat] = []
            if let inside = c.shortInside ? short ?? full : full { blocks.append(inside) }
            var dates: CGFloat = 0
            if c.bars, let bars { dates += bars }
            if c.years, let years { dates += (dates > 0 ? tight : 0) + years }
            if dates > 0 { blocks.append(dates) }
            if c.size, let size { blocks.append(size) }
            if withViewed, let viewed { blocks.append(viewed) }
            return blocks.reduce(0, +) + gap * CGFloat(max(0, blocks.count - 1))
        }
        for var c in configs {
            for withViewed in [true, false] where need(c, withViewed: withViewed) <= room + 0.5 {
                c.viewed = withViewed
                return c
            }
        }
        var last = configs[configs.count - 1]
        last.viewed = false
        return last
    }
}

/// A folder or an archive as a poster: the square cover, and under it a band of facts that the grid reserves exactly
/// (`GridLayout.bandHeight`): the name line (the name, ⧉, RTL, a problem badge), and from 200 pt wide a facts line —
/// `248 · 3 folders`, the dates' histogram and years, the size, and from 280 pt "137 / 248". Under 200 pt the band is
/// the name line with the photo count at its end. A thin line on the seam between cover and band shows how far the
/// folder was viewed; `+12` (new photos) or ✓ (viewed to the end) sits in the cover's top right corner.
final class PosterCard: FolderCard {
    override var pictureFrame: CGRect { CGRect(x: 0, y: 0, width: bounds.width, height: bounds.width) }
    override var nameLine: CGRect {
        CGRect(x: 0, y: bounds.width + metrics.bandInset, width: bounds.width, height: nameLineHeight)
    }

    override func layout() {
        super.layout()
        let m = metrics, w = bounds.width
        layoutCover(pictureFrame)
        let flag = flagPill.fittingSize
        flagPill.frame = CGRect(x: w - 8 - flag.width, y: 8, width: flag.width, height: flag.height)
        // The line sits on the cover's bottom edge, inside its rounded clip (the picture's coordinates are not flipped).
        let fraction = min(1, max(0, shownProgress ?? 0))
        progressBar.frame = CGRect(x: 0, y: 0, width: (w * fraction).rounded(), height: 3)
        let narrow = w < m.bandTwoLinesFrom
        let s = summary
        layoutNameLine(nameLine, trailing: [(countLabel, narrow && !countLabel.stringValue.isEmpty),
                                            (problemIcon, s?.problem != nil), (rtlLabel, s?.rightToLeft ?? false),
                                            (twoPagesIcon, s?.twoPages ?? false)])
        let factsY = nameLine.maxY
        guard !narrow else {
            for view in [insideLabel, histogram, yearsLabel, sizeLabel, viewedLabel, fallbackLabel] as [NSView] { view.isHidden = true }
            return
        }
        func width(_ text: String) -> CGFloat? { text.isEmpty ? nil : Self.textWidth(text) }
        let hasBars = histogram.hasBars
        let pick = PosterFacts.pick(room: w, full: width(insideFull.isEmpty ? fallbackLabel.stringValue : insideFull),
                                    short: width(insideShort), size: width(sizeLabel.stringValue),
                                    years: width(yearsLabel.stringValue),
                                    bars: hasBars ? Self.width(of: histogram) : nil,
                                    viewed: w >= m.bandProgressFrom ? width(viewedLabel.stringValue) : nil)
        let hasInside = !insideFull.isEmpty
        insideLabel.stringValue = pick.shortInside ? insideShort : insideFull
        insideLabel.isHidden = !hasInside
        fallbackLabel.isHidden = hasInside || fallbackLabel.stringValue.isEmpty
        sizeLabel.isHidden = !pick.size || sizeLabel.stringValue.isEmpty
        yearsLabel.isHidden = !pick.years || yearsLabel.stringValue.isEmpty
        histogram.isHidden = !pick.bars || !hasBars
        viewedLabel.isHidden = !pick.viewed || w < m.bandProgressFrom || viewedLabel.stringValue.isEmpty
        // In display order from the left, the size at the right end.
        let h = factsLineHeight
        var x: CGFloat = 0
        func put(_ view: NSView, height: CGFloat, gap: CGFloat = PosterFacts.gap) {
            guard !view.isHidden else { return }
            let vw = view === insideLabel ? Self.textWidth(insideLabel.stringValue) : Self.width(of: view)
            view.frame = CGRect(x: x, y: factsY + (h - height) / 2, width: vw, height: height)
            x += vw + gap
        }
        put(insideLabel, height: h)
        put(fallbackLabel, height: h)
        put(histogram, height: HistogramView.height, gap: PosterFacts.tight)
        put(yearsLabel, height: h)
        put(viewedLabel, height: h)
        if !sizeLabel.isHidden {
            let sw = Self.width(of: sizeLabel)
            sizeLabel.frame = CGRect(x: w - sw, y: factsY, width: sw, height: h)
        }
    }
}
