import AppKit
import HomeChrome
import HomeScreenModel

/// A folder or an archive as a compact card (mockup B «Карточка»), 300 × 92 pt (wider when the columns share more):
/// radius 12, a 0.5 pt ring, 8 pt padding. At the left a 76 pt cover (radius 8; an archive's `ZIP` chip at its bottom
/// left); 11 pt to its right four rows spread over the card's height:
/// 1. the name with ⧉ and RTL;
/// 2. the counts with their glyphs — photos, subfolders `· the photos in them` — and the size;
/// 3. the dates' bars and their span (`Jun – Aug 2024`);
/// 4. the progress track with "153 / 248 · 3 d ago" and `+12` — or, when the volume is away or the archive is damaged, the
///    warning line.
final class CompactCard: FolderCard {
    static let radius: CGFloat = 12
    static let coverRadius: CGFloat = 8
    /// Between the cover and the text column.
    static let columnGap: CGFloat = 11
    /// The rows' heights (their fonts' lines: 13.5 pt semibold, 11.5 pt, the bars' 14 pt row, the 10.5 pt pill).
    static let rows: [CGFloat] = [16, 14, 14, 15]

    let photoIcon = GlyphView(ChromeGlyph.photo, color: Chrome.Palette.card.secondary, lineWidth: 1.5)
    let folderIcon = GlyphView(ChromeGlyph.folder, color: Chrome.Palette.card.secondary, lineWidth: 1.5)
    /// Row 2: the photo count, the subfolders' count and (fainter) the photos in them.
    let ownLabel = CardText()
    let foldersLabel = CardText()

