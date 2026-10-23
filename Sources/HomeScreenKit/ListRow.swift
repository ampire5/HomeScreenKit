import AppKit
import HomeChrome
import HomeScreenModel

/// The columns of the list (mockup C), which the header and every row share: `cover 32 | Name | Inside 64 |
/// Dates 118 | Viewed 104 | Size 52`, 10 pt apart, 12 pt in from the container's sides. The name takes what the
/// others leave; when the window is narrow the columns go, the least needed first (Viewed, Inside, then Dates), so
/// that the name keeps `minName`.
struct ListColumns: Equatable {
    enum Column: CaseIterable {
        case name, inside, dates, viewed, size
    }

    /// The container's padding at the sides.
    static let edge: CGFloat = 12
    static let gap: CGFloat = 10
    static let minName: CGFloat = 160
    /// The mockup's column widths.
    static let widths: [Column: CGFloat] = [.inside: 64, .dates: 118, .viewed: 104, .size: 52]
    /// Which columns are kept first when the width is short.
    private static let priority: [Column] = [.size, .dates, .inside, .viewed]

    /// Each shown column's left edge and width.
    let frames: [Column: (x: CGFloat, width: CGFloat)]

    init(width: CGFloat, metrics: GridMetrics = GridMetrics()) {
        let nameX = Self.edge + metrics.listCover + Self.gap
        var room = width - Self.edge - nameX - Self.minName
        var kept = Set<Column>()
        for column in Self.priority {
            let need = Self.widths[column]! + Self.gap
            guard need <= room else { continue }
            room -= need
            kept.insert(column)
        }
        var frames: [Column: (x: CGFloat, width: CGFloat)] = [:]
        var right = width - Self.edge
        for column in [Column.size, .viewed, .dates, .inside] where kept.contains(column) {
            let w = Self.widths[column]!
            frames[column] = (right - w, w)
            right -= w + Self.gap
        }
        frames[.name] = (nameX, max(0, right - nameX))
        self.frames = frames
    }

    static func == (a: ListColumns, b: ListColumns) -> Bool {
        a.frames.count == b.frames.count && a.frames.allSatisfy { key, value in
            b.frames[key].map { $0.x == value.x && $0.width == value.width } ?? false
        }
    }

    subscript(column: Column) -> (x: CGFloat, width: CGFloat)? { frames[column] }
}

/// A folder, an archive or a file as a row of the list (mockup C «Список»), 44 pt with a 1 pt separator at its
/// bottom, inside the list's container (`ListPlate`): a 32 pt cover (radius 6; a folder's is four photos), the name
/// (13 pt) with the archive's type chip, ⧉ and a warning glyph, then the columns of `ListColumns` — Inside (12 pt),
/// Dates (the bars and the years), Viewed (a track and `+12`), Size. A file has its format where a folder has its
/// count, and its own date and size. The text is set when the item arrives, not while drawing.
final class ListRow: FolderCard {
    /// Dates in a column: `Oct 22, 2026`. One formatter for all rows.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    static func dateText(_ date: Date) -> String { dateFormatter.string(from: date) }

    static let coverRadius: CGFloat = 6
    /// The archive's type next to the name, outlined (`ZIP`).
    let typeChip = TextChip(.outlined(size: 9.5))
    private let separator = CALayer()
    /// The 1 pt line under the row; the last row of the container has none (the container's edge is there).
    var showsSeparator = true { didSet { separator.isHidden = !showsSeparator } }

