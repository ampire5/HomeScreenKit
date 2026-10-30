import AppKit
import HomeChrome
import HomeScreenModel

/// Home as one view, as in Photos: the sidebar of sources, places and the folder tree on the
/// left, the browser beside it. The sidebar follows the browser: the path to the folder on screen opens at once, and
/// the other folders along it are listed only after the folder's own listing, one at a time, so a slow share serves
/// what was asked first. ⌃⌘S (the app's menu) and the toolbar's button hide it; Tab moves the keys between the two.
public final class HomeView: NSView {
    public let browser: HomeBrowserView
    let sidebarView = HomeSidebar()

    /// The toolbar's sidebar button: the app flips `isSidebarVisible` and keeps it.
    public var onSidebarToggle: (() -> Void)?
    /// The toolbar's house: the app shows its start page.
    public var onHome: (() -> Void)?
    /// A file dropped on Home. Nil leaves drops to what is under it (Home registers only while it has a handler).
    public var onDrop: ((URL) -> Void)? {
        didSet {
            if onDrop == nil { unregisterDraggedTypes() } else { registerForDraggedTypes([.fileURL]) }
        }
    }

    /// What Home is drawn on (the app's background).
    /// Unset, it is the window's background in the view's appearance and follows it; once the owner sets it, it stays.
    public var background: CGColor {
        get { customBackground ?? Chrome.resolve(Chrome.Palette.window.background, in: self) }
        set {
            customBackground = newValue
            paintBackground()
        }
    }
    /// Set by the owner (`isBackgroundCustom`): an appearance change does not replace it.
    private var customBackground: CGColor?
    var isBackgroundCustom: Bool { customBackground != nil }

    private func paintBackground() {
        layer?.backgroundColor = background
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paintBackground()
    }

