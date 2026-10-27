import AppKit
import HomeChrome
import HomeScreenModel

/// The browser's toolbar as the window's `NSToolbar`.
/// Every item is made once, here, and kept: the app gives the toolbar to its window while Home shows and takes it
/// away while the viewer does, and what was chosen is still there when it comes back. A narrow window hides the items
/// by `HomeToolbarItem.priority`; the toolbar knows nothing of the window but `nsToolbar`.
@MainActor final class HomeToolbarController: NSObject, NSToolbarDelegate, NSMenuDelegate, NSSearchFieldDelegate {
    let nsToolbar: NSToolbar

    /// The house: back to the start page (the app decides which).
    var onHome: (() -> Void)?
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onCrumb: ((BrowserLocation) -> Void)?
    /// A sort field chosen: the view decides the direction (`BrowserSortChoice`).
    var onSortKey: ((BrowserSort.Key) -> Void)?
    var onKind: ((BrowserKindFilter) -> Void)?
    /// An item of a page's filter (`show(pageFilters:)`).
    var onPageFilter: ((Int) -> Void)?
    var onZoom: ((HomeResize) -> Void)?
    var onStyle: ((GridStyle) -> Void)?
    /// A segment of the posters / cards / list switch: the view saves the choice and re-tiles.
    var onCardStyle: ((CardStyle) -> Void)?
    var onFilterText: ((String) -> Void)?
    /// Esc in the name field: it is cleared and the keys go back to the grid.
    var onFilterEnd: (() -> Void)?
    /// The path menu is opening: the view may start on the folders its submenus will list.
    var onPathMenu: (() -> Void)?
    /// The sibling menu of path item `i` is opening: the view fills it with the folders beside that crumb.
    var onSiblings: ((Int) -> Void)?
    /// The sibling menu closed: a reply still on its way is not wanted.
    var onSiblingsClosed: (() -> Void)?
    /// The window's title and subtitle: the folder's name (or a page's) and the line under it.
    var onWindowText: ((_ title: String, _ subtitle: String) -> Void)?

    private var items: [HomeToolbarItem: NSToolbarItem] = [:]
    private let titleView = HomeToolbarTitleView()
    private let filterControl = NSSegmentedControl(labels: BrowserKindFilter.allCases.map(\.title),
                                                    trackingMode: .selectOne, target: nil, action: nil)
    /// The sort fields as text segments: the active one carries its direction (↑ ↓), a click on it reverses.
    private let sortControl = NSSegmentedControl()
    private var crumbs: [(title: String, location: BrowserLocation)] = []
    private var pageFilterTitles: [String] = []
    private var selectedPageFilter: Int?
    private var selectedKindFilter = BrowserKindFilter.all
    /// The kind filter is wanted (a folder, not a page or the places); a page's filter takes its place while it has one.
    private var kindWanted = true
    private var controlsOn = true
    private var cardsWanted = false
    private var sort = BrowserSort.standard
    /// The sort fields of this location, in order; none: the source cannot be sorted.
    private var sortKeys: [BrowserSort.Key] = [.name, .date, .size]
    private var gridStyle = GridStyle.aspect
    /// The thumbnails' ring: the progress item's view, the ring alone (its text is the item's tip).
    let progress = ThumbsProgressPill()
    /// The state the ring shows while there is work.
    private(set) var progressState: ThumbsProgressState?
    /// The sibling menu that is open (or was last), and the folders it lists.
    private var siblingMenu: SiblingMenu?
    private var siblingLocations: [BrowserLocation] = []

    private static let ringTip = "Thumbnails"
    private static let keyTitles: [(BrowserSort.Key, String)] = [(.name, "Name"), (.date, "Date"), (.size, "Size")]

    /// The submenu of a crumb of the path pill: first the entry that goes to the crumb itself (a menu item with a submenu
    /// does nothing when it is chosen), then, after a divider, the folders beside it.
    private final class SiblingMenu: NSMenu {
        let crumb: Int
        /// The entries before the folders: open, divider.
        static let heading = 2
        init(crumb: Int, delegate: NSMenuDelegate) {
            self.crumb = crumb
            super.init(title: "")
            self.delegate = delegate
            autoenablesItems = false
        }
        required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    }

