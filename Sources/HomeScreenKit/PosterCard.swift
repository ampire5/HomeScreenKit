import AppKit
import HomeChrome
import HomeScreenModel

/// A folder or an archive as a poster (mockup E «Плакат»): one card, as wide as the cover, radius 12 with a 0.5 pt
/// ring. At its top the square cover (an archive's `ZIP` chip at its top left); under it a 3 pt seam, the progress
/// track filled as far as the folder was viewed; then the band (`GridMetrics.posterBand`, which the grid reserves
/// exactly), by width:
/// - under 200 pt: the name, and at the line's end `+12` and ✓;
/// - from 200 pt: also `248 photos · 3 folders · 1.9 GB` whole, the years at the line's end, and the dates' bars
///   between the two where they fit (the tooltip has every fact whatever the card cuts);
/// - from 280 pt: the facts line with the subfolders' photos (`3 folders (412)`), and a third line of larger bars
///   with the dates' span, the progress and when the folder was viewed: `Jun – Aug 2024 · 153 / 248 · 3 d ago` (short
///   of room the last goes first, before any cutting).
/// A folder whose volume is away, or an archive that cannot be read, has its cover faint with a warning glyph over
/// it and a warning line in place of the facts.
final class PosterCard: FolderCard {
    static let radius: CGFloat = 12
    static let side: CGFloat = 10
    /// The warning glyph over the cover: 34 pt, 92 pt down a 232 pt cover (the mockup's place, scaled).
    let coverAlert = GlyphView(nil, color: Chrome.Palette.card.label, lineWidth: 1.2)