    override init(item: HomeCardItem) {
        super.init(item: item)
        addSubview(typeChip)
        layer?.addSublayer(separator)
        plate.isHidden = true
        edge.isHidden = true
        nameLabel.font = CardFont.text(13, NSFont.Weight(0.265))   // the mockup's weight 550
        insideLabel.font = CardFont.text(12)
        insideLabel.textColor = Chrome.Palette.card.label
        for label in [yearsLabel, sizeLabel] { label.font = CardFont.text(11.5) }
        sizeLabel.alignRight = true
        histogram.barWidth = 2.5
        histogram.barGap = 1
        newPill.style = .newPill(size: 10, padX: 5, padY: 0)
        itemChanged()
        appearanceChanged()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var pictureFrame: CGRect {
        let side = metrics.listCover
        return CGRect(x: metrics.listPadding, y: ((metrics.listRow - side) / 2).rounded(.down), width: side, height: side)
    }

    /// The content's middle: the row without its separator.
    private var middle: CGFloat { (bounds.height - 1) / 2 }

    override var nameLine: CGRect {
        let c = ListColumns(width: bounds.width, metrics: metrics)
        let name = c[.name] ?? (x: 0, width: bounds.width)
        return CGRect(x: name.x, y: (middle - 8).rounded(), width: name.width, height: 16)
    }

    /// Waiting: the placeholder in the small cover's place; a line in the Inside and the Dates columns (the board's
    /// 70 % and 45 % of the column), on the row's middle.
    override var waitingCover: (rect: CGRect, radius: CGFloat, topOnly: Bool) { (pictureFrame, Self.coverRadius, false) }
    override var waitingLines: [CGRect] {
        let c = ListColumns(width: bounds.width, metrics: metrics), h = Self.waitingLineHeight
        let y = (middle - h / 2).rounded()
        return zip([ListColumns.Column.inside, .dates], Self.waitingWidths).compactMap { column, fraction in
            c[column].map { CGRect(x: $0.x, y: y, width: ($0.width * fraction).rounded(), height: h) }
        }
    }

    override func itemChanged() {
        super.itemChanged()
        // No poster seam, no cover chip (the type is beside the name), no ✓ or RTL in the mockup's row.
        for view in [coverChip, checkIcon, rtlLabel, fallbackLabel, viewedLabel, warningLabel] as [NSView] { view.isHidden = true }
        typeChip.text = item.badge ?? ""
        if let s = summary {
            insideLabel.stringValue = CardSummaryText.listInside(s, pages: holdsPages)
            yearsLabel.stringValue = CardSummaryText.years(s) ?? item.date.map(Self.dateText) ?? ""
            sizeLabel.stringValue = CardSummaryText.size(s) ?? "—"
        } else if isWaiting {
            insideLabel.stringValue = ""
            yearsLabel.stringValue = ""
            sizeLabel.stringValue = ""
        } else {
            insideLabel.stringValue = item.format ?? fallbackLabel.stringValue
            yearsLabel.stringValue = item.date.map(Self.dateText) ?? ""
            sizeLabel.stringValue = item.bytes.flatMap { CardSummaryText.size(CardSummary(bytes: $0)) } ?? ""
        }
    }

    override func appearanceChanged() {
        super.appearanceChanged()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        separator.backgroundColor = Chrome.resolve(Chrome.Palette.card.separator, in: self)
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        let inset = Self.ringGap + Self.ringWidth
        layoutPlate(.zero, radius: 0, selection: bounds.insetBy(dx: 6, dy: inset), selectionRadius: Self.coverRadius)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        separator.frame = CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        CATransaction.commit()
        layoutCover(pictureFrame, radius: Self.coverRadius)
        let c = ListColumns(width: bounds.width, metrics: metrics)
        let s = summary
        layoutNameLine(nameLine, after: [(typeChip, typeChip.fittingSize, !typeChip.text.isEmpty),
                                         (twoPagesIcon, CGSize(width: 13, height: 13), s?.twoPages ?? false),
                                         (problemIcon, CGSize(width: 13, height: 13), s?.problem != nil)])
        func place(_ label: CardText, _ column: ListColumns.Column, height: CGFloat) {
            guard let f = c[column], !label.stringValue.isEmpty else { label.isHidden = true; return }
            label.isHidden = false
            label.frame = CGRect(x: f.x, y: (middle - height / 2).rounded(), width: f.width, height: height)
        }
        place(insideLabel, .inside, height: 15)
        place(sizeLabel, .size, height: 14)
        // Dates: the bars (12 tall) and the years on one bottom line.
        histogram.isHidden = true
        let datesTop = (middle - 6).rounded()
        if let f = c[.dates], !yearsLabel.stringValue.isEmpty {
            yearsLabel.isHidden = false
            var x = f.x
            if s != nil, !histogram.bins.isEmpty {
                histogram.isHidden = false
                let hw = histogram.barsWidth
                histogram.frame = CGRect(x: x, y: datesTop, width: hw, height: 12)
                x += hw + 6
            }
            yearsLabel.frame = CGRect(x: x, y: datesTop, width: max(0, f.x + f.width - x), height: 12)
        } else {
            yearsLabel.isHidden = true
        }
        // Viewed: the track (4 pt, fully rounded) and `+12`.
        guard let f = c[.viewed], s != nil else {
            for view in [progressTrack, progressBar, newPill] as [NSView] { view.isHidden = true }
            return
        }
        var right = f.x + f.width
        newPill.isHidden = newPill.text.isEmpty
        if !newPill.isHidden {
            let pill = newPill.fittingSize
            right -= pill.width
            newPill.frame = CGRect(x: right, y: (middle - pill.height / 2).rounded(), width: pill.width, height: pill.height)
            right -= 6
        }
        let track = max(0, right - f.x), barY = (middle - 2).rounded()
        progressTrack.isHidden = false
        progressTrack.frame = CGRect(x: f.x, y: barY, width: track, height: 4)
        let fraction = min(1, max(0, shownProgress ?? 0))
        progressBar.isHidden = shownProgress == nil
        progressBar.frame = CGRect(x: f.x, y: barY, width: (track * fraction).rounded(), height: 4)
        // The track is fully rounded; the fill is cut by it, so only its start is round (square where it stops).
        progressTrack.layer?.cornerRadius = 2
        progressBar.layer?.cornerRadius = 2
        progressBar.layer?.maskedCorners = fraction >= 1 ? [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner,
                                                             .layerMaxXMaxYCorner]
                                                         : [.layerMinXMinYCorner, .layerMinXMaxYCorner]
    }
}
