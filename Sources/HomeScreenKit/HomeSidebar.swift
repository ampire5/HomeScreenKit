import AppKit
import HomeChrome
import HomeScreenModel

/// Home's sidebar: a native sidebar material with the app's sources, the places and the folder tree
/// under them, from a `SidebarTree`. A click on a row opens it in the browser, on its
/// triangle opens or closes it; ↑ ↓ ← → move the lit row as in Finder and Return opens it; Tab gives the keys back.
/// A row whose folders take long to list shows a small spinner where its count goes.
final class HomeSidebar: NSView {
    /// The column the sidebar takes by default.
    static let width: CGFloat = 236
    /// How narrow and how wide it can be kept; shown, it is at most a third of the window (`HomeView.widestSidebar`).
    public static let widthRange: ClosedRange<CGFloat> = 180...1600
    /// The widest it may show in any window, however narrow.
    static let widestAlways: CGFloat = 400
    static let inset: CGFloat = 10
    static let rowHeight: CGFloat = 28
    static let headingHeight: CGFloat = 26
    static let indent: CGFloat = 14
    /// Compact indent: the step past the first three levels.
    static let deepIndent: CGFloat = 6

    /// A row's indent at `depth`: compact, the levels past the third step less (and show guides), so deep trees fit.
    static func offset(depth: Int, compact: Bool) -> CGFloat {
        guard compact else { return CGFloat(depth) * indent }
        return CGFloat(min(depth, 3)) * indent + CGFloat(max(0, depth - 3)) * deepIndent
    }

    /// Compact indent with guides (`home-sidebar-indent=compact`), or the same step at every level.
    var compactIndent = true {
        didSet { if compactIndent != oldValue { rebuild() } }
    }
    private static let top: CGFloat = 10

    var onOpen: ((BrowserLocation) -> Void)?
    var onExpand: ((URL) -> Void)?
    var onCollapse: ((URL) -> Void)?
    var onToggleSection: ((String) -> Void)?
    /// Tab: the keys go back to the grid.
    var onEndKeys: (() -> Void)?
    /// A click on a row: the keys stay with (or go to) the browser.
    var onClickKeys: (() -> Void)?
    /// A row's context menu (`HomeSource.sidebarMenu(for:)`); none, or no items: no menu.
    var menuItems: ((HomeSidebarRow) -> [HomeMenuItem])?
    /// An item of a row's menu was chosen.
    var onMenu: ((String, HomeSidebarRow) -> Void)?
    /// How long a row lists before its spinner shows.
    var slowAfter: Duration = .milliseconds(300)
    var contentTopInset = HomeBrowserView.defaultTopInset {
        didSet { if contentTopInset != oldValue { needsLayout = true } }
    }

    var tree = SidebarTree(sections: []) {
        didSet {
            let current = tree.currentLine
            let currentID = current.flatMap(rowID)
            if currentID != followedID {
                // The browser moved: the light follows it, into view after the layout.
                followedID = currentID
                selectedID = currentID
                if current != nil { revealsSelected = true }
            }
            // The row the arrows lit stays lit when rows come or go around it (a folder opened, a reply).
            let line = selectedID.flatMap(line(of:)) ?? current
            if line != nil, line != selected, selectedID == currentID { revealsSelected = true }
            selected = line
            rebuild()
        }
    }
    /// The lit row by its id: lines move as folders open and replies fill in.
    private var selectedID: String?
    /// The current row's id as last followed.
    private var followedID: String?

    private func rowID(at line: Int) -> String? {
        let lines = tree.lines
        guard lines.indices.contains(line), case .row(let row, _, _, _) = lines[line] else { return nil }
        return row.id
    }

    private func line(of id: String) -> Int? {
        tree.lines.firstIndex { if case .row(let row, _, _, _) = $0 { row.id == id } else { false } }
    }
    private var revealsSelected = false

    private let scroll = NSScrollView()
    private let document = FlippedView()
    private var lineViews: [SidebarLineView] = []
    /// The lit row: the current one, or where the arrows moved.
    private var selected: Int?
    /// Folders listing for longer than `slowAfter`, by path.
    private var slow: Set<String> = []
    private var slowTimers: [String: Task<Void, Never>] = [:]

    init() {
        super.init(frame: .zero)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document
        addSubview(scroll)   // on the material the split view's sidebar item gives
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
    }

