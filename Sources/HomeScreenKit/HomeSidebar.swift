import AppKit
import HomeChrome
import HomeScreenModel

/// Home's sidebar: a native sidebar material with the app's sources, the places and the folder tree
/// under them, from a `SidebarTree`. A click on a row opens it in the browser, on its
/// triangle opens or closes it; ↑ ↓ ← → move the lit row as in Finder and Return opens it; Tab gives the keys back.
/// A row whose folders take long to list shows a small spinner where its count goes.
final class HomeSidebar: NSView {
    /// The column the sidebar takes by default.
    static let width: CGFloat = 240
    /// How narrow and how wide it can be kept; shown, it is at most a third of the window (`HomeView.widestSidebar`).
    public static let widthRange: ClosedRange<CGFloat> = 180...1600
    /// The widest it may show in any window, however narrow.
    static let widestAlways: CGFloat = 400
    static let inset: CGFloat = 12
    // 32 pt rows and headings, with a shared symbol column and a neutral selection plate.
    static let rowHeight: CGFloat = 32
    static let indent: CGFloat = 12
    /// Compact indent: the step past the first three levels.
    static let deepIndent: CGFloat = 8

    /// A row's indent at `depth`: compact, the levels past the third step less (and show guides), so deep trees fit.
    static func offset(depth: Int, compact: Bool) -> CGFloat {
        guard compact else { return CGFloat(depth) * indent }
        return CGFloat(min(depth, 3)) * indent + CGFloat(max(0, depth - 3)) * deepIndent
    }

    /// Compact indent with guides (`home-sidebar-indent=compact`), or the same step at every level.
    var compactIndent = true {
        didSet { if compactIndent != oldValue { rebuild() } }
    }
    private static let top: CGFloat = 4

