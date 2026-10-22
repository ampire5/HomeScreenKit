import AppKit
import HomeChrome
import HomeScreenModel

/// The home screen: a switch at the top (with two or more tabs), and on the first tab a grid of cards in sections;
/// on the others the app's own view goes under the switch (`contentTop`). The arrows move the selection and Return
/// opens it (⌘Return a new tab, ⇧Return a new window, where the app has tabs); the switch never takes the keys.
/// `showMessage` puts a centred message in place of the grid (why a file did not open).
public final class HomeScreenView: NSView {
    // MARK: Set by the app

    /// The switch's titles; fewer than two hide it.
    public var tabs: [String] = [] { didSet { if tabs != oldValue { relabelSwitch() }; update() } }
    public var selectedTab = 0 { didSet { update() } }
    /// Cards in sections, top down. Setting it makes the cards again; their pictures come from `setImage`.
    public var sections: [HomeSection] = [] { didSet { rebuildCards() } }
    /// A picture's height over its width (2/3 photos, 9/16 video).
    public var aspect: CGFloat = 2.0 / 3 { didSet { cards.forEach { $0.aspect = aspect }; needsLayout = true } }
    public var layoutMode = HomeLayoutMode.fit { didSet { needsLayout = true } }
    /// The cards' width in points (the largest one with `fit`).
    public var cardSize: CGFloat = 220 { didSet { if cardSize != oldValue { needsLayout = true } } }
    /// ⌘ / ⇧ / the middle button open in a new tab or window; without tabs every click opens here.
    public var supportsTabs = true
    /// Shown in the middle while there are no cards.
    public var emptyHint = "" { didSet { hint.stringValue = emptyHint } }

    public var onTab: ((Int) -> Void)?
    /// A card's id and where to open it.
    public var onCard: ((String, HomeClick) -> Void)?
    /// A card's id and the chosen menu item's id.
    public var onMenu: ((String, String) -> Void)?
    /// A file dropped on the screen. Nil leaves drops to what is under the screen: AppKit finds a drop's view by the
    /// registered types, not by `hitTest`, so the screen registers only while it has a handler.
    public var onDrop: ((URL) -> Void)? {
        didSet {
            if onDrop == nil { unregisterDraggedTypes() } else { registerForDraggedTypes([.fileURL]) }
        }
    }

    /// A card size step: ⌘= / ⌘− / ⌘0, ⌘ + wheel, a pinch, a mouse's side wheel (right is larger), or `resize(notches:)`.
    public var onResize: ((HomeResize) -> Void)?

    /// Where the app's view for the other tabs goes: under the switch.
    public var contentTop: NSLayoutYAxisAnchor { bar.bottomAnchor }

    // MARK: Read by the app

    /// The cards on screen now, top down: their pictures are wanted first.
    public var visibleIDs: [String] {
        let visible = scroll.contentView.documentVisibleRect
        return cards.filter { $0.frame.intersects(visible) }.map(\.item.id)
    }

    /// A card's width in points now.
    public var pictureWidth: CGFloat { lastFit?.cardWidth ?? cardSize }

    public private(set) var isShowingMessage = false

    // MARK: Parts

    private let transparent: Bool
    private let metrics = HomeMetrics()
    let switcher = NSSegmentedControl()
    private let bar = NSView()
    private var barHeight: NSLayoutConstraint!
    private let scroll = GridScrollView()
    /// The grid's scroll view: wheel and pinch reach it, and it turns resize gestures into `onResize`.
    var gridScrollView: NSScrollView { scroll }
    private let document = FlippedView()
    private let hint = NSTextField(labelWithString: "")
    private let message = HomeMessageView()
    private var headings: [NSTextField?] = []
    private var cardsBySection: [[HomeCard]] = []
    private var cards: [HomeCard] { cardsBySection.flatMap { $0 } }
    private var columns = 1
    private var selected = 0
    private var lastFit: HomeGridFit?

