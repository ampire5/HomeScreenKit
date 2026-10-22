import AppKit
import HomeChrome
import HomeScreenModel

/// A folder or an archive as a poster: the square cover, and under it a band of facts that the grid reserves exactly
/// (`GridLayout.bandHeight`): the name line (the name, ⧉, RTL, a problem badge), and from 200 pt wide a facts line —
/// `248 · 3 folders`, the dates' histogram and years, the size, and from 280 pt "137 / 248". Under 200 pt the band is
/// the name line with the photo count at its end. A thin line on the seam between cover and band shows how far the
/// folder was viewed; `+12` (new photos) or ✓ (viewed to the end) sits in the cover's top right corner.
final class PosterCard: FolderCard {
    private static let metrics = GridMetrics()

    override var pictureFrame: CGRect { CGRect(x: 0, y: 0, width: bounds.width, height: bounds.width) }
    override var nameFrame: CGRect { CGRect(x: 0, y: bounds.width + 1, width: bounds.width, height: 22) }

    override func layout() {
        super.layout()
        let m = Self.metrics, w = bounds.width
        layoutCover(pictureFrame)
        let flag = flagPill.fittingSize
        flagPill.frame = CGRect(x: w - 8 - flag.width, y: 8, width: flag.width, height: flag.height)
        // The line sits on the cover's bottom edge, inside its rounded clip (the picture's coordinates are not flipped).
        let fraction = min(1, max(0, shownProgress ?? 0))
        progressBar.frame = CGRect(x: 0, y: 0, width: (w * fraction).rounded(), height: 3)
        let nameY = w + m.bandInset
        let narrow = w < m.bandTwoLinesFrom
        countLabel.isHidden = !narrow || countLabel.stringValue.isEmpty
        layoutNameLine(x: 0, y: nameY, width: w, trailing: [countLabel, problemIcon, rtlLabel, twoPagesIcon])
        let factsY = nameY + m.bandNameLine
        guard !narrow else {
            for view in [insideLabel, histogram, yearsLabel, sizeLabel, viewedLabel, fallbackLabel] as [NSView] { view.isHidden = true }
            return
        }
        // What fits, in priority order: the count, the size, the years with their bars, the progress text (wide only).
        var room = w
        func fit(_ need: CGFloat, _ present: Bool) -> Bool {
            guard present, need <= room + 0.5 else { return false }
            room -= need + 8
            return true
        }
        let barsWidth = histogram.hasBars ? Self.width(of: histogram) + 5 : 0
        let inside = fit(Self.width(of: insideLabel), !insideLabel.stringValue.isEmpty)
        let fallback = fit(Self.width(of: fallbackLabel), !fallbackLabel.stringValue.isEmpty)
        let size = fit(Self.width(of: sizeLabel), !sizeLabel.stringValue.isEmpty)
        let years = fit(Self.width(of: yearsLabel) + barsWidth, !yearsLabel.stringValue.isEmpty || histogram.hasBars)
        let viewed = fit(Self.width(of: viewedLabel), w >= m.bandProgressFrom && !viewedLabel.stringValue.isEmpty)
        insideLabel.isHidden = !inside
        fallbackLabel.isHidden = !fallback
        sizeLabel.isHidden = !size
        yearsLabel.isHidden = !years || yearsLabel.stringValue.isEmpty
        histogram.isHidden = !years || !histogram.hasBars
        viewedLabel.isHidden = !viewed
        // In display order from the left, the size at the right end.
        let h = Self.factsLineHeight
        var x: CGFloat = 0
        func put(_ view: NSView, height: CGFloat, gap: CGFloat = 8) {
            guard !view.isHidden else { return }
            let vw = Self.width(of: view)
            view.frame = CGRect(x: x, y: factsY + (h - height) / 2, width: vw, height: height)
            x += vw + gap
        }
        put(insideLabel, height: h)
        put(fallbackLabel, height: h)
        put(histogram, height: HistogramView.height, gap: 5)
        put(yearsLabel, height: h)
        put(viewedLabel, height: h)
        if !sizeLabel.isHidden {
            let sw = Self.width(of: sizeLabel)
            sizeLabel.frame = CGRect(x: w - sw, y: factsY, width: sw, height: h)
        }
    }
}