    var onOpen: ((BrowserLocation) -> Void)?
    var onChooseRoot: ((SidebarTree.Root?) -> Void)?
    var onMoveFavorite: ((URL, URL?) -> Void)?
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
            presentation = tree.presentation
            let current = presentation.currentLine
            let currentID = current.flatMap(rowID)
            if currentID != followedID {
                // The browser moved: the light follows it, into view after the layout.
                followedID = currentID
                selectedID = currentID
                followsCurrent = true
                if current != nil { revealsSelected = true }
            }
            // The row the arrows lit stays lit when rows come or go around it (a folder opened, a reply); the current
            // one is kept in view only while the replies of its path come, not when the user opens a folder above it.
            let line = selectedID.flatMap(line(of:)) ?? current
            if line != nil, line != selected, selectedID == currentID, followsCurrent { revealsSelected = true }
            selected = line
            rebuild()
        }
    }
    /// The lit row by its id: lines move as folders open and replies fill in.
    private struct RowIdentity: Equatable {
        let id: String
        let root: SidebarTree.Root?
    }
    private var selectedID: RowIdentity?
    /// The current row's id as last followed.
    private var followedID: RowIdentity?
    /// The browser moved and the user has not opened or closed a folder since: the current row is kept in view as
    /// the rows above it fill in.
    private var followsCurrent = false

    private func rowID(at line: Int) -> RowIdentity? {
        guard lines.indices.contains(line), case .row(let row, _, _, _) = lines[line] else { return nil }
        return RowIdentity(id: row.id, root: presentation.roots[line])
    }

    private func line(of id: RowIdentity) -> Int? {
        return lines.indices.first { index in
            guard case .row(let row, _, _, _) = lines[index], row.id == id.id else { return false }
            return presentation.roots[index] == id.root
        }
    }
    private var revealsSelected = false

    private let scroll = NSScrollView()
    private let document = FlippedView()
    private var presentation: (lines: [SidebarTree.Line], roots: [SidebarTree.Root?], currentLine: Int?) = ([], [], nil)
    private var lines: [SidebarTree.Line] { presentation.lines }
    private var lineViews: [Int: SidebarLineView] = [:]
    private var laidOutRows: Range<Int> = 0..<0
    private static let favoriteDragType = NSPasteboard.PasteboardType("org.homescreenkit.favorite-folder")
    private var favoritePress: (event: NSEvent, folder: URL, line: Int)?
    private var draggedFavorite: URL?
    private let dropIndicator = NSBox()
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
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        addSubview(scroll)   // on the material the split view's sidebar item gives
        registerForDraggedTypes([Self.favoriteDragType])
        dropIndicator.boxType = .custom
        dropIndicator.borderType = .noBorder
        dropIndicator.fillColor = .controlAccentColor
        dropIndicator.isHidden = true
        document.addSubview(dropIndicator)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// An arrow over the sidebar, as over the browser: its lines take no hits, so nothing under the pointer would put
    /// back the arrow, and the divider's ↔ stayed over the list after the pointer crossed it.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if !trackingAreas.contains(where: { $0.owner === self }) {
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                           owner: self))
        }
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.arrow.set() }

    override func becomeFirstResponder() -> Bool {
        lineViews.values.forEach { $0.hasKeys = true }
        return true
    }

    override func resignFirstResponder() -> Bool {
        lineViews.values.forEach { $0.hasKeys = false }
        return true
    }

    // MARK: Lines

    private func rebuild() {
        watchLoading(lines)
        updateVisibleRows()
        needsLayout = true
    }

    private func frame(of line: Int) -> CGRect {
        CGRect(x: 0, y: Self.top + CGFloat(line) * Self.rowHeight,
               width: document.bounds.width, height: Self.rowHeight)
    }

    private func row(at point: CGPoint) -> SidebarLineView? {
        guard point.y >= Self.top, document.bounds.contains(point) else { return nil }
        let line = Int((point.y - Self.top) / Self.rowHeight)
        return lineViews[line]
    }

    @objc private func scrolled() {
        updateVisibleRows()
    }

    /// Keep one row outside each edge to cover partially visible rows during scrolling.
    private func updateVisibleRows() {
        let visible = scroll.documentVisibleRect
        let first = min(lines.count, max(0, Int(floor((visible.minY - Self.top) / Self.rowHeight)) - 1))
        let end = max(first, min(lines.count, Int(ceil((visible.maxY - Self.top) / Self.rowHeight)) + 1))
        let range = first..<end
        var reusable: [SidebarLineView] = []
        if laidOutRows != range {
            for line in laidOutRows where !range.contains(line) {
                if let view = lineViews.removeValue(forKey: line) {
                    view.prepareForReuse()
                    reusable.append(view)
                }
            }
            laidOutRows = range
        }
        let keys = window?.firstResponder === self
        for line in range {
            let view = lineViews[line] ?? reusable.popLast() ?? SidebarLineView()
            if view.superview == nil { document.addSubview(view, positioned: .below, relativeTo: dropIndicator) }
            lineViews[line] = view
            view.tag = line
            view.sidebar = self
            view.compactIndent = compactIndent
            view.hasKeys = keys
            let item = lines[line]
            let spinning: Bool
            if case .row(_, _, _, true) = item, let path = path(of: item) {
                spinning = slow.contains(path)
            } else {
                spinning = false
            }
            view.show(item, current: line == presentation.currentLine, lit: line == selected, spinning: spinning)
            let frame = frame(of: line)
            if view.frame.size != frame.size { view.needsLayout = true }
            if view.frame != frame { view.frame = frame }
        }
        for view in reusable { view.removeFromSuperview() }
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
                self.updateVisibleRows()
            }
        }
    }

    private func path(of line: SidebarTree.Line) -> String? {
        guard case .row(let row, _, _, _) = line, case .folder(let url) = row.location else { return nil }
        return url.quicklyStandardized.path
    }

    override func layout() {
        super.layout()
        scroll.frame = CGRect(x: 0, y: contentTopInset, width: bounds.width, height: max(0, bounds.height - contentTopInset))
        // The height first: a legacy scroller shows or hides for it and takes its width before the rows are laid out.
        let height = max(2 * Self.top + CGFloat(lines.count) * Self.rowHeight, fillHeight)
        if document.frame.height != height { document.frame.size.height = height }
        scroll.tile()
        let width = max(0, scroll.contentSize.width)
        if document.frame.width != width { document.frame.size.width = width }
        if revealsSelected, let selected, lines.indices.contains(selected) {
            revealsSelected = false
            document.scrollToVisible(frame(of: selected).insetBy(dx: 0, dy: -Self.rowHeight))
        }
        updateVisibleRows()
    }

    /// The height that fills the view and no more: the scroll view's less the inset AppKit gives it under the title
    /// bar. A list as tall as the whole view was taller than what shows by that inset, and a legacy scroller (a mouse
    /// plugged in) stayed with nothing to scroll.
    private var fillHeight: CGFloat {
        let insets = scroll.contentInsets
        return max(0, scroll.contentSize.height - insets.top - insets.bottom)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        favoritePress = nil
        let point = document.convert(event.locationInWindow, from: nil)
        guard let view = row(at: point) else { return }
        // As in Finder, a click leaves the keys with the browser (letters pick a name there); Tab brings them here.
        onClickKeys?()
        if view.hitsDisclosure(at: view.convert(point, from: document)) {
            clickDisclosure(line: view.tag)
        } else if let folder = favorite(at: view.tag) {
            favoritePress = (event, folder, view.tag)
        } else {
            click(line: view.tag)
        }
    }

    private var favoriteFolders: [URL] {
        tree.sections.first { $0.id == HomeSidebarSection.favoritesID }?.rows.compactMap {
            if case .folder(let folder) = $0.location { return folder }
            return nil
        } ?? []
    }

    private func favorite(at line: Int) -> URL? {
        guard lines.indices.contains(line), case .row(let row, 0, _, _) = lines[line],
              presentation.roots[line]?.sectionID == HomeSidebarSection.favoritesID,
              case .folder(let folder) = row.location else { return nil }
        return folder
    }

    override func mouseDragged(with event: NSEvent) {
        guard let press = favoritePress, favoriteFolders.count > 1 else { return }
        let from = press.event.locationInWindow, to = event.locationInWindow
        guard hypot(from.x - to.x, from.y - to.y) >= 4, let row = lineViews[press.line],
              favorite(at: press.line) == press.folder else { return }
        favoritePress = nil
        draggedFavorite = press.folder
        let data = NSPasteboardItem()
        data.setString("favorite", forType: Self.favoriteDragType)
        let item = NSDraggingItem(pasteboardWriter: data)
        let image = NSImage(size: row.bounds.size, flipped: true) { rect in
            NSColor.windowBackgroundColor.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            let title = press.folder.path == "/" ? "/" : press.folder.lastPathComponent
            (title as NSString).draw(at: CGPoint(x: 12, y: 8), withAttributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor,
            ])
            return true
        }
        item.setDraggingFrame(convert(row.frame, from: document), contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    private func favoriteDrop(at point: CGPoint) -> (before: URL?, y: CGFloat)? {
        guard let heading = lines.firstIndex(where: {
            if case .heading(let id, _, false) = $0 { return id == HomeSidebarSection.favoritesID }
            return false
        }), lines.indices.contains(heading) else { return nil }
        let end = lines[(heading + 1)...].firstIndex { if case .heading = $0 { return true }; return false } ?? lines.count
        guard end > heading + 1,
              point.y >= frame(of: heading).minY,
              point.y <= frame(of: end - 1).maxY else { return nil }
        for line in (heading + 1)..<end {
            guard case .row(let row, 0, _, _) = lines[line], case .folder(let folder) = row.location else { continue }
            let frame = frame(of: line)
            if point.y < frame.midY { return (folder, frame.minY) }
        }
        return (nil, frame(of: end - 1).maxY)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingSource as? HomeSidebar === self, draggedFavorite != nil,
              let target = favoriteDrop(at: document.convert(sender.draggingLocation, from: nil)) else {
            dropIndicator.isHidden = true
            return []
        }
        dropIndicator.frame = CGRect(x: Self.inset, y: target.y - 1,
                                     width: max(0, document.bounds.width - 2 * Self.inset), height: 2)
        if dropIndicator.isHidden {
            document.addSubview(dropIndicator, positioned: .above, relativeTo: nil)
            dropIndicator.isHidden = false
        }
        return .move
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) { dropIndicator.isHidden = true }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { dropIndicator.isHidden = true }
        guard sender.draggingSource as? HomeSidebar === self, let folder = draggedFavorite,
              let target = favoriteDrop(at: document.convert(sender.draggingLocation, from: nil)) else { return false }
        if folder != target.before { onMoveFavorite?(folder, target.before) }
        return true
    }

    override func mouseUp(with event: NSEvent) {
        guard let press = favoritePress else { return }
        favoritePress = nil
        let point = document.convert(event.locationInWindow, from: nil)
        guard row(at: point)?.tag == press.line,
              favorite(at: press.line) == press.folder else { return }
        click(line: press.line)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = document.convert(event.locationInWindow, from: nil)
        guard let view = row(at: point) else { return nil }
        return menu(forLine: view.tag)
    }

    /// The context menu of a row (the app's items for it); nil for a heading or a row without items.
    func menu(forLine line: Int) -> NSMenu? {
        guard lines.indices.contains(line), case .row(let row, _, _, _) = lines[line] else { return nil }
        let menu = NSMenu()
        for item in menuItems?(row) ?? [] {
            HomeMenuAction.add(item.title, to: menu) { [weak self] in self?.onMenu?(item.id, row) }
        }
        let folders = favoriteFolders
        if let folder = favorite(at: line), let index = folders.firstIndex(of: folder) {
            if index > 0 {
                HomeMenuAction.add("Move Up", to: menu) { [weak self] in self?.onMoveFavorite?(folder, folders[index - 1]) }
            }
            if index + 1 < folders.count {
                let next = folders.indices.contains(index + 2) ? folders[index + 2] : nil
                HomeMenuAction.add("Move Down", to: menu) { [weak self] in self?.onMoveFavorite?(folder, next) }
            }
        }
        return menu.items.isEmpty ? nil : menu
    }

    /// A click on a line: a heading folds its section, a row opens.
    func click(line: Int) {
        guard lines.indices.contains(line) else { return }
        switch lines[line] {
        case .heading(let section, _, _):
            followsCurrent = false
            onToggleSection?(section)
        case .row(let row, _, _, _):
            let root = presentation.roots[line]
            selected = line
            selectedID = rowID(at: line)
            rebuild()
            guard !row.isDimmed || root?.sectionID != HomeSidebarSection.favoritesID else { return }
            onChooseRoot?(root)
            onOpen?(row.location)
        }
    }

    func clickDisclosure(line: Int) {
        guard lines.indices.contains(line), case .row(let row, _, let expanded, _) = lines[line], row.expandable,
              case .folder(let url) = row.location else { return }
        followsCurrent = false
        if expanded { onCollapse?(url) } else { onExpand?(url) }
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        if !handleKey(event) { super.keyDown(with: event) }
    }

    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if flags == .control, event.keyCode == 36, let line = selected ?? presentation.currentLine {
            return showMenu(at: line)
        }
        guard flags.isEmpty else { return false }
        if event.keyCode == 48 {
            onEndKeys?()
            return true
        }
        let keys: [UInt16: SidebarTree.Key] = [126: .up, 125: .down, 123: .left, 124: .right, 36: .open, 76: .open]
        guard let key = keys[event.keyCode] else { return false }
        guard let from = selected ?? presentation.currentLine else {
            // Nothing lit yet: the first row.
            if let first = lines.firstIndex(where: { if case .row = $0 { true } else { false } }) { light(first) }
            return true
        }
        switch tree.move(key, from: from) {
        case .select(let i): light(i)
        case .expand(let url):
            followsCurrent = false
            onExpand?(url)
        case .collapse(let url):
            followsCurrent = false
            onCollapse?(url)
        case .open: click(line: from)
        case .none: break
        }
        return true
    }

    fileprivate func showMenu(at line: Int) -> Bool {
        guard let menu = menu(forLine: line) else { return false }
        document.scrollToVisible(frame(of: line))
        let frame = frame(of: line)
        menu.popUp(positioning: nil, at: CGPoint(x: Self.inset, y: frame.midY), in: document)
        return true
    }

    private func light(_ line: Int) {
        selected = line
        selectedID = rowID(at: line)
        rebuild()
        document.scrollToVisible(frame(of: line))
    }

    // MARK: For tests

    var titles: [String] {
        lines.map { line in
            switch line {
            case .heading(_, let title, _): title
            case .row(let row, _, _, _): row.title
            }
        }
    }
    private var visibleRows: [SidebarLineView] { laidOutRows.compactMap { lineViews[$0] } }
    var visibleLineRect: CGRect { scroll.documentVisibleRect }
    var lineFrames: [CGRect] { lines.indices.map(frame(of:)) }
    var titleFrames: [CGRect] { visibleRows.map(\.title.frame) }
    var guideCounts: [Int] { visibleRows.map(\.guideCount) }
    var scrollWidth: CGFloat { scroll.frame.width }
    var rowTitleWidths: [CGFloat] { visibleRows.filter { !$0.isHeading }.map(\.title.frame.width) }
    var countTexts: [String] { visibleRows.map(\.count.stringValue) }
    var lineRedraws: Int { visibleRows.reduce(0) { $0 + $1.redraws } }
    var titleBreakModes: [NSLineBreakMode] { visibleRows.map(\.title.lineBreakMode) }
    var highlightedLine: Int? { selected }
    func isSpinning(line: Int) -> Bool { lineViews[line]?.spinner.isHidden == false }
}