    override func becomeFirstResponder() -> Bool {
        lineViews.forEach { $0.hasKeys = true }
        return true
    }

    override func resignFirstResponder() -> Bool {
        lineViews.forEach { $0.hasKeys = false }
        return true
    }

    // MARK: Lines

    private func rebuild() {
        let lines = tree.lines
        while lineViews.count < lines.count {
            let view = SidebarLineView()
            document.addSubview(view)
            lineViews.append(view)
        }
        while lineViews.count > lines.count { lineViews.removeLast().removeFromSuperview() }
        watchLoading(lines)
        let keys = window?.firstResponder === self
        for (i, (view, line)) in zip(lineViews, lines).enumerated() {
            view.compactIndent = compactIndent
            view.show(line, lit: i == selected, spinning: path(of: line).map(slow.contains) == true)
            view.hasKeys = keys
            view.tag = i
        }
        needsLayout = true
    }

    /// Spinners only for rows that keep listing past `slowAfter`.
    private func watchLoading(_ lines: [SidebarTree.Line]) {
        var loading = Set<String>()
        for line in lines {
            if case .row(_, _, _, true) = line, let path = path(of: line) { loading.insert(path) }
        }
        slow.formIntersection(loading)
        for (path, timer) in slowTimers where !loading.contains(path) {
            timer.cancel()
            slowTimers[path] = nil
        }
        for path in loading where slowTimers[path] == nil && !slow.contains(path) {
            slowTimers[path] = Task { @MainActor [weak self] in
                guard let after = self?.slowAfter else { return }
                try? await Task.sleep(for: after)
                guard let self, !Task.isCancelled else { return }
                self.slowTimers[path] = nil
                self.slow.insert(path)
                self.rebuild()
            }
        }
    }

    private func path(of line: SidebarTree.Line) -> String? {
        guard case .row(let row, _, _, _) = line, case .folder(let url) = row.location else { return nil }
        return url.standardizedFileURL.path
    }

