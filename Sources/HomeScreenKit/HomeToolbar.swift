import AppKit
import HomeChrome
import HomeScreenModel

/// The browser's toolbar, drawn over the grid as in Photos: a backdrop fading from the background into the grid,
/// the sidebar button, the start page button, ‹ › ↑ and the path (or a source's title) with the subtitle under it on the left, the kind filter
/// (or a page's own filter) in the middle, and the sort, − | +, the style and a name field on the right. Only its
/// controls take clicks; the rest goes to the grid under it.
final class HomeToolbar: NSView, NSSearchFieldDelegate, NSMenuDelegate {
    static let height: CGFloat = 56

    var onSidebar: (() -> Void)?
    /// The house: back to the start page (the app decides which).
    var onHome: (() -> Void)?
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onUp: (() -> Void)?
    var onCrumb: ((BrowserLocation) -> Void)?
    /// A sort segment clicked: the view decides the direction (`BrowserSortChoice`).
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
    /// A click on the › before crumb `i`: the view fills its menu with the folders beside that crumb.
    var onSiblings: ((Int) -> Void)?
    /// The sibling menu closed: a reply still on its way is not wanted.
    var onSiblingsClosed: (() -> Void)?
    /// Shows a menu under a view; tests replace it (`NSMenu.popUp` tracks the mouse until the menu closes).
    var popUp: (NSMenu, NSView) -> Void = { menu, view in
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
    }

    /// The colour the backdrop fades from: the browser's background.
    var background = Chrome.Palette.window.background { didSet { updateBackdrop() } }

    /// Runs along the bottom edge while a folder loads.
    let loading = LoadingLine()
    let sidebarButton = GlassGroup(items: [(symbol: "sidebar.left", tip: "Sidebar (⌃⌘S)")])
    let homeButton = GlassGroup(items: [(symbol: "house", tip: "Start Page (⇧⌘H)")])
    let zoom = GlassGroup(items: [(symbol: "minus", tip: "Smaller (⌘−)"), (symbol: "plus", tip: "Larger (⌘=)")])
    let styleButton = GlassGroup(items: [(symbol: "rectangle.grid.2x2", tip: "Square or Aspect (⌥T)")])
    /// Posters / Cards / List, in `CardStyle.allCases` order; only a folder has folder cards, so it is off elsewhere.
    let cardSwitch = GlassGroup(items: [(symbol: "square.grid.2x2", tip: "as Posters (⌃⌘1)"),
                                        (symbol: "rectangle.grid.1x2", tip: "as Cards (⌃⌘2)"),
                                        (symbol: "list.bullet", tip: "as List (⌃⌘3)")])
    let field = NSSearchField()
    private(set) var styleSymbol = "rectangle.grid.2x2"

    private let backdrop = CAGradientLayer()
    private let nav = GlassGroup(items: [(symbol: "chevron.left", tip: "Back"), (symbol: "chevron.right", tip: "Forward"),
                                         (symbol: "chevron.up", tip: "Enclosing Folder")])
    private let crumbs = NSStackView()
    private let subtitle = NSTextField(labelWithString: "")
    private let kind = GlassCapsule(titles: BrowserKindFilter.allCases.map(\.title))
    private let sortCapsule = GlassCapsule(titles: HomeToolbar.keyTitles.map(\.1))
    private var crumbLocations: [BrowserLocation] = []
    private var siblingMenu: NSMenu?
    private var siblingLocations: [BrowserLocation] = []
    private var sort = BrowserSort.standard
    /// The sort capsule's fields, in order (⌥1 is the first).
    private(set) var sortKeys: [BrowserSort.Key] = [.name, .date, .size]
    /// A page's filter in place of the kind filter; empty: the kind filter.
    private var pageFilterTitles: [String] = []