extension HomeSidebar: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        draggedFavorite = nil
        dropIndicator.isHidden = true
    }
}

/// Keep a menu's action alive and tied to the item chosen when the menu was opened.
@MainActor final class HomeMenuAction: NSObject {
    private let action: () -> Void
    private init(_ action: @escaping () -> Void) { self.action = action }
    @objc func chose(_ sender: NSMenuItem) { action() }

    static func add(_ title: String, to menu: NSMenu, action: @escaping () -> Void) {
        let item = menu.addItem(withTitle: title, action: #selector(chose(_:)), keyEquivalent: "")
        let target = Self(action)
        item.target = target
        item.representedObject = target  // NSMenuItem holds its target weakly.
    }
}

/// A section heading or a folder/source row. The current location and the keyboard cursor can occupy different rows.
private final class SidebarLineView: NSView {
    let title = NSTextField(labelWithString: "")
    let count = NSTextField(labelWithString: "")
    let spinner = NSProgressIndicator()
    private let symbol = NSImageView()
    private let triangle = NSImageView()
    private let light = NSView()
    private(set) var isHeading = false
    /// How many times `show` changed what the line draws (for tests).
    private(set) var redraws = 0
    /// What the line draws now: the tree set again leaves an unchanged line as it is (a new symbol image is drawn
    /// again at the next commit, a title set again is laid out again).
    private var shown: (line: SidebarTree.Line, current: Bool, lit: Bool, spinning: Bool)?
    weak var sidebar: HomeSidebar?
    private var depth = 0
    private var locationHint: String?
    var compactIndent = true {
        didSet { if compactIndent != oldValue { needsLayout = true } }
    }
    /// Thin lines down the levels above the row (compact indent).
    private let guides = CAShapeLayer()
    private var hovering = false
    var hasKeys = false { didSet { if hasKeys != oldValue, shown?.lit == true { paint() } } }
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
        light.layer?.cornerCurve = .continuous
        title.lineBreakMode = .byTruncatingTail
        count.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        count.textColor = .secondaryLabelColor
        count.alignment = .right
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.isHidden = true
        triangle.contentTintColor = .secondaryLabelColor
        symbol.contentTintColor = .secondaryLabelColor
        for view in [light, triangle, symbol, title, count, spinner] { addSubview(view) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    /// Clicks go to the sidebar, which knows the lines.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        paint()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        paint()
    }