    override init(item: HomeCardItem) {
        super.init(item: item)
        addSubview(coverAlert, positioned: .above, relativeTo: coverClip)
        itemChanged()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var band: PosterBand { metrics.posterBand(width: bounds.width) }

    override var pictureFrame: CGRect { CGRect(x: 0, y: 0, width: bounds.width, height: bounds.width) }
    override var nameLine: CGRect {
        let w = bounds.width
        return CGRect(x: Self.side, y: w + metrics.seam + band.top, width: max(0, w - 2 * Self.side), height: band.nameLine)
    }

    /// Waiting: the placeholder over the whole cover, its top corners round; a line in each facts line of the band
    /// (the board's 70 % and 45 % of the band's width), centred in it.
    override var waitingCover: (rect: CGRect, radius: CGFloat, topOnly: Bool) { (pictureFrame, Self.radius, true) }
    override var waitingLines: [CGRect] {
        let band = band, h = Self.waitingLineHeight
        let width = max(0, bounds.width - 2 * Self.side)
        var y = nameLine.maxY + band.gap
        var lines: [CGRect] = []
        for fraction in Self.waitingWidths.prefix(max(0, band.lines - 1)) {
            lines.append(CGRect(x: Self.side, y: (y + (band.factsLine - h) / 2).rounded(), width: (width * fraction).rounded(),
                                height: h))
            y += band.factsLine + band.gap
        }
        return lines
    }

    /// The third line's words without and with when the folder was viewed (`· 3 d ago`; nil when not known), and
    /// the width of the latter as last measured (its text and font).
    private var progressWords = ""
    private var progressWithRecency: String?
    private var measuredWithRecency: (text: String, font: NSFont, width: CGFloat)?

    /// The facts line's words: with the subfolders' photos on a large poster.
    private var withInside: Bool { bounds.width >= metrics.bandProgressFrom }

    override func itemChanged() {
        super.itemChanged()
        problemIcon.isHidden = true   // a poster says it on its cover and in the warning line
        coverAlert.glyph = problemIcon.glyph
        coverAlert.isHidden = problem == nil
        guard let s = summary else {
            insideLabel.stringValue = fallbackLabel.stringValue
            yearsLabel.stringValue = ""
            viewedLabel.stringValue = ""
            progressWords = ""
            progressWithRecency = nil
            return
        }
        insideLabel.stringValue = CardSummaryText.facts(s, pages: holdsPages, withInside: withInside, noun: fileNoun)
        yearsLabel.stringValue = CardSummaryText.years(s) ?? ""
        let words = [CardSummaryText.span(s), CardSummaryText.viewed(s)].compactMap { $0 }
        progressWords = words.joined(separator: " · ")
        progressWithRecency = s.visited.map { (words + [CardSummaryText.ago($0, now: Self.now())]).joined(separator: " · ") }
        viewedLabel.stringValue = progressWithRecency ?? progressWords
    }

    override func setFrameSize(_ newSize: NSSize) {
        let was = withInside
        super.setFrameSize(newSize)
        if withInside != was { itemChanged() }   // the facts line's words change with the size
    }

    override func layout() {
        super.layout()
        let w = bounds.width, band = band
        layoutPlate(bounds, radius: Self.radius)
        layoutCover(pictureFrame, radius: Self.radius, topOnly: true)
        let chip = coverChip.fittingSize
        coverChip.frame = CGRect(x: 8, y: 8, width: chip.width, height: chip.height)
        let alert: CGFloat = 34
        coverAlert.frame = CGRect(x: ((w - alert) / 2).rounded(), y: (w * 92 / 232).rounded(), width: alert, height: alert)
        // The seam: the track the whole width, the fill as far as viewed.
        progressTrack.frame = CGRect(x: 0, y: w, width: w, height: metrics.seam)
        progressTrack.isHidden = isWaitingForFacts
        progressBar.isHidden = isWaitingForFacts || shownProgress == nil
        let fraction = min(1, max(0, shownProgress ?? 0))
        progressBar.frame = CGRect(x: 0, y: w, width: (w * fraction).rounded(), height: metrics.seam)
        // Line 1: the name, ⧉ and RTL after it; `+12` and ✓ at the end.
        nameLabel.font = CardFont.text(band.nameSize, .semibold)
        let line1 = nameLine
        let s = summary
        layoutNameLine(line1, after: [(twoPagesIcon, CGSize(width: 13, height: 13), s?.twoPages ?? false),
                                      (rtlLabel, rtlLabel.fittingSize, s?.rightToLeft ?? false)],
                       end: [(newPill, newPill.fittingSize, !newPill.text.isEmpty),
                             (checkIcon, CGSize(width: 13, height: 13), s?.done ?? false)])
        sizeLabel.isHidden = true
        fallbackLabel.isHidden = true
        guard band.lines > 1 else {
            for view in [insideLabel, histogram, yearsLabel, viewedLabel, warningLabel] as [NSView] { view.isHidden = true }
            return
        }
        let x = Self.side, width = max(0, w - 2 * Self.side)
        let y2 = line1.maxY + band.gap
        let line2 = CGRect(x: x, y: y2, width: width, height: band.factsLine)
        let font = CardFont.text(band.factsSize)
        for label in [insideLabel, yearsLabel, viewedLabel] { label.font = font }
        if let problem {
            warningLabel.font = CardFont.text(11)
            warningLabel.stringValue = Self.warning(problem, short: true)
            warningLabel.isHidden = false
            warningLabel.frame = line2
            insideLabel.isHidden = true
        } else {
            warningLabel.isHidden = true
            insideLabel.isHidden = insideLabel.stringValue.isEmpty
        }
        if band.lines == 2 {
            viewedLabel.isHidden = true
            // The years at the line's end; the facts whole before them, and the bars between the two only where
            // they fit (owner, 2026-10-23: the facts are what the card is for, the bars are the garnish).
            histogram.barWidth = 2.5
            histogram.barGap = 1.5
            var right = line2.maxX
            yearsLabel.isHidden = problem != nil || yearsLabel.stringValue.isEmpty
            if !yearsLabel.isHidden {
                let yw = yearsLabel.textWidth
                right -= yw
                yearsLabel.frame = CGRect(x: right, y: y2, width: yw, height: band.factsLine)
                right -= 8
            }
            let factsWidth = insideLabel.isHidden ? 0 : insideLabel.textWidth + 8
            histogram.isHidden = problem != nil || !histogram.hasBars || x + factsWidth + histogram.barsWidth > right
            if !histogram.isHidden {
                let hw = histogram.barsWidth
                right -= hw
                histogram.frame = CGRect(x: right, y: line2.maxY - 12, width: hw, height: 12)
                right -= 8
            }
            insideLabel.frame = CGRect(x: x, y: y2, width: max(0, right - x), height: band.factsLine)
            return
        }
        // Three lines: the facts alone, then the larger bars with the span and the progress.
        insideLabel.frame = line2
        yearsLabel.isHidden = true
        let y3 = line2.maxY + band.gap
        histogram.barWidth = 4
        histogram.barGap = 2
        histogram.isHidden = !histogram.hasBars
        var cursor = x
        if !histogram.isHidden {
            let hw = histogram.barsWidth
            histogram.frame = CGRect(x: x, y: y3 + band.factsLine - 14, width: hw, height: 14)
            cursor += hw + 8
        }
        let room = max(0, x + width - cursor)
        viewedLabel.stringValue = fits(progressWithRecency, room) ? progressWithRecency! : progressWords
        viewedLabel.isHidden = viewedLabel.stringValue.isEmpty
        viewedLabel.frame = CGRect(x: cursor, y: y3, width: room, height: band.factsLine)
    }

    /// Whether the third line's words with the recency fit `room` in the label's font (measured once per text and
    /// font).
    private func fits(_ text: String?, _ room: CGFloat) -> Bool {
        guard let text else { return false }
        if measuredWithRecency?.text != text || measuredWithRecency?.font != viewedLabel.font {
            measuredWithRecency = (text, viewedLabel.font, viewedLabel.textWidth(of: text))
        }
        return measuredWithRecency!.width <= room
    }
}
