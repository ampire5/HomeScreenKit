import AppKit
import HomeChrome
import HomeScreenModel

/// The file browser: a toolbar over a grid of folders and files from a `HomeSource`, as Photos draws it — the
/// folders and archives first as collection cards, then the photos, each run under its heading when both are there,
/// and a footer at the end. The app's own sources show here too: a list as collection cards (Recent, under date
/// headings), or the app's page under the toolbar (Stash). `HomeView` puts it beside the sidebar. A folder can hold tens of thousands of files, so only the rows on
/// screen and a screen's worth either side have cards, taken from a pool as the grid scrolls; a card that leaves drops
/// its picture, and one that comes back asks again (the app's own cache answers fast).
public final class HomeBrowserView: NSView {
    // MARK: Set by the app

    /// The wanted photo slot width in points; the columns are the nearest count to it.
    public var cardSize: CGFloat = 220 { didSet { if cardSize != oldValue { tile() } } }
    /// Square or Aspect: a change re-tiles, the cards keep their pictures.
    public var style = GridStyle.aspect {
        didSet { if style != oldValue { toolbar.show(style: style); tile() } }
    }
    /// Where the names go: a change re-tiles, the cards keep their pictures.
    public var names = GridNames.off { didSet { if names != oldValue { tile() } } }
    /// The name filter, as the field shows it; setting it filters as typing does.
    public var filterText: String {
        get { filter.text }
        set {
            toolbar.filterText = newValue
            filterChanged { $0.text = newValue }
        }
    }
    /// The user asked for another style (⌥T, the style button) or names (⌥N): the app saves it and sets it back.
    public var onStyle: ((GridStyle) -> Void)?
    public var onNames: ((GridNames) -> Void)?

    /// A card size step: ⌘= / ⌘− / ⌘0, ⌘ + wheel, a pinch, a mouse's side wheel.
    public var onResize: ((HomeResize) -> Void)?
    /// After every move: the app keeps the last folder.
    public var onLocation: ((BrowserLocation) -> Void)?
    /// The location on screen got its first complete listing (`HomeView` lists the tree's folders only after it).
    var onListingComplete: ((BrowserLocation) -> Void)?
    /// After every move, for `HomeView` (the sidebar follows).
    var onMoved: ((BrowserLocation) -> Void)?
    /// A mouse's other buttons (down: true) for the app to route (Loupe's button layout, a Logitech mouse's own
    /// events); true when taken. Nil: the back and forward buttons (3, 4) are Back and Forward here.
    public var onOtherMouse: ((NSEvent, Bool) -> Bool)?

    // MARK: Read by the app

    public var location: BrowserLocation { history.current }
    /// The last places or folder shown: where the app's "Folders" goes back to.
    public private(set) var lastBrowsed = BrowserLocation.places

    /// The cards in view now, in order: their pictures are wanted first.
    public var visibleIDs: [String] {
        let visible = scroll.contentView.documentVisibleRect
        return live.keys.sorted().filter { grid.frame(of: $0).intersects(visible) }.map { entries[$0].id }
    }

    /// The widest slot in view, in points: the width the pictures are asked at.
    public var slotWidth: CGFloat {
        (0..<sections.count).map { grid.slotWidth(inSection: $0) }.max() ?? cardSize
    }

    /// The wanted slot width for ⌘= / ⌘−: one photo column fewer (at one column, the range's top) or one more, at the
    /// grid's width now, within `range`. Nil for `reset`: the app's default.
    public func cardSize(after step: HomeResize, range: ClosedRange<CGFloat>) -> CGFloat? {
        let m = GridMetrics(), columns = photoColumns
        let size: CGFloat
        switch step {
        case .larger:
            size = columns > 1 ? GridLayout.target(columns: columns - 1, width: gridWidth, gap: m.photoGap, edge: m.photoEdge)
                               : range.upperBound
        case .smaller: size = GridLayout.target(columns: columns + 1, width: gridWidth, gap: m.photoGap, edge: m.photoEdge)
        case .reset: return nil
        }
        return min(range.upperBound, max(range.lowerBound, size))
    }

    /// The photo columns at the grid's width now (also where there are no photos: the steps are the same).
    private var photoColumns: Int {
        let m = GridMetrics()
        return GridLayout.columns(width: gridWidth, target: cardSize, gap: m.photoGap, edge: m.photoEdge)
    }

    // MARK: State

    private weak var source: HomeSource?
    private(set) var history = BrowserHistory(start: .places)
    private var hasShown = false
    /// The entries on screen, in `sort` order, filtered: the containers first, then the files.
    private(set) var entries: [BrowserEntry] = []
    /// How many of `entries` are containers (the first section).
    private var containerCount = 0
    /// What the filter capsule and the name field leave of the listing.
    private(set) var filter = BrowserFilter()
    private var footerText: (line: String, state: String?) = ("", nil)
    private var indexByID: [String: Int] = [:]
    private var sort: BrowserSort { sortChoice.current }
    /// The folder's sort and the last direction of each field in this view (the capsule and ⌥1–3).
    private var sortChoice = BrowserSortChoice(current: .standard)
    /// The last listing of this place and whether a complete one has come (a sort by date or size waits for it).
    private var listing: BrowserListing?
    private var hasComplete = false
    /// The order the grid keeps while a sort by date or size chosen over it waits for the complete listing: the one
    /// on screen when it was chosen, so the grid stays (more names join it) instead of blanking. Nil: none kept.
    private var heldSort: BrowserSort?
    /// What the app says of the source on screen; nil in a folder or at the places.
    private var info: HomeSourceInfo?
    /// The date headings of a source's list (`DateGroups`), or nil for one untitled run.
    private var dateSections: [(title: String, count: Int)]?
    /// Bumped on every move: a listing or a timer of an older place is dropped.
    private var generation = 0
    private var listTask: Task<Void, Never>?
    /// A big listing's order, made off the main actor, one at a time: a listing that comes meanwhile waits in
    /// `orderPending` (only the latest), so a slow share's parts keep showing. A new sort or place bumps `orderCount`,
    /// and an order made before it is dropped.
    private var orderTask: Task<Void, Never>?
    private var orderPending: BrowserListing?
    private var orderCount = 0
    /// Listings over this many entries are ordered off the main actor, the grid on screen staying until it is ready.
    static let orderInlineLimit = 2_000
    private var loadingTask: Task<Void, Never>?
    /// What to select and how far to scroll once the place's entries come (Back, Up, or the app's `show`).
    private var pendingSelection: String?
    private var pendingScroll: CGFloat?
    private(set) var selectedID: String?

