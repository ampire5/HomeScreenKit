import AppKit
import HomeChrome
import HomeScreenModel

/// The heads of the list's columns, above the rows. A click on Name, Dates or Size sorts (the browser passes it on as
/// the sort capsule's choice); Inside and Viewed do not sort. The active column carries the direction.
final class ListHeader: NSView {
    static let height: CGFloat = 28

    /// A click on a sortable column.
    var onSort: ((BrowserSort.Key) -> Void)?
    /// The sort shown: its column is lit and carries ↑ or ↓.
    /// The sorts the place offers (the capsule's keys); the other heads are plain text.
    var sortable: [BrowserSort.Key] = [.name, .date, .size] { didSet { if sortable != oldValue { showTitles() } } }
    var sort = BrowserSort.standard { didSet { if sort != oldValue { showTitles() } } }

    private static let names: [ListColumns.Column: String] = [.name: "Name", .inside: "Inside", .dates: "Dates",
                                                              .viewed: "Viewed", .size: "Size"]
    private static let keys: [ListColumns.Column: BrowserSort.Key] = [.name: .name, .dates: .date, .size: .size]
    private static let font = Chrome.Text.font(.small, weight: .semibold)

    private var labels: [ListColumns.Column: NSTextField] = [:]
    /// The columns now laid out.
    private(set) var columns = ListColumns(width: 0)

    override init(frame: NSRect) {
        super.init(frame: frame)
        for column in ListColumns.Column.allCases {
            let label = NSTextField(labelWithString: "")
            label.font = Self.font
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
            labels[column] = label
        }
        showTitles()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    // MARK: Shown

    /// The heads' texts in column order, whether or not the width has room for them.
    var titles: [String] { ListColumns.Column.allCases.map { labels[$0]!.stringValue } }

    private func showTitles() {
        for column in ListColumns.Column.allCases {
            let label = labels[column]!
            let active = Self.keys[column] == sort.key
            label.stringValue = Self.names[column]! + (active ? (sort.ascending ? " ↑" : " ↓") : "")
            let canSort = Self.keys[column].map(sortable.contains) ?? false
            label.textColor = active ? Chrome.Palette.window.label
                                     : canSort ? Chrome.Palette.window.secondaryLabel : Chrome.Palette.window.tertiaryLabel
        }
    }

    override func layout() {
        super.layout()
        columns = ListColumns(width: bounds.width)
        let h = labels[.name]!.intrinsicContentSize.height
        for column in ListColumns.Column.allCases {
            let label = labels[column]!
            guard let f = columns[column] else { label.isHidden = true; continue }
            label.isHidden = false
            label.frame = CGRect(x: f.x, y: bounds.height - h - 6, width: f.width, height: h)
        }
    }

    // MARK: Clicks

    /// What a click on `column` does: the sortable ones call `onSort`.
    func click(_ column: ListColumns.Column) {
        if let key = Self.keys[column], sortable.contains(key) { onSort?(key) }
    }

    private func column(at point: CGPoint) -> ListColumns.Column? {
        ListColumns.Column.allCases.first { column in
            columns[column].map { point.x >= $0.x - ListColumns.gap / 2 && point.x < $0.x + $0.width + ListColumns.gap / 2 } ?? false
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { !isHidden && frame.contains(point) ? self : nil }

    override func mouseDown(with event: NSEvent) {
        // The press gives the keys to the browser, as a card's does.
        if let browser = sequence(first: self as NSView, next: { $0.superview }).lazy.compactMap({ $0 as? HomeBrowserView }).first {
            window?.makeFirstResponder(browser)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let column = column(at: convert(event.locationInWindow, from: nil)) else { return }
        click(column)
    }
}
