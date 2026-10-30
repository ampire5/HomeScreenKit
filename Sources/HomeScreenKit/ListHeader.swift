import AppKit
import HomeChrome
import HomeScreenModel

/// The heads of the list's columns (mockup C): the top of the list's container — the card's plate with its rounded
/// top corners and its ring, 11 pt secondary titles 7 pt from the top and 12 from the sides, a 1 pt separator under
/// them; Size is right-aligned. It stays at the top of the visible area while the rows scroll under it (the browser
/// places it). A click on Name, Dates or Size sorts (the browser passes it on as the sort capsule's choice); Inside
/// and Viewed do not sort. The active column carries the direction.
final class ListHeader: NSView {
    static let height: CGFloat = GridMetrics().listHeader
    static let radius: CGFloat = 12

    /// A click on a sortable column.
    var onSort: ((BrowserSort.Key) -> Void)?
    /// The sorts the place offers (the capsule's keys); the other heads are plain text.
    var sortable: [BrowserSort.Key] = [.name, .date, .size] { didSet { if sortable != oldValue { showTitles() } } }
    /// The sort shown: its column carries ↑ or ↓.
    var sort = BrowserSort.standard { didSet { if sort != oldValue { showTitles() } } }

    private static let names = Dictionary(uniqueKeysWithValues: TableColumn.allCases.map { ($0, $0.title) })
    var selectedColumns = TableColumn.standard { didSet { if selectedColumns != oldValue { needsLayout = true } } }
    var mediaKind = FileStyle.MediaKind.photo
    var onColumns: ((Set<TableColumn>) -> Void)?
    private static let keys: [ListColumns.Column: BrowserSort.Key] = [.name: .name, .dates: .date, .size: .size]

    private var labels: [ListColumns.Column: CardText] = [:]
    private let plate = CAShapeLayer()
    private let rim = CAShapeLayer()
    private let separator = CALayer()
    /// The columns now laid out.
    private(set) var columns = ListColumns(width: 0)
    /// The rows' metrics: the name column starts after their cover, whose size follows the size step.
    var metrics = GridMetrics() { didSet { if metrics != oldValue { needsLayout = true } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(plate)
        rim.fillColor = nil
        rim.lineWidth = 0.5
        layer?.addSublayer(rim)
        layer?.addSublayer(separator)
        for column in ListColumns.Column.allCases {
            let label = CardText()
            label.font = CardFont.text(11)
            label.textColor = Chrome.Palette.card.secondary
            label.alignRight = column == .size
            addSubview(label)
            labels[column] = label
        }
        toolTip = "Right-click to choose columns"
        showTitles()
        appearanceChanged()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    // MARK: Shown

    /// The heads' texts in column order, whether or not the width has room for them.
    var titles: [String] { ListColumns.Column.allCases.filter { selectedColumns.contains($0) }.map { labels[$0]!.stringValue } }

    private func showTitles() {
        for column in ListColumns.Column.allCases {
            let active = Self.keys[column] == sort.key
            labels[column]!.stringValue = Self.names[column]! + (active ? (sort.ascending ? " ↑" : " ↓") : "")
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceChanged()
    }

    private func appearanceChanged() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        plate.fillColor = Chrome.resolve(Chrome.Palette.card.background, in: self)
        rim.strokeColor = Chrome.resolve(Chrome.Palette.card.separator, in: self)
        separator.backgroundColor = Chrome.resolve(Chrome.Palette.card.separator, in: self)
        CATransaction.commit()
    }

    /// The container's top: a rectangle with its top corners rounded, and the ring along its top and sides.
    private static func top(_ rect: CGRect, radius r: CGFloat, closed: Bool) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + r, y: rect.minY), radius: r)
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r), radius: r)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        if closed { p.closeSubpath() }
        return p
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        plate.frame = bounds
        plate.path = Self.top(bounds, radius: Self.radius, closed: true)
        rim.frame = bounds
        rim.path = Self.top(bounds.insetBy(dx: -0.25, dy: -0.25), radius: Self.radius + 0.25, closed: false)
        separator.frame = CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        CATransaction.commit()
        columns = ListColumns(width: bounds.width, metrics: metrics, selected: selectedColumns)
        let h = ceil(CardFont.lineHeight(CardFont.text(11)))
        for column in ListColumns.Column.allCases {
            let label = labels[column]!
            guard let f = columns[column] else { label.isHidden = true; continue }
            label.isHidden = false
            label.frame = CGRect(x: f.x, y: 7, width: f.width, height: h)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu(title: "Columns")
        menu.autoenablesItems = false
        for column in TableColumn.allCases where column.isAvailable(for: mediaKind) {
            let item = NSMenuItem(title: column.title, action: #selector(toggleColumn(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = column.rawValue
            item.state = selectedColumns.contains(column) ? .on : .off
            item.isEnabled = column != .name
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let reset = NSMenuItem(title: "Default Columns", action: #selector(resetColumns), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        return menu
    }

    @objc private func toggleColumn(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let column = TableColumn(rawValue: key), column != .name else { return }
        if !selectedColumns.insert(column).inserted { selectedColumns.remove(column) }
        onColumns?(selectedColumns)
    }

    @objc private func resetColumns() {
        selectedColumns = TableColumn.standard
        onColumns?(selectedColumns)
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

/// The list's container under its rows (mockup C): the card's plate, radius 12, its 0.5 pt ring outside. The header
/// covers its top; the rows lie on it.
final class ListPlate: NSView {
    private let edge = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = ListHeader.radius
        layer?.cornerCurve = .continuous
        edge.borderWidth = 0.5
        edge.cornerCurve = .continuous
        layer?.addSublayer(edge)
        layer?.masksToBounds = false
        appearanceChanged()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceChanged()
    }

    private func appearanceChanged() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = Chrome.resolve(Chrome.Palette.card.background, in: self)
        edge.borderColor = Chrome.resolve(Chrome.Palette.card.separator, in: self)
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edge.frame = bounds.insetBy(dx: -0.5, dy: -0.5)
        edge.cornerRadius = ListHeader.radius + 0.5
        CATransaction.commit()
    }
}