    private(set) var windowTitle = "" {
        didSet {
            titleView.title = windowTitle
            fitTitleItem()
        }
    }
    private(set) var subtitleText = "" {
        didSet {
            titleView.subtitle = subtitleText
            fitTitleItem()
        }
    }

    override init() {
        nsToolbar = NSToolbar(identifier: "home.browser")
        super.init()
        nsToolbar.delegate = self
        nsToolbar.displayMode = .iconOnly
        nsToolbar.allowsUserCustomization = false
        nsToolbar.autosavesConfiguration = false
        nsToolbar.centeredItemIdentifiers = [HomeToolbarItem.filter.identifier]   // the title's length does not move it
        filterControl.segmentStyle = .automatic
        filterControl.controlSize = .regular
        filterControl.target = self
        filterControl.action = #selector(filterSegmentClicked(_:))
        for index in BrowserKindFilter.allCases.indices { filterControl.setWidth(92, forSegment: index) }
        sortControl.segmentStyle = .automatic
        sortControl.trackingMode = .selectOne
        sortControl.target = self
        sortControl.action = #selector(sortSegmentClicked(_:))
        sortControl.setAccessibilityLabel("Sort by")
        for item in HomeToolbarItem.allCases { items[item] = make(item) }
        // The search item keeps its own priority, 1001 (set to anything else, it stays): it folds into the magnifier long
        // before it goes. The sidebar toggle is AppKit's standard item.
        for (item, toolbarItem) in items where item != .search { toolbarItem.visibilityPriority = .init(item.priority) }
        items[.cards]?.isHidden = true
        items[.progress]?.isHidden = true
        items[.path]?.isHidden = true
        items[.sort]?.isHidden = true
        pathMenu.delegate = self
        pathMenu.autoenablesItems = false
        resetPathMenu()
        updateControls()
    }

    // MARK: Items

