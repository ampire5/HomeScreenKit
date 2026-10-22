import AppKit
import HomeChrome
import HomeScreenModel

/// A folder or an archive as a compact card, 300 × 92 pt: the cover a 92 pt square at the left, and at its right four
/// lines: the name with its badges; `248 · 3 folders · 4.2 GB`; the dates' histogram with the years; and how far the
/// folder was viewed (a bar, "137 / 248") with `+12` or ✓ at the end. The card sits on a faint plate; the selection
/// ring goes round the whole card.
final class CompactCard: FolderCard {
    private static let gap: CGFloat = 10
    private let plate = CALayer()

    override init(item: HomeCardItem) {
        super.init(item: item)
        plate.cornerRadius = Self.corner
        plate.cornerCurve = .continuous
        layer?.insertSublayer(plate, at: 0)
        for view in [progressTrack, progressBar] {
            view.layer?.cornerRadius = 2
            addSubview(view)   // out of the cover: the bar is a line of the text column
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Line 2 is one string: the count, the folders and the size (or the subtitle without a summary).
    override func itemChanged() {
        super.itemChanged()
        var parts: [String] = []
        if let s = summary {
            if let photos = s.photos, photos > 0 {
                // "248 photos · 3 folders · 4.2 GB": the app's words, with the noun after the count
                parts.append(photos == 1 ? "1 photo" : "\(CardSummaryText.inside(CardSummary(photos: photos))) photos")
                var rest = s
                rest.photos = nil
                parts.append(CardSummaryText.inside(rest))
            } else {
                parts.append(insideFull)
            }
            parts.append(sizeLabel.stringValue)
        }
        let chips = parts.filter { !$0.isEmpty }.joined(separator: " · ")
        insideLabel.stringValue = chips.isEmpty ? fallbackLabel.stringValue : chips
    }

    override var showsTrack: Bool { true }
    override var pictureFrame: CGRect {
        CGRect(x: 0, y: 0, width: metrics.cardHeight, height: min(bounds.height, metrics.cardHeight))
    }
    /// The text column's left edge and width, and the four lines' tops: the name line, then three of the facts' height,
    /// spaced evenly over the card's height.
    private var column: (x: CGFloat, width: CGFloat) {
        let x = pictureFrame.maxX + Self.gap
        return (x, max(0, bounds.width - x - 8))
    }
    private var lineTops: [CGFloat] {
        let nameH = metrics.bandNameLine, lineH = metrics.bandFactsLine
        let space = (metrics.cardHeight - nameH - 3 * lineH) / 5
        let y2 = space + nameH + space, y3 = y2 + lineH + space
        return [space, y2, y3, y3 + lineH + space]
    }
    override var nameLine: CGRect { CGRect(x: column.x, y: lineTops[0], width: column.width, height: nameLineHeight) }

    override func appearanceChanged() {
        super.appearanceChanged()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        plate.backgroundColor = Chrome.resolve(Chrome.Palette.window.fill, in: self)
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        let m = metrics, p = pictureFrame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        plate.frame = bounds
        CATransaction.commit()
        layoutCover(p, ringAround: bounds)
        let (x, width) = column
        let lineH = m.bandFactsLine
        let tops = lineTops, y2 = tops[1], y3 = tops[2], y4 = tops[3]
        let s = summary
        layoutNameLine(nameLine, trailing: [(problemIcon, s?.problem != nil), (rtlLabel, s?.rightToLeft ?? false),
                                            (twoPagesIcon, s?.twoPages ?? false)])
        insideLabel.isHidden = insideLabel.stringValue.isEmpty
        insideLabel.frame = CGRect(x: x, y: y2, width: width, height: lineH)
        for view in [sizeLabel, fallbackLabel, countLabel] as [NSView] { view.isHidden = true }
        // Line 3: the bars and the years.
        var cursor = x
        histogram.isHidden = !histogram.hasBars
        if !histogram.isHidden {
            let hw = Self.width(of: histogram)
            histogram.frame = CGRect(x: cursor, y: y3 + (lineH - HistogramView.height) / 2, width: hw, height: HistogramView.height)
            cursor += hw + 5
        }
        yearsLabel.isHidden = yearsLabel.stringValue.isEmpty
        yearsLabel.frame = CGRect(x: cursor, y: y3, width: max(0, x + width - cursor), height: lineH)
        // Line 4: the bar, its text, and the flag at the end.
        var right = x + width
        if !flagPill.isHidden {
            let f = flagPill.fittingSize
            right -= f.width
            flagPill.frame = CGRect(x: right, y: y4 + (lineH - f.height) / 2, width: f.width, height: f.height)
            right -= 6
        }
        viewedLabel.isHidden = viewedLabel.stringValue.isEmpty
        if !viewedLabel.isHidden {
            let vw = min(Self.width(of: viewedLabel), max(0, right - x))
            right -= vw
            viewedLabel.frame = CGRect(x: right, y: y4, width: vw, height: lineH)
            right -= 6
        }
        let trackWidth = max(0, right - x)
        let barY = y4 + (lineH - 4) / 2
        progressTrack.frame = CGRect(x: x, y: barY, width: trackWidth, height: 4)
        let fraction = min(1, max(0, shownProgress ?? 0))
        progressBar.frame = CGRect(x: x, y: barY, width: (trackWidth * fraction).rounded(), height: 4)
    }
}
