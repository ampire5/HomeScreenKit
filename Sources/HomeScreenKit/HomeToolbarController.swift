import AppKit
import HomeScreenModel

/// The browser's toolbar as the window's `NSToolbar`, as in Photos: the sidebar and start page buttons, ‹ ›, the path as
/// a pill menu, the kind filter (or a page's own) in text segments, the thumbnails' ring, the card switch, − +, View ▾
/// and the search. The window shows the folder's name and the subtitle (`onWindowText`) and the toolbar does not draw
/// them. Every item is made once, here, and kept: the app gives the toolbar to its window while Home shows and takes it
/// away while the viewer does, and what was chosen is still there when it comes back. A narrow window hides the items
/// by `HomeToolbarItem.priority`; the toolbar knows nothing of the window but `nsToolbar`.
@MainActor final class HomeToolbarController: NSObject, NSToolbarDelegate, NSMenuDelegate, NSSearchFieldDelegate {
    let nsToolbar: NSToolbar

    var onSidebar: (() -> Void)?
    /// The house: back to the start page (the app decides which).
    var onHome: (() -> Void)?
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onCrumb: ((BrowserLocation) -> Void)?
    /// A sort field chosen: the view decides the direction (`BrowserSortChoice`).
    var onSortKey: ((BrowserSort.Key) -> Void)?
    var onKind: ((BrowserKindFilter) -> Void)?
    /// A segment of a page's filter (`show(pageFilters:)`).
    var onPageFilter: ((Int) -> Void)?
    var onZoom: ((HomeResize) -> Void)?
    var onStyle: (() -> Void)?
    /// A segment of the posters / cards / list switch: the view saves the choice and re-tiles.
    var onCardStyle: ((CardStyle) -> Void)?
    var onFilterText: ((String) -> Void)?
    /// Esc in the name field: it is cleared and the keys go back to the grid.
    var onFilterEnd: (() -> Void)?
    /// The sibling menu of path item `i` is opening: the view fills it with the folders beside that crumb.
    var onSiblings: ((Int) -> Void)?
    /// The sibling menu closed: a reply still on its way is not wanted.
    var onSiblingsClosed: (() -> Void)?
    /// The window's title and subtitle: the folder's name (or a page's) and the line under it.
    var onWindowText: ((_ title: String, _ subtitle: String) -> Void)?

    private var items: [HomeToolbarItem: NSToolbarItem] = [:]
    private var crumbs: [(title: String, location: BrowserLocation)] = []
    private var pageFilterTitles: [String] = []
    /// The kind filter is wanted (a folder, not a page or the places); a page's filter takes its place while it has one.
    private var kindWanted = true
    private var controlsOn = true
    private var cardsWanted = false
    private var sort = BrowserSort.standard
    /// The sort fields of this location, in order; none: the source cannot be sorted.
    private var sortKeys: [BrowserSort.Key] = [.name, .date, .size]
    private var styleSymbol = "rectangle.grid.2x2"
    /// The sibling menu that is open (or was last), and the folders it lists.
    /// The thumbnails' ring: the progress item's view, the ring alone (its text is the item's tip).
    let progress = ThumbsProgressPill()
    /// The state the ring shows while there is work.
    private(set) var progressState: ThumbsProgressState?
    private var siblingMenu: SiblingMenu?
    private var siblingLocations: [BrowserLocation] = []

    private static let ringTip = "Thumbnails"
    private static let keyTitles: [(BrowserSort.Key, String)] = [(.name, "Name"), (.date, "Date"), (.size, "Size")]

    /// The menu of the folders beside one crumb: a submenu of the path pill's item for it.
    private final class SiblingMenu: NSMenu {
        let crumb: Int
        init(crumb: Int, delegate: NSMenuDelegate) {
            self.crumb = crumb
            super.init(title: "")
            self.delegate = delegate
            autoenablesItems = false
            addItem(withTitle: "Loading…", action: nil, keyEquivalent: "").isEnabled = false
        }
        required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    }

    private enum ViewChoice { case sort(BrowserSort.Key), style, card(CardStyle) }

    private(set) var windowTitle = ""
    private(set) var subtitleText = ""