    override func layout() {
        super.layout()
        scroll.frame = CGRect(x: 0, y: contentTopInset, width: bounds.width, height: max(0, bounds.height - contentTopInset))
        // The height first: a legacy scroller shows or hides for it and takes its width before the rows are laid out.
        let height = lineViews.reduce(2 * Self.top) { $0 + ($1.isHeading ? Self.headingHeight : Self.rowHeight) }
        document.frame.size.height = max(height, scroll.contentSize.height)
        scroll.tile()
        var y = Self.top
        let width = max(0, scroll.contentSize.width)
        for view in lineViews {
            let h = view.isHeading ? Self.headingHeight : Self.rowHeight
            let frame = CGRect(x: 0, y: y, width: width, height: h)
            if view.frame.size != frame.size { view.needsLayout = true }
            view.frame = frame
            y += h
        }
        document.frame = CGRect(x: 0, y: 0, width: width, height: max(height, scroll.contentSize.height))
        if revealsSelected, let selected, lineViews.indices.contains(selected) {
            revealsSelected = false
            document.scrollToVisible(lineViews[selected].frame.insetBy(dx: 0, dy: -Self.rowHeight))
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let point = document.convert(event.locationInWindow, from: nil)
        guard let view = lineViews.first(where: { $0.frame.contains(point) }) else { return }
        // As in Finder, a click leaves the keys with the browser (letters pick a name there); Tab brings them here.
        onClickKeys?()
        let x = point.x - view.frame.minX
        if view.disclosureFrame.insetBy(dx: -4, dy: -4).contains(CGPoint(x: x, y: view.bounds.midY)) {
            clickDisclosure(line: view.tag)
        } else {
            click(line: view.tag)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = document.convert(event.locationInWindow, from: nil)
        guard let view = lineViews.first(where: { $0.frame.contains(point) }) else { return nil }
        return menu(forLine: view.tag)
    }

    /// The context menu of a row (the app's items for it); nil for a heading or a row without items.
    func menu(forLine line: Int) -> NSMenu? {
        let lines = tree.lines
        guard lines.indices.contains(line), case .row(let row, _, _, _) = lines[line],
              let items = menuItems?(row), !items.isEmpty else { return nil }
        let menu = NSMenu()
        for item in items {
            let menuItem = menu.addItem(withTitle: item.title, action: #selector(SidebarMenuTarget.chose(_:)),
                                        keyEquivalent: "")
            let target = SidebarMenuTarget { [weak self] in self?.onMenu?(item.id, row) }
            menuItem.target = target
            menuItem.representedObject = target   // a menu item holds its target weakly
        }
        return menu
    }

    /// A click on a line: a heading folds its section, a row opens.
    func click(line: Int) {
        let lines = tree.lines
        guard lines.indices.contains(line) else { return }
        switch lines[line] {
        case .heading(let section, _, _): onToggleSection?(section)
        case .row(let row, _, _, _):
            selected = line
            selectedID = row.id
            rebuild()
            onOpen?(row.location)
        }
    }

    func clickDisclosure(line: Int) {
        let lines = tree.lines
        guard lines.indices.contains(line), case .row(let row, _, let expanded, _) = lines[line], row.expandable,
              case .folder(let url) = row.location else { return }
        if expanded { onCollapse?(url) } else { onExpand?(url) }
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        if !handleKey(event) { super.keyDown(with: event) }
    }

    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags.isEmpty else { return false }
        if event.keyCode == 48 {
            onEndKeys?()
            return true
        }
        let keys: [UInt16: SidebarTree.Key] = [126: .up, 125: .down, 123: .left, 124: .right, 36: .open, 76: .open]
        guard let key = keys[event.keyCode] else { return false }
        let lines = tree.lines
        guard let from = selected ?? tree.currentLine else {
            // Nothing lit yet: the first row.
            if let first = lines.firstIndex(where: { if case .row = $0 { true } else { false } }) { light(first) }
            return true
        }
        switch tree.move(key, from: from) {
        case .select(let i): light(i)
        case .expand(let url): onExpand?(url)
        case .collapse(let url): onCollapse?(url)
        case .open(let location): onOpen?(location)
        case .none: break
        }
        return true
    }

    private func light(_ line: Int) {
        selected = line
        selectedID = rowID(at: line)
        rebuild()
        if lineViews.indices.contains(line) { document.scrollToVisible(lineViews[line].frame) }
    }

    // MARK: For tests

    var titles: [String] { lineViews.map(\.title.stringValue) }
    var visibleLineRect: CGRect { scroll.contentView.documentVisibleRect }
    var lineFrames: [CGRect] { lineViews.map(\.frame) }
    var titleFrames: [CGRect] { lineViews.map(\.title.frame) }
    var guideCounts: [Int] { lineViews.map(\.guideCount) }
    var scrollWidth: CGFloat { scroll.frame.width }
    var rowTitleWidths: [CGFloat] { lineViews.filter { !$0.isHeading }.map(\.title.frame.width) }
    var countTexts: [String] { lineViews.map(\.count.stringValue) }
    var highlightedLine: Int? { selected }
    func isSpinning(line: Int) -> Bool { lineViews.indices.contains(line) && !lineViews[line].spinner.isHidden }
}

/// A sidebar menu item's action: the item and its row, kept by the item.
private final class SidebarMenuTarget: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func chose(_ sender: NSMenuItem) { action() }
}

