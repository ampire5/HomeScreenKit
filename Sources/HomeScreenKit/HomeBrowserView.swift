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
    public var cardSize: CGFloat = 220 {
        didSet {
            if cardSize != oldValue { tile() }
            toolbar.show(cardSize: cardSize, range: cardSizeRange)
        }
    }
    /// The sizes the slider spans (the app's limits of `cardSize`).
    public var cardSizeRange: ClosedRange<CGFloat> = 60...480 {
        didSet { toolbar.show(cardSize: cardSize, range: cardSizeRange) }
    }
    /// Square or Aspect: a change re-tiles, the cards keep their pictures.
    public var style = GridStyle.aspect {
        didSet { if style != oldValue { toolbar.show(style: style); tile() } }
    }
    /// Where the names go: a change re-tiles, the cards keep their pictures.
    public var names = GridNames.off { didSet { if names != oldValue { tile() } } }
    /// What the files are (`FileStyle`: photos, or a video app's videos): their noun in the counts, their slot's shape
    /// and the length and progress on their pictures. Set before the first `show`; a change re-tiles.
    public var files = FileStyle.photos {
        didSet {
            guard files != oldValue else { return }
            toolbar.filesTitle = files.heading
            tile()
        }
    }
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
    /// The location on screen got its first complete listing, with its entries (`HomeView` gives them to the tree's
    /// node of the folder and lists the path's other folders only after it).
    var onListingComplete: ((BrowserLocation, [BrowserEntry]) -> Void)?
    /// After every move, for `HomeView` (the sidebar follows).
    var onMoved: ((BrowserLocation) -> Void)?
    /// A mouse's other buttons (down: true) for the app to route (Loupe's button layout, a Logitech mouse's own
    /// events); true when taken. Nil: the back and forward buttons (3, 4) are Back and Forward here.
    public var onOtherMouse: ((NSEvent, Bool) -> Bool)?

    // MARK: Read by the app

    public var location: BrowserLocation { history.current }
    /// The last places or folder shown: where the app's "Folders" goes back to.
    public private(set) var lastBrowsed = BrowserLocation.places

    /// The selected entry's id (a session keeps it); while a restore waits for its entry, that one.
    public var selection: String? { pendingSelection ?? selectedID }

    /// How far the grid is scrolled, for a session: the first card fully in view (else the first in view) and its
    /// offset below the view's top; nil at the top or with nothing on screen. While a session's anchor waits for its
    /// names, that one.
    public var anchor: BrowserAnchor? {
        if let pendingAnchor { return pendingAnchor }
        let top = scroll.contentView.bounds.origin.y
        guard top > 0, page == nil else { return nil }
        let visible = scroll.contentView.documentVisibleRect
        let shown = live.keys.sorted().filter { grid.frame(of: $0).intersects(visible) }
        guard let i = shown.first(where: { grid.frame(of: $0).minY >= top }) ?? shown.first else { return nil }
        return BrowserAnchor(id: entries[i].id, offset: Double(grid.frame(of: i).minY - top), index: i)
    }

    /// The cards laid out now (in view and a screen either side), in order; a card's facts set while it is not among
    /// them show when it is laid out, and one laid out anew asks for its picture.
    public var liveIDs: [String] { live.keys.sorted().map { entries[$0].id } }

    /// The cards in view now, in order: their pictures are wanted first.
    public var visibleIDs: [String] {
        let visible = scroll.contentView.documentVisibleRect
        return live.keys.sorted().filter { grid.frame(of: $0).intersects(visible) }.map { entries[$0].id }
    }

    /// The widest picture in view, in points: the width the pictures are asked at. A row's picture is its small cover
    /// and a compact card's its square (`cardCover`), not the row or the card; a section with no cards counts not.
    public var slotWidth: CGFloat {
        let style = shownCardStyle(width: gridWidth)
        if style == .list { return GridMetrics().listCover }
        let widths = sections.indices.filter { sections[$0].count > 0 }.map { s -> CGFloat in
            style == .cards && sections[s].kind == .collections ? GridMetrics().cardCover : grid.slotWidth(inSection: s)
        }
        return widths.max() ?? cardSize
    }

    /// The width of a folder's or an archive's picture in the style shown, in points: a poster's slot, a compact
    /// card's square, a row's cover. In a folder with photos too, `slotWidth` is the photos' (the wider); the app
    /// makes its folder covers at this one.
    public var coverWidth: CGFloat {
        switch shownCardStyle(width: gridWidth) {
        case .list: return GridMetrics().listCover
        case .cards: return GridMetrics().cardCover
        case .posters:
            let containers = sections.indices.first { sections[$0].kind == .collections && sections[$0].count > 0 }
            return containers.map { grid.slotWidth(inSection: $0) } ?? slotWidth
        }
    }

    /// How the folders are drawn now (the chosen style, or posters in a narrow column and outside folders): a list
    /// row's cover is four photos at 32 pt (`HomeMosaic.Layout.quad`).
    public var shownStyle: CardStyle { shownCardStyle(width: gridWidth) }

    /// The wanted slot width for a step: for the wheel and a pinch one photo column fewer (at one column, the range's
    /// top) or one more, at the grid's width now; for ⌘= / ⌘− the next of `HomeResize.sizes`; the slider's own size;
    /// within `range`. Nil for `reset`: the app's default.
    public func cardSize(after step: HomeResize, range: ClosedRange<CGFloat>) -> CGFloat? {
        let m = GridMetrics(), columns = photoColumns
        let size: CGFloat
        switch step {
        case .larger:
            size = columns > 1 ? GridLayout.target(columns: columns - 1, width: gridWidth, gap: m.photoGap, edge: m.photoEdge)
                               : range.upperBound
        case .smaller: size = GridLayout.target(columns: columns + 1, width: gridWidth, gap: m.photoGap, edge: m.photoEdge)
        case .largerSize, .smallerSize: size = HomeResize.nextSize(after: cardSize, larger: step == .largerSize)
        case .to(let wanted): size = wanted
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

    weak var source: HomeSource?
    private(set) var history = BrowserHistory(start: .places)
    private var hasShown = false
    /// The entries on screen, in `sort` order, filtered: the containers first, then the files.
    private(set) var entries: [BrowserEntry] = []
    /// How many of `entries` are containers (the first section).
    private var containerCount = 0
    /// What the filter group and the name field leave of the listing.
    private(set) var filter = BrowserFilter()
    private var footerText: (line: String, state: String?) = ("", nil)
    private var indexByID: [String: Int] = [:]
    var sort: BrowserSort { sortChoice.current }
    /// The folder's sort and the last direction of each field in this view (More and ⌥1–3).
    private var sortChoice = BrowserSortChoice(current: .standard)
    /// The last listing of this place and whether a complete one has come (a sort by date or size waits for it).
    private var listing: BrowserListing?
    private var hasComplete = false
    /// The order the grid keeps while a sort by date or size waits for the complete listing: the one on screen when it
    /// was chosen, so the grid stays (more names join it) instead of blanking; a place whose saved sort is by date or
    /// size shows its names in Finder's order meanwhile (`BrowserSort.standard`). Nil: none kept.
    private var heldSort: BrowserSort?
    /// The complete listing changed the order on screen from the held one: its show keeps the selected card (or the
    /// first in view) where it was in the view.
    private var anchorsNextShow = false
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
    /// A session's scroll (`show(_:selecting:anchor:)`): taken once the names are all there or have its entry.
    private var pendingAnchor: BrowserAnchor?
    /// The scroll is a session's (its anchor waits or was taken): a selection that comes later selects without
    /// scrolling. Cleared by a move and by the user's own scroll or selection.
    private var restoredScroll = false
    private(set) var selectedID: String?
    /// Photos whose picture the source cannot make (`setUnavailable`): their cards are faint and the arrow keys go past
    /// them. A place of its own, so it is forgotten with the place.
    private var unavailable: Set<String> = []
    /// The app's files the decoders could not read: their cards are faint and the arrow keys go past them, as
    /// `unavailable`'s; a change touches only the cards on screen of the files it names.
    public var unreadable: UnreadableFiles? {
        didSet {
            unreadableObservation = unreadable?.observe { [weak self] urls in self?.unreadableChanged(urls) }
            reloadUnavailableCards()
        }
    }
    private var unreadableObservation: UnreadableFiles.Observation?
    /// Photos not viewed yet and pages of a pair (`setPhotoMarks`): forgotten with the place, like `unavailable`.
    /// Files' facts sent after their listing (`setFacts`), for the place on screen.
    private var facts: [String: FileFacts] = [:]
    private var unseen: Set<String> = []
    private var paired: Set<String> = []

    // MARK: Parts

    /// Below the window's toolbar the grid starts; without a window (tests) or a toolbar this far from its top.
    static let defaultTopInset: CGFloat = 52

    /// What the toolbar and the title bar take at the view's top: the safe area's, once the window has a toolbar.
    var topInset: CGFloat { window?.toolbar != nil ? safeAreaInsets.top : Self.defaultTopInset }

    /// The toolbar for the window of the app to show while Home is on screen (`window.toolbar = browser.nsToolbar`).
    public var nsToolbar: NSToolbar { toolbar.nsToolbar }

    /// The window's title and subtitle for the folder on screen (its name, and the count line under it), as the app
    /// shows them in the window: set whenever either changes.
    public var onWindowText: ((_ title: String, _ subtitle: String) -> Void)? {
        get { toolbar.onWindowText }
        set { toolbar.onWindowText = newValue }
    }

    /// The edges that follow `topInset`: the loading line's bottom and the skeleton's and a page's top.
    private lazy var loadingBottom = loading.bottomAnchor.constraint(equalTo: topAnchor, constant: Self.defaultTopInset)
    private lazy var skeletonTop = skeleton.topAnchor.constraint(equalTo: topAnchor, constant: Self.defaultTopInset)
    private var pageTop: NSLayoutConstraint?

    private func updateTopInset() {
        let inset = topInset
        guard loadingBottom.constant != inset || skeletonTop.constant != inset || pageTop?.constant != inset else { return }
        loadingBottom.constant = inset
        skeletonTop.constant = inset
        pageTop?.constant = inset
        needsLayout = true
    }


    let toolbar = HomeToolbarController()
    /// Runs along the bottom of the toolbar's inset while a folder loads.
    let loading = LoadingLine()
    private let skeleton = BrowserSkeleton()
    /// After this long without all the names, the skeleton says why it waits.
    var slowAfter: Duration = .seconds(3)
    private var slowTask: Task<Void, Never>?
    let scroll = GridScrollView()
    /// Under the grid: the path bar over the status line, on one material; hidden when both rows are.
    private let statusBar = NSVisualEffectView()
    private let statusRow = NSView()
    private let statusLabel = NSTextField(labelWithString: "")
    /// Finder's path bar: the crumbs from the places down, a click goes to one. In the window's body, not its toolbar,
    /// as the HIG has path controls.
    private let pathRow = NSView()
    private let pathControl = NSPathControl()
    private var pathLocations: [BrowserLocation] = []
    /// The path bar shown under a folder (the app's setting); a source's page has none.
    public var showsPathBar = true {
        didSet { if showsPathBar != oldValue { updatePathBar() } }
    }
    private let message = HomeMessageView()
    /// A source's empty hint, in the middle.
    private let hint = NSTextField(labelWithString: "")
    /// The page on screen (a source's `info.page`), kept as a subview while hidden.
    var page: NSView?
    private let toast = ChromeToastView(style: .window)
    private var toastLine: String?
    private(set) var renameField: BrowserRenameField?
    let document = FlippedView()
    private(set) var grid = GridLayout(sections: [], width: 0, target: 220, names: .off)
    private var sections: [GridSection] = []
    var gridWidth: CGFloat = 0
    /// The cards on screen by entry index, and the ones put aside (a pool for each kind).
    private var live: [Int: GridCard] = [:]
    private var photoPool: [PhotoCard] = []
    private var collectionPool: [CollectionCard] = []
    private var posterPool: [PosterCard] = []
    private var compactPool: [CompactCard] = []
    private var filePool: [FileCard] = []
    var rowPool: [ListRow] = []
    /// The column heads over the list's rows; made with the first list.
    var listHeader: ListHeader?
    /// The list's container under its rows.
    var listPlate: ListPlate?
    /// How the folders and archives of this location are drawn, from the source; a narrow column shows posters anyway.
    /// The style of this folder's cards (the View menu's checkmark).
    public internal(set) var cardStyle = CardStyle.posters
    /// The facts that came after the listing, by id: they outlive a new listing of the same place, which may not carry
    /// them yet. Cleared on a move.
    private var summaries: [String: CardSummary] = [:]
    /// The cards the source gave up on (`stopWaiting`): nothing more will come for them in this location.
    private var givenUp: Set<String> = []
    private var headers: [GridHeader] = []
    private let footer = GridFooter()
    private var lastWanted: [String] = []
    /// The visible ids last sent, and the send of the margin that waits for scrolling to stop.
    private var lastVisibleSent: [String] = []
    private var marginTask: Task<Void, Never>?
    /// Scrolling must pause this long before the margin around the view is asked for.
    var marginDelay: Duration = .milliseconds(150)
    /// The margin ask waiting for `marginDelay`, for tests to send at once (`sendMarginNow`).
    private var pendingMargin: (all: [String], visible: Int)?

    public init(source: HomeSource) {
        self.source = source
        super.init(frame: .zero)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document
        scroll.onResize = { [weak self] step in self?.onResize?(step) }
        scroll.onUserScroll = { [weak self] in self?.dropRestore() }
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification,
                                               object: scroll.contentView)
        toast.translatesAutoresizingMaskIntoConstraints = false
        skeleton.translatesAutoresizingMaskIntoConstraints = false
        hint.font = Chrome.Text.font(.title, weight: .regular)
        hint.textColor = .secondaryLabelColor
        hint.isHidden = true
        hint.translatesAutoresizingMaskIntoConstraints = false
        statusBar.material = .underWindowBackground
        statusBar.blendingMode = .withinWindow
        statusBar.state = .followsWindowActiveState
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.maximumNumberOfLines = 1
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        pathControl.pathStyle = .standard
        pathControl.controlSize = .small
        pathControl.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        pathControl.backgroundColor = .clear
        pathControl.focusRingType = .none
        pathControl.refusesFirstResponder = true
        pathControl.target = self
        pathControl.action = #selector(pathItemClicked(_:))
        pathControl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pathControl.translatesAutoresizingMaskIntoConstraints = false
        pathRow.addSubview(pathControl)
        statusRow.addSubview(statusLabel)
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        statusBar.addSubview(line)
        let rows = NSStackView(views: [pathRow, statusRow])
        rows.orientation = .vertical
        rows.spacing = 0
        rows.translatesAutoresizingMaskIntoConstraints = false
        statusBar.addSubview(rows)
        document.addSubview(footer)
        // The grid runs under the toolbar, as in Photos; the skeleton starts below it.
        loading.translatesAutoresizingMaskIntoConstraints = false
        for view in [scroll, skeleton, hint, loading, message, toast, statusBar] { addSubview(view) }
        NSLayoutConstraint.activate([
            loading.leadingAnchor.constraint(equalTo: leadingAnchor), loading.trailingAnchor.constraint(equalTo: trailingAnchor),
            loading.heightAnchor.constraint(equalToConstant: 2), loadingBottom, skeletonTop,
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            skeleton.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            skeleton.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            skeleton.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            statusBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            rows.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor),
            line.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor),
            line.topAnchor.constraint(equalTo: statusBar.topAnchor),
            rows.topAnchor.constraint(equalTo: statusBar.topAnchor),
            rows.bottomAnchor.constraint(equalTo: statusBar.bottomAnchor),
            pathRow.widthAnchor.constraint(equalTo: rows.widthAnchor),
            pathRow.heightAnchor.constraint(equalToConstant: 24),
            pathControl.leadingAnchor.constraint(equalTo: pathRow.leadingAnchor, constant: 10),
            pathControl.trailingAnchor.constraint(lessThanOrEqualTo: pathRow.trailingAnchor, constant: -8),
            pathControl.centerYAnchor.constraint(equalTo: pathRow.centerYAnchor),
            statusRow.widthAnchor.constraint(equalTo: rows.widthAnchor),
            statusRow.heightAnchor.constraint(equalToConstant: 24),
            statusLabel.leadingAnchor.constraint(equalTo: statusRow.leadingAnchor, constant: 14),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusRow.trailingAnchor, constant: -14),
            statusLabel.centerYAnchor.constraint(equalTo: statusRow.centerYAnchor),
            message.centerXAnchor.constraint(equalTo: centerXAnchor), message.centerYAnchor.constraint(equalTo: centerYAnchor),
            hint.centerXAnchor.constraint(equalTo: centerXAnchor), hint.centerYAnchor.constraint(equalTo: centerYAnchor),
            message.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -32),
            toast.centerXAnchor.constraint(equalTo: centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: statusBar.topAnchor, constant: -24),
            toast.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -64),
        ])
        toolbar.show(style: style)
        toolbar.show(cardSize: cardSize, range: cardSizeRange)
        toolbar.onCrumb = { [weak self] location in self?.show(location, selecting: nil) }
        toolbar.onBack = { [weak self] in self?.goBack() }
        toolbar.onForward = { [weak self] in self?.goForward() }
        toolbar.onSortKey = { [weak self] key in self?.sortKeyChosen(key) }
        toolbar.onCardStyle = { [weak self] style in self?.chooseCardStyle(style) }
        toolbar.onZoom = { [weak self] step in self?.onResize?(step) }
        toolbar.onStyle = { [weak self] style in self?.onStyle?(style) }
        toolbar.onKind = { [weak self] kind in self?.filterChanged { $0.kind = kind } }
        toolbar.onPageFilter = { [weak self] i in
            guard let self, case .source(let id) = self.location else { return }
            self.source?.pageFilterChosen(i, in: id)
        }
        toolbar.onFilterText = { [weak self] text in self?.filterChanged { $0.text = text } }
        toolbar.onPathMenu = { [weak self] in self?.listSiblings() }
        toolbar.onSiblings = { [weak self] i in self?.siblingsAsked(i) }
        toolbar.onSiblingsClosed = { [weak self] in self?.siblingTask?.cancel() }
        toolbar.progress.onPause = { [weak self] on in
            guard let self else { return }
            self.source?.pauseThumbs(on, in: self.location)
        }
        toolbar.progress.onPrepare = { [weak self] in
            guard let self else { return }
            self.source?.prepareSubtree(of: self.location)
        }
        toolbar.progress.onStopSubtree = { [weak self] in
            guard let self else { return }
            self.source?.stopSubtree(in: self.location)
        }
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

    /// Opens `location` and selects `selecting` there (nil: what was selected there last time). The folder already on
    /// screen with its complete listing (the viewer going back to it) keeps its cards and pictures: `selecting` is
    /// selected at once and the folder is listed again behind them (`refresh`). `anchor`: a session's scroll, in place
    /// of the one remembered for the place.
    public func show(_ location: BrowserLocation, selecting: String?, anchor: BrowserAnchor? = nil) {
        if hasShown, location == self.location, hasComplete, page == nil, !isShowingMessage {
            return refresh(selecting: selecting)
        }
        if hasShown {
            rememberPlace()
            history.go(to: location)
        } else {
            history = BrowserHistory(start: location)
            hasShown = true
        }
        unavailable = []
        unseen = []
        paired = []
        facts = [:]
        pendingSelection = selecting ?? history.selection(for: location)
        pendingScroll = selecting == nil && anchor == nil ? history.scroll(for: location) : nil
        pendingAnchor = anchor
        restoredScroll = anchor != nil
        load()
    }

    /// The place on screen shown again without wiping it: the cards, their pictures, facts, the filter, the scroll and
    /// the progress stay; `selecting` (nil: the selection as it is) is selected now, or once a listing has it. The
    /// listing already open goes on (the app relists into it: its watcher's re-read when the viewer goes), so nothing
    /// is listed twice at once; only a stream that has ended is opened again. A names-only part changes nothing
    /// (`apply`); a complete one replaces the entries by id.
    private func refresh(selecting: String?) {
        siblingTask?.cancel()
        if let selecting {
            if indexByID[selecting] != nil {
                pendingSelection = nil
                select(id: selecting)
            } else {
                pendingSelection = selecting
            }
            pendingScroll = nil
        }
        if !isListing { subscribe(generation) }
        onLocation?(location)
        onMoved?(location)
        // Its listing is complete as it is: the sidebar may list the path now.
        onListingComplete?(location, listing?.entries ?? [])
    }

    /// The source's listings of the place on screen, as they come, until the next move (`generation`).
    private func subscribe(_ generation: Int) {
        guard let stream = source?.list(location) else { return }
        isListing = true
        listTask = Task { @MainActor [weak self] in
            do {
                for try await listing in stream {
                    guard let self, self.generation == generation else { return }
                    self.received(listing)
                }
                if let self, self.generation == generation { self.isListing = false }
            } catch {
                guard let self, self.generation == generation else { return }
                self.isListing = false
                self.listFailed(error)
            }
        }
    }

    /// The stream of the place on screen is still open (`subscribe`).
    private var isListing = false

    /// A listing from the source's stream: the one already on screen again (the kept listing drawn at the move, then
    /// delivered by the stream) changes nothing.
    private func received(_ new: BrowserListing) {
        if new.complete, hasComplete, let listing, listing.complete, listing.more == new.more,
           listing.entries == new.entries {
            // The share's listing is the one kept: nothing to redraw, the checking ends.
            if listing.isProvisional, !new.isProvisional {
                self.listing = new
                endChecking(new)
            }
            return
        }
        apply(new)
    }

    /// The listing on screen was kept by the app and is not checked yet (`BrowserListing.isProvisional`).
    var isChecking: Bool { listing?.isProvisional == true }

    /// The share's complete listing replaced a kept one: the pictures are asked again (with the stamps now known) and
    /// the sidebar has the folder's checked entries.
    private func endChecking(_ new: BrowserListing) {
        lastWanted = []
        lastVisibleSent = []
        onListingComplete?(location, new.entries)
        updateLoading()
        updateSubtitle()
    }

    /// The window closes: no more listing, timers or toasts.
    public func stop() {
        generation += 1
        listTask?.cancel()
        isListing = false
        orderCount += 1
        orderPending = nil
        loadingTask?.cancel()
        toast.hide()
        slowTask?.cancel()
        loading.run(false)
        skeleton.stop()
        endRename()
        resetProgress()
    }

    /// The places again (a volume came or went), if they are on screen.
    public func reloadPlaces() {
        if location == .places { load() }
    }

    /// The location on screen listed again, its selection, scroll and name filter kept (the app's list changed).
    public func reload() {
        freeSpaceAsked.remove(location)
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
        pendingAnchor = nil
        restoredScroll = false
        history.remember(selection: selectedID, scroll: scroll.contentView.bounds.origin.y)
    }

    private func load(keepingFilter: Bool = false) {
        generation += 1
        let generation = generation
        listTask?.cancel()
        isListing = false
        siblingTask?.cancel()
        dropSiblingLists()
        orderCount += 1
        orderPending = nil
        loadingTask?.cancel()
        listing = nil
        hasComplete = false
        anchorsNextShow = false
        footerText = ("", nil)
        containerCount = 0
        askFreeSpace()
        // A filter is for the place it was set in: a move starts with everything shown. The progress pill was the old
        // folder's: it goes out at once (a reload of the same place keeps both).
        if !keepingFilter {
            filter = BrowserFilter()
            toolbar.filterText = ""
            resetProgress()
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
        // A saved sort by date or size: the names in Finder's order until the dates and sizes come, then once in it.
        heldSort = sort.key == .name ? nil : .standard
        cardStyle = source?.cardStyle(for: location) ?? .posters
        summaries = [:]
        givenUp = []
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
            subscribe(generation)
        }
        updateBar()
        if !keepingFilter { takeKeysBack() }
        if location != lastLoaded {
            source?.moved(from: lastLoaded, to: location)
            lastLoaded = location
        }
        onLocation?(location)
        onMoved?(location)
        // A place visited earlier: its kept listing now, in this turn, after the move was told (its completeness is
        // told to the sidebar after it), not after the stream's hops.
        if page == nil, self.generation == generation, let kept = source?.lastListing(for: location), kept.complete {
            apply(kept)
        }
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
                addSubview(new, positioned: .below, relativeTo: loading)
                let top = new.topAnchor.constraint(equalTo: topAnchor, constant: topInset)
                pageTop = top
                NSLayoutConstraint.activate([
                    new.leadingAnchor.constraint(equalTo: leadingAnchor), new.trailingAnchor.constraint(equalTo: trailingAnchor),
                    top, new.bottomAnchor.constraint(equalTo: bottomAnchor),
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
        let before = shownSort
        let checked = new.complete && !new.isProvisional && isChecking
        listing = new
        if checked { endChecking(new) }
        if new.complete, !hasComplete {
            hasComplete = true
            // Pictures asked with names only are asked again: the app makes thumbnails of files whose date and size
            // it knows.
            lastWanted = []
            lastVisibleSent = []
            onListingComplete?(location, new.entries)
            if before != nil, before != shownSort { anchorsNextShow = true }
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
        /// The order it is in.
        var sort: BrowserSort
    }

    /// What arranging a source's list needs of its `info`: the footer's noun and whether it is under date headings.
    struct ArrangeInfo: Sendable {
        var noun: String?
        var groupsByDate: Bool
        var fileNoun = "photo"
    }

    private var arrangeInfo: ArrangeInfo {
        ArrangeInfo(noun: info?.noun, groupsByDate: info?.groupsByDate == true && shownSort?.key == .date,
                    fileNoun: files.noun)
    }

    /// Off the main actor for a big listing: nothing here touches the view.
    nonisolated static func arrange(_ listing: BrowserListing, sort: BrowserSort, filter: BrowserFilter,
                                    info: ArrangeInfo = ArrangeInfo(noun: nil, groupsByDate: false)) -> Arranged {
        let ordered = filter.apply(sort.order(listing.entries))
        let containers = ordered.firstIndex { $0.isFile } ?? ordered.count
        let summary = BrowserSummary.footer(entries: listing.entries, filtered: filter.isActive ? ordered.count : nil,
                                            complete: listing.complete, more: listing.more, noun: info.noun,
                                            fileNoun: info.fileNoun)
        let groups = info.groupsByDate ? DateGroups.sections(ordered.map(\.date), now: Date(), calendar: .current) : nil
        return Arranged(entries: ordered, containers: containers, footer: summary.line, state: summary.state,
                        dateSections: groups, sort: sort)
    }

    /// `listing`'s entries in order on screen, the selection and scroll kept or restored.
    private func show(_ arranged: Arranged, of new: BrowserListing) {
        loadingTask?.cancel()
        let anchor = anchorsNextShow ? viewAnchor() : nil
        anchorsNextShow = false
        let old = selectedID.flatMap { indexByID[$0] }
        footerText = (arranged.footer, arranged.state)
        containerCount = arranged.containers
        dateSections = arranged.dateSections
        setEntries(arranged.entries)
        if let field = renameField, indexByID[field.entryID] == nil { endRename() }
        if let wanted = pendingSelection, indexByID[wanted] != nil {
            pendingSelection = nil
            select(id: wanted, scrolls: pendingScroll == nil && !restoredScroll)
        } else if let id = selectedID, indexByID[id] != nil {
            select(id: id, scrolls: false)
        } else if !entries.isEmpty {
            select(id: entries[min(old ?? 0, entries.count - 1)].id, scrolls: false)
        }
        // A scroll remembered for the place is for its own order, not the held one.
        if let y = pendingScroll, !entries.isEmpty, arranged.sort == sort {
            pendingScroll = nil
            scrollGrid(to: y)
        } else if let anchor, let i = indexByID[anchor.id] {
            scrollGrid(to: grid.frame(of: i).minY - anchor.offset)
        } else if let saved = pendingAnchor, arranged.sort == sort, indexByID[saved.id] != nil || !new.more {
            // The entry, or once the names are all there, the one at its index; none, the top.
            pendingAnchor = nil
            if let i = saved.target(count: entries.count, index: { indexByID[$0] }) {
                scrollGrid(to: grid.frame(of: i).minY - CGFloat(saved.offset))
            }
        }
        updateSubtitle()
    }

    /// The selected card when it is in view, else the first card in view, and how far below the view's top it is; none
    /// while the grid is at its top (it stays there, on the new order's first cards).
    private func viewAnchor() -> (id: String, offset: CGFloat)? {
        guard scroll.contentView.bounds.origin.y > 0 else { return nil }
        let visible = visibleIDs
        guard let id = selectedID.flatMap({ visible.contains($0) ? $0 : nil }) ?? visible.first,
              let i = indexByID[id] else { return nil }
        return (id, grid.frame(of: i).minY - scroll.contentView.bounds.origin.y)
    }

    /// Under the path: while names come, how many; else the selected card; else the footer line.
    private func updateSubtitle() {
        let loading = listing?.more == true ? listing?.entries.count : nil
        var line = loading.map { "Loading… \(BrowserSummary.number($0))" } ?? footerText.line
        if loading == nil, let state = footerText.state, !state.isEmpty {
            line = [line, state].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        // The room the volume has goes at the end of every line but the count of names still coming.
        if loading == nil, !line.isEmpty, let room = VolumeSpace.line(free: freeSpace[location]) { line += " · " + room }
        if isChecking { line = line.isEmpty ? "Checking…" : "Checking… · " + line }
        toolbar.show(subtitle: line)
        let selected = loading == nil ? BrowserSummary.selection(selectedEntry, fileNoun: files.noun) : ""
        statusLabel.stringValue = selected.isEmpty ? line : selected
        statusRow.isHidden = statusLabel.stringValue.isEmpty
        statusBar.isHidden = statusRow.isHidden && pathRow.isHidden
    }

    /// The path bar from the crumbs: under a folder and the places, not on a source's page.
    private func updatePathBar() {
        let crumbs = info == nil && showsPathBar ? path() : []
        pathLocations = crumbs.map(\.location)
        pathControl.pathItems = crumbs.indices.map { i in
            let item = NSPathControlItem()
            item.title = crumbs[i].title
            item.image = Self.pathIcon(crumbs[i].location == .places ? .places : i == 1 ? .volume : .folder)
            return item
        }
        pathRow.isHidden = crumbs.isEmpty
        statusBar.isHidden = statusRow.isHidden && pathRow.isHidden
    }

    private enum PathIcon { case places, volume, folder }

    /// Finder's icons by kind, not each folder's own: nothing is read from a share to draw the bar.
    private static func pathIcon(_ kind: PathIcon) -> NSImage {
        switch kind {
        case .places: placesIcon
        case .volume: volumeIcon
        case .folder: folderIcon
        }
    }

    private static let placesIcon = smallIcon(NSImage(named: NSImage.computerName) ?? NSWorkspace.shared.icon(for: .volume))
    private static let volumeIcon = smallIcon(NSWorkspace.shared.icon(for: .volume))
    private static let folderIcon = smallIcon(NSWorkspace.shared.icon(for: .folder))

    private static func smallIcon(_ icon: NSImage) -> NSImage {
        let image = icon.copy() as! NSImage
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    @objc private func pathItemClicked(_ sender: NSPathControl) {
        guard let item = sender.clickedPathItem, let i = sender.pathItems.firstIndex(of: item) else { return }
        goToPathItem(i)
    }

    /// Path bar item `i`: its folder, unless it is the one shown.
    func goToPathItem(_ i: Int) {
        guard pathLocations.indices.contains(i), pathLocations[i] != location else { return }
        show(pathLocations[i], selecting: nil)
    }

    var selectionInfoText: String { statusLabel.stringValue }

    /// The bytes free on the volume of each folder shown, from the source's answer; the folders asked already (an answer
    /// that did not come is not asked for again until `reload`).
    private var freeSpace: [BrowserLocation: Int64] = [:]
    private var freeSpaceAsked: Set<BrowserLocation> = []

    /// Asks the source how much room the volume of the folder on screen has, once for each folder.
    private func askFreeSpace() {
        guard case .folder = location, let source, freeSpaceAsked.insert(location).inserted else { return }
        let asked = location
        Task(priority: .utility) { @MainActor [weak self] in
            guard let room = await source.freeSpace(for: asked), let self else { return }
            self.freeSpace[asked] = room
            if self.location == asked { self.updateSubtitle() }
        }
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
        loading.run((!hasComplete || isChecking) && !failed)
        let showSkeleton = entries.isEmpty && !hasComplete && !failed
        skeleton.isHidden = !showSkeleton
        // Started on the first load too: the skeleton is not hidden before it.
        if showSkeleton != skeleton.isActive {
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
    /// The entries of that complete listing (none before it), unfiltered.
    var completeEntries: [BrowserEntry] { hasComplete ? listing?.entries ?? [] : [] }
    var isShowingLoadingLine: Bool { loading.isRunning }
    var isSkeletonMoving: Bool { skeleton.isMoving }
    var isShowingSkeleton: Bool { !skeleton.isHidden }
    var skeletonPictureFrames: [CGRect] { skeleton.pictureFrames }
    var slowText: String? { slowCaption.map { "\($0.0)\n\($0.1)" } }

    /// The folder could not be listed: why, in place of the grid; Up and Back still work. After its complete listing
    /// (a relist behind the grid failed: the share dropped) the grid stays and the failure is a toast.
    private func listFailed(_ error: Error) {
        loadingTask?.cancel()
        guard case .folder(let url) = location else { return }
        if hasComplete {
            // A kept listing stays, unchecked: the toast says why, the checking line goes.
            listing?.isProvisional = false
            showToast("Could not list \(url.lastPathComponent): \(error.localizedDescription)")
            updateSubtitle()
            return updateLoading()
        }
        toolbar.show(subtitle: "")
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

    // MARK: Progress

    /// The pill goes out this long after the work is done (the spec's 1 s).
    var progressHideAfter: Duration = .seconds(1)
    /// How long a state with nothing being prepared must hold before it counts: it then drops a show still waiting for
    /// its delay, or starts the pill's going out. Basis: the source sends at most four states a second
    /// (`FolderBrowserSource.progressInterval`, 250 ms) and a scroll's new ask can leave one of them with the work
    /// ahead briefly all done (the ask replaces it); 0.5 s is two updates, so one such blip never counts, while the
    /// pill still goes out 1.5 s after the work really ended.
    var progressGrace: Duration = .milliseconds(500)
    /// The latest state while the pill waits for its delay.
    private var pendingProgress: ThumbsProgressState?
    /// The wait before the pill shows, or, once it shows, before it goes out; one cancellable task, no timer.
    private var progressTask: Task<Void, Never>?
    /// Running while a non-working state is within its grace (`progressGrace`).
    private var progressGraceTask: Task<Void, Never>?
    /// The delay ran out while the work was within its grace: the pill lights as soon as work comes back in it.
    private var progressDelayOver = false

    /// Whether the pill is lit (a narrow toolbar may still leave it out).
    var isShowingProgress: Bool { toolbar.progressState != nil }

    /// How far the thumbnails of the folder on screen are; nil or not `working`: all done. The pill shows only after
    /// `delay` of continuous work (a folder served from the catalog finishes sooner and never lights it), follows every
    /// state while lit, and goes out `progressHideAfter` (1 s) after the work is done. A non-working state counts only
    /// once it has held for `progressGrace`: work back within it keeps the pill, and a pending show's clock. The popover
    /// (the pill's, or View › Thumbnails…'s with the pill out) shows the latest state given, done or not. A move to
    /// another folder puts the pill out at once and leaves the popover at zeros until that folder's state comes.
    public func setProgress(_ state: ThumbsProgressState?, delay: Duration) {
        toolbar.show(progressDetail: state)
        guard let state, state.working else { return progressMayHaveStopped() }
        progressGraceTask?.cancel()
        progressGraceTask = nil
        if isShowingProgress {
            // Lit (perhaps counting down to going out): new work keeps it.
            progressTask?.cancel()
            progressTask = nil
            toolbar.show(progress: state)
            return
        }
        if progressDelayOver {
            progressDelayOver = false
            pendingProgress = nil
            toolbar.show(progress: state)
            return
        }
        pendingProgress = state
        guard progressTask == nil else { return }   // the delay runs from the first state, not the latest
        guard delay > .zero else {
            pendingProgress = nil
            toolbar.show(progress: state)
            return
        }
        progressTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, let state = self.pendingProgress else { return }
            self.progressTask = nil
            // Within the grace the work may come back: it then lights the pill at once.
            if self.progressGraceTask != nil { return self.progressDelayOver = true }
            self.pendingProgress = nil
            self.toolbar.show(progress: state)
        }
    }

    /// A state with nothing being prepared: counted once it has held for `progressGrace` (from the first such state).
    private func progressMayHaveStopped() {
        guard progressGraceTask == nil else { return }
        let lit = isShowingProgress
        // Nothing waiting to show, or the pill already going out.
        guard lit ? progressTask == nil : pendingProgress != nil || progressDelayOver else { return }
        let grace = progressGrace
        progressGraceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: grace)
            guard let self, !Task.isCancelled else { return }
            self.progressGraceTask = nil
            self.progressStopped()
        }
    }

    /// The work stayed done through the grace: a show still waiting is dropped, a lit pill goes out after
    /// `progressHideAfter`.
    private func progressStopped() {
        pendingProgress = nil
        progressDelayOver = false
        progressTask?.cancel()
        progressTask = nil
        guard isShowingProgress else { return }
        let after = progressHideAfter
        progressTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: after)
            guard let self, !Task.isCancelled else { return }
            self.progressTask = nil
            self.toolbar.show(progress: nil)
        }
    }

    /// View › Thumbnails… can open the popover: whenever a folder is shown (its counts, zeros included, the pill lit or
    /// not); elsewhere while the pill is lit.
    public var canShowProgressPopover: Bool {
        if case .folder = location { return true }
        return isShowingProgress
    }

    /// View › Thumbnails…: the popover with the current counts, from the ring when it shows, else from the window's top.
    public func showProgressPopover() { toolbar.showProgressPopover(in: window) }

    private func resetProgress() {
        progressTask?.cancel()
        progressTask = nil
        pendingProgress = nil
        progressGraceTask?.cancel()
        progressGraceTask = nil
        progressDelayOver = false
        if isShowingProgress { toolbar.show(progress: nil) }
        toolbar.show(progressDetail: nil)
    }

    // MARK: Motion

    /// Waiting cards that shimmer at once at most, the first in view in the grid's order; the others in view keep
    /// still (the Reduce Motion look) until a slot frees or they scroll first. Basis: every shimmering card is a layer
    /// the window server redraws 60 times a second; a window of 220 pt posters shows about 20-30 cards, so 24 lets a
    /// usual screen of waiting folders all move, while small cards (60 pt: 130+ in view) never animate more than that.
    static let shimmerCap = 24
    /// Tests have no window: whether to count it as on screen.
    var windowVisibleForTests: Bool?

    /// The window is on screen (not minimized, not hidden with the app, not covered whole): only then does anything
    /// move (the cards' shimmer, the loading line, the skeleton's shine).
    private var isWindowVisible: Bool {
        windowVisibleForTests ?? (window?.occlusionState.contains(.visible) == true)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let center = NotificationCenter.default
        center.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        if let window {
            center.addObserver(self, selector: #selector(windowVisibilityChanged),
                               name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
        updateMotion()
    }

    @objc func windowVisibilityChanged() { updateMotion() }

    /// Home's other tab shows in a visible window: the browser hidden keeps still.
    public override func viewDidHide() {
        super.viewDidHide()
        updateMotion()
    }

    public override func viewDidUnhide() {
        super.viewDidUnhide()
        if tilesWhenShown {
            tilesWhenShown = false
            needsLayout = true
        }
        updateMotion()
    }

    /// A layout came while the browser was hidden (the window resized under a parked Home): the cards are laid out
    /// when it shows again, not for a size nobody sees.
    private var tilesWhenShown = false

    /// What may move: nothing while the window is off screen or the browser hidden; else the loading line, the
    /// skeleton, and the waiting cards in view, the first `shimmerCap` of them in the grid's order (the margin's and
    /// the pool's keep still).
    private func updateMotion() {
        let onScreen = isWindowVisible && !isHiddenOrHasHiddenAncestor
        loading.mayMove = onScreen
        skeleton.mayMove = onScreen
        var slots = onScreen ? Self.shimmerCap : 0
        let visible = scroll.contentView.documentVisibleRect
        for i in live.keys.sorted() {
            guard let card = live[i] as? FolderCard else { continue }
            let may = slots > 0 && card.isWaiting && grid.frame(of: i).intersects(visible)
            if may { slots -= 1 }
            card.mayShimmer = may
        }
    }

    // MARK: Toast

    /// A short line at the bottom for 3 s: an action that failed.
    /// A message over the grid, above the status line: one line, or several separated by "\n".
    public func showToast(_ text: String, for seconds: TimeInterval = 3) {
        toastLine = text
        toast.show(text, for: seconds)
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
        if let card = live[indexByID[field.entryID] ?? -1], card.nameFrame != .zero {
            let name = card.nameFrame
            field.place(over: CGRect(x: slot.minX + name.minX, y: slot.minY + name.minY, width: name.width,
                                     height: name.height))
            return
        }
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

    /// The kind filter or a keystroke in the name field: the listing again through the filter, off the main actor when
    /// it is big; a change while one is ordered drops that one's result.
    private func filterChanged(_ change: (inout BrowserFilter) -> Void) {
        var new = filter
        change(&new)
        guard new != filter else { return }
        filter = new
        orderCount += 1
        if let listing { apply(listing) }
    }

    /// A sort choice or ⌥1–3: the field, or the other direction of the active one. More shows it at
    /// once; a sort by date or size before the complete listing leaves the grid as it is until that listing comes.
    func sortKeyChosen(_ key: BrowserSort.Key) {
        guard sortKeys.contains(key) else { return }
        let before = shownSort
        source?.setSort(sortChoice.choose(key), for: location)
        heldSort = hasComplete ? nil : before
        toolbar.show(sort: sort, keys: sortKeys)
        listHeader?.sort = sort
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

    /// Sort menu fields here: a folder's three, a source's own, none at the places or on a page.
    var sortKeys: [BrowserSort.Key] {
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
        updatePathBar()
        toolbar.show(sort: sort, keys: sortKeys)
        toolbar.show(pageFilters: info?.pageFilters ?? [], selected: info?.pageFilters.isEmpty == false ? 0 : nil)
        toolbar.show(filter: filter.kind, visible: info == nil && location != .places)
        toolbar.show(controls: page == nil)
        showCardSwitch()
    }


    private var siblingTask: Task<Void, Never>?
    /// The folders beside each crumb, asked for one crumb after another (nearest first) as the path menu opens, and the
    /// ones that are in. A submenu shows its folders at once when they are in: an open menu does not widen for items
    /// added late, so a reply filled in after `Loading…` came out with every name cut in the middle.
    private var siblingLists: [Int: Task<[BrowserEntry], Never>] = [:]
    private var siblingsIn: [Int: [BrowserEntry]] = [:]
    private var siblingListsGeneration = -1

    /// The path menu opens: the folders beside its crumbs are asked for again while the pointer travels to one.
    private func listSiblings() {
        dropSiblingLists()
        for i in path().indices.reversed() { _ = siblingList(i) }
    }

    private func dropSiblingLists() {
        siblingLists.values.forEach { $0.cancel() }
        siblingLists = [:]
        siblingsIn = [:]
    }

    /// The folders beside crumb `i` (in their parent's sort), asked for after the crumb below it; nil for the first.
    private func siblingList(_ i: Int) -> Task<[BrowserEntry], Never>? {
        if siblingListsGeneration != generation {
            dropSiblingLists()
            siblingListsGeneration = generation
        }
        if let list = siblingLists[i] { return list }
        let crumbs = path()
        guard crumbs.indices.contains(i), i > 0 else { return nil }
        let parent = crumbs[i - 1].location
        let before = siblingLists[i + 1]   // one listing at a time
        let list = Task { @MainActor [weak self] () -> [BrowserEntry] in
            _ = await before?.value
            guard !Task.isCancelled, let source = self?.source else { return [] }
            let entries: [BrowserEntry]
            switch parent {
            case .places, .source: entries = await source.places()
            case .folder(let url): entries = source.sort(for: parent).order((try? await source.folders(in: url)) ?? [])   // an error: none
            }
            if !Task.isCancelled, self?.siblingLists[i] != nil { self?.siblingsIn[i] = entries }
            return entries
        }
        siblingLists[i] = list
        return list
    }

    /// The › before crumb `i`: its menu opens at once, with the folders beside that crumb when they are in, else with
    /// `Loading…` until the source answers; a reply after a move or after the menu closed is dropped.
    private func siblingsAsked(_ i: Int) {
        let crumbs = path()
        guard crumbs.indices.contains(i), let list = siblingList(i) else { return }
        let current = crumbs[i].location
        let shown = { (entries: [BrowserEntry]) in
            entries.map { (title: $0.name, location: BrowserLocation.folder($0.url), current: BrowserLocation.folder($0.url) == current) }
        }
        siblingTask?.cancel()
        if let entries = siblingsIn[i] {
            toolbar.showSiblings(shown(entries), at: i)
            return
        }
        let generation = generation
        siblingTask = Task { @MainActor [weak self] in
            let entries = await list.value
            guard let self, !Task.isCancelled, self.generation == generation else { return }
            self.toolbar.updateSiblings(shown(entries))
        }
        toolbar.showSiblings(nil, at: i)
    }

    /// The crumbs from the places down to here, by the source's parents.
    private func path() -> [(title: String, location: BrowserLocation)] {
        var crumbs: [(title: String, location: BrowserLocation)] = []
        var at = location
        for _ in 0..<64 {
            guard case .folder(let url) = at else { break }
            crumbs.append((url.path == "/" ? FileManager.default.displayName(atPath: "/") : url.lastPathComponent, at))
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
            document.scrollToVisible(CGRect(x: frame.minX, y: frame.minY - topInset - 8, width: frame.width,
                                            height: frame.height + topInset + 16))
        }
        updateSubtitle()
    }

    private func select(index: Int) {
        guard entries.indices.contains(index) else { return }
        dropRestore()
        select(id: entries[index].id)
    }

    /// The user scrolled or selected: a scroll and selection still waiting for their names (a session's, or one
    /// restored without an anchor) are dropped, so the grid does not jump away from what the user is doing.
    private func dropRestore() {
        pendingAnchor = nil
        pendingSelection = nil
        restoredScroll = false
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

    private func clicked(_ id: String, middle: Bool, flags: NSEvent.ModifierFlags, clickCount: Int) {
        if middle || flags.contains(.shift) || flags.contains(.command) {
            activate(id, HomeClick.from(shift: flags.contains(.shift), command: flags.contains(.command), middle: middle,
                                        supportsTabs: true))
            return
        }
        select(id: id, scrolls: false)
        if clickCount > 1 { activate(id, .open) }
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
    /// The digit keys 1 / 2 / 3: with ⌥ the first, second and third sort fields, with ⌥⌘ the card style (⌘
    /// alone is the app's: a window's tabs by number).
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
        // ⌥⌘1 / ⌥⌘2 / ⌥⌘3: Posters, Cards, List (the View menu's items have the same keys); ⌘1–⌘3 go on to the app.
        if flags == [.option, .command], let i = Self.sortKeyIndex[event.keyCode] {
            guard canChooseCardStyle else { return false }   // no folder cards here: the key is someone else's
            chooseCardStyle(CardStyle.allCases[i])
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
            if let id = selectedID {
                activate(id, HomeClick.from(shift: flags.contains(.shift), command: command, middle: false,
                                            supportsTabs: true))
            }
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
            // A photo whose picture cannot be made is gone past: its card stays, faint, for a click or Return.
            var next = grid.neighbour(of: current, d)
            while let candidate = next, entries.indices.contains(candidate), isUnavailable(entries[candidate]) {
                next = grid.neighbour(of: candidate, d)
            }
            if let next { select(index: next) }
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
        guard !isHiddenOrHasHiddenAncestor else {
            tilesWhenShown = true
            return
        }
        updateTopInset()   // AppKit lays the view out when the window's toolbar changes its safe area
        tile()
    }

    @objc private func scrolled() { tile() }

    /// The sections of what is on screen: at the top level one run of places; in a folder the containers, then the
    /// files, titled only when both are there.
    private func makeSections() -> [GridSection] {
        if let dateSections {
            // A source of files (a video app's Recent) is laid out as files; of collections, as collections.
            let kind: GridSection.Kind = !entries.isEmpty && entries.allSatisfy(\.isFile) ? .photos : .collections
            return dateSections.map { GridSection(kind: kind, count: $0.count, title: $0.title) }
        }
        guard case .folder = location else { return [GridSection(kind: .collections, count: entries.count)] }
        let files = entries.count - containerCount
        // In the list the headings go inside its container, between the folders' rows and the files' (owner,
        // 2026-10-23).
        let both = containerCount > 0 && files > 0
        return [GridSection(kind: .collections, count: containerCount, title: both ? "Folders" : nil),
                GridSection(kind: .photos, count: files,
                            title: both ? "\(self.files.heading) · \(BrowserSummary.number(files))" : nil)]
    }

    /// Cards for the rows in view and a screen either side; the others go back to their pool.
    func tile() {
        let width = scroll.contentSize.width > 0 ? scroll.contentSize.width : bounds.width
        gridWidth = width
        sections = makeSections()
        var metrics = GridMetrics()
        metrics.top = topInset
        // The list has its column heads under the toolbar, above the first row.
        let shownStyle = shownCardStyle(width: width)
        let showsListHeader = shownStyle == .list && !entries.isEmpty && isShowingEntries
        if showsListHeader { metrics.top += ListHeader.height }
        grid = GridLayout(sections: sections, width: width, target: cardSize, names: names, style: shownStyle,
                          fileAspect: files.aspect, factsLine: files.factsLine, metrics: metrics)
        // At least the view's height less the inset AppKit gives the scroll view under the toolbar: as tall as the
        // whole view, a grid that fits scrolled by that inset and kept a legacy scroller (a mouse plugged in).
        let insets = scroll.contentInsets
        let height = max(grid.contentHeight, scroll.contentSize.height - insets.top - insets.bottom)
        if document.frame.size != CGSize(width: width, height: height) {
            document.frame = CGRect(x: 0, y: 0, width: width, height: height)
            // A legacy scroller shows or hides for the new height and takes its width now, not at the next layout:
            // laid out at the old width, the cards would move under a scroll just set from their frames (a session's
            // anchor). A narrower grid is only taller, so the second pass keeps the scroller as it is.
            scroll.tile()
            if scroll.contentSize.width != width { return tile() }
        }
        let visible = scroll.contentView.documentVisibleRect
        let range = grid.indices(in: visible, margin: max(visible.height, 1))
        // A card goes with its entry to the entry's slot now (a new order, a filter, names before it), its picture and
        // closures kept; one whose entry left the range, or whose slot is of the other kind now, goes back to its pool.
        let wantedIDs = Set(lastWanted)
        var newlyConfigured = false
        var kept: [Int: GridCard] = [:]
        for card in live.values {
            if let i = indexByID[card.item.id], range.contains(i), kept[i] == nil,
               kind(of: i) == kind(of: card) {
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
                let card: GridCard
                switch kind(of: i) {
                case .poster: card = posterPool.popLast() ?? makePoster()
                case .compact: card = compactPool.popLast() ?? makeCompact()
                case .row: card = rowPool.popLast() ?? makeRow()
                case .collection: card = collectionPool.popLast() ?? makeCollection()
                case .photo: card = photoPool.popLast() ?? makePhoto()
                case .file: card = filePool.popLast() ?? makeFile()
                }
                configure(card, entry)
                card.isHidden = false
                live[i] = card
                // The card the ask was sent for is gone (a density switch remakes it, picture and all): ask again.
                if wantedIDs.contains(entry.id) { newlyConfigured = true }
            }
            let card = live[i]!
            card.fileNoun = files.noun
            let section = grid.section(of: i)
            if let photo = card as? PhotoCard {
                photo.style = style
                photo.names = names
                photo.aspect = files.aspect
                photo.showsFacts = files.facts
                photo.showsFactsLine = files.factsLine
                photo.showsNames = grid.showsNames(inSection: section)
            } else if let collection = card as? CollectionCard {
                collection.names = names
            } else if let file = card as? FileCard {
                file.aspect = files.aspect
            }
            if let row = card as? ListRow { row.showsSeparator = i < entries.count - 1 }
            // Straight to the slot: a view's frame animates only in an animation group that allows it (the sidebar's).
            card.frame = grid.frame(of: i)
        }
        if newlyConfigured {
            lastWanted = []
            lastVisibleSent = []
        }
        placeHeaders()
        placeListHeader(showsListHeader, width: width)   // over the rows just made: it stays at the top
        let summary = footerText.state.map { [footerText.line, $0] } ?? [footerText.line]
        footer.show(lines: isShowingEntries ? summary.filter { !$0.isEmpty } : [])
        footer.frame = grid.footerFrame
        placeRenameField()
        askImages()
        updateMotion()
    }

    private func isCollection(_ i: Int) -> Bool { !entries[i].isFile }

    private enum CardKind { case poster, compact, row, collection, photo, file }

    /// A folder or archive in a folder is a poster, a compact card or a row; in the list the files are rows too. The
    /// rest of the containers (places, the app's collections) keep the collection card; files are photos.
    private func kind(of i: Int) -> CardKind {
        let entry = entries[i]
        let style = shownCardStyle(width: gridWidth)
        guard !entry.isFile else { return style == .list ? .row : style == .cards ? .file : .photo }
        guard entry.kind == .folder || entry.kind == .archive else { return .collection }
        switch style {
        case .posters: return .poster
        case .cards: return .compact
        case .list: return .row
        }
    }

    private func kind(of card: GridCard) -> CardKind {
        switch card {
        case is PosterCard: .poster
        case is CompactCard: .compact
        case is ListRow: .row
        case is CollectionCard: .collection
        case is FileCard: .file
        default: .photo
        }
    }

    private func putAside(_ card: GridCard) {
        card.isHidden = true
        (card as? FolderCard)?.mayShimmer = false
        card.image = nil
        if let photo = card as? PhotoCard { photoPool.append(photo) }
        if let collection = card as? CollectionCard { collectionPool.append(collection) }
        if let poster = card as? PosterCard { posterPool.append(poster) }
        if let compact = card as? CompactCard { compactPool.append(compact) }
        if let file = card as? FileCard { filePool.append(file) }
        if let row = card as? ListRow { rowPool.append(row) }
    }

    private func placeHeaders() {
        let titled = sections.indices.compactMap { s in grid.headerFrame(ofSection: s).map { (sections[s].title ?? "", $0) } }
        while headers.count < titled.count {
            let header = GridHeader()
            document.addSubview(header)
            headers.append(header)
        }
        // In the list the headings sit inside the container: their text in line with the rows' covers.
        let m = GridMetrics()
        let inset = shownCardStyle(width: gridWidth) == .list ? m.collectionEdge + m.listPadding : m.collectionEdge
        for (i, header) in headers.enumerated() {
            header.isHidden = i >= titled.count
            guard i < titled.count else { continue }
            header.title = titled[i].0
            header.inset = inset
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

    private func makePoster() -> PosterCard {
        let card = PosterCard(item: HomeCardItem(id: "", title: "", tooltip: "", symbol: "folder"))
        document.addSubview(card)
        return card
    }

    private func makeFile() -> FileCard {
        let card = FileCard(item: HomeCardItem(id: "", title: "", tooltip: "", symbol: "doc"))
        document.addSubview(card)
        return card
    }

    private func makeCompact() -> CompactCard {
        let card = CompactCard(item: HomeCardItem(id: "", title: "", tooltip: "", symbol: "folder"))
        document.addSubview(card)
        return card
    }

    private func configure(_ card: GridCard, _ entry: BrowserEntry) {
        card.show(item(for: entry))
        card.image = nil
        card.isSelected = entry.id == selectedID
        if let photo = card as? PhotoCard {
            photo.isUnseen = unseen.contains(entry.id)
            photo.isPaired = paired.contains(entry.id)
        }
        let id = entry.id
        card.onClick = { [weak self] middle, flags, clickCount in
            self?.clicked(id, middle: middle, flags: flags, clickCount: clickCount)
        }
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
            subtitle = entry.count.map { CardSummaryText.count($0, files.noun) }
        case .file:
            switch (shownSort ?? sort).key {
            case .name: subtitle = nil
            case .date: subtitle = entry.date.map(Self.dateFormat.string)
            case .size: subtitle = entry.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
            }
        case .place, .collection:
            subtitle = nil
        }
        let summary = entry.summary ?? summaries[entry.id]
        // With the files' facts on their pictures, a file's line is only its own (a video's length), never the sort's.
        let line = files.facts && entry.isFile ? entry.subtitle : entry.subtitle ?? subtitle
        return HomeCardItem(id: entry.id, title: entry.name, subtitle: line,
                            tooltip: entry.kind == .collection ? entry.name : entry.url.path,
                            symbol: source?.symbol(for: entry) ?? "doc", progress: entry.progress,
                            badge: entry.badge ?? (entry.kind == .archive ? "ZIP" : nil),
                            isDimmed: entry.isDimmed || isUnavailable(entry)
                                || (summary?.problem == .offline && entry.kind != .folder
                                                                        && entry.kind != .archive),
                            menu: source?.menu(for: entry, in: location) ?? [], glassSymbol: entry.kind == .place,
                            summary: summary, count: entry.count,
                            format: entry.isFile && !entry.url.pathExtension.isEmpty ? entry.url.pathExtension.uppercased() : nil,
                            date: entry.date, bytes: entry.size, facts: entry.facts ?? facts[entry.id],
                            waiting: waits(entry, summary: summary))
    }

    /// Whether the source may still send the card's facts or cover (`HomeCardItem.waiting`): a folder or an archive in
    /// reach, of a source that sends facts, not given up on, without facts or with facts that expect a cover (no
    /// problem, photos here or inside).
    private func waits(_ entry: BrowserEntry, summary: CardSummary?) -> Bool {
        guard source?.sendsCardFacts == true, entry.kind == .folder || entry.kind == .archive, !entry.isDimmed,
              !givenUp.contains(entry.id) else { return false }
        guard let summary else { return true }
        return summary.problem == nil && ((summary.photos ?? 0) > 0 || (summary.insidePhotos ?? 0) > 0)
    }

    /// The source will send nothing more for these cards (its cover queue gave up, or a folder has no cover to give):
    /// they stop waiting and show what they have. Ids not in the listing are ignored; a new location forgets them.
    public func stopWaiting(for ids: [String]) {
        for id in ids {
            guard let i = indexByID[id] else { continue }
            givenUp.insert(id)
            guard let card = live[i], card.item.id == id else { continue }
            let item = item(for: entries[i])
            if card.item != item { card.show(item) }
        }
        updateMotion()
    }

    /// The source works on these cards again (a refreshed cover): those it gave up on wait again, shimmering, until
    /// their facts and cover come or it gives up once more.
    public func resumeWaiting(for ids: [String]) {
        for id in ids where givenUp.remove(id) != nil {
            guard let i = indexByID[id], let card = live[i], card.item.id == id else { continue }
            let item = item(for: entries[i])
            if card.item != item { card.show(item) }
        }
        updateMotion()
    }

    /// The live cards without a picture, those in view first. The visible ones go to the source at once; the margin
    /// around them only after 150 ms without a bounds change, so a fast scroll does not queue what it passes.
    private func askImages() {
        let visible = visibleIDs
        let shown = Set(visible)
        let rest = live.keys.sorted().map { entries[$0].id }.filter { !shown.contains($0) }
        func lacksImage(_ id: String) -> Bool { indexByID[id].flatMap { live[$0] }?.image == nil }
        let visibleWanted = visible.filter(lacksImage)
        let marginWanted = rest.filter(lacksImage)
        marginTask?.cancel()
        marginTask = nil
        pendingMargin = nil
        if visibleWanted != lastVisibleSent {
            lastVisibleSent = visibleWanted
            if !visibleWanted.isEmpty, visibleWanted + marginWanted != lastWanted {
                lastWanted = visibleWanted
                source?.wantImages(visibleWanted, visible: visibleWanted.count, width: slotWidth)
            }
        }
        guard !marginWanted.isEmpty, visibleWanted + marginWanted != lastWanted else { return }
        let all = visibleWanted + marginWanted
        pendingMargin = (all, visibleWanted.count)
        marginTask = Task { @MainActor [weak self] in
            guard let delay = self?.marginDelay else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.sendMarginNow()
        }
    }

    /// Sends the margin ask waiting for scrolling to stop now (the delay's end, or a test).
    func sendMarginNow() {
        marginTask?.cancel()
        marginTask = nil
        guard let (all, visible) = pendingMargin else { return }
        pendingMargin = nil
        guard all != lastWanted else { return }
        lastWanted = all
        source?.wantImages(all, visible: visible, width: slotWidth)
    }

    /// Size steps from a wheel the app hears itself (a mouse's thumb wheel): positive larger; a step a whole notch.
    public func resize(notches: Double) { scroll.resize(notches: notches) }

    /// A folder's or archive's facts, which come after the listing like the pictures: the card on screen shows them at
    /// once, the grid keeps its order, its pictures and its listing; nil takes them back. One not in the listing is
    /// ignored.
    public func setSummary(_ summary: CardSummary?, for id: String) {
        guard let i = indexByID[id] else { return }
        summaries[id] = summary
        entries[i].summary = summary
        guard let card = live[i], card.item.id == id else { return }
        let item = item(for: entries[i])
        if card.item != item {
            card.show(item)
            updateMotion()   // a card done waiting frees its slot
        }
    }

    /// The source cannot make the picture of `id` (a file that is not an image, or broken): its card is faint and the
    /// arrow keys skip it; `false` when the picture came after all. Forgotten when the place changes.
    public func setUnavailable(_ on: Bool, for id: String) {
        guard unavailable.contains(id) != on else { return }
        if on { unavailable.insert(id) } else { unavailable.remove(id) }
        guard let i = indexByID[id], let card = live[i], card.item.id == id else { return }
        card.show(item(for: entries[i]))
    }

    /// A file whose picture the source cannot make, or that the decoders could not read.
    private func isUnavailable(_ entry: BrowserEntry) -> Bool {
        unavailable.contains(entry.id) || unreadable?.contains(entry) == true
    }

    private func unreadableChanged(_ urls: Set<URL>) {
        for (i, card) in live where entries.indices.contains(i) && card.item.id == entries[i].id
            && urls.contains(entries[i].url.standardizedFileURL) {
            card.show(item(for: entries[i]))
        }
    }

    private func reloadUnavailableCards() {
        for (i, card) in live where entries.indices.contains(i) && card.item.id == entries[i].id && entries[i].isFile {
            card.show(item(for: entries[i]))
        }
    }

    /// The photos of the place on screen not viewed yet (a dot) and in a two-page pair (a ⧉ chip), by id; forgotten
    /// when the place changes. Only the cards on screen whose marks changed are touched; a card laid out later takes
    /// its marks then.
    public func setPhotoMarks(unseen: Set<String>, paired: Set<String>) {
        self.unseen = unseen
        self.paired = paired
        for card in live.values {
            guard let photo = card as? PhotoCard else { continue }
            let id = photo.item.id
            photo.isUnseen = unseen.contains(id)
            photo.isPaired = paired.contains(id)
        }
    }

    /// Files' facts learned after their listing (a poster made, a photo's EXIF read), for the place on screen: kept
    /// until the place changes, and drawn at once on the cards in view (file-cards spec §2). O(live).
    public func setFacts(_ new: [String: FileFacts]) {
        guard !new.isEmpty else { return }
        facts.merge(new) { _, latest in latest }
        for (i, card) in live where new[card.item.id] != nil && entries.indices.contains(i) {
            let item = item(for: entries[i])
            if card.item != item { card.show(item) }
        }
    }

    /// A card's picture; one not on screen now is ignored.
    public func setImage(_ image: CGImage?, for id: String) {
        guard let card = card(for: id) else { return }
        let waited = (card as? FolderCard)?.isWaiting == true
        card.image = image
        if waited, (card as? FolderCard)?.isWaiting == false { updateMotion() }
    }

    func card(for id: String) -> GridCard? {
        indexByID[id].flatMap { live[$0] }.flatMap { $0.item.id == id ? $0 : nil }
    }

    // MARK: For tests

    var liveCardCount: Int { live.count }
    /// The columns of the last section (the photos in a folder, the places at the top).
    var columns: Int { sections.isEmpty ? 0 : grid.columns(inSection: sections.count - 1) }
    var headerTitles: [String] { shownHeaders.map(\.title) }
    var shownHeaders: [GridHeader] { headers.filter { !$0.isHidden } }
    var footerLines: [String] { footer.lines }
    /// The path bar's items, empty while it is hidden.
    var pathBarTitles: [String] { pathRow.isHidden ? [] : pathControl.pathItems.map(\.title) }
    var scrollOffset: CGFloat { scroll.contentView.bounds.origin.y }
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