    override init(item: HomeCardItem) {
        super.init(item: item)
        for view in [photoIcon, folderIcon, ownLabel, foldersLabel] as [NSView] { addSubview(view) }
        rtlLabel.style = .outlined(size: 10)
        coverChip.style = .overCover(size: 9, padX: 4, padY: 1, radius: 4, veil: 0.6)
        nameLabel.font = CardFont.text(13.5, .semibold)
        for label in [ownLabel, foldersLabel, sizeLabel, yearsLabel, fallbackLabel] {
            label.font = CardFont.text(11.5)
            label.textColor = Chrome.Palette.card.secondary
        }
        viewedLabel.font = CardFont.text(11)
        warningLabel.font = CardFont.text(11)
        histogram.barWidth = 3
        histogram.barGap = 1.5
        itemChanged()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var pictureFrame: CGRect {
        let p = metrics.cardPadding, side = metrics.cardCover
        return CGRect(x: p, y: p, width: side, height: side)
    }

    /// The text column's left edge and width, and its rows' tops: spread from 1 pt inside the padding to 1 pt inside
    /// the padding at the bottom, the space between them equal (`justify-content: space-between`).
    private var column: (x: CGFloat, width: CGFloat) {
        let x = pictureFrame.maxX + Self.columnGap
        return (x, max(0, bounds.width - x - metrics.cardPadding))
    }
    var rowTops: [CGFloat] {
        let top = metrics.cardPadding + 1, bottom = metrics.cardHeight - metrics.cardPadding - 1
        let space = (bottom - top - Self.rows.reduce(0, +)) / CGFloat(Self.rows.count - 1)
        var y = top, tops: [CGFloat] = []
        for h in Self.rows {
            tops.append(y.rounded())
            y += h + space
        }
        return tops
    }
    override var nameLine: CGRect { CGRect(x: column.x, y: rowTops[0], width: column.width, height: Self.rows[0]) }

    override func itemChanged() {
        super.itemChanged()
        guard let s = summary else {
            ownLabel.stringValue = ""
            foldersLabel.stringValue = ""
            sizeLabel.stringValue = ""
            yearsLabel.stringValue = ""
            viewedLabel.stringValue = ""
            insideLabel.stringValue = fallbackLabel.stringValue
            return
        }
        insideLabel.stringValue = ""
        ownLabel.stringValue = s.photos.map { CardSummaryText.inside(CardSummary(photos: $0)) } ?? "?"
        if let folders = s.folders, folders > 0 {
            let count = CardSummaryText.inside(CardSummary(folders: folders)).components(separatedBy: " ").first ?? "\(folders)"
            var inside = ""
            if let n = s.insidePhotos {
                inside = "· " + CardSummaryText.inside(CardSummary(photos: n)) + (s.insideIncomplete ? "+" : "")
            }
            foldersLabel.stringValue = inside.isEmpty ? count : count + "\u{2005}" + inside
            let text = NSMutableAttributedString(string: count, attributes: [.font: foldersLabel.font,
                                                                            .foregroundColor: Chrome.Palette.card.secondary])
            if !inside.isEmpty {
                // The mockup's 3 pt gap, then the photos in them at .8.
                text.append(NSAttributedString(string: "\u{2005}" + inside, attributes: [
                    .font: foldersLabel.font,
                    .foregroundColor: Chrome.Palette.card.secondary.withAlphaComponent(0.8),
                ]))
            }
            foldersLabel.attributedValue = text
        } else {
            foldersLabel.stringValue = ""
            foldersLabel.attributedValue = nil
        }
        sizeLabel.stringValue = CardSummaryText.size(s) ?? "—"
        yearsLabel.stringValue = CardSummaryText.span(s) ?? ""
        viewedLabel.stringValue = CardSummaryText.progressLine(s, now: Self.now()) ?? ""
        if let problem = s.problem { warningLabel.stringValue = Self.warning(problem, short: false) }
    }

    override func layout() {
        super.layout()
        layoutPlate(bounds, radius: Self.radius)
        let p = pictureFrame
        layoutCover(p, radius: Self.coverRadius)
        let chip = coverChip.fittingSize
        coverChip.frame = CGRect(x: p.minX + 4, y: p.maxY - 4 - chip.height, width: chip.width, height: chip.height)
        let (x, width) = column
        let tops = rowTops, rows = Self.rows
        let s = summary
        // Row 1: the name, ⧉ 14 pt, RTL.
        layoutNameLine(nameLine, after: [(twoPagesIcon, CGSize(width: 14, height: 14), s?.twoPages ?? false),
                                         (rtlLabel, rtlLabel.fittingSize, s?.rightToLeft ?? false)])
        // Row 2: [photo] 248   [folder] 3 · 412   1.9 GB — 10 pt apart, each glyph 3 pt from its number.
        let y2 = tops[1], h2 = rows[1]
        let rowViews: [NSView] = [photoIcon, ownLabel, folderIcon, foldersLabel, sizeLabel]
        if s == nil {
            for view in rowViews { view.isHidden = true }
            fallbackLabel.isHidden = fallbackLabel.stringValue.isEmpty
            fallbackLabel.frame = CGRect(x: x, y: y2, width: width, height: h2)
        } else {
            fallbackLabel.isHidden = true
            var cursor = x
            func put(_ glyph: GlyphView?, _ label: CardText) {
                if let glyph {
                    glyph.isHidden = false
                    glyph.frame = CGRect(x: cursor, y: (y2 + (h2 - 12) / 2).rounded(), width: 12, height: 12)
                    cursor += 12 + 3
                }
                let lw = min(label.textWidth, max(0, x + width - cursor))
                label.isHidden = false
                label.frame = CGRect(x: cursor, y: y2, width: lw, height: h2)
                cursor += lw + 10
            }
            put(photoIcon, ownLabel)
            if foldersLabel.stringValue.isEmpty {
                folderIcon.isHidden = true
                foldersLabel.isHidden = true
            } else {
                put(folderIcon, foldersLabel)
            }
            put(nil, sizeLabel)
        }
        insideLabel.isHidden = true
        // Row 3: the bars (3 pt, 12 tall) and the span, on the row's bottom.
        let y3 = tops[2], h3 = rows[2]
        histogram.isHidden = s == nil || histogram.bins.isEmpty
        var cursor = x
        if !histogram.isHidden {
            let hw = histogram.barsWidth
            histogram.frame = CGRect(x: x, y: y3 + h3 - 12, width: hw, height: 12)
            cursor += hw + 8
        }
        yearsLabel.isHidden = yearsLabel.stringValue.isEmpty
        yearsLabel.frame = CGRect(x: cursor, y: y3 + h3 - 12, width: max(0, x + width - cursor), height: 12)
        // Row 4: the track, its text and `+12`; or the warning line.
        let y4 = tops[3], h4 = rows[3]
        checkIcon.isHidden = true
        if s?.problem != nil {
            for view in [progressTrack, progressBar, viewedLabel, newPill] as [NSView] { view.isHidden = true }
            problemIcon.isHidden = false
            problemIcon.frame = CGRect(x: x, y: (y4 + (h4 - 12) / 2).rounded(), width: 12, height: 12)
            warningLabel.isHidden = false
            warningLabel.frame = CGRect(x: x + 12 + 5, y: y4, width: max(0, width - 17), height: h4)
            return
        }
        problemIcon.isHidden = true
        warningLabel.isHidden = true
        guard s != nil else {
            for view in [progressTrack, progressBar, viewedLabel, newPill] as [NSView] { view.isHidden = true }
            return
        }
        var right = x + width
        if !newPill.text.isEmpty {
            let pill = newPill.fittingSize
            right -= pill.width
            newPill.isHidden = false
            newPill.frame = CGRect(x: right, y: (y4 + (h4 - pill.height) / 2).rounded(), width: pill.width, height: pill.height)
            right -= 7
        } else {
            newPill.isHidden = true
        }
        viewedLabel.isHidden = viewedLabel.stringValue.isEmpty
        if !viewedLabel.isHidden {
            let vw = viewedLabel.textWidth
            right -= vw
            viewedLabel.frame = CGRect(x: right, y: y4, width: vw, height: h4)
            right -= 7
        }
        let track = max(0, right - x)
        let barY = (y4 + (h4 - 4) / 2).rounded()
        progressTrack.isHidden = false
        progressTrack.frame = CGRect(x: x, y: barY, width: track, height: 4)
        let fraction = min(1, max(0, shownProgress ?? 0))
        progressBar.isHidden = shownProgress == nil
        progressBar.frame = CGRect(x: x, y: barY, width: (track * fraction).rounded(), height: 4)
        for bar in [progressTrack, progressBar] { bar.layer?.cornerRadius = 2 }
    }
}