    override init() {
        nsToolbar = NSToolbar(identifier: "home.browser")
        super.init()
        nsToolbar.delegate = self
        nsToolbar.displayMode = .iconOnly
        nsToolbar.allowsUserCustomization = false
        nsToolbar.autosavesConfiguration = false
        for item in HomeToolbarItem.allCases { items[item] = make(item) }
        // The search item keeps its own priority, 1001 (set to anything else, it stays): it folds into the magnifier long
        // before it goes, and the sidebar button, at 1000, is the first of the two to leave.
        for (item, toolbarItem) in items where item != .search { toolbarItem.visibilityPriority = .init(item.priority) }
        items[.pageFilter]?.isHidden = true
        items[.cards]?.isHidden = true
        items[.progress]?.isHidden = true
        items[.path]?.isHidden = true
        for menu in [pathMenu, viewMenu] {
            menu.delegate = self
            menu.autoenablesItems = false
        }
        viewMenu.addItem(withTitle: "View", action: nil, keyEquivalent: "")
    }

    // MARK: Items

    private func make(_ item: HomeToolbarItem) -> NSToolbarItem {
        let id = item.identifier
        switch item {
        case .sidebar:
            return button(id, "sidebar.left", label: "Sidebar", tip: "Sidebar (⌃⌘S)", action: #selector(sidebarClicked))
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
        case .filter:
            return titleGroup(id, BrowserKindFilter.allCases.map(\.title), label: "Show", tip: "Show All, Folders or Photos")
        case .pageFilter:
            return titleGroup(id, [""], label: "Page Filter", tip: "Filter this page")
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
        case .zoom:
            return group(id, [("minus", "Smaller", "Smaller (⌘−)"), ("plus", "Larger", "Larger (⌘=)")], mode: .momentary,
                         label: "Zoom", tip: "Smaller or Larger", action: #selector(zoomClicked(_:)))
        case .view:
            let menu = NSMenuToolbarItem(itemIdentifier: id)
            menu.title = "View"
            menu.image = symbol("slider.horizontal.3", "View")
            menu.label = "View"
            menu.toolTip = "Sort, shape and folder cards"
            menu.showsIndicator = true
            menu.menu = NSMenu()
            return menu
        case .search:
            let search = NSSearchToolbarItem(itemIdentifier: id)
            search.label = "Filter"
            search.toolTip = "Filter by name (⌘F)"
            search.searchField.placeholderString = "Filter"
            search.searchField.sendsSearchStringImmediately = true
            search.searchField.delegate = self
            search.resignsFirstResponderWithCancel = true
            return search
        }
    }

    private func symbol(_ name: String, _ description: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: description) ?? NSImage()
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

    /// Text segments, one selected (`All | Folders | Photos`, or a page's own).
    private func titleGroup(_ id: NSToolbarItem.Identifier, _ titles: [String], label: String, tip: String) -> NSToolbarItemGroup {
        let group = NSToolbarItemGroup(itemIdentifier: id, titles: titles, selectionMode: .selectOne, labels: titles, target: self,
                                       action: #selector(kindClicked(_:)))
        group.controlRepresentation = .expanded
        group.label = label
        group.toolTip = tip
        group.selectedIndex = 0
        return group
    }

    private var kindGroup: NSToolbarItemGroup { items[.filter] as! NSToolbarItemGroup }
    private var historyGroup: NSToolbarItemGroup { items[.history] as! NSToolbarItemGroup }
    private var cardsGroup: NSToolbarItemGroup { items[.cards] as! NSToolbarItemGroup }
    private var pageGroup: NSToolbarItemGroup { items[.pageFilter] as! NSToolbarItemGroup }
    private var activeFilter: NSToolbarItemGroup { pageFilterTitles.isEmpty ? kindGroup : pageGroup }
    private var pathMenu: NSMenu { (items[.path] as! NSMenuToolbarItem).menu }
    private var viewMenu: NSMenu { (items[.view] as! NSMenuToolbarItem).menu }
    var searchField: NSSearchField { (items[.search] as! NSSearchToolbarItem).searchField }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { HomeToolbarItem.browserOrder }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { HomeToolbarItem.browserOrder }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        HomeToolbarItem.allCases.first { $0.identifier == identifier }.flatMap { items[$0] }
    }

    // MARK: Shown

    var kindTitles: [String] { activeFilter.subitems.map(\.title) }
    var kindSelection: Int? { activeFilter.selectedIndex >= 0 ? activeFilter.selectedIndex : nil }
    var isFilterVisible: Bool { !activeFilter.isHidden }
    var isNavVisible: Bool { !historyGroup.isHidden }
    var canBack: Bool { historyGroup.subitems[0].isEnabled }
    var canForward: Bool { historyGroup.subitems[1].isEnabled }
    var isCardSwitchVisible: Bool { !cardsGroup.isHidden }
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
        if titles != pageFilterTitles {
            pageFilterTitles = titles
            if !titles.isEmpty { replacePageGroup(titles) }
        }
        if !titles.isEmpty { pageGroup.selectedIndex = selected ?? -1 }
        updateFilterVisibility()
    }

    func show(filter: BrowserKindFilter, visible: Bool) {
        kindWanted = visible
        kindGroup.selectedIndex = BrowserKindFilter.allCases.firstIndex(of: filter) ?? -1
        updateFilterVisibility()
    }

    private func updateFilterVisibility() {
        let page = !pageFilterTitles.isEmpty
        pageGroup.isHidden = !page
        kindGroup.isHidden = page || !kindWanted
    }

    /// A group cannot change its number of segments: a page whose filter differs gets a new group in the old one's place.
    private func replacePageGroup(_ titles: [String]) {
        let group = titleGroup(HomeToolbarItem.pageFilter.identifier, titles, label: "Page Filter", tip: "Filter this page")
        group.visibilityPriority = .init(HomeToolbarItem.pageFilter.priority)
        items[.pageFilter] = group
        guard let index = nsToolbar.items.firstIndex(where: { $0.itemIdentifier == group.itemIdentifier }) else { return }
        nsToolbar.removeItem(at: index)
        nsToolbar.insertItem(withItemIdentifier: group.itemIdentifier, at: index)
    }

    /// The card switch lit for `style`; shown only where there are folder cards (`visible`).
    func show(cardStyle style: CardStyle, visible: Bool) {
        cardsGroup.selectedIndex = CardStyle.allCases.firstIndex(of: style) ?? -1
        cardsWanted = visible
        updateControls()
    }

    /// The search, − + and the card switch: off on a page.
    func show(controls: Bool) {
        controlsOn = controls
        updateControls()
    }

    private func updateControls() {
        items[.zoom]?.isHidden = !controlsOn
        items[.search]?.isHidden = !controlsOn
        cardsGroup.isHidden = !(controlsOn && cardsWanted)
        items[.view]?.isHidden = sortKeys.isEmpty && !controlsOn
    }

    /// The sort fields of the location; the active one is shown with its direction in the View menu. None: not sortable.
    func show(sort: BrowserSort, keys: [BrowserSort.Key]) {
        self.sort = sort
        sortKeys = keys
        updateControls()
        resetViewMenu()
    }

    /// The thumbnails' shape, as the View menu's Square / Aspect shows it.
    func show(style: GridStyle) {
        styleSymbol = style == .square ? "square.grid.2x2" : "rectangle.grid.2x2"
        resetViewMenu()
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

    func clickSidebar() { onSidebar?() }
    func clickHome() { onHome?() }

    func clickHistory(_ i: Int) {
        if i == 0 { onBack?() } else if i == 1 { onForward?() }
    }

    func clickZoom(_ i: Int) {
        if i == 0 { onZoom?(.smaller) } else if i == 1 { onZoom?(.larger) }
    }

    func clickCardStyle(_ i: Int) {
        guard CardStyle.allCases.indices.contains(i) else { return }
        onCardStyle?(CardStyle.allCases[i])
    }

    func clickKind(_ i: Int) {
        if !pageFilterTitles.isEmpty {
            if pageFilterTitles.indices.contains(i) { onPageFilter?(i) }
            return
        }
        guard BrowserKindFilter.allCases.indices.contains(i) else { return }
        onKind?(BrowserKindFilter.allCases[i])
    }

    @objc private func sidebarClicked() { clickSidebar() }
    @objc private func homeClicked() { clickHome() }
    @objc private func historyClicked(_ sender: NSToolbarItemGroup) { clickHistory(sender.selectedIndex) }
    @objc private func zoomClicked(_ sender: NSToolbarItemGroup) { clickZoom(sender.selectedIndex) }
    @objc private func cardsClicked(_ sender: NSToolbarItemGroup) { clickCardStyle(sender.selectedIndex) }
    @objc private func kindClicked(_ sender: NSToolbarItemGroup) { clickKind(sender.selectedIndex) }

    // MARK: Menus

    var isPathVisible: Bool { items[.path]?.isHidden == false }
    var isViewVisible: Bool { items[.view]?.isHidden == false }
    var pathMenuTitles: [String] { pathMenu.items.map(\.title) }
    var pathMenuChecked: [Bool] { pathMenu.items.map { $0.state == .on } }
    var viewMenuTitles: [String] { viewMenu.items.map(\.title) }
    var viewMenuChecked: [Bool] { viewMenu.items.map { $0.state == .on } }
    var siblingTitles: [String] { siblingMenu?.items.map(\.title) ?? [] }
    var siblingChecked: [Bool] { siblingMenu?.items.map { $0.state == .on } ?? [] }

    /// What opening a menu does: AppKit asks the delegate to fill it first.
    func openPathMenu() { menuNeedsUpdate(pathMenu) }
    func openViewMenu() { menuNeedsUpdate(viewMenu) }
    func clickPathItem(_ i: Int) { pathMenu.performActionForItem(at: i) }
    func clickViewItem(_ i: Int) { viewMenu.performActionForItem(at: i) }
    func hasSiblingMenu(atPathItem i: Int) -> Bool { pathMenu.items.indices.contains(i) && pathMenu.items[i].submenu is SiblingMenu }
    func openSiblingMenu(atPathItem i: Int) {
        if let menu = pathMenu.items[i].submenu { menuNeedsUpdate(menu) }
    }

    /// Until the menu is first opened it holds one item: filling every menu of the window costs more than the window can
    /// spare (`NSPopUpButton` measures each item at about a millisecond), and most are never opened.
    private func resetPathMenu() {
        pathMenu.removeAllItems()
        pathMenu.addItem(withTitle: windowTitle, action: nil, keyEquivalent: "")
        items[.path]?.isHidden = crumbs.isEmpty
    }

    private func resetViewMenu() {
        viewMenu.removeAllItems()
        viewMenu.addItem(withTitle: "View", action: nil, keyEquivalent: "")
    }

    /// The folder and the folders above it, nearest first, the current one checked; each but the first place has the
    /// folders beside it in a submenu.
    private func fillPathMenu() {
        pathMenu.removeAllItems()
        for index in crumbs.indices.reversed() {
            let crumb = crumbs[index]
            let item = pathMenu.addItem(withTitle: crumb.title, action: #selector(pathItemChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = index == crumbs.count - 1 ? .on : .off
            item.image = symbol(crumb.location == .places ? "externaldrive" : "folder", crumb.title)
            if index > 0 { item.submenu = SiblingMenu(crumb: index, delegate: self) }
        }
    }

    private func fillViewMenu() {
        viewMenu.removeAllItems()
        func add(_ title: String, _ choice: ViewChoice, checked: Bool = false, image: String? = nil) {
            let item = viewMenu.addItem(withTitle: title, action: #selector(viewItemChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice
            item.state = checked ? .on : .off
            if let image { item.image = symbol(image, title) }
        }
        if !sortKeys.isEmpty {
            viewMenu.addItem(.sectionHeader(title: "Sort by"))
            for key in sortKeys {
                let name = Self.keyTitles.first { $0.0 == key }?.1 ?? key.rawValue
                add(key == sort.key ? name + (sort.ascending ? " ↑" : " ↓") : name, .sort(key))
            }
        }
        guard controlsOn else { return }
        if !sortKeys.isEmpty { viewMenu.addItem(.separator()) }
        add("Square / Aspect", .style, image: styleSymbol)
        guard cardsWanted else { return }
        viewMenu.addItem(.separator())
        let shown = cardsGroup.selectedIndex
        for (i, style) in CardStyle.allCases.enumerated() { add(style.rawValue.capitalized, .card(style), checked: i == shown) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === pathMenu {
            fillPathMenu()
        } else if menu === viewMenu {
            fillViewMenu()
        } else if let sibling = menu as? SiblingMenu {
            siblingMenu = sibling
            onSiblings?(sibling.crumb)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        // The chosen item's action comes after the close: the menu's items stay readable until the next one opens.
        if menu is SiblingMenu { onSiblingsClosed?() }
    }

    @objc private func pathItemChosen(_ sender: NSMenuItem) {
        if crumbs.indices.contains(sender.tag) { onCrumb?(crumbs[sender.tag].location) }
    }

    @objc private func viewItemChosen(_ sender: NSMenuItem) {
        switch sender.representedObject as? ViewChoice {
        case .sort(let key): onSortKey?(key)
        case .style: onStyle?()
        case .card(let style): onCardStyle?(style)
        case nil: break
        }
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
        menu.removeAllItems()
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