    // MARK: Parts

    let toolbar = HomeToolbar()
    private let skeleton = BrowserSkeleton()
    /// After this long without all the names, the skeleton says why it waits.
    var slowAfter: Duration = .seconds(3)
    private var slowTask: Task<Void, Never>?
    private let scroll = GridScrollView()
    private let message = HomeMessageView()
    /// A source's empty hint, in the middle.
    private let hint = NSTextField(labelWithString: "")
    /// The page on screen (a source's `info.page`), kept as a subview while hidden.
    private var page: NSView?
    private let toast = ChromeToastView(style: .window)
    private var toastLine: String?
    private(set) var renameField: BrowserRenameField?
    private let document = FlippedView()
    private var grid = GridLayout(sections: [], width: 0, target: 220, names: .off)
    private var sections: [GridSection] = []
    private var gridWidth: CGFloat = 0
    /// The cards on screen by entry index, and the ones put aside (a pool for each kind).
    private var live: [Int: GridCard] = [:]
    private var photoPool: [PhotoCard] = []
    private var collectionPool: [CollectionCard] = []
    private var headers: [GridHeader] = []
    private let footer = GridFooter()
    private var lastWanted: [String] = []

    public init(source: HomeSource) {
        self.source = source
        super.init(frame: .zero)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document
        scroll.onResize = { [weak self] step in self?.onResize?(step) }
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification,
                                               object: scroll.contentView)
        toast.translatesAutoresizingMaskIntoConstraints = false
        skeleton.translatesAutoresizingMaskIntoConstraints = false
        hint.font = Chrome.Text.font(.title, weight: .regular)
        hint.textColor = .secondaryLabelColor
        hint.isHidden = true
        hint.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(footer)
        // The grid runs under the toolbar, as in Photos; the skeleton starts below it.
        for view in [scroll, skeleton, hint, toolbar, message, toast] { addSubview(view) }
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor), toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: HomeToolbar.height),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            skeleton.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            skeleton.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            skeleton.topAnchor.constraint(equalTo: toolbar.bottomAnchor), skeleton.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            message.centerXAnchor.constraint(equalTo: centerXAnchor), message.centerYAnchor.constraint(equalTo: centerYAnchor),
            hint.centerXAnchor.constraint(equalTo: centerXAnchor), hint.centerYAnchor.constraint(equalTo: centerYAnchor),
            message.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -32),
            toast.centerXAnchor.constraint(equalTo: centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24),
            toast.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -64),
        ])
        toolbar.show(style: style)
        toolbar.onCrumb = { [weak self] location in self?.show(location, selecting: nil) }
        toolbar.onBack = { [weak self] in self?.goBack() }
        toolbar.onForward = { [weak self] in self?.goForward() }
        toolbar.onUp = { [weak self] in self?.goUp() }
        toolbar.onSortKey = { [weak self] key in self?.sortKeyChosen(key) }
        toolbar.onZoom = { [weak self] step in self?.onResize?(step) }
        toolbar.onStyle = { [weak self] in self?.toggleStyle() }
        toolbar.onKind = { [weak self] kind in self?.filterChanged { $0.kind = kind } }
        toolbar.onPageFilter = { [weak self] i in
            guard let self, case .source(let id) = self.location else { return }
            self.source?.pageFilterChosen(i, in: id)
        }
        toolbar.onFilterText = { [weak self] text in self?.filterChanged { $0.text = text } }
        toolbar.onSiblings = { [weak self] i in self?.siblingsAsked(i) }
        toolbar.onSiblingsClosed = { [weak self] in self?.siblingTask?.cancel() }
        toolbar.onFilterEnd = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// An arrow over the browser, whatever the view under it would show (a photo's hand cursor).
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if !trackingAreas.contains(where: { $0.owner === self }) {
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                           owner: self))
        }
    }

    public override func cursorUpdate(with event: NSEvent) { NSCursor.arrow.set() }

    // MARK: Moving

    /// Opens `location` and selects `selecting` there (nil: what was selected there last time).
    public func show(_ location: BrowserLocation, selecting: String?) {
        if hasShown {
            rememberPlace()
            history.go(to: location)
        } else {
            history = BrowserHistory(start: location)
            hasShown = true
        }
        pendingSelection = selecting ?? history.selection(for: location)
        pendingScroll = selecting == nil ? history.scroll(for: location) : nil
        load()
    }

    /// The window closes: no more listing, timers or toasts.
    public func stop() {
        generation += 1
        listTask?.cancel()
        orderCount += 1
        orderPending = nil
        loadingTask?.cancel()
        toast.hide()
        slowTask?.cancel()
        toolbar.loading.run(false)
        skeleton.stop()
        endRename()
    }

    /// The places again (a volume came or went), if they are on screen.
    public func reloadPlaces() {
        if location == .places { load() }
    }

    /// The location on screen listed again, its selection, scroll and name filter kept (the app's list changed).
    public func reload() {
        rememberPlace()
        pendingSelection = selectedID
        pendingScroll = scroll.contentView.bounds.origin.y
        load(keepingFilter: true)
    }

    /// The page filter's lit segment, as the page now shows (nil: none).
    public func showPageFilter(_ index: Int?) {
        guard let info, !info.pageFilters.isEmpty else { return }
        toolbar.show(pageFilters: info.pageFilters, selected: index)
    }

    /// Back, Forward and Up (⌘[ / ⌘] / ⌘↑, the bar's buttons; the app routes a mouse's side buttons here).
    public func goBack() {
        rememberPlace()
        guard history.back() else { return }
        restorePlace()
    }

    public func goForward() {
        rememberPlace()
        guard history.forward() else { return }
        restorePlace()
    }

    public func goUp() {
        guard case .folder(let url) = location else { return }
        rememberPlace()
        pendingSelection = history.up(parent: source?.parent(of: url) ?? .places)
        pendingScroll = nil
        load()
    }

    /// The place's remembered selection and scroll, once its entries come.
    private func restorePlace() {
        pendingSelection = history.selection(for: location)
        pendingScroll = history.scroll(for: location)
        load()
    }

    private func rememberPlace() {
        history.remember(selection: selectedID, scroll: scroll.contentView.bounds.origin.y)
    }

    private func load(keepingFilter: Bool = false) {
        generation += 1
        let generation = generation
        listTask?.cancel()
        siblingTask?.cancel()
        orderCount += 1
        orderPending = nil
        loadingTask?.cancel()
        listing = nil
        hasComplete = false
        heldSort = nil
        footerText = ("", nil)
        containerCount = 0
        // A filter is for the place it was set in: a move starts with everything shown.
        if !keepingFilter {
            filter = BrowserFilter()
            toolbar.filterText = ""
        }
        dateSections = nil
        selectedID = nil
        endRename()
        hideMessage()
        setEntries([])
        scroll.contentView.scroll(to: .zero)
        toolbar.show(subtitle: "")
        loadingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, self.generation == generation, self.listing == nil || !self.isShowingEntries else { return }
            self.toolbar.show(subtitle: "Loading…")
        }
        if case .source(let id) = location { info = source?.info(for: id) } else { info = nil; lastBrowsed = location }
        sortChoice = BrowserSortChoice(current: source?.sort(for: location) ?? .standard)
        showPage(info?.page)
        if page != nil {
            // A page lists nothing: it is complete as it is.
            loadingTask?.cancel()
            listing = BrowserListing(entries: [], complete: true)
            hasComplete = true
            slowTask?.cancel()
            updateLoading()
        } else {
            startSlowWatch(generation)
            updateLoading()
            if let stream = source?.list(location) {
                listTask = Task { @MainActor [weak self] in
                    do {
                        for try await listing in stream {
                            guard let self, self.generation == generation else { return }
                            self.apply(listing)
                        }
                    } catch {
                        guard let self, self.generation == generation else { return }
                        self.listFailed(error)
                    }
                }
            }
        }
        updateBar()
        if !keepingFilter { takeKeysBack() }
        if location != lastLoaded {
            source?.moved(from: lastLoaded, to: location)
            lastLoaded = location
        }
        onLocation?(location)
        onMoved?(location)
    }

    /// A move gives the keys back to the grid when they were left with something of the browser's that no longer
    /// has a use for them: the filter field (its text just went), a page now hidden, or nothing at all. The sidebar,
    /// reached by Tab, keeps them; so does a page shown now (`showPage`).
    private func takeKeysBack() {
        guard let window, page == nil, renameField == nil else { return }
        switch window.firstResponder {
        case nil, is NSWindow: break
        case let text as NSText:   // a field's editor: the filter's, which is ours
            guard let field = text.delegate as? NSView, field.isDescendant(of: self) else { return }
        case let view as NSView:
            guard view !== self, view.isDescendant(of: self) else { return }
        default: return
        }
        window.makeFirstResponder(self)
    }

    /// The keys to the browser's content: the page when one is shown, else the grid (a click in the sidebar, Tab).
    public func takeFocus() {
        window?.makeFirstResponder(page ?? self)
    }

    /// A name is being typed in the grid (`BrowserTypeSelect.isTyping`): a key the app would take for itself while
    /// the browser has the keys (F for full screen) goes to the name instead.
    public func isTypingName(at time: TimeInterval) -> Bool { typeSelect.isTyping(at: time) }

    /// A click on the grid's empty space takes the keys from the filter or the sidebar, as in Finder.
    public override func mouseDown(with event: NSEvent) {
        if page == nil { window?.makeFirstResponder(self) }
    }

    /// The location the last load was for: a reload is no move.
    private var lastLoaded: BrowserLocation?

    /// The source's page under the toolbar in place of the grid, or the grid again (nil).
    private func showPage(_ new: NSView?) {
        if let page, page !== new { page.isHidden = true }
        page = new
        if let new {
            if new.superview !== self {
                new.removeFromSuperview()
                new.translatesAutoresizingMaskIntoConstraints = false
                addSubview(new, positioned: .below, relativeTo: toolbar)
                NSLayoutConstraint.activate([
                    new.leadingAnchor.constraint(equalTo: leadingAnchor), new.trailingAnchor.constraint(equalTo: trailingAnchor),
                    new.topAnchor.constraint(equalTo: toolbar.bottomAnchor), new.bottomAnchor.constraint(equalTo: bottomAnchor),
                ])
            }
            new.isHidden = false
            window?.makeFirstResponder(new)
        }
        scroll.isHidden = new != nil || isShowingMessage
    }

    var isGridHidden: Bool { scroll.isHidden }
    var hintText: String? { hint.isHidden ? nil : hint.stringValue }

    /// The order entries go on screen in: `sort`, or until the complete listing that a sort by date or size needs, the
    /// held one (`heldSort`); nil shows none.
    private var shownSort: BrowserSort? { sort.key == .name || hasComplete ? sort : heldSort }

    /// Whether entries are on screen: a sort by date or size shows none until the complete listing, unless it was
    /// chosen over a grid that stays.
    private var isShowingEntries: Bool { shownSort != nil }

    private func apply(_ new: BrowserListing) {
        // Names only after a complete listing (the one remembered, shown on Back): it has nothing the other lacks.
        if !new.complete, hasComplete { return }
        listing = new
        if new.complete, !hasComplete {
            hasComplete = true
            // Pictures asked with names only are asked again: the app makes thumbnails of files whose date and size
            // it knows.
            lastWanted = []
            onListingComplete?(location)
        }
        defer { updateLoading() }
        guard let shownSort else { return }
        if new.entries.count <= Self.orderInlineLimit, orderTask == nil {
            orderCount += 1   // an older big order still on its way must not cover this one
            show(Self.arrange(new, sort: shownSort, filter: filter, info: arrangeInfo), of: new)
        } else if orderTask != nil {
            orderPending = new
        } else {
            order(new, by: shownSort)
        }
    }

    private func order(_ new: BrowserListing, by sort: BrowserSort) {
        let count = orderCount, filter = filter, info = arrangeInfo
        orderTask = Task { @MainActor [weak self] in
            let arranged = await Task.detached(priority: .userInitiated) { Self.arrange(new, sort: sort, filter: filter, info: info) }.value
            guard let self else { return }
            self.orderTask = nil
            if self.orderCount == count { self.show(arranged, of: new) }
            if let next = self.orderPending {
                self.orderPending = nil
                self.apply(next)
            }
        }
    }

    /// A listing ready for the screen: ordered, filtered, split into containers and files, and summed up.
    struct Arranged: Sendable {
        var entries: [BrowserEntry]
        var containers: Int
        var footer: String
        var state: String?
        var dateSections: [(title: String, count: Int)]?
    }

    /// What arranging a source's list needs of its `info`: the footer's noun and whether it is under date headings.
    struct ArrangeInfo: Sendable {
        var noun: String?
        var groupsByDate: Bool
    }

    private var arrangeInfo: ArrangeInfo {
        ArrangeInfo(noun: info?.noun, groupsByDate: info?.groupsByDate == true && shownSort?.key == .date)
    }

    /// Off the main actor for a big listing: nothing here touches the view.
    nonisolated static func arrange(_ listing: BrowserListing, sort: BrowserSort, filter: BrowserFilter,
                                    info: ArrangeInfo = ArrangeInfo(noun: nil, groupsByDate: false)) -> Arranged {
        let ordered = filter.apply(sort.order(listing.entries))
        let containers = ordered.firstIndex { $0.isFile } ?? ordered.count
        let summary = BrowserSummary.footer(entries: listing.entries, filtered: filter.isActive ? ordered.count : nil,
                                            complete: listing.complete, more: listing.more, noun: info.noun)
        let groups = info.groupsByDate ? DateGroups.sections(ordered.map(\.date), now: Date(), calendar: .current) : nil
        return Arranged(entries: ordered, containers: containers, footer: summary.line, state: summary.state,
                        dateSections: groups)
    }

    /// `listing`'s entries in order on screen, the selection and scroll kept or restored.
    private func show(_ arranged: Arranged, of new: BrowserListing) {
        loadingTask?.cancel()
        let old = selectedID.flatMap { indexByID[$0] }
        footerText = (arranged.footer, arranged.state)
        containerCount = arranged.containers
        dateSections = arranged.dateSections
        setEntries(arranged.entries)
        if let field = renameField, indexByID[field.entryID] == nil { endRename() }
        if let wanted = pendingSelection, indexByID[wanted] != nil {
            pendingSelection = nil
            select(id: wanted, scrolls: pendingScroll == nil)
        } else if let id = selectedID, indexByID[id] != nil {
            select(id: id, scrolls: false)
        } else if !entries.isEmpty {
            select(id: entries[min(old ?? 0, entries.count - 1)].id, scrolls: false)
        }
        if let y = pendingScroll, !entries.isEmpty {
            pendingScroll = nil
            scrollGrid(to: y)
        }
        updateSubtitle()
    }

    /// Under the path: while names come, how many; else the selected card; else the footer line.
    private func updateSubtitle() {
        let loading = listing?.more == true ? listing?.entries.count : nil
        toolbar.show(subtitle: loading == nil && selectedEntry == nil
                     ? footerText.line : BrowserSummary.subtitle(selected: selectedEntry, entries: [], loading: loading))
    }

    // MARK: Loading

    /// Names still to come (none yet, or more of them follow).
    private var namesPending: Bool { listing == nil || listing?.more == true }

    /// The line under the bar until the complete listing; the skeleton while nothing is on screen.
    private func updateLoading() {
        let failed = isShowingMessage
        let empty = hasComplete && entries.isEmpty && !failed && page == nil && !(info?.emptyHint.isEmpty ?? true)
            && !filter.isActive
        hint.stringValue = info?.emptyHint ?? ""
        hint.isHidden = !empty
        toolbar.loading.run(!hasComplete && !failed)
        let showSkeleton = entries.isEmpty && !hasComplete && !failed
        if showSkeleton != !skeleton.isHidden {
            skeleton.isHidden = !showSkeleton
            if showSkeleton { skeleton.start() } else { skeleton.stop() }
        }
        skeleton.cardSize = cardSize
        if !namesPending || failed { slowCaption = nil }
    }

    /// Past `slowAfter` without all the names: what it waits for, and how long it has, every half second.
    private func startSlowWatch(_ generation: Int) {
        slowTask?.cancel()
        slowCaption = nil
        let started = ContinuousClock.now
        slowTask = Task { @MainActor [weak self] in
            guard let after = self?.slowAfter else { return }
            try? await Task.sleep(for: after)
            while let self, self.generation == generation, !Task.isCancelled, self.namesPending, !self.isShowingMessage {
                let seconds = Int((ContinuousClock.now - started) / .seconds(1))
                let count = self.listing?.entries.count ?? 0
                self.slowCaption = count == 0
                    ? ("Waiting for the share…", "\(seconds) s · ⌘[ Back")
                    : ("Slow folder", "\(count) items so far · \(seconds) s")
                try? await Task.sleep(for: .milliseconds(500))
            }
            if let self, self.generation == generation { self.slowCaption = nil }
        }
    }

    /// The skeleton's middle line while names are slow to come; with entries on screen it shows over them, in the bar's
    /// count only.
    private var slowCaption: (String, String)? {
        didSet {
            skeleton.show(title: slowCaption?.0, detail: slowCaption?.1)
        }
    }

    /// The location on screen has had its complete listing.
    var hasCompleteListing: Bool { hasComplete }
    var isShowingLoadingLine: Bool { toolbar.loading.isRunning }
    var isShowingSkeleton: Bool { !skeleton.isHidden }
    var skeletonPictureFrames: [CGRect] { skeleton.pictureFrames }
    var slowText: String? { slowCaption.map { "\($0.0)\n\($0.1)" } }

    /// The folder could not be listed: why, in place of the grid; Up and Back still work.
    private func listFailed(_ error: Error) {
        loadingTask?.cancel()
        toolbar.show(subtitle: "")
        guard case .folder(let url) = location else { return }
        message.show(title: url.lastPathComponent, reason: error.localizedDescription, detail: url.path,
                     hints: ["⌘↑ Up", "⌘[ Back"])
        message.isHidden = false
        scroll.isHidden = true
        updateLoading()
    }

    private func hideMessage() {
        message.isHidden = true
        scroll.isHidden = page != nil
    }

    var isShowingMessage: Bool { !message.isHidden }
    var messageTexts: [String] { message.texts }

    // MARK: Toast

    /// A short line at the bottom for 3 s: an action that failed.
    public func showToast(_ text: String) {
        toastLine = text
        toast.show(text, for: 3)
    }

    var toastText: String? { toast.isShowing ? toastLine : nil }

    // MARK: Rename and trash

    private var selectedEntry: BrowserEntry? { selectedIndex.map { entries[$0] } }

    /// The name field over the selected card's title (F2, or the app's Rename… item).
    public func beginRename() {
        guard let entry = selectedEntry, entry.canRename, let i = indexByID[entry.id] else { return }
        endRename()
        document.scrollToVisible(grid.frame(of: i))
        tile()
        let field = BrowserRenameField(entryID: entry.id, name: entry.name, isFile: entry.kind == .file)
        field.onCommit = { [weak self] in self?.commitRename() }
        field.onCancel = { [weak self] in self?.endRename() }
        document.addSubview(field)
        renameField = field
        placeRenameField()
        field.beginEditing()
    }

    private func placeRenameField() {
        guard let field = renameField, let i = indexByID[field.entryID] else { return }
        let slot = grid.frame(of: i)
        let y: CGFloat
        if names == .below {
            y = slot.minY + slot.width + 1   // on the name line
        } else if isCollection(i) {
            y = slot.minY + slot.width - 42   // over the title on the picture
        } else {
            let bottom = (live[i] as? PhotoCard)?.pictureRect.maxY ?? slot.width
            y = slot.minY + bottom - 26   // the bottom of the picture, where a name on it goes
        }
        field.place(over: CGRect(x: slot.minX, y: y, width: slot.width, height: 22))
    }

    private func endRename() {
        guard let field = renameField else { return }
        renameField = nil
        field.isCommitting = true   // leaving the field now is not a cancel
        field.remove()
        if field.window != nil || window?.firstResponder == nil { window?.makeFirstResponder(self) }
    }

    private func commitRename() {
        guard let field = renameField, let entry = indexByID[field.entryID].map({ entries[$0] }) else { return }
        let name = field.stringValue
        guard name != entry.name else { endRename(); return }
        field.isCommitting = true
        let generation = generation
        Task { @MainActor [weak self] in
            guard let source = self?.source else { return }
            do {
                let renamed = try await source.rename(entry, to: name)
                guard let self, self.generation == generation else { return }
                self.endRename()
                self.replace(entry.id, with: renamed)
            } catch {
                guard let self, self.renameField === field else { return }
                field.isCommitting = false
                field.show(reason: error.localizedDescription)
            }
        }
    }

    /// The listing with `id` replaced (nil: removed), `select` selected.
    private func replace(_ id: String, with new: BrowserEntry?, select next: String? = nil) {
        guard var current = listing else { return }
        if let new, let i = current.entries.firstIndex(where: { $0.id == id }) {
            current.entries[i] = new
        } else {
            current.entries.removeAll { $0.id == id }
        }
        pendingSelection = new?.id ?? next
        apply(current)
    }

    /// The selected card to the Trash (⌘⌫, or the app's Move to Trash item); the next one is selected after.
    public func trashSelected() {
        guard let entry = selectedEntry, entry.canTrash, let i = indexByID[entry.id] else { return }
        let next = entries.indices.contains(i + 1) ? entries[i + 1].id : i > 0 ? entries[i - 1].id : nil
        let generation = generation
        Task { @MainActor [weak self] in
            guard let source = self?.source else { return }
            do {
                try await source.trash(entry)
                guard let self, self.generation == generation else { return }
                self.replace(entry.id, with: nil, select: next)
            } catch is CancellationError {
                // The app asked and the user said no.
            } catch {
                self?.showToast(error.localizedDescription)
            }
        }
    }

    /// The kind capsule or a keystroke in the name field: the listing again through the filter, off the main actor when
    /// it is big; a change while one is ordered drops that one's result.
    private func filterChanged(_ change: (inout BrowserFilter) -> Void) {
        var new = filter
        change(&new)
        guard new != filter else { return }
        filter = new
        orderCount += 1
        if let listing { apply(listing) }
    }

    /// A segment of the capsule or ⌥1–3: the field, or the other direction of the active one. The capsule shows it at
    /// once; a sort by date or size before the complete listing leaves the grid as it is until that listing comes.
    private func sortKeyChosen(_ key: BrowserSort.Key) {
        guard sortKeys.contains(key) else { return }
        let before = shownSort
        source?.setSort(sortChoice.choose(key), for: location)
        heldSort = hasComplete ? nil : before
        toolbar.show(sort: sort, keys: sortKeys)
        if shownSort != before {
            orderCount += 1
            if let listing { apply(listing) }
        }
        if shownSort != sort { toolbar.show(subtitle: "Loading…") } else { updateSubtitle() }   // back to the order shown
    }

    private func setEntries(_ new: [BrowserEntry]) {
        entries = new
        indexByID = Dictionary(new.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        tile()
    }

    /// The sort capsule's fields here: a folder's three, a source's own, none at the places or on a page.
    private var sortKeys: [BrowserSort.Key] {
        switch location {
        case .places: []
        case .folder: [.name, .date, .size]
        case .source: info?.page == nil ? info?.sortKeys ?? [] : []
        }
    }

    private func updateBar() {
        if let info {
            toolbar.show(title: info.title)
        } else {
            toolbar.show(path: path(), canBack: history.canGoBack, canForward: history.canGoForward,
                         canUp: location != .places)
        }
        toolbar.show(sort: sort, keys: sortKeys)
        toolbar.show(pageFilters: info?.pageFilters ?? [], selected: info?.pageFilters.isEmpty == false ? 0 : nil)
        toolbar.show(filter: filter.kind, visible: info == nil && location != .places)
        toolbar.show(controls: page == nil)
    }

    private var siblingTask: Task<Void, Never>?

    /// The › before crumb `i`: its menu opens at once, the folders beside that crumb (in their parent's sort) fill it
    /// when the source answers; a reply after a move or after the menu closed is dropped.
    private func siblingsAsked(_ i: Int) {
        let crumbs = path()
        guard crumbs.indices.contains(i), i > 0 else { return }
        let current = crumbs[i].location, parent = crumbs[i - 1].location
        let generation = generation
        siblingTask?.cancel()
        siblingTask = Task { @MainActor [weak self] in
            guard let source = self?.source else { return }
            let entries: [BrowserEntry]
            switch parent {
            case .places, .source: entries = await source.places()
            case .folder(let url): entries = source.sort(for: parent).order(await source.folders(in: url))
            }
            guard let self, !Task.isCancelled, self.generation == generation else { return }
            self.toolbar.updateSiblings(entries.map { (title: $0.name, location: .folder($0.url),
                                                       current: BrowserLocation.folder($0.url) == current) })
        }
        toolbar.showSiblings(nil, at: i)
    }

    /// The crumbs from the places down to here, by the source's parents.
    private func path() -> [(title: String, location: BrowserLocation)] {
        var crumbs: [(title: String, location: BrowserLocation)] = []
        var at = location
        for _ in 0..<64 {
            guard case .folder(let url) = at else { break }
            crumbs.append((url.lastPathComponent, at))
            at = source?.parent(of: url) ?? .places
        }
        crumbs.append(("Places", .places))
        return crumbs.reversed()
    }

    // MARK: Selection

    func select(id: String, scrolls: Bool = true) {
        selectedID = id
        for card in live.values { card.isSelected = card.item.id == id }
        if scrolls, let i = indexByID[id] {
            // Clear of the toolbar over the grid's top.
            let frame = grid.frame(of: i)
            document.scrollToVisible(CGRect(x: frame.minX, y: frame.minY - HomeToolbar.height - 8, width: frame.width,
                                            height: frame.height + HomeToolbar.height + 16))
        }
        updateSubtitle()
    }

    private func select(index: Int) {
        guard entries.indices.contains(index) else { return }
        select(id: entries[index].id)
    }

    private var selectedIndex: Int? { selectedID.flatMap { indexByID[$0] } }

    // MARK: Opening

    /// A folder or an archive is entered here; a file, or anything in a new tab or window, goes to the app.
    private func activate(_ id: String, _ click: HomeClick) {
        guard let entry = indexByID[id].map({ entries[$0] }) else { return }
        if entry.isContainer, click == .open {
            show(.folder(entry.url), selecting: nil)
        } else {
            source?.open(entry, in: location, sort: sort, how: click)
        }
    }

    private func clicked(_ id: String, middle: Bool, flags: NSEvent.ModifierFlags) {
        activate(id, HomeClick.from(shift: flags.contains(.shift), command: flags.contains(.command), middle: middle,
                                    supportsTabs: true))
    }

    // MARK: Keys

    public override func keyDown(with event: NSEvent) {
        if !handleKey(event) { super.keyDown(with: event) }
    }

    /// ⌘ keys reach the browser before the menu (⌘[ is File › Back, ⌘= Larger Cards), while it has the keys.
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command), !isHiddenOrHasHiddenAncestor,
              window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        return handleKey(event) || super.performKeyEquivalent(with: event)
    }

    // MARK: Mouse

    public override func otherMouseDown(with event: NSEvent) {
        if onOtherMouse?(event, true) == true { return }
        super.otherMouseDown(with: event)
    }

    public override func otherMouseUp(with event: NSEvent) {
        if let onOtherMouse {
            if !onOtherMouse(event, false) { super.otherMouseUp(with: event) }
            return
        }
        switch event.buttonNumber {
        case 3: goBack()
        case 4: goForward()
        default: super.otherMouseUp(with: event)
        }
    }

    private var typeSelect = BrowserTypeSelect()
    /// ⌥1 / ⌥2 / ⌥3: the sort capsule's first, second and third field.
    private static let sortKeyIndex: [UInt16: Int] = [18: 0, 19: 1, 20: 2]

    /// Arrows, Return (⌘ a new tab, ⇧ a new window), ⌘↓ open, ⌘↑ up, ⌘[ / ⌘] back and forward, the size keys and
    /// typing a name; false for any other key.
    public func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let command = flags.contains(.command)
        // ⌘ alone: ⇧⌘[ / ⇧⌘] are the window's tab steps, ⌥⌘↑ and the like belong to others.
        if command, flags != .command, [33, 30, 125, 126, 51].contains(event.keyCode) { return false }
        if flags == .command, event.keyCode == 3 {   // ⌘F
            toolbar.focusFilter()
            return true
        }
        if command, let resize = HomeScreenView.resizeKeys[event.keyCode] {
            onResize?(resize)
            return true
        }
        switch (event.keyCode, command) {
        case (126, true): goUp(); return true
        case (125, true):
            if let id = selectedID { activate(id, .open) }
            return true
        case (33, true): goBack(); return true
        case (30, true): goForward(); return true
        case (51, true): trashSelected(); return true
        case (120, false): beginRename(); return true
        case (36, _), (76, _):
            if let id = selectedID { clicked(id, middle: false, flags: event.modifierFlags) }
            return true
        default: break
        }
        guard !command, !flags.contains(.control) else { return false }
        // ⌥1 / ⌥2 / ⌥3 pick the sort, ⌥T the style, ⌥N the names (by key code, any layout); any other key with ⌥ is
        // someone else's, never a name.
        if flags.contains(.option) {
            guard flags == .option else { return false }
            switch event.keyCode {
            case 17: toggleStyle()                        // ⌥T
            case 45: onNames?(names.next)                 // ⌥N
            default:
                guard let i = Self.sortKeyIndex[event.keyCode] else { return false }
                if sortKeys.indices.contains(i) { sortKeyChosen(sortKeys[i]) }
            }
            return true
        }
        let current = selectedIndex ?? 0
        let directions: [UInt16: GridLayout.Direction] = [123: .left, 124: .right, 125: .down, 126: .up]
        if let d = directions[event.keyCode] {
            if let next = grid.neighbour(of: current, d) { select(index: next) }
            return true
        }
        guard let text = event.charactersIgnoringModifiers, let scalar = text.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar), !(0xF700...0xF8FF).contains(scalar.value) else { return false }
        let prefix = typeSelect.type(text, at: event.timestamp)
        // A longer prefix may still match the card selected now; a new one starts after it.
        let start = prefix.count > 1 ? current : current + 1
        if let i = BrowserTypeSelect.match(prefix, in: entries.map(\.name), from: start) { select(index: i) }
        return true
    }

    // MARK: Cards

    public override func layout() {
        super.layout()
        tile()
    }

    @objc private func scrolled() { tile() }

    /// The sections of what is on screen: at the top level one run of places; in a folder the containers, then the
    /// files, titled only when both are there.
    private func makeSections() -> [GridSection] {
        if let dateSections {
            return dateSections.map { GridSection(kind: .collections, count: $0.count, title: $0.title) }
        }
        guard case .folder = location else { return [GridSection(kind: .collections, count: entries.count)] }
        let files = entries.count - containerCount
        let both = containerCount > 0 && files > 0
        return [GridSection(kind: .collections, count: containerCount, title: both ? "Folders" : nil),
                GridSection(kind: .photos, count: files, title: both ? "Photos · \(BrowserSummary.number(files))" : nil)]
    }

    /// Cards for the rows in view and a screen either side; the others go back to their pool.
    private func tile() {
        let width = scroll.contentSize.width > 0 ? scroll.contentSize.width : bounds.width
        gridWidth = width
        sections = makeSections()
        var metrics = GridMetrics()
        metrics.top = HomeToolbar.height
        grid = GridLayout(sections: sections, width: width, target: cardSize, names: names, metrics: metrics)
        let height = max(grid.contentHeight, scroll.contentSize.height)
        if document.frame.size != CGSize(width: width, height: height) {
            document.frame = CGRect(x: 0, y: 0, width: width, height: height)
        }
        let visible = scroll.contentView.documentVisibleRect
        let range = grid.indices(in: visible, margin: max(visible.height, 1))
        // A card goes with its entry to the entry's slot now (a new order, a filter, names before it), its picture and
        // closures kept; one whose entry left the range, or whose slot is of the other kind now, goes back to its pool.
        var kept: [Int: GridCard] = [:]
        for card in live.values {
            if let i = indexByID[card.item.id], range.contains(i), kept[i] == nil,
               isCollection(i) == (card is CollectionCard) {
                kept[i] = card
            } else {
                putAside(card)
            }
        }
        live = kept
        for i in range {
            let entry = entries[i]
            if let card = live[i] {
                let item = item(for: entry)   // a count, a date, dimming or a menu changed: the picture stays
                if card.item != item { card.show(item) }
            } else {
                let card: GridCard = isCollection(i) ? collectionPool.popLast() ?? makeCollection()
                                                     : photoPool.popLast() ?? makePhoto()
                configure(card, entry)
                card.isHidden = false
                live[i] = card
            }
            let card = live[i]!
            let section = grid.section(of: i)
            if let photo = card as? PhotoCard {
                photo.style = style
                photo.names = names
                photo.showsNames = grid.showsNames(inSection: section)
            } else if let collection = card as? CollectionCard {
                collection.names = names
            }
            // Straight to the slot: a view's frame animates only in an animation group that allows it (the sidebar's).
            card.frame = grid.frame(of: i)
        }
        placeHeaders()
        let summary = footerText.state.map { [footerText.line, $0] } ?? [footerText.line]
        footer.show(lines: isShowingEntries ? summary.filter { !$0.isEmpty } : [])
        footer.frame = grid.footerFrame
        placeRenameField()
        askImages()
    }

    private func isCollection(_ i: Int) -> Bool { !entries[i].isFile }

    private func putAside(_ card: GridCard) {
        card.isHidden = true
        card.image = nil
        if let photo = card as? PhotoCard { photoPool.append(photo) }
        if let collection = card as? CollectionCard { collectionPool.append(collection) }
    }

    private func placeHeaders() {
        let titled = sections.indices.compactMap { s in grid.headerFrame(ofSection: s).map { (sections[s].title ?? "", $0) } }
        while headers.count < titled.count {
            let header = GridHeader()
            document.addSubview(header)
            headers.append(header)
        }
        for (i, header) in headers.enumerated() {
            header.isHidden = i >= titled.count
            guard i < titled.count else { continue }
            header.title = titled[i].0
            header.frame = titled[i].1
        }
    }

    private func makePhoto() -> PhotoCard {
        let card = PhotoCard(item: HomeCardItem(id: "", title: "", tooltip: "", symbol: "photo"))
        document.addSubview(card)
        return card
    }

    private func makeCollection() -> CollectionCard {
        let card = CollectionCard(item: HomeCardItem(id: "", title: "", tooltip: "", symbol: "folder"))
        document.addSubview(card)
        return card
    }

    private func configure(_ card: GridCard, _ entry: BrowserEntry) {
        card.show(item(for: entry))
        card.image = nil
        card.isSelected = entry.id == selectedID
        let id = entry.id
        card.onClick = { [weak self] middle, flags in self?.clicked(id, middle: middle, flags: flags) }
        card.onHover = { [weak self] in self?.select(id: id, scrolls: false) }
        card.onMenu = { [weak self] item in self?.menuChosen(item, id) }
    }

    /// The style button and ⌥T: the other style, through the app.
    private func toggleStyle() { onStyle?(style == .square ? .aspect : .square) }

    private func menuChosen(_ item: String, _ id: String) {
        guard let entry = indexByID[id].map({ entries[$0] }) else { return }
        source?.perform(item, on: entry, in: location)
    }

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private func item(for entry: BrowserEntry) -> HomeCardItem {
        var subtitle: String?
        switch entry.kind {
        case .folder, .archive:
            subtitle = entry.count.map { $0 == 1 ? "1 photo" : "\($0) photos" }
        case .file:
            switch (shownSort ?? sort).key {
            case .name: subtitle = nil
            case .date: subtitle = entry.date.map(Self.dateFormat.string)
            case .size: subtitle = entry.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
            }
        case .place, .collection:
            subtitle = nil
        }
        return HomeCardItem(id: entry.id, title: entry.name, subtitle: entry.subtitle ?? subtitle,
                            tooltip: entry.kind == .collection ? entry.name : entry.url.path,
                            symbol: source?.symbol(for: entry) ?? "doc", progress: entry.progress,
                            badge: entry.badge ?? (entry.kind == .archive ? "ZIP" : nil), isDimmed: entry.isDimmed,
                            menu: source?.menu(for: entry, in: location) ?? [], glassSymbol: entry.kind == .place)
    }

    /// The live cards without a picture, those in view first; asked again only when the set changes.
    private func askImages() {
        let visible = visibleIDs
        let shown = Set(visible)
        let rest = live.keys.sorted().map { entries[$0].id }.filter { !shown.contains($0) }
        let wanted = (visible + rest).filter { id in indexByID[id].flatMap { live[$0] }?.image == nil }
        guard wanted != lastWanted else { return }
        lastWanted = wanted
        if !wanted.isEmpty { source?.wantImages(wanted, width: slotWidth) }
    }

    /// Size steps from a wheel the app hears itself (a mouse's thumb wheel): positive larger; a step a whole notch.
    public func resize(notches: Double) { scroll.resize(notches: notches) }

    /// A card's picture; one not on screen now is ignored.
    public func setImage(_ image: CGImage?, for id: String) {
        guard let card = card(for: id) else { return }
        card.image = image
    }

    func card(for id: String) -> GridCard? {
        indexByID[id].flatMap { live[$0] }.flatMap { $0.item.id == id ? $0 : nil }
    }

    // MARK: For tests

    var liveCardCount: Int { live.count }
    /// The columns of the last section (the photos in a folder, the places at the top).
    var columns: Int { sections.isEmpty ? 0 : grid.columns(inSection: sections.count - 1) }
    var headerTitles: [String] { headers.filter { !$0.isHidden }.map(\.title) }
    var footerLines: [String] { footer.lines }
    var scrollOffset: CGFloat { scroll.contentView.bounds.origin.y }
    var liveIDs: [String] { live.values.map(\.item.id) }
    var gridContentHeight: CGFloat { document.frame.height }
    var gridContentWidth: CGFloat { document.frame.width }

    func scrollGrid(to y: CGFloat) {
        let top = max(0, min(y, document.frame.height - scroll.contentSize.height))
        scroll.contentView.scroll(to: CGPoint(x: 0, y: top))
        scroll.reflectScrolledClipView(scroll.contentView)
        tile()
    }

    public override var acceptsFirstResponder: Bool { true }
}