    /// The sidebar shows or is collapsed: the split view item slides it, as the system's toggle does.
    public var isSidebarVisible = true {
        didSet {
            guard isSidebarVisible != oldValue else { return }
            if !isSidebarVisible, window?.firstResponder === sidebarView { window?.makeFirstResponder(browser) }
            guard !isParked, sidebarItem.isCollapsed == isSidebarVisible else { return }
            if window?.isVisible == true, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                sidebarItem.animator().isCollapsed = !isSidebarVisible
            } else {
                sidebarItem.isCollapsed = !isSidebarVisible
            }
        }
    }

    /// Home hidden in its window while the app shows something else there (a viewer): it stays in the window as it was
    /// built, so showing it again moves no view between windows and lays nothing out from scratch (a view taken out
    /// and put back costs its whole tree: `_setWindow`, the layout engine, vibrancy, its images prepared again). Its
    /// sidebar item is collapsed meanwhile, without animation: an open one makes the system keep a sidebar's room in
    /// the window's other toolbar. Unparked, the sidebar comes back as `isSidebarVisible` says, at its width.
    public var isParked = false {
        didSet {
            guard isParked != oldValue else { return }
            if isParked {
                sidebarItem.isCollapsed = true
                inspectorItem?.isCollapsed = true
            } else {
                materializeInspectorIfNeeded()
                inspectorItem?.isCollapsed = !isInspectorVisible
                wantsInspectorWidth = true
                sidebarItem.isCollapsed = !isSidebarVisible
                wantsSidebarWidth = true
                needsLayout = true
            }
        }
    }

    /// The sidebar's kept width, within `HomeSidebar.widthRange`: the app sets it, the user drags the divider. Collapsed
    /// and shown again, the sidebar comes back at this width; shown, at most `widestSidebar`.
    public var sidebarWidth = HomeSidebar.width {
        didSet {
            sidebarWidth = min(max(sidebarWidth, HomeSidebar.widthRange.lowerBound), HomeSidebar.widthRange.upperBound)
            guard sidebarWidth != oldValue, !isAdoptingDrag else { return }
            wantsSidebarWidth = true
            needsLayout = true
        }
    }

    /// The widest the sidebar shows in this window: a third of it, never under `HomeSidebar.widestAlways`.
    var widestSidebar: CGFloat { max(HomeSidebar.widestAlways, (bounds.width / 3).rounded(.down)) }

    /// The width asked for is put on the divider at the next layout, when the split view has a size.
    private var wantsSidebarWidth = true {
        didSet { if wantsSidebarWidth { triedAtWidth = nil } }
    }
    /// The width follows a drag of the divider: it is not put back on it.
    private var isAdoptingDrag = false
    private var widthReport: Task<Void, Never>?
    /// Whether the divider is moving under the user's drag now: a left-button drag in this window (the split view's
    /// tracking loop makes each of its events the current one). The split view moves the divider itself too — the
    /// window not at its size yet, narrowed, the sidebar's minimum — and none of that is a width to keep.
    /// Only a drag at the divider itself counts: a release elsewhere in the window (the green button, a title-bar
    /// double click: the window narrows and the split moves the divider with it) once passed for one, and that
    /// passing width was kept and came back smaller at the next launch (the owner's report of 2026-10-27).
    lazy var isUserDrag: () -> Bool = { [weak self] in
        guard let self, let event = NSApp.currentEvent, event.window === self.window,
              event.type == .leftMouseDragged || event.type == .leftMouseUp else { return false }
        let split = self.splitController.splitView
        let x = split.convert(event.locationInWindow, from: nil).x
        return abs(x - self.sidebarPaneWidth) <= 12
    }
    /// The split view's width when the kept width was last put on the divider without holding (the split too narrow
    /// for it): it is put again once the split has another width, not at every layout.
    private var triedAtWidth: CGFloat?

    private func applySidebarWidth() {
        let split = splitController.splitView
        guard !sidebarItem.isCollapsed, split.bounds.width > 0 else { return }
        sidebarItem.maximumThickness = widestSidebar
        guard wantsSidebarWidth, triedAtWidth != split.bounds.width else { return }
        let target = min(sidebarWidth, widestSidebar)
        split.setPosition(target, ofDividerAt: 0)
        // Put on a split not yet at its size (Home shown in a window still being laid out), the divider stops at the
        // sidebar's minimum: tried again when the split's width changes.
        wantsSidebarWidth = abs(sidebarPaneWidth - target) >= 1
        triedAtWidth = wantsSidebarWidth ? split.bounds.width : nil
    }

    /// The divider moved: when it is the user's drag (`isUserDrag`, the width differs from the kept one) the new width
    /// is kept, and told to the app once the pointer has been still for a moment.
    /// The sidebar's pane, up to the divider: the width the divider is set to and a drag leaves. Not the sidebar view's:
    /// on macOS 26 its glass floats 8 pt inside the pane (228 in a 236 pane, CI 2026-10-26), on macOS 27 it fills it.
    var sidebarPaneWidth: CGFloat {
        splitController.splitView.arrangedSubviews.first?.frame.width ?? sidebarView.frame.width
    }

    private func splitDidResize() {
        reportInspectorWidth()
        guard !sidebarItem.isCollapsed else { return }
        guard isUserDrag() else {
            // The split took its size (or another): a width that did not hold yet is put on the divider again.
            if wantsSidebarWidth { needsLayout = true }
            return
        }
        let width = sidebarPaneWidth.rounded()
        guard width > 0, abs(width - min(sidebarWidth, widestSidebar)) >= 1, window?.inLiveResize != true else { return }
        isAdoptingDrag = true
        sidebarWidth = width
        isAdoptingDrag = false
        widthReport?.cancel()
        widthReport = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            self.onSidebarWidthChange?(self.sidebarWidth)
        }
    }

    public override func layout() {
        super.layout()
        sidebarView.contentTopInset = max(browser.topInset, sidebarView.safeAreaInsets.top)
        applySidebarWidth()
        applyInspectorWidth()
    }

    /// A folder holding one folder shows with it on one row (`home-sidebar-compact`).
    public var sidebarCompactChains: Bool {
        get { tree.options.compactChains }
        set { setTreeOptions { $0.compactChains = newValue } }
    }

    /// The current folder this deep under its place or deeper starts the tree again further down (0: never; else 3
    /// or more, `home-sidebar-reroot`).
    public var sidebarRerootDepth: Int {
        get { tree.options.rerootDepth }
        set { setTreeOptions { $0.rerootDepth = newValue } }
    }

    /// A folder's subfolders before its archives in the tree (`home-sidebar-folders-first`).
    public var sidebarFoldersFirst: Bool {
        get { tree.options.foldersFirst }
        set { setTreeOptions { $0.foldersFirst = newValue } }
    }

    /// Levels past the third step less, with guides (`home-sidebar-indent=compact`).
    public var sidebarCompactIndent: Bool {
        get { sidebarView.compactIndent }
        set { sidebarView.compactIndent = newValue }
    }

    private func setTreeOptions(_ change: (inout SidebarTree.Options) -> Void) {
        var options = tree.options
        change(&options)
        guard options != tree.options else { return }
        tree.options = options
        showTree()
    }

    /// The user moved the divider: the width to keep (the app writes it back and sets it next time).
    public var onSidebarWidthChange: ((CGFloat) -> Void)?

    private var inspectorItem: NSSplitViewItem?
    private var inspectorFactory: (() -> NSViewController)?
    private var inspectorCollapseObservation: NSKeyValueObservation?
    private var wantsInspectorWidth = false
    private var inspectorWidth: CGFloat = 320
    /// Docked inspector width changed by a divider drag, for the owner to persist.
    public var onInspectorWidthChange: ((CGFloat) -> Void)?
    /// The owner starts/stops its work when the inspector is shown or hidden.
    public var onInspectorVisibilityChange: ((Bool) -> Void)?
    public var isInspectorVisible = false {
        didSet {
            guard isInspectorVisible != oldValue else { return }
            materializeInspectorIfNeeded()
            browser.toolbar.showInspector(visible: isInspectorVisible)
            guard let item = inspectorItem else {
                onInspectorVisibilityChange?(isInspectorVisible)
                return
            }
            if !isInspectorVisible, let responder = window?.firstResponder as? NSView,
               responder.isDescendant(of: item.viewController.view) { window?.makeFirstResponder(browser) }
            // One layout transaction, without a repeating animation or hidden tree reconstruction.
            item.isCollapsed = isParked || !isInspectorVisible
            wantsInspectorWidth = isInspectorVisible
            browser.toolbar.showInspector(visible: isInspectorVisible)
            needsLayout = true
            onInspectorVisibilityChange?(isInspectorVisible)
        }
    }

    /// Register a one-shot factory and expose the toolbar toggle without creating a controller, view or split item.
    /// A parked Home keeps only the visibility intent; first unpark materializes it if still wanted.
    public func configureInspector(width: CGFloat = 320, make: @escaping () -> NSViewController) {
        guard inspectorItem == nil, inspectorFactory == nil else { return }
        inspectorWidth = min(400, max(280, width))
        inspectorFactory = make
        browser.toolbar.onInspector = { [weak self] in self?.isInspectorVisible.toggle() }
        browser.toolbar.showInspector(visible: isInspectorVisible)
        materializeInspectorIfNeeded()
    }

    private func materializeInspectorIfNeeded() {
        guard isInspectorVisible, !isParked, inspectorItem == nil, let factory = inspectorFactory else { return }
        inspectorFactory = nil
        installInspector(factory(), width: inspectorWidth)
    }

    /// Immediate installation for clients that already own a controller; closing it keeps its view and state alive.
    public func installInspector(_ controller: NSViewController, width: CGFloat = 320) {
        guard inspectorItem == nil else { return }
        inspectorWidth = min(400, max(280, width))
        let item = NSSplitViewItem(inspectorWithViewController: controller)
        item.minimumThickness = 280
        item.maximumThickness = 400
        item.canCollapse = true
        item.isCollapsed = true
        inspectorItem = item
        splitController.addSplitViewItem(item)
        inspectorCollapseObservation = item.observe(\.isCollapsed, options: [.new]) { [weak self] item, _ in
            MainActor.assumeIsolated {
                guard let self, !self.isParked else { return }
                self.isInspectorVisible = !item.isCollapsed
            }
        }
        browser.toolbar.onInspector = { [weak self] in self?.isInspectorVisible.toggle() }
        if isInspectorVisible, !isParked {
            item.isCollapsed = false
            wantsInspectorWidth = true
            needsLayout = true
        }
    }

    private func applyInspectorWidth() {
        guard wantsInspectorWidth, let item = inspectorItem, !item.isCollapsed else { return }
        let split = splitController.splitView
        guard split.bounds.width > 0 else { return }
        wantsInspectorWidth = false
        split.setPosition(max(0, split.bounds.width - inspectorWidth - split.dividerThickness),
                          ofDividerAt: split.arrangedSubviews.count - 2)
    }

    private func reportInspectorWidth() {
        guard let item = inspectorItem, !item.isCollapsed, !wantsInspectorWidth,
              let event = NSApp.currentEvent, event.window === window,
              event.type == .leftMouseUp || event.type == .leftMouseDragged else { return }
        let split = splitController.splitView
        let width = item.viewController.view.frame.width.rounded()
        let edge = split.bounds.width - width
        guard abs(split.convert(event.locationInWindow, from: nil).x - edge) <= 12,
              abs(width - inspectorWidth) >= 1 else { return }
        inspectorWidth = width
        onInspectorWidthChange?(width)
    }

    /// The system's split: the sidebar item (with its material, divider, collapsing and the toolbar's tracking
    /// separator) and the browser's.
    let splitController = HomeSplitViewController()
    private let sidebarItem: NSSplitViewItem
    private var splitObservers: [any NSObjectProtocol] = []
    private var collapseObservation: NSKeyValueObservation?

    private weak var source: HomeSource?
    private var tree = SidebarTree(sections: [])
    /// Bumped on every move: the path's folders still to come for an older one are not asked. New sections keep them
    /// (they keep what is open under the roots still there).
    private var generation = 0
    /// The path's folders still to list for the location on screen, once its listing is complete.
    private var pending: (location: BrowserLocation, folders: [URL])?
    private var followTask: Task<Void, Never>?
    /// The path's folders are being listed (`followTask` has not finished).
    private var isFollowing = false

    /// Extends the browser's edge under native window chrome without covering
    /// the interactive content. Older systems retain the ordinary browser view.
    public init(source: HomeSource, extendsBrowserBackground: Bool = false) {
        self.source = source
        browser = HomeBrowserView(source: source)
        let sidebarController = NSViewController()
        sidebarController.view = sidebarView
        let browserController = NSViewController()
        if extendsBrowserBackground, #available(macOS 26.0, *) {
            let background = NSBackgroundExtensionView()
            background.contentView = browser
            browserController.view = background
        } else {
            browserController.view = browser
        }
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        super.init(frame: .zero)
        wantsLayer = true
        paintBackground()
        sidebarItem.minimumThickness = HomeSidebar.widthRange.lowerBound
        sidebarItem.maximumThickness = HomeSidebar.widthRange.upperBound
        splitController.addSplitViewItem(sidebarItem)
        splitController.addSplitViewItem(NSSplitViewItem(viewController: browserController))
        let split = splitController.view
        split.translatesAutoresizingMaskIntoConstraints = false
        addSubview(split)
        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: leadingAnchor), split.trailingAnchor.constraint(equalTo: trailingAnchor),
            split.topAnchor.constraint(equalTo: topAnchor), split.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        splitController.onToggleSidebar = { [weak self] in self?.onSidebarToggle?() }
        splitObservers.append(NotificationCenter.default.addObserver(
            forName: NSSplitView.didResizeSubviewsNotification, object: splitController.splitView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.splitDidResize() }
        })
        // The divider dragged past its minimum collapses the sidebar: the app is told as for the toggle's click.
        collapseObservation = sidebarItem.observe(\.isCollapsed, options: [.new]) { [weak self] item, _ in
            MainActor.assumeIsolated {
                guard let self, !self.isParked, item.isCollapsed == self.isSidebarVisible else { return }
                self.onSidebarToggle?()
            }
        }
        browser.toolbar.onHome = { [weak self] in self?.onHome?() }
        browser.onMoved = { [weak self] location in self?.moved(to: location) }
        browser.onListingComplete = { [weak self] location, entries in self?.listingComplete(location, entries: entries) }
        sidebarView.onOpen = { [weak self] location in self?.browser.show(location, selecting: nil) }
        sidebarView.onExpand = { [weak self] folder in self?.expand(folder) }
        sidebarView.onCollapse = { [weak self] folder in
            self?.tree.collapse(folder)
            self?.showTree()
        }
        sidebarView.onToggleSection = { [weak self] id in
            self?.tree.toggleSection(id)
            self?.showTree()
        }
        sidebarView.menuItems = { [weak self] row in self?.source?.sidebarMenu(for: row) ?? [] }
        sidebarView.onMenu = { [weak self] item, row in self?.source?.performSidebar(item, on: row) }
        sidebarView.onEndKeys = { [weak self] in self?.browser.takeFocus() }
        sidebarView.onClickKeys = { [weak self] in self?.browser.takeFocus() }
        reloadSidebar()
    }

    @objc func toggleSidebar(_ sender: Any?) {
        onSidebarToggle?()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The sidebar's sections again (a volume came or went, a pin): what was opened stays.
    public func reloadSidebar() {
        Task { @MainActor [weak self] in
            guard let sections = await self?.source?.sidebar(), let self else { return }
            self.tree.setSections(sections)
            let location = self.browser.location
            let unknown = self.tree.follow(location)
            self.showTree()
            // The first sections (or new roots) after the browser moved: the path's folders are listed now, as a move
            // would have had them, unless a listing of them is on its way.
            guard !self.isFollowing, !unknown.isEmpty else { return }
            self.pending = (location, unknown)
            if self.browser.hasCompleteListing { self.listingComplete(location, entries: self.browser.completeEntries) }
        }
    }

    private func showTree() { sidebarView.tree = tree }

    var loadingFolders: Set<String> { tree.loadingPaths }

    // MARK: Following

    private func moved(to location: BrowserLocation) {
        generation += 1
        followTask?.cancel()
        isFollowing = false
        pending = (location, tree.follow(location))
        showTree()
    }

    /// The folder's own listing is in: its entries are its node's children (the browser's listing is the one that
    /// counts, no listing of its own); then the path's other folders still unlisted, top first, one at a time.
    private func listingComplete(_ location: BrowserLocation, entries: [BrowserEntry]) {
        if case .folder(let folder) = location {
            tree.setChildren(entries, of: folder)
            showTree()
        }
        guard let pending, pending.location == location else { return }
        self.pending = nil
        let folders = pending.folders.filter { !tree.isListed($0) }
        guard !folders.isEmpty else { return }
        let generation = generation
        isFollowing = true
        followTask = Task { @MainActor [weak self] in
            defer { if self?.generation == generation { self?.isFollowing = false } }
            for folder in folders {
                guard let source = self?.source else { return }
                self?.tree.setLoading(true, of: folder)
                self?.showTree()
                let entries = try? await source.folders(in: folder)
                guard let self else { return }
                guard !Task.isCancelled, self.generation == generation else {
                    // Left before the answer: the row stops spinning, and is asked again when opened.
                    self.tree.setLoading(false, of: folder)
                    self.showTree()
                    return
                }
                // A share's error: the row stops spinning, unlisted (asked again when opened or followed).
                if let entries { self.tree.setChildren(entries, of: folder) } else { self.tree.setLoading(false, of: folder) }
                self.showTree()
            }
        }
    }

    /// The app checked `folder`'s subfolders after answering `folders(in:)` from what it kept (a catalog of an earlier
    /// run): a folder the tree has listed takes the checked ones; one it has not is left to its own asking.
    public func sidebarFoldersChanged(_ entries: [BrowserEntry], in folder: URL) {
        guard tree.isListed(folder) else { return }
        tree.setChildren(entries, of: folder)
        showTree()
    }

    /// A row opened by the user: its folders are asked now, whatever else is listing.
    private func expand(_ folder: URL) {
        let asks = tree.expand(folder)
        showTree()
        guard asks else { return }
        Task { @MainActor [weak self] in
            guard let source = self?.source else { return }
            let entries = try? await source.folders(in: folder)
            guard let self else { return }
            // A share's error: the row stops spinning, unlisted (asked again when opened).
            if let entries { self.tree.setChildren(entries, of: folder) } else { self.tree.setLoading(false, of: folder) }
            self.showTree()
        }
    }

    // MARK: Keys

    public override func keyDown(with event: NSEvent) {
        if !handleTab(event) { super.keyDown(with: event) }
    }

    /// Tab from the grid to the sidebar (when it shows); a field with the keys keeps its own Tab.
    private func handleTab(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard event.keyCode == 48, flags.isEmpty, isSidebarVisible, window?.firstResponder === browser else { return false }
        window?.makeFirstResponder(sidebarView)
        return true
    }

    // MARK: Drop

    public override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        onDrop != nil && fileURL(sender) != nil ? .copy : []
    }

    public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let onDrop, let url = fileURL(sender) else { return false }
        onDrop(url)
        return true
    }

    private func fileURL(_ info: any NSDraggingInfo) -> URL? {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?
            .first as? URL
    }
}

/// The system's split view controller with its toggle given to the app: the toolbar's Sidebar button (and the menu's
/// item) reaches `toggleSidebar(_:)` along the responder chain, and the app decides (it keeps `home-sidebar`).
final class HomeSplitViewController: NSSplitViewController {
    var onToggleSidebar: (() -> Void)?

    override func toggleSidebar(_ sender: Any?) {
        if let onToggleSidebar { onToggleSidebar() } else { super.toggleSidebar(sender) }
    }
}
