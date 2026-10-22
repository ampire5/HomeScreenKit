import AppKit
import HomeChrome
import HomeScreenModel

/// The columns of the list, which the header and every row share: `Name · Inside · Dates · Viewed · Size`. The name
/// takes what the others leave; when the window is narrow the columns go, the least needed first (Viewed, Inside, then
/// Dates), so that the name keeps `minName`.
struct ListColumns: Equatable {
    enum Column: CaseIterable {
        case name, inside, dates, viewed, size
    }

    static let edge: CGFloat = 20
    static let gap: CGFloat = 12
    /// The gap between the cover and the name.
    static let coverGap: CGFloat = 10
    static let minName: CGFloat = 160
    /// The fixed columns' widths (layout values, not performance limits; picked to fit the texts below): "248 · +1 204+ inside", "Oct 22, 2026" or bars with "2019–2023", "137 / 248", "4.2 GB".
    static let widths: [Column: CGFloat] = [.inside: 140, .dates: 150, .viewed: 90, .size: 70]
    /// Which columns are kept first when the width is short.
    private static let priority: [Column] = [.size, .dates, .inside, .viewed]

    /// Each shown column's left edge and width.
    let frames: [Column: (x: CGFloat, width: CGFloat)]

    init(width: CGFloat, metrics: GridMetrics = GridMetrics()) {
        let nameX = Self.edge + metrics.listCover + Self.coverGap
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

/// A folder, an archive or a file as a row of the list, 44 pt: a 36 pt cover, then the name with its badges and the
/// facts in the columns of `ListColumns`. A file has its format where a folder has its count, and its own date and
/// size. The row reuses `FolderCard`'s labels and does not make strings while it is drawn: the text is set when the
/// item arrives.
final class ListRow: FolderCard {
    /// Dates in a column: `Oct 22, 2026`. One formatter for all rows.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    static func dateText(_ date: Date) -> String { dateFormatter.string(from: date) }

    override var pictureFrame: CGRect {
        let side = metrics.listCover
        return CGRect(x: ListColumns.edge, y: ((bounds.height - side) / 2).rounded(), width: side, height: side)
    }

    override var nameLine: CGRect {
        let c = ListColumns(width: bounds.width, metrics: metrics)
        let name = c[.name] ?? (x: 0, width: bounds.width)
        return CGRect(x: name.x, y: ((bounds.height - nameLineHeight) / 2).rounded(), width: name.width, height: nameLineHeight)
    }

    override func itemChanged() {
        super.itemChanged()
        // Rows have neither the poster's line along the cover nor the card's track, and the pill would cover the cover.
        for view in [progressBar, progressTrack, badgePill, countLabel, fallbackLabel] as [NSView] { view.isHidden = true }
        if let s = summary {
            if s.done { viewedLabel.stringValue = "✓" }
            if yearsLabel.stringValue.isEmpty { yearsLabel.stringValue = item.date.map(Self.dateText) ?? "" }
        } else {
            insideLabel.stringValue = item.format ?? fallbackLabel.stringValue
            yearsLabel.stringValue = item.date.map(Self.dateText) ?? ""
            sizeLabel.stringValue = item.bytes.flatMap { CardSummaryText.size(CardSummary(bytes: $0)) } ?? ""
        }
    }

    override func layout() {
        super.layout()
        let outset = Chrome.Ring.gap + Chrome.Ring.width
        layoutCover(pictureFrame, ringAround: bounds.insetBy(dx: 8 + outset, dy: outset))
        let c = ListColumns(width: bounds.width, metrics: metrics)
        let s = summary
        layoutNameLine(nameLine, trailing: [(flagPill, flagPill.text.hasPrefix("+")), (problemIcon, s?.problem != nil),
                                            (rtlLabel, s?.rightToLeft ?? false), (twoPagesIcon, s?.twoPages ?? false)])
        let lineH = metrics.bandFactsLine
        let y = ((bounds.height - lineH) / 2).rounded()
        func place(_ label: NSTextField, _ column: ListColumns.Column) {
            guard let f = c[column], !label.stringValue.isEmpty else { label.isHidden = true; return }
            label.isHidden = false
            label.frame = CGRect(x: f.x, y: y, width: f.width, height: lineH)
        }
        place(insideLabel, .inside)
        place(viewedLabel, .viewed)
        place(sizeLabel, .size)
        // Dates: the bars before the years when both fit the column.
        histogram.isHidden = true
        if let f = c[.dates], !yearsLabel.stringValue.isEmpty {
            yearsLabel.isHidden = false
            var x = f.x
            if histogram.hasBars {
                let hw = Self.width(of: histogram)
                if hw + 5 + Self.textWidth(yearsLabel.stringValue) <= f.width {
                    histogram.isHidden = false
                    histogram.frame = CGRect(x: x, y: y + (lineH - HistogramView.height) / 2, width: hw,
                                             height: HistogramView.height)
                    x += hw + 5
                }
            }
            yearsLabel.frame = CGRect(x: x, y: y, width: f.x + f.width - x, height: lineH)
        } else {
            yearsLabel.isHidden = true
        }
    }
}