    private static let keyTitles: [(BrowserSort.Key, String)] = [(.name, "Name"), (.date, "Date"), (.size, "Size")]
    private static let edge: CGFloat = 20
    private static let spacing: CGFloat = 10

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(backdrop)
        updateBackdrop()
        sidebarButton.onPress = { [weak self] _ in self?.onSidebar?() }
        homeButton.onPress = { [weak self] _ in self?.onHome?() }
        nav.onPress = { [weak self] i in
            switch i {
            case 0: self?.onBack?()
            case 1: self?.onForward?()
            default: self?.onUp?()
            }
        }
        crumbs.orientation = .horizontal
        crumbs.spacing = 2
        subtitle.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        kind.selected = 0
        kind.onChoose = { [weak self] i in self?.clickKind(i) }
        sortCapsule.onChoose = { [weak self] i in self?.clickSort(i) }
        zoom.onPress = { [weak self] i in self?.onZoom?(i == 0 ? .smaller : .larger) }
        styleButton.onPress = { [weak self] _ in self?.onStyle?() }
        cardSwitch.onPress = { [weak self] i in self?.clickCardStyle(i) }
        cardSwitch.selected = 0
        cardSwitch.isHidden = true
        field.placeholderString = "Filter"
        field.sendsSearchStringImmediately = true
        field.delegate = self
        field.controlSize = .regular
        for view in [sidebarButton, homeButton, nav, crumbs, subtitle, kind, sortCapsule, zoom, styleButton, cardSwitch, field, loading] as [NSView] {
            addSubview(view)
        }
        showSort()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    /// Only the controls take clicks.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self || hit === crumbs ? nil : hit
    }

    private func updateBackdrop() {
        backdrop.colors = [Chrome.resolve(background.withAlphaComponent(0.9), in: self),
                           Chrome.resolve(background.withAlphaComponent(0), in: self)]
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackdrop()
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = Self.height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = CGRect(x: 0, y: 0, width: w, height: h + 12)
        CATransaction.commit()
        let controlY = (h - GlassCapsule.height) / 2
        func size(_ v: NSView) -> CGSize { v.intrinsicContentSize }
        sidebarButton.frame = CGRect(origin: CGPoint(x: Self.edge, y: controlY), size: size(sidebarButton))
        homeButton.frame = CGRect(origin: CGPoint(x: sidebarButton.frame.maxX + Self.spacing, y: controlY),
                                  size: size(homeButton))
        nav.frame = CGRect(origin: CGPoint(x: homeButton.frame.maxX + Self.spacing, y: controlY), size: size(nav))
        var right = w - Self.edge
        if !field.isHidden {
            field.frame = CGRect(x: right - 180, y: (h - 24) / 2, width: 180, height: 24)
            right = field.frame.minX - Self.spacing
        }
        for v in [styleButton, cardSwitch, zoom, sortCapsule] as [NSView] where !v.isHidden {
            let s = size(v)
            v.frame = CGRect(x: right - s.width, y: controlY, width: s.width, height: s.height)
            right = v.frame.minX - Self.spacing
        }
        let k = size(kind)
        // Centred, unless the right group reaches the middle: then just left of it.
        let kindX = min(((w - k.width) / 2).rounded(), right - k.width)
        kind.frame = CGRect(x: kindX, y: controlY, width: k.width, height: k.height)
        let pathRight = (kind.isHidden ? right : min(right, kind.frame.minX - Self.spacing))
        let left = (nav.isHidden ? homeButton.frame.maxX : nav.frame.maxX) + 14
        crumbs.frame = CGRect(x: left, y: 8, width: max(0, pathRight - left), height: 22)
        subtitle.frame = CGRect(x: left + 4, y: 32, width: max(0, pathRight - left - 4), height: 15)
        loading.frame = CGRect(x: 0, y: h - 2, width: w, height: 2)
    }

    // MARK: Shown

    var crumbTitles: [String] { crumbButtons.map(\.title) }
    var crumbFonts: [NSFont] { crumbButtons.compactMap(\.font) }
    var subtitleText: String { subtitle.stringValue }
    var sortTitles: [String] { sortCapsule.titles }
    var kindTitles: [String] { kind.titles }
    var navFrame: CGRect { nav.frame }
    var isNavVisible: Bool { !nav.isHidden }
    var isSortVisible: Bool { !sortCapsule.isHidden }
    var isFilterVisible: Bool { !kind.isHidden }
    var kindFrame: CGRect { kind.frame }
    var sortFrame: CGRect { sortCapsule.frame }
    var isCardSwitchVisible: Bool { !cardSwitch.isHidden }
    /// The lit segment: 0 posters, 1 cards, 2 list.
    var cardSwitchSelection: Int? { cardSwitch.selected }
    var filterText: String {
        get { field.stringValue }
        set { field.stringValue = newValue }
    }

    private var crumbButtons: [NSButton] {
        crumbs.arrangedSubviews.compactMap { $0 as? NSButton }.filter { $0.identifier != Self.arrowID }
    }
    private static let arrowID = NSUserInterfaceItemIdentifier("sibling-arrow")

    func show(path: [(title: String, location: BrowserLocation)], canBack: Bool, canForward: Bool, canUp: Bool) {
        if nav.isHidden {
            nav.isHidden = false
            needsLayout = true
        }
        nav.setEnabled(canBack, at: 0)
        nav.setEnabled(canForward, at: 1)
        nav.setEnabled(canUp, at: 2)
        crumbs.arrangedSubviews.forEach { $0.removeFromSuperview() }
        crumbLocations = path.map(\.location)
        for (i, crumb) in path.enumerated() {
            let last = i == path.count - 1
            if i > 0 {
                // The › opens a menu of the folders beside this crumb.
                let arrow = NSButton(title: "›", target: self, action: #selector(siblingsClicked(_:)))
                arrow.isBordered = false
                arrow.refusesFirstResponder = true
                arrow.font = .systemFont(ofSize: 15)
                arrow.contentTintColor = .tertiaryLabelColor
                arrow.tag = i
                arrow.identifier = Self.arrowID
                crumbs.addArrangedSubview(arrow)
            }
            let b = NSButton(title: crumb.title, target: self, action: #selector(crumbClicked(_:)))
            b.isBordered = false
            b.refusesFirstResponder = true
            b.tag = i
            b.font = .systemFont(ofSize: 15, weight: last ? .semibold : .regular)
            b.contentTintColor = last ? .labelColor : .secondaryLabelColor
            b.lineBreakMode = .byTruncatingMiddle
            // The first crumbs give way first.
            b.setContentCompressionResistancePriority(.init(Float(250 + i)), for: .horizontal)
            crumbs.addArrangedSubview(b)
        }
    }

    /// A source's title in place of the path; ‹ › ↑ go until the next path.
    func show(title: String) {
        nav.isHidden = true
        crumbs.arrangedSubviews.forEach { $0.removeFromSuperview() }
        crumbLocations = []
        let b = NSButton(title: title, target: nil, action: nil)
        b.isBordered = false
        b.refusesFirstResponder = true
        b.font = .systemFont(ofSize: 15, weight: .semibold)
        b.contentTintColor = .labelColor
        crumbs.addArrangedSubview(b)
        needsLayout = true
    }

    func show(subtitle text: String) { subtitle.stringValue = text }

    /// The sort capsule with `keys` as its fields, in that order; none hides it.
    func show(sort: BrowserSort, keys: [BrowserSort.Key]) {
        self.sort = sort
        sortKeys = keys
        sortCapsule.isHidden = keys.isEmpty
        showSort()
    }

    /// A page's filter (Stash: Scenes · Images · Galleries) in the middle; empty gives the kind filter back.
    func show(pageFilters titles: [String], selected: Int?) {
        if titles != pageFilterTitles {
            pageFilterTitles = titles
            kind.titles = titles.isEmpty ? BrowserKindFilter.allCases.map(\.title) : titles
        }
        if !titles.isEmpty {
            kind.selected = selected
            kind.isHidden = false
        }
        needsLayout = true
    }

    /// The name field, − | + and the style button: off on a page.
    func show(controls: Bool) {
        guard field.isHidden == controls else { return }
        for v in [field, zoom, styleButton] as [NSView] { v.isHidden = !controls }
        if !controls { cardSwitch.isHidden = true }
        needsLayout = true
    }

    func show(filter: BrowserKindFilter, visible: Bool) {
        guard pageFilterTitles.isEmpty else { return }
        kind.selected = BrowserKindFilter.allCases.firstIndex(of: filter)
        guard kind.isHidden == visible else { return }
        kind.isHidden = !visible
        needsLayout = true
    }

    func show(style: GridStyle) {
        styleSymbol = style == .square ? "square.grid.2x2" : "rectangle.grid.2x2"
        styleButton.setSymbol(styleSymbol, at: 0)
    }

    /// The switch lit for `style`; shown only where there are folder cards (`visible`).
    func show(cardStyle style: CardStyle, visible: Bool) {
        cardSwitch.selected = CardStyle.allCases.firstIndex(of: style)
        guard cardSwitch.isHidden == visible else { return }
        cardSwitch.isHidden = !visible
        needsLayout = true
    }

    func focusFilter() { window?.makeFirstResponder(field) }

    private func showSort() {
        sortCapsule.titles = sortKeys.map { key in
            let name = Self.keyTitles.first { $0.0 == key }?.1 ?? key.rawValue
            return key == sort.key ? name + (sort.ascending ? " ↑" : " ↓") : name
        }
        sortCapsule.selected = sortKeys.firstIndex(of: sort.key)
        needsLayout = true
    }

    // MARK: Clicks

    func clickSort(_ i: Int) {
        guard sortKeys.indices.contains(i) else { return }
        onSortKey?(sortKeys[i])
        showSort()   // the active field stays lit until the view shows the new sort
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

    func clickCrumb(_ i: Int) {
        if crumbLocations.indices.contains(i) { onCrumb?(crumbLocations[i]) }
    }

    @objc private func crumbClicked(_ sender: NSButton) { clickCrumb(sender.tag) }

    // MARK: Sibling menus

    var siblingTitles: [String] { siblingMenu?.items.map(\.title) ?? [] }
    var siblingChecked: [Bool] { siblingMenu?.items.map { $0.state == .on } ?? [] }

    func clickSiblings(_ i: Int) { onSiblings?(i) }

    @objc private func siblingsClicked(_ sender: NSButton) { clickSiblings(sender.tag) }

    /// The menu under the › before crumb `i`, at once: the folders when known, else one `Loading…` line.
    func showSiblings(_ entries: [(title: String, location: BrowserLocation, current: Bool)]?, at i: Int) {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        siblingMenu = menu
        fill(menu, entries)
        let anchor = crumbs.arrangedSubviews.first { ($0 as? NSButton)?.identifier == Self.arrowID && $0.tag == i } ?? crumbs
        popUp(menu, anchor)
    }

    /// The reply for the open menu.
    func updateSiblings(_ entries: [(title: String, location: BrowserLocation, current: Bool)]) {
        guard let menu = siblingMenu else { return }
        fill(menu, entries)
    }

    func chooseSibling(_ i: Int) {
        guard siblingLocations.indices.contains(i) else { return }
        let location = siblingLocations[i]
        siblingMenu?.cancelTracking()
        onCrumb?(location)
    }

    func closeSiblings() {
        guard siblingMenu != nil else { return }
        siblingMenu = nil
        onSiblingsClosed?()
    }

    func menuDidClose(_ menu: NSMenu) {
        // The chosen item's action comes after the close: the menu's items stay readable until the next one opens.
        if menu === siblingMenu { onSiblingsClosed?() }
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
        onFilterText?(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        field.stringValue = ""
        onFilterText?("")
        onFilterEnd?()
        return true
    }
}