/// One line of the sidebar: a heading (small, grey, with a fold chevron on hover) or a row (triangle, symbol, title,
/// count or spinner), lit as a capsule when current.
private final class SidebarLineView: NSView {
    let title = NSTextField(labelWithString: "")
    let count = NSTextField(labelWithString: "")
    let spinner = NSProgressIndicator()
    private let symbol = NSImageView()
    private let triangle = NSImageView()
    private let light = NSView()
    private(set) var isHeading = false
    private var depth = 0
    var compactIndent = true
    /// Thin lines down the levels above the row (compact indent).
    private let guides = CAShapeLayer()
    private var lit = false
    private var hovering = false
    private var collapsed = false
    var hasKeys = false { didSet { if hasKeys != oldValue { paint() } } }
    private var tagValue = 0
    override var tag: Int {
        get { tagValue }
        set { tagValue = newValue }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        guides.lineWidth = 1
        guides.fillColor = nil
        layer?.addSublayer(guides)
        light.wantsLayer = true
        light.layer?.cornerRadius = Chrome.Radius.control
        title.lineBreakMode = .byTruncatingMiddle
        count.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        count.textColor = .secondaryLabelColor
        count.alignment = .right
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.isHidden = true
        triangle.contentTintColor = .secondaryLabelColor
        symbol.contentTintColor = .controlAccentColor
        for view in [light, triangle, symbol, title, count, spinner] { addSubview(view) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    /// Clicks go to the sidebar, which knows the lines.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func mouseEntered(with event: NSEvent) { hovering = true; paint() }
    override func mouseExited(with event: NSEvent) { hovering = false; paint() }

    func show(_ line: SidebarTree.Line, lit: Bool, spinning: Bool) {
        self.lit = lit
        switch line {
        case .heading(_, let text, let folded):
            isHeading = true
            collapsed = folded
            depth = 0
            title.stringValue = text
            count.stringValue = ""
            symbol.image = nil
            alphaValue = 1
            showSpinner(false)
        case .row(let row, let d, let expanded, _):
            isHeading = false
            depth = d
            title.stringValue = row.title
            count.stringValue = row.count.map(BrowserSummary.number) ?? ""
            symbol.image = NSImage(systemSymbolName: row.symbol, accessibilityDescription: nil)
            triangle.image = row.expandable
                ? NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
                : nil
            alphaValue = row.isDimmed ? 0.45 : 1
            showSpinner(spinning)
        }
        paint()
        needsLayout = true
    }

    private func showSpinner(_ on: Bool) {
        spinner.isHidden = !on
        count.isHidden = on
        if on { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    private func paint() {
        if isHeading {
            title.font = .systemFont(ofSize: 11, weight: .semibold)
            title.textColor = .secondaryLabelColor
            triangle.image = hovering
                ? NSImage(systemSymbolName: collapsed ? "chevron.right" : "chevron.down", accessibilityDescription: nil)
                : nil
            light.isHidden = true
            return
        }
        title.font = .systemFont(ofSize: 13)
        title.textColor = lit && hasKeys ? .alternateSelectedControlTextColor : .labelColor
        // On the strong light the accent symbol would vanish into it.
        symbol.contentTintColor = lit && hasKeys ? .alternateSelectedControlTextColor : .controlAccentColor
        light.isHidden = !lit
        light.layer?.backgroundColor = Chrome.resolve(NSColor.selectedContentBackgroundColor.withAlphaComponent(hasKeys ? 1 : 0.55),
                                                      in: self)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if lit, !isHeading { paint() }
        needsLayout = true   // the guides' stroke is resolved in `layout`
    }

    /// The triangle's frame (rows that open; headings put their chevron at the right).
    var disclosureFrame: CGRect {
        isHeading ? .zero : CGRect(x: 8 + HomeSidebar.offset(depth: depth, compact: compactIndent), y: (bounds.height - 12) / 2,
                                   width: 12, height: 12)
    }

    override func layout() {
        super.layout()
        let h = bounds.height, w = bounds.width
        light.frame = CGRect(x: 6, y: 1, width: max(0, w - 12), height: h - 2)
        if isHeading {
            title.frame = CGRect(x: 12, y: (h - 15) / 2 + 2, width: max(0, w - 44), height: 15)
            triangle.frame = CGRect(x: w - 26, y: (h - 12) / 2, width: 12, height: 12)
            return
        }
        let x = 8 + HomeSidebar.offset(depth: depth, compact: compactIndent)
        layoutGuides()
        triangle.frame = CGRect(x: x, y: (h - 12) / 2, width: 12, height: 12)
        symbol.frame = CGRect(x: x + 14, y: (h - 16) / 2, width: 16, height: 16)
        let countWidth: CGFloat = count.stringValue.isEmpty ? 0 : 40
        count.frame = CGRect(x: w - 12 - countWidth, y: (h - 15) / 2, width: countWidth, height: 15)
        spinner.frame = CGRect(x: w - 28, y: (h - 16) / 2, width: 16, height: 16)
        title.frame = CGRect(x: x + 36, y: (h - 17) / 2, width: max(0, w - 12 - countWidth - (x + 36) - 4), height: 17)
    }

    /// A line under each level's triangle, from the first level down to the row's own.
    private func layoutGuides() {
        let path = CGMutablePath()
        if compactIndent, !isHeading {
            for level in 0..<depth {
                let x = (8 + HomeSidebar.offset(depth: level, compact: true) + 6).rounded() + 0.5
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: bounds.height))
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guides.frame = bounds
        guides.path = path
        guides.strokeColor = Chrome.resolve(Chrome.Palette.window.separator, in: self)
        CATransaction.commit()
    }

    var guideCount: Int { guides.path.map { p in var n = 0; p.applyWithBlock { if $0.pointee.type == .moveToPoint { n += 1 } }; return n } ?? 0 }
}