    /// `background` nil: transparent, and only the cards and the switch take the mouse (what is under the screen gets
    /// the rest); else filled with it.
    public init(background: CGColor?) {
        transparent = background == nil
        super.init(frame: .zero)
        if let background {
            wantsLayer = true
            layer?.backgroundColor = background
        }
        bar.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document
        scroll.onResize = { [weak self] step in self?.onResize?(step) }
        hint.font = Chrome.Text.font(.title, weight: .regular)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        for view in [bar, scroll, hint, message] { addSubview(view) }
        barHeight = bar.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            barHeight,
            bar.leadingAnchor.constraint(equalTo: leadingAnchor), bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            hint.centerXAnchor.constraint(equalTo: centerXAnchor), hint.centerYAnchor.constraint(equalTo: centerYAnchor),
            message.centerXAnchor.constraint(equalTo: centerXAnchor), message.centerYAnchor.constraint(equalTo: centerYAnchor),
            message.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -32),
        ])
        switcher.trackingMode = .selectOne
        switcher.target = self
        switcher.action = #selector(switched(_:))
        switcher.refusesFirstResponder = true
        switcher.translatesAutoresizingMaskIntoConstraints = false
        addSubview(switcher)
        NSLayoutConstraint.activate([
            switcher.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
            switcher.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
        update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Pictures

    /// A card's picture; an id not on screen (the list changed meanwhile) is ignored.
    public func setImage(_ image: CGImage?, for id: String) {
        cardView(for: id)?.image = image
    }

    func cardView(for id: String) -> HomeCard? {
        cards.first { $0.item.id == id }
    }

    // MARK: Message

    /// A centred message in place of the grid and the switch: a title, why, the details and a line of keys.
    public func showMessage(title text: String, reason: String, detail: String, hints keys: [String]) {
        message.show(title: text, reason: reason, detail: detail, hints: keys)
        isShowingMessage = true
        update()
    }

    /// The grid (and the switch) again.
    public func showGrid() {
        isShowingMessage = false
        update()
    }

    // MARK: Building

    /// New titles on the same control: one replaced while its click is being handled would be released mid-action.
    private func relabelSwitch() {
        switcher.segmentCount = tabs.count
        for (i, title) in tabs.enumerated() {
            switcher.setLabel(title, forSegment: i)
            switcher.setWidth(0, forSegment: i)   // sized to the title
        }
    }

    /// The same cards in the same sections (a picture, a time or dimming changed) are updated in place, keeping the
    /// pictures, the hover and an open menu; anything else makes them again.
    private func updateCards() -> Bool {
        let shown = sections.filter { !$0.items.isEmpty }
        guard shown.count == cardsBySection.count else { return false }
        for (section, cards) in zip(shown, cardsBySection) {
            guard section.items.map(\.id) == cards.map(\.item.id) else { return false }
        }
        for (s, section) in shown.enumerated() {
            guard (section.title == nil) == (headings[s] == nil) else { return false }
        }
        for (s, section) in shown.enumerated() {
            headings[s]?.stringValue = section.title ?? ""
            for (card, item) in zip(cardsBySection[s], section.items) where card.item != item { card.show(item) }
        }
        return true
    }

    private func rebuildCards() {
        if !cards.isEmpty, updateCards() { return }
        cards.forEach { $0.removeFromSuperview() }
        headings.forEach { $0?.removeFromSuperview() }
        cardsBySection = []
        headings = []
        var offset = 0
        for section in sections where !section.items.isEmpty {
            if let title = section.title {
                let heading = NSTextField(labelWithString: title)
                heading.font = Chrome.Text.font(.hero)
                heading.textColor = Chrome.Palette.window.label
                document.addSubview(heading)
                headings.append(heading)
            } else {
                headings.append(nil)
            }
            let start = offset
            cardsBySection.append(section.items.enumerated().map { i, item in
                let card = HomeCard(item: item, aspect: aspect)
                let index = start + i
                card.onClick = { [weak self] middle, flags in self?.click(index, middle: middle, flags: flags) }
                card.onHover = { [weak self] in self?.select(index, scrolls: false) }
                card.onMenu = { [weak self, id = item.id] itemID in self?.onMenu?(id, itemID) }
                document.addSubview(card)
                return card
            })
            offset += section.items.count
        }
        selected = min(selected, max(cards.count - 1, 0))
        select(selected, scrolls: false)
        update()
        needsLayout = true
    }

    // MARK: Layout

    public override func layout() {
        barHeight.constant = switcher.isHidden ? 0 : switcher.fittingSize.height + 16
        super.layout()
        let area = scroll.contentSize
        let shape = cardsBySection.enumerated().map { (count: $1.count, heading: headings[$0] != nil) }
        let fit = HomeLayout.fit(mode: layoutMode, area: area, cardSize: cardSize, aspect: aspect, sections: shape,
                                 metrics: metrics)
        lastFit = fit
        columns = fit.columns
        scroll.hasVerticalScroller = fit.scrolls
        let cardHeight = HomeLayout.cardHeight(width: fit.cardWidth, aspect: aspect, metrics: metrics)
        var y = metrics.top
        for (s, section) in cardsBySection.enumerated() {
            if s > 0 { y += metrics.rowSpacing + metrics.sectionGap }
            if let heading = headings[s] {
                heading.frame = CGRect(x: metrics.inset, y: y, width: max(0, area.width - 2 * metrics.inset),
                                       height: metrics.headingHeight)
                y += metrics.headingHeight + metrics.headingGap
            }
            for (i, card) in section.enumerated() {
                let row = i / columns, column = i % columns
                card.frame = CGRect(x: metrics.inset + CGFloat(column) * (fit.cardWidth + metrics.spacing),
                                    y: y + CGFloat(row) * (cardHeight + metrics.rowSpacing),
                                    width: fit.cardWidth, height: cardHeight)
            }
            let rows = (section.count + columns - 1) / columns
            y += CGFloat(rows) * cardHeight + CGFloat(rows - 1) * metrics.rowSpacing
        }
        let height = fit.scrolls ? max(y + metrics.inset, area.height) : area.height
        document.frame = CGRect(x: 0, y: 0, width: area.width, height: height)
    }

    // MARK: Tabs

    @objc private func switched(_ sender: NSSegmentedControl) {
        guard sender.selectedSegment != selectedTab else { return }
        selectedTab = sender.selectedSegment
        onTab?(selectedTab)
    }

    /// The grid is the first tab's.
    private var onGridTab: Bool { tabs.count < 2 || selectedTab == 0 }

    private func update() {
        switcher.isHidden = tabs.count < 2 || isShowingMessage
        if !switcher.isHidden { switcher.selectedSegment = selectedTab }
        message.isHidden = !isShowingMessage
        scroll.isHidden = isShowingMessage || !onGridTab
        hint.isHidden = isShowingMessage || !onGridTab || !cards.isEmpty
        needsLayout = true
    }

    var showsEmptyHint: Bool { !hint.isHidden }

    // MARK: Mouse

    public override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        guard transparent, let hit else { return hit }
        if !switcher.isHidden, hit === switcher || hit.isDescendant(of: switcher) { return hit }
        if hit is HomeCard { return hit }
        // A grid that scrolls needs its scroll view (the wheel); one that does not lets the rest through.
        // Wheel and pinch over the grid are the screen's (resize, scroll), not the video's under it.
        if let type = NSApp.currentEvent?.type, type == .scrollWheel || type == .magnify, !scroll.isHidden,
           hit.isDescendant(of: scroll) || hit === scroll {
            return hit
        }
        let overflows = document.frame.height > scroll.contentSize.height
        if overflows, !scroll.isHidden, hit.isDescendant(of: scroll) { return hit }
        return nil
    }

    // MARK: Keys

    public override var acceptsFirstResponder: Bool { true }

    public override func keyDown(with event: NSEvent) {
        if !handleKey(event) { super.keyDown(with: event) }
    }

    /// Arrows and Return over the cards; false for any other key, or when no cards are on screen.
    public func handleKey(_ event: NSEvent) -> Bool {
        guard !isShowingMessage, onGridTab else { return false }
        if event.modifierFlags.contains(.command), let resize = Self.resizeKeys[event.keyCode] {
            onResize?(resize)
            return true
        }
        guard !cards.isEmpty else { return false }
        switch event.keyCode {
        case 123: select(selected - 1)
        case 124: select(selected + 1)
        case 125: if selected + columns < cards.count { select(selected + columns) }
        case 126: if selected - columns >= 0 { select(selected - columns) }
        case 36, 76: click(selected, middle: false, flags: event.modifierFlags)
        default: return false
        }
        return true
    }

    /// ⌘= (and ⌘+, keypad +) larger, ⌘− smaller, ⌘0 the default size: a browser's zoom keys.
    static let resizeKeys: [UInt16: HomeResize] = [24: .larger, 69: .larger, 27: .smaller, 78: .smaller,
                                                            29: .reset, 82: .reset]

    /// Size steps from a wheel or a mouse's side wheel: positive larger; a step for each whole notch.
    public func resize(notches: Double) { scroll.resize(notches: notches) }

    /// Hovering selects without scrolling (a scroll under a still pointer would select the next card).
    private func select(_ index: Int, scrolls: Bool = true) {
        let all = cards
        guard all.indices.contains(index) else { return }
        selected = index
        for (i, card) in all.enumerated() { card.isSelected = i == index }
        if scrolls { document.scrollToVisible(all[index].frame.insetBy(dx: 0, dy: -metrics.rowSpacing)) }
    }

    private func click(_ index: Int, middle: Bool, flags: NSEvent.ModifierFlags) {
        let all = cards
        guard all.indices.contains(index) else { return }
        let kind = HomeClick.from(shift: flags.contains(.shift), command: flags.contains(.command), middle: middle,
                                  supportsTabs: supportsTabs)
        onCard?(all[index].item.id, kind)
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

/// The grid's document view: top-down, as the cards are laid out.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