    override func isAccessibilityElement() -> Bool { shown != nil }
    override func accessibilityRole() -> NSAccessibility.Role? { isHeading ? .disclosureTriangle : .button }
    override func accessibilityLabel() -> String? { title.stringValue }
    override func accessibilityChildren() -> [Any]? { [] }
    override func accessibilityHelp() -> String? { locationHint }
    override func isAccessibilitySelected() -> Bool { shown?.current == true }
    override func accessibilityDisclosureLevel() -> Int { depth }

    override func isAccessibilityExpanded() -> Bool {
        switch shown?.line {
        case .heading(_, _, let folded): !folded
        case .row(_, _, let expanded, _): expanded
        case nil: false
        }
    }

    override func setAccessibilityExpanded(_ expanded: Bool) {
        guard expanded != isAccessibilityExpanded(), let sidebar else { return }
        if isHeading { sidebar.click(line: tag) }
        else { sidebar.clickDisclosure(line: tag) }
    }

    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        if selector == #selector(isAccessibilityExpanded) || selector == #selector(setAccessibilityExpanded(_:)) {
            return isHeading || isExpandableFolder
        }
        return super.isAccessibilitySelectorAllowed(selector)
    }

    override func accessibilityPerformPress() -> Bool {
        guard let sidebar, shown != nil else { return false }
        sidebar.click(line: tag)
        return true
    }

    override func accessibilityPerformShowMenu() -> Bool {
        sidebar?.showMenu(at: tag) ?? false
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        shown = nil
        hovering = false
        showSpinner(false)
    }

    func show(_ line: SidebarTree.Line, current: Bool, lit: Bool, spinning: Bool) {
        let previous = shown
        shown = (line, current, lit, spinning)
        if let previous, previous.line == line, previous.spinning == spinning {
            if previous.current != current || previous.lit != lit { paint() }
            return
        }
        redraws += 1
        switch line {
        case .heading(_, let text, let folded):
            isHeading = true
            depth = 0
            title.stringValue = text
            locationHint = nil
            toolTip = nil
            count.stringValue = ""
            symbol.image = nil
            triangle.image = Self.triangle(folded ? "chevron.right" : "chevron.down")
            showSpinner(false)
        case .row(let row, let d, let expanded, _):
            isHeading = false
            depth = d
            title.stringValue = row.title
            locationHint = row.locationHint
            count.font = row.locationHint == nil
                ? .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                : .systemFont(ofSize: 11)
            count.lineBreakMode = .byTruncatingTail
            count.stringValue = row.locationHint ?? row.count.map(BrowserSummary.number) ?? ""
            symbol.image = Self.symbol(row.symbol)
            triangle.image = row.expandable ? Self.triangle(expanded ? "chevron.down" : "chevron.right") : nil
            showSpinner(spinning)
        }
        paint()
        needsLayout = true
    }

    /// A row's symbol (Lucide keeps one image per name and size for every line).
    private static func symbol(_ name: String) -> NSImage? { Icons.symbol(name, pointSize: 16) }

    /// The disclosure triangle's chevron.
    private static func triangle(_ name: String) -> NSImage? { Icons.symbol(name, pointSize: 10, weight: .semibold) }

    private func showSpinner(_ on: Bool) {
        spinner.isHidden = !on
        count.isHidden = on
        if on { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    private func paint() {
        let current = shown?.current == true
        let keys = shown?.lit == true && hasKeys
        let accent = Chrome.Palette.window.accent
        let fill: NSColor = if current { accent.withAlphaComponent(hovering ? 0.18 : 0.13) }
                            else if keys || hovering { NSColor.labelColor.withAlphaComponent(0.06) }
                            else { .clear }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        light.isHidden = !current && !keys && !hovering
        light.layer?.backgroundColor = Chrome.resolve(fill, in: self)
        light.layer?.borderWidth = keys ? 1.5 : 0
        light.layer?.borderColor = keys ? Chrome.resolve(.keyboardFocusIndicatorColor, in: self) : nil
        CATransaction.commit()

        if isHeading {
            title.font = .systemFont(ofSize: 11, weight: .semibold)
            title.textColor = hovering ? .labelColor : .secondaryLabelColor
            triangle.contentTintColor = hovering ? .secondaryLabelColor : .tertiaryLabelColor
            return
        }
        guard case .row(let row, _, _, _) = shown?.line else { return }
        let dimmed = row.isDimmed
        let font = NSFont.systemFont(ofSize: 13, weight: current ? .semibold : .regular)
        let titleColor: NSColor = dimmed ? .secondaryLabelColor : .labelColor
        title.font = font
        title.textColor = titleColor
        if row.title.contains("/") || row.title.contains("⁄") {
            // Keep the original name, with space around a slash so the glyph clears its neighbors.
            let text = NSMutableAttributedString(string: row.title, attributes: [.font: font, .foregroundColor: titleColor])
            let name = row.title as NSString
            for (index, unit) in row.title.utf16.enumerated() where unit == 0x2F || unit == 0x2044 {
                let spacing = unit == 0x2044 ? 3 : 1
                if index > 0 {
                    text.addAttribute(.kern, value: spacing, range: name.rangeOfComposedCharacterSequence(at: index - 1))
                }
                text.addAttribute(.kern, value: spacing, range: NSRange(location: index, length: 1))
            }
            title.attributedStringValue = text
        }
        triangle.contentTintColor = current || hovering ? .secondaryLabelColor : .tertiaryLabelColor
        symbol.contentTintColor = dimmed ? .tertiaryLabelColor : current ? accent : .secondaryLabelColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
        needsLayout = true   // the guides' stroke is resolved in `layout`
    }

    private var isExpandableFolder: Bool {
        guard case .row(let row, _, _, _) = shown?.line, case .folder = row.location else { return false }
        return row.expandable
    }

    func hitsDisclosure(at point: CGPoint) -> Bool {
        isExpandableFolder && triangle.frame.insetBy(dx: -4, dy: -8).contains(point)
    }

    private static let lead: CGFloat = 12
    private static let fieldInset: CGFloat = 2
    private static let titleOffset: CGFloat = 38
    private static let minimumTitleWidth: CGFloat = 64
    // Reserve the spinner even when idle, so a deep row never moves sideways when it starts loading.
    private static let spinnerWidth: CGFloat = 16
    private static let accessoryGap: CGFloat = 6

    private var trailing: CGFloat { bounds.width - HomeSidebar.inset - 6 }

    private var displayedDepth: Int {
        let room = max(0, trailing - Self.lead - Self.titleOffset - Self.minimumTitleWidth
                          - Self.spinnerWidth - Self.accessoryGap)
        let compactStart = 3 * HomeSidebar.indent
        if compactIndent, room >= compactStart {
            return min(depth, 3 + Int((room - compactStart) / HomeSidebar.deepIndent))
        }
        return min(depth, Int(room / HomeSidebar.indent))
    }

    override func layout() {
        super.layout()
        let h = bounds.height, w = bounds.width
        light.frame = CGRect(x: HomeSidebar.inset - 2, y: 3, width: max(0, w - 2 * (HomeSidebar.inset - 2)), height: max(0, h - 6))
        if isHeading {
            guides.path = nil
            // Photos sets a heading low in its line, nearer the rows it heads.
            title.frame = CGRect(x: 16 - Self.fieldInset, y: h - 16 - 4, width: max(0, w - 48), height: 16)
            triangle.frame = CGRect(x: w - 30, y: h - 12 - 5, width: 12, height: 12)
            return
        }
        let level = displayedDepth
        let x = Self.lead + HomeSidebar.offset(depth: level, compact: compactIndent)
        layoutGuides(upTo: level)
        triangle.frame = CGRect(x: x, y: (h - 12) / 2, width: 12, height: 12)
        symbol.frame = CGRect(x: x + 16, y: (h - 20) / 2, width: 20, height: 20)
        let textX = x + Self.titleOffset
        let available = max(0, trailing - textX)
        let countRoom = max(0, min(available * 0.36, available - Self.minimumTitleWidth - Self.accessoryGap))
        let countWidth: CGFloat
        if count.stringValue.isEmpty || countRoom < Self.spinnerWidth {
            countWidth = 0
        } else {
            let ideal = ceil(count.intrinsicContentSize.width) + 2 * Self.fieldInset
            countWidth = locationHint == nil && ideal > countRoom ? 0 : min(ideal, countRoom)
        }
        count.frame = CGRect(x: trailing - countWidth, y: (h - 15) / 2, width: countWidth, height: 15)
        spinner.frame = CGRect(x: trailing - Self.spinnerWidth, y: (h - Self.spinnerWidth) / 2,
                               width: Self.spinnerWidth, height: Self.spinnerWidth)
        let accessory = max(countWidth, Self.spinnerWidth)
        title.frame = CGRect(x: textX, y: (h - 17) / 2,
                             width: max(0, available - accessory - Self.accessoryGap), height: 17)
        let tip = locationHint.map { "\(title.stringValue) — \($0)" }
            ?? (title.intrinsicContentSize.width > title.frame.width ? title.stringValue : nil)
        if toolTip != tip { toolTip = tip }
    }

    /// A line under each level's triangle, from the first level down to the row's own.
    private func layoutGuides(upTo depth: Int) {
        let path = CGMutablePath()
        if compactIndent, !isHeading {
            for level in 0..<depth {
                let x = (Self.lead + HomeSidebar.offset(depth: level, compact: true) + 6).rounded() + 0.5
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