    private func make(_ item: HomeToolbarItem) -> NSToolbarItem {
        let id = item.identifier
        switch item {
        case .title:
            let toolbarItem = NSToolbarItem(itemIdentifier: id)
            toolbarItem.label = "Location"
            toolbarItem.toolTip = "Current location"
            toolbarItem.view = titleView
            toolbarItem.isBordered = false
            return toolbarItem
        case .home:
            return button(id, "house", label: "Start Page", tip: "Start Page (⇧⌘H)", action: #selector(homeClicked))
        case .history:
            return group(id, [("chevron.left", "Back", "Back"), ("chevron.right", "Forward", "Forward")], mode: .momentary,
                         label: "History", tip: "Back and Forward", action: #selector(historyClicked(_:)))
        case .path:
            let menu = NSMenuToolbarItem(itemIdentifier: id)
            menu.image = symbol("folder", "Path")
            menu.label = "Path"
            menu.toolTip = "The folder and the folders around it"
            menu.showsIndicator = true
            menu.menu = NSMenu()
            return menu
        case .aspect:
            return button(id, "rectangle.arrowtriangle.2.outward", label: "Aspect", tip: "Aspect thumbnails",
                          action: #selector(aspectClicked))
        case .filter:
            let toolbarItem = NSToolbarItem(itemIdentifier: id)
            toolbarItem.label = "Filter"
            toolbarItem.toolTip = "Show all, folders or \(filesTitle.lowercased())"
            toolbarItem.view = filterControl
            return toolbarItem
        case .sort:
            let toolbarItem = NSToolbarItem(itemIdentifier: id)
            toolbarItem.label = "Sort"
            toolbarItem.toolTip = "Sort by name, date or size; click the active one to reverse"
            toolbarItem.view = sortControl
            return toolbarItem
        case .zoom:
            let item = NSToolbarItem(itemIdentifier: id)
            item.label = "Card Size"
            item.toolTip = "Card size: − and + (⌘− ⌘=) go a size at a time, the slider a column"
            item.view = zoomView
            item.isBordered = true   // a capsule, as the items beside it
            return item
        case .progress:
            let ring = NSToolbarItem(itemIdentifier: id)
            ring.label = "Thumbnails"
            ring.toolTip = Self.ringTip
            ring.isBordered = true
            progress.drawsBackdrop = false
            progress.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([progress.widthAnchor.constraint(equalToConstant: ThumbsProgressPill.height),
                                         progress.heightAnchor.constraint(equalToConstant: ThumbsProgressPill.height)])
            ring.view = progress
            return ring
        case .cards:
            return group(id, [("square.grid.2x2", "Posters", "as Posters (⌥⌘1)"), ("rectangle.grid.1x2", "Cards", "as Cards (⌥⌘2)"),
                              ("list.bullet", "List", "as List (⌥⌘3)")], mode: .selectOne,
                         label: "Folders", tip: "Show folders as Posters, Cards or List", action: #selector(cardsClicked(_:)))
        case .search:
            let search = NSSearchToolbarItem(itemIdentifier: id)
            search.label = "Filter"
            search.toolTip = "Filter by name (⌘F)"
            search.searchField.placeholderString = "Filter"
            search.preferredWidthForSearchField = 180
            search.searchField.sendsSearchStringImmediately = true
            search.searchField.delegate = self
            search.resignsFirstResponderWithCancel = true
            return search
        }
    }

    /// The location's name over its summary, as the title and subtitle of a Finder window: plain text on the toolbar, in
    /// the system's label colours, as wide as its text where the toolbar has the room; it gives way down to `minWidth`
    /// (cut at the tail) before any item goes to the overflow.
    @MainActor private final class HomeToolbarTitleView: NSView {
        private let titleLabel = NSTextField(labelWithString: "")
        private let subtitleLabel = NSTextField(labelWithString: "")
        private let stack = NSStackView()
        static let minWidth: CGFloat = 150

        var title = "" {
            didSet {
                titleLabel.stringValue = title
                invalidateIntrinsicContentSize()
            }
        }
        var subtitle = "" {
            didSet {
                subtitleLabel.stringValue = subtitle
                subtitleLabel.isHidden = subtitle.isEmpty
                invalidateIntrinsicContentSize()
            }
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            titleLabel.textColor = .labelColor
            titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
            subtitleLabel.font = .systemFont(ofSize: 12)
            subtitleLabel.textColor = .secondaryLabelColor
            for label in [titleLabel, subtitleLabel] {
                label.lineBreakMode = .byTruncatingTail
                label.maximumNumberOfLines = 1
                label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            }
            subtitleLabel.isHidden = true
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 0
            stack.addArrangedSubview(titleLabel)
            stack.addArrangedSubview(subtitleLabel)
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
                stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        /// The whole text's width, with the stack's margins.
        var textWidth: CGFloat {
            let subtitleWidth = subtitleLabel.isHidden ? 0 : subtitleLabel.intrinsicContentSize.width
            return ceil(max(titleLabel.intrinsicContentSize.width, subtitleWidth)) + 8
        }

        override var intrinsicContentSize: NSSize {
            let titleSize = titleLabel.fittingSize
            let subtitleSize = subtitleLabel.isHidden ? .zero : subtitleLabel.fittingSize
            return NSSize(width: NSView.noIntrinsicMetric, height: titleSize.height + subtitleSize.height)
        }
    }

    /// The title item is flexible, from `minWidth` up to its whole text: the toolbar gives it the room beside it and
    /// takes it back before an item goes to the overflow. A view's constraints do not do this (the toolbar sizes a view
    /// to its fitting size, measured 2026-10-26 on macOS 27), the item's own range does.
    private func fitTitleItem() {
        guard let item = items[.title] else { return }
        let height = titleView.intrinsicContentSize.height
        item.minSize = NSSize(width: HomeToolbarTitleView.minWidth, height: height)
        item.maxSize = NSSize(width: max(HomeToolbarTitleView.minWidth, titleView.textWidth), height: height)
    }

    /// A toolbar icon: Lucide at the size of the toolbar's symbols, smaller for the zoom slider's ends.
    private func symbol(_ name: String, _ description: String, pointSize: CGFloat = 14) -> NSImage {
        Lucide.icon(name, pointSize: pointSize, description: description) ?? NSImage()
    }

    private func button(_ id: NSToolbarItem.Identifier, _ symbolName: String, label: String, tip: String,
                        action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        item.image = symbol(symbolName, label)
        item.label = label
        item.toolTip = tip
        item.isBordered = true
        item.target = self
        item.action = action
        return item
    }

    /// Icon segments: `parts` are the symbol, the label and the tip of each.
    private func group(_ id: NSToolbarItem.Identifier, _ parts: [(symbol: String, label: String, tip: String)],
                       mode: NSToolbarItemGroup.SelectionMode, label: String, tip: String, action: Selector) -> NSToolbarItemGroup {
        let group = NSToolbarItemGroup(itemIdentifier: id, images: parts.map { symbol($0.symbol, $0.label) }, selectionMode: mode,
                                       labels: parts.map(\.label), target: self, action: action)
        group.controlRepresentation = .expanded
        group.label = label
        group.toolTip = tip
        for (subitem, part) in zip(group.subitems, parts) { subitem.toolTip = part.tip }
        if mode == .selectOne { group.selectedIndex = 0 }
        return group
    }

    private var historyGroup: NSToolbarItemGroup { items[.history] as! NSToolbarItemGroup }
    private var cardsGroup: NSToolbarItemGroup { items[.cards] as! NSToolbarItemGroup }
    private var pathMenu: NSMenu { (items[.path] as! NSMenuToolbarItem).menu }
    var searchField: NSSearchField { (items[.search] as! NSSearchToolbarItem).searchField }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { HomeToolbarItem.browserOrder }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { HomeToolbarItem.browserOrder }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        HomeToolbarItem.allCases.first { $0.identifier == identifier }.flatMap { items[$0] }
    }

    // MARK: Shown

    /// The files' segment (`FileStyle.heading`: Photos, Videos).
    var filesTitle = BrowserKindFilter.photos.title {
        didSet { if filesTitle != oldValue { updateFilterGroup() } }
    }

    var kindTitles: [String] {
        pageFilterTitles.isEmpty ? BrowserKindFilter.allCases.map { $0 == .photos ? filesTitle : $0.title } : pageFilterTitles
    }
    var kindSelection: Int? {
        if !pageFilterTitles.isEmpty { return selectedPageFilter }
        return BrowserKindFilter.allCases.firstIndex(of: selectedKindFilter)
    }
    var isFilterVisible: Bool { !pageFilterTitles.isEmpty || kindWanted }
    var isNavVisible: Bool { !historyGroup.isHidden }
    var canBack: Bool { historyGroup.subitems[0].isEnabled }
    var canForward: Bool { historyGroup.subitems[1].isEnabled }
    var isCardSwitchVisible: Bool { !cardsGroup.isHidden }
    var isAspectVisible: Bool { items[.aspect]?.isHidden == false }
    var isFilterControlVisible: Bool { items[.filter]?.isHidden == false }
    var filterSelection: Int? { filterControl.selectedSegment >= 0 ? filterControl.selectedSegment : nil }
    /// The lit segment: 0 posters, 1 cards, 2 list.
    var cardSwitchSelection: Int? { cardsGroup.selectedIndex >= 0 ? cardsGroup.selectedIndex : nil }
    var isZoomVisible: Bool { items[.zoom]?.isHidden == false }
    var isSearchVisible: Bool { items[.search]?.isHidden == false }
    var filterText: String {
        get { searchField.stringValue }
        set { searchField.stringValue = newValue }
    }

    func show(path: [(title: String, location: BrowserLocation)], canBack: Bool, canForward: Bool, canUp: Bool) {
        historyGroup.isHidden = false
        historyGroup.subitems[0].isEnabled = canBack
        historyGroup.subitems[1].isEnabled = canForward
        crumbs = path
        windowTitle = path.last?.title ?? ""
        resetPathMenu()
        reportWindowText()
    }

    /// A source's title in place of the path; ‹ › go until the next path.
    func show(title: String) {
        historyGroup.isHidden = true
        crumbs = []
        windowTitle = title
        resetPathMenu()
        reportWindowText()
    }

    func show(subtitle text: String) {
        subtitleText = text
        reportWindowText()
    }

    private func reportWindowText() { onWindowText?(windowTitle, subtitleText) }

    /// A page's filter (Stash: Scenes · Images · Galleries) in place of the kind filter; empty gives the kind filter back.
    func show(pageFilters titles: [String], selected: Int?) {
        pageFilterTitles = titles
        selectedPageFilter = titles.isEmpty ? nil : selected
        updateControls()
    }

    func show(filter: BrowserKindFilter, visible: Bool) {
        kindWanted = visible
        selectedKindFilter = filter
        updateControls()
    }

    /// The card switch lit for `style`; shown only where there are folder cards (`visible`).
    func show(cardStyle style: CardStyle, visible: Bool) {
        cardsGroup.selectedIndex = CardStyle.allCases.firstIndex(of: style) ?? -1
        cardsWanted = visible
        updateControls()
    }

    /// The thumbnail-only controls are off on a page; the page's filter remains available.
    func show(controls: Bool) {
        controlsOn = controls
        updateControls()
    }

    private func updateControls() {
        items[.zoom]?.isHidden = !controlsOn
        items[.search]?.isHidden = !controlsOn
        cardsGroup.isHidden = !(controlsOn && cardsWanted)
        items[.aspect]?.isHidden = !controlsOn
        items[.filter]?.isHidden = !isFilterVisible
        items[.sort]?.isHidden = sortKeys.isEmpty
        updateFilterGroup()
        updateSortControl()
        updateAspectItem()
    }

    /// The sort fields of the location; the active one is shown with its direction in its segment. None: not sortable.
    func show(sort: BrowserSort, keys: [BrowserSort.Key]) {
        self.sort = sort
        sortKeys = keys
        updateControls()
    }

    /// The thumbnails' shape, represented by the aspect-ratio button.
    func show(style: GridStyle) {
        gridStyle = style
        let isSquare = style == .square
        let tip = isSquare ? "Square thumbnails" : "Aspect thumbnails"
        items[.aspect]?.toolTip = tip
        items[.aspect]?.image = symbol(isSquare ? "rectangle.arrowtriangle.2.inward" : "rectangle.arrowtriangle.2.outward", tip)
    }

    var isProgressVisible: Bool { items[.progress]?.isHidden == false }

    /// The thumbnails' ring with `state`; nil hides it. The text is in the ring's tip.
    func show(progress state: ThumbsProgressState?) {
        progressState = state
        progress.show(state)
        items[.progress]?.isHidden = state == nil
        items[.progress]?.toolTip = state?.text ?? Self.ringTip
    }

    /// The popover's counts, whether the ring is lit or not (nothing being prepared); nil: none for this folder yet.
    func show(progressDetail state: ThumbsProgressState?) { progress.showDetail(state) }

    /// View › Thumbnails…: the progress popover with the current counts (zeros before any), from the ring when it shows,
    /// else from the top of the window (the ring is out, or a narrow window put it behind »). False without a window:
    /// `window` is the one that holds the toolbar, the ring's own when it is in one.
    @discardableResult func showProgressPopover(in window: NSWindow? = nil) -> Bool {
        if isProgressVisible, progress.window != nil {
            progress.openPopover(from: progress)
            return true
        }
        guard let content = (window ?? progress.window)?.contentView else { return false }
        let top = content.isFlipped ? content.bounds.minY : content.bounds.maxY
        progress.openPopover(from: content, rect: NSRect(x: content.bounds.midX - 1, y: top - 1, width: 2, height: 2),
                             edge: content.isFlipped ? .maxY : .minY)
        return true
    }

    func focusFilter() { (items[.search] as? NSSearchToolbarItem)?.beginSearchInteraction() }

    // MARK: Clicks

    func clickHome() { onHome?() }

    func clickHistory(_ i: Int) {
        if i == 0 { onBack?() } else if i == 1 { onForward?() }
    }

    func clickZoom(_ i: Int) {
        if i == 0 { onZoom?(.smallerSize) } else if i == 1 { onZoom?(.largerSize) }
    }

    func clickCardStyle(_ i: Int) {
        guard CardStyle.allCases.indices.contains(i) else { return }
        onCardStyle?(CardStyle.allCases[i])
    }

    /// Segment `i` of the sort control: another field takes its last direction, the active one reverses
    /// (`BrowserSortChoice`, the view's).
    func clickSort(_ i: Int) {
        guard sortKeys.indices.contains(i) else { return }
        onSortKey?(sortKeys[i])
    }

    func clickAction(_ i: Int) {
        guard i == 0, controlsOn else { return }
        onStyle?(gridStyle == .square ? .aspect : .square)
    }

    func clickKind(_ i: Int) {
        if !pageFilterTitles.isEmpty {
            guard pageFilterTitles.indices.contains(i) else { return }
            selectedPageFilter = i
            filterControl.selectedSegment = i
            onPageFilter?(i)
            return
        }
        guard BrowserKindFilter.allCases.indices.contains(i) else { return }
        selectedKindFilter = BrowserKindFilter.allCases[i]
        filterControl.selectedSegment = i
        onKind?(selectedKindFilter)
    }

    @objc private func homeClicked() { clickHome() }
    @objc private func aspectClicked() { clickAction(0) }
    @objc private func filterSegmentClicked(_ sender: NSSegmentedControl) { clickKind(sender.selectedSegment) }
    @objc private func sortSegmentClicked(_ sender: NSSegmentedControl) { clickSort(sender.selectedSegment) }
    @objc private func historyClicked(_ sender: NSToolbarItemGroup) { clickHistory(sender.selectedIndex) }
    @objc private func zoomButtonClicked(_ sender: NSButton) { clickZoom(sender.tag) }

    /// A drag re-tiles the grid at every whole point: 4.9 ms median, 12.8 ms at worst of main-thread CPU per step for
    /// 5000 photos in a 2400 pt window (debug build, Apple Silicon, 2026-10-26), within the 50 ms of a setting.
    @objc private func zoomSliderMoved(_ sender: NSSlider) {
        let size = exp(sender.doubleValue).rounded()
        guard size != shownCardSize else { return }
        shownCardSize = size
        onZoom?(.to(size))
    }

    /// − and + about a slider of the card size; the slider runs on a log scale, so each column is about as far as the
    /// next.
    private lazy var zoomView: NSView = {
        let minus = zoomButton("minus", "Smaller (⌘−)", tag: 0)
        let plus = zoomButton("plus", "Larger (⌘=)", tag: 1)
        zoomSlider.controlSize = .small
        zoomSlider.isContinuous = true
        zoomSlider.target = self
        zoomSlider.action = #selector(zoomSliderMoved(_:))
        zoomSlider.setAccessibilityLabel("Card size")
        let stack = NSStackView(views: [minus, zoomSlider, plus])
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        zoomSlider.widthAnchor.constraint(equalToConstant: 96).isActive = true
        return stack
    }()

    private let zoomSlider = NSSlider()
    /// The size the slider last showed or sent: a drag sends a size only when it changes.
    private var shownCardSize: CGFloat = 0

    private func zoomButton(_ symbolName: String, _ tip: String, tag: Int) -> NSButton {
        let button = NSButton(image: symbol(symbolName, tip, pointSize: 11), target: self, action: #selector(zoomButtonClicked(_:)))
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.tag = tag
        button.toolTip = tip
        return button
    }

    /// The slider at `size` within `range`.
    func show(cardSize size: CGFloat, range: ClosedRange<CGFloat>) {
        zoomSlider.minValue = log(range.lowerBound)
        zoomSlider.maxValue = log(range.upperBound)
        zoomSlider.doubleValue = log(size)
        shownCardSize = size.rounded()
    }

    var zoomSliderSize: CGFloat { exp(zoomSlider.doubleValue) }

    func dragZoomSlider(to size: CGFloat) {
        zoomSlider.doubleValue = log(size)
        zoomSliderMoved(zoomSlider)
    }
    @objc private func cardsClicked(_ sender: NSToolbarItemGroup) { clickCardStyle(sender.selectedIndex) }
    // MARK: Menus

    var isPathVisible: Bool { items[.path]?.isHidden == false }
    var isStyleVisible: Bool { controlsOn }
    var isSortVisible: Bool { items[.sort]?.isHidden == false }
    /// The sort segments' texts, the active one with its arrow; the segment lit.
    var sortSegmentTitles: [String] { (0..<sortControl.segmentCount).map { sortControl.label(forSegment: $0) ?? "" } }
    var sortSelection: Int? { sortControl.selectedSegment >= 0 ? sortControl.selectedSegment : nil }
    /// The path menu keeps a placeholder until opened.
    var pathMenuTitles: [String] { pathMenu.items.dropFirst().map(\.title) }
    var pathMenuChecked: [Bool] { pathMenu.items.dropFirst().map { $0.state == .on } }
    var siblingTitles: [String] { siblingMenu?.items.dropFirst(SiblingMenu.heading).map(\.title) ?? [] }
    var siblingChecked: [Bool] { siblingMenu?.items.dropFirst(SiblingMenu.heading).map { $0.state == .on } ?? [] }

    /// What opening a menu does: AppKit asks the delegate to fill it first.
    func openPathMenu() { menuNeedsUpdate(pathMenu) }
    func clickPathItem(_ i: Int) { pathMenu.performActionForItem(at: i + 1) }
    /// The entry of path item `i`'s submenu that goes to the crumb itself.
    func clickPathOpen(_ i: Int) { pathMenu.items.dropFirst().dropFirst(i).first?.submenu?.performActionForItem(at: 0) }
    /// Whether choosing path item `i` itself goes to its folder (it has no submenu).
    func pathItemOpensItself(_ i: Int) -> Bool { pathMenu.items.dropFirst().dropFirst(i).first.map { $0.submenu == nil && $0.action != nil } ?? false }
    func hasSiblingMenu(atPathItem i: Int) -> Bool { pathMenu.items.dropFirst().dropFirst(i).first?.submenu is SiblingMenu }
    func closeSiblingMenu(atPathItem i: Int) {
        if let menu = pathMenu.items.dropFirst().dropFirst(i).first?.submenu { menuDidClose(menu) }
    }
    func openSiblingMenu(atPathItem i: Int) {
        if let menu = pathMenu.items.dropFirst().dropFirst(i).first?.submenu { menuNeedsUpdate(menu) }
    }

    /// Until the menu is first opened it holds one item: filling every menu of the window costs more than the window can
    /// spare (`NSPopUpButton` measures each item at about a millisecond), and most are never opened.
    private func resetPathMenu() {
        pathMenu.removeAllItems()
        pathMenu.addItem(withTitle: "Path", action: nil, keyEquivalent: "")   // the button's own (`pathMenuTitles`)
        items[.path]?.isHidden = crumbs.isEmpty
    }

    private static let kindSymbols: [BrowserKindFilter: String] = [
        .all: "square.grid.2x2", .folders: "folder", .photos: "photo",
    ]

    private func updateFilterGroup() {
        let titles = kindTitles
        filterControl.segmentCount = titles.count
        for (index, title) in titles.enumerated() {
            filterControl.setLabel(title, forSegment: index)
            let width = ceil((title as NSString).size(withAttributes: [.font: filterControl.font ?? NSFont.systemFont(ofSize: 13)]).width + 32)
            filterControl.setWidth(max(84, width), forSegment: index)
        }
        filterControl.selectedSegment = kindSelection ?? -1
    }

    /// One text segment per sort field of the location, each of one width so the arrow's coming and going does not move
    /// the others; the active one is lit and shows its direction.
    private func updateSortControl() {
        sortControl.segmentCount = sortKeys.count
        for (index, key) in sortKeys.enumerated() {
            let name = Self.keyTitles.first { $0.0 == key }?.1 ?? key.rawValue
            sortControl.setLabel(key == sort.key ? name + (sort.ascending ? " ↑" : " ↓") : name, forSegment: index)
            sortControl.setWidth(Self.sortSegmentWidth, forSegment: index)
        }
        sortControl.selectedSegment = sortKeys.firstIndex(of: sort.key) ?? -1
    }

    private static let sortSegmentWidth: CGFloat = 70

    private func updateAspectItem() {
        let tip = gridStyle == .square ? "Square thumbnails" : "Aspect thumbnails"
        items[.aspect]?.toolTip = tip
        items[.aspect]?.image = symbol(gridStyle == .square ? "rectangle.arrowtriangle.2.inward" : "rectangle.arrowtriangle.2.outward", tip)
    }

    /// The folder and the folders above it, nearest first, the current one checked; each but the first place has the
    /// folders beside it in a submenu.
    private func fillPathMenu() {
        resetPathMenu()
        for index in crumbs.indices.reversed() {
            let crumb = crumbs[index]
            let item = pathMenu.addItem(withTitle: crumb.title, action: nil, keyEquivalent: "")
            item.tag = index
            item.state = index == crumbs.count - 1 ? .on : .off
            item.image = symbol(crumb.location == .places ? "externaldrive" : "folder", crumb.title)
            if index > 0 {
                item.submenu = makeSiblingMenu(for: index, title: crumb.title)
            } else {
                item.action = #selector(pathItemChosen(_:))
                item.target = self
            }
        }
    }

    private func makeSiblingMenu(for crumb: Int, title: String) -> SiblingMenu {
        let menu = SiblingMenu(crumb: crumb, delegate: self)
        let open = menu.addItem(withTitle: "Open “\(title)”", action: #selector(pathItemChosen(_:)), keyEquivalent: "")
        open.target = self
        open.tag = crumb
        menu.addItem(.separator())
        menu.addItem(withTitle: "Loading…", action: nil, keyEquivalent: "").isEnabled = false
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === pathMenu {
            fillPathMenu()
            onPathMenu?()
        } else if let sibling = menu as? SiblingMenu {
            siblingMenu = sibling
            onSiblings?(sibling.crumb)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        // The chosen item's action comes after the close: the menu's items stay readable until the next one opens.
        if menu === siblingMenu { onSiblingsClosed?() }
    }

    @objc private func pathItemChosen(_ sender: NSMenuItem) {
        if crumbs.indices.contains(sender.tag) { onCrumb?(crumbs[sender.tag].location) }
    }

    // MARK: Sibling menus

    /// The submenu of crumb `i` at once: the folders when known, else one `Loading…` line.
    func showSiblings(_ entries: [(title: String, location: BrowserLocation, current: Bool)]?, at i: Int) {
        guard let menu = pathMenu.items.compactMap({ $0.submenu as? SiblingMenu }).first(where: { $0.crumb == i }) else { return }
        siblingMenu = menu
        fill(menu, entries)
    }

    /// The reply for the open menu.
    func updateSiblings(_ entries: [(title: String, location: BrowserLocation, current: Bool)]) {
        guard let menu = siblingMenu else { return }
        fill(menu, entries)
    }

    func chooseSibling(_ i: Int) {
        guard siblingLocations.indices.contains(i) else { return }
        let location = siblingLocations[i]
        pathMenu.cancelTracking()
        onCrumb?(location)
    }

    func closeSiblings() {
        guard siblingMenu != nil else { return }
        siblingMenu = nil
        onSiblingsClosed?()
    }

    private func fill(_ menu: NSMenu, _ entries: [(title: String, location: BrowserLocation, current: Bool)]?) {
        while menu.items.count > SiblingMenu.heading { menu.removeItem(at: menu.items.count - 1) }
        siblingLocations = entries?.map(\.location) ?? []
        guard let entries else {
            menu.addItem(withTitle: "Loading…", action: nil, keyEquivalent: "").isEnabled = false
            return
        }
        for (i, entry) in entries.enumerated() {
            let item = menu.addItem(withTitle: entry.title, action: #selector(siblingChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = entry.current ? .on : .off
        }
    }

    @objc private func siblingChosen(_ sender: NSMenuItem) { chooseSibling(sender.tag) }

    // MARK: Name field

    func controlTextDidChange(_ note: Notification) {
        onFilterText?(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        searchField.stringValue = ""
        onFilterText?("")
        onFilterEnd?()
        return true
    }
}
