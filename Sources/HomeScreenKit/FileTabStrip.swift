import AppKit
import HomeChrome
import HomeScreenModel

final class FileTabStrip: NSView {
    static let height: CGFloat = 34
    var onAdd: (() -> Void)?
    var onSelect: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?
    var onMove: ((UUID, Int) -> Void)?

    private struct Item: Equatable {
        let id: UUID
        let title: String
        let path: String?
    }

    private var items: [Item] = []
    private var selected: UUID?
    private var groups: [UUID: TabGroup] = [:]
    private let scroll = NSScrollView()
    private let tabs = NSStackView()
    private let scrollFade = CAGradientLayer()
    private var tabsWidth: CGFloat = 0
    private var revealsSelection = false
    private lazy var add = NSButton(image: Self.symbol("plus", description: "New Tab"),
                                    target: self, action: #selector(addTab))
    private lazy var overflow = NSButton(image: Self.symbol("chevron.down", description: "Show All Tabs"),
                                         target: self, action: #selector(showAllTabs(_:)))

    init() {
        super.init(frame: .zero)
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.contentView.wantsLayer = true
        scroll.contentView.postsBoundsChangedNotifications = true
        scrollFade.startPoint = CGPoint(x: 0, y: 0.5)
        scrollFade.endPoint = CGPoint(x: 1, y: 0.5)
        scrollFade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        NotificationCenter.default.addObserver(self, selector: #selector(updateScrollFade),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        tabs.orientation = .horizontal
        tabs.alignment = .centerY
        tabs.spacing = 4
        scroll.documentView = tabs

        for (button, title) in [(add, "New Tab"), (overflow, "Show All Tabs")] {
            button.bezelStyle = .accessoryBarAction
            button.controlSize = .small
            button.toolTip = title
            button.setAccessibilityLabel(title)
        }
        overflow.isHidden = true
        let line = NSBox()
        line.boxType = .separator

        for view in [scroll, add, overflow, line] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let margin: CGFloat = 20
        let gap: CGFloat = 4
        let buttonWidth: CGFloat = 26
        let controlHeight: CGFloat = 24
        let available = max(0, bounds.width - 2 * margin - gap - buttonWidth)
        let overflowing = tabsWidth > available
        let viewport = max(0, available - (overflowing ? buttonWidth + gap : 0))
        let oldWidth = scroll.frame.width
        // The scroll document can grow independently of this view and the window's minimum size.
        scroll.frame = NSRect(x: margin, y: 0, width: min(tabsWidth, viewport), height: bounds.height)
        tabs.setFrameSize(NSSize(width: tabsWidth, height: bounds.height))
        let y = (bounds.height - controlHeight) / 2
        add.frame = NSRect(x: scroll.frame.maxX + gap, y: y, width: buttonWidth, height: controlHeight)
        overflow.frame = NSRect(x: add.frame.maxX + gap, y: y, width: buttonWidth, height: controlHeight)
        overflow.isHidden = !overflowing || viewport == 0
        if scroll.frame.width > 0, revealsSelection || oldWidth != scroll.frame.width {
            revealsSelection = false
            tabs.layoutSubtreeIfNeeded()
            if let selected, let group = groups[selected] {
                var visibleTab = group.bounds
                visibleTab.size.width = min(visibleTab.width, scroll.frame.width)
                group.scrollToVisible(visibleTab)
            }
        }
        updateScrollFade()
    }

    @objc private func updateScrollFade() {
        guard let clip = scroll.contentView.layer else { return }
        let visible = scroll.documentVisibleRect
        let fadeLeft = visible.minX > 1
        let fadeRight = visible.maxX < tabsWidth - 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if visible.width > 0, fadeLeft || fadeRight {
            let edge = min(0.2, 12 / visible.width)
            scrollFade.frame = clip.bounds
            scrollFade.locations = [0, NSNumber(value: fadeLeft ? edge : 0),
                                    NSNumber(value: fadeRight ? 1 - edge : 1), 1]
            if clip.mask == nil { clip.mask = scrollFade }
        } else if clip.mask === scrollFade {
            clip.mask = nil
        }
        CATransaction.commit()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        // AppKit may invalidate outside an unclipped view's bounds.
        dirtyRect.intersection(bounds).fill()
    }

    private static func symbol(_ name: String, description: String) -> NSImage {
        Icons.symbol(name, pointSize: 10, weight: .semibold, description: description) ?? NSImage()
    }

    func show(_ tabs: [HomeFileTab], selected: UUID?) {
        let next = tabs.map { tab in
            let folder = tab.navigation.folder
            let title = folder.map { $0.lastPathComponent.isEmpty ? $0.path : $0.lastPathComponent } ?? "Places"
            return Item(id: tab.id, title: title, path: folder?.path)
        }
        guard next != items || selected != self.selected else { return }
        if next != items {
            updateTabs(next)
            items = next
        }
        if let old = self.selected, old != selected { groups[old]?.isSelected = false }
        self.selected = selected
        if let selected { groups[selected]?.isSelected = true }
        revealsSelection = true
        needsLayout = true
        if bounds.width > 0 { layoutSubtreeIfNeeded() }
    }

    private func updateTabs(_ next: [Item]) {
        let nextIDs = next.map(\.id)
        let orderChanged = nextIDs != items.map(\.id)
        let previous = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let canClose = next.count > 1
        let closeControlsChanged = canClose != (items.count > 1)
        if orderChanged {
            let retained = Set(nextIDs)
            for id in groups.keys.filter({ !retained.contains($0) }) {
                groups.removeValue(forKey: id)?.removeFromSuperview()
            }
        }
        for (index, item) in next.enumerated() {
            let group: TabGroup
            if let existing = groups[item.id] {
                group = existing
            } else {
                let tab = TabButton(id: item.id, title: item.title, target: self, action: #selector(selectTab(_:)))
                let close = TabButton(id: item.id, title: "", target: self, action: #selector(closeTab(_:)))
                close.image = Self.symbol("xmark", description: "Close Tab")
                group = TabGroup(tab: tab, close: close)
                groups[item.id] = group
            }
            if previous[item.id] != item || closeControlsChanged {
                group.show(title: item.title, path: item.path, canClose: canClose)
            }
            if orderChanged {
                tabs.insertArrangedSubview(group, at: index)
                group.tab.menu = menu(for: item.id, index: index, count: next.count)
            }
        }
        tabsWidth = tabs.fittingSize.width
    }

    private func menu(for id: UUID, index: Int, count: Int) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        func item(_ title: String, action: Selector, enabled: Bool) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = id
            item.isEnabled = enabled
            menu.addItem(item)
        }
        item("Move Tab Left", action: #selector(moveTabLeft(_:)), enabled: index > 0)
        item("Move Tab Right", action: #selector(moveTabRight(_:)), enabled: index + 1 < count)
        return menu
    }

    @objc private func addTab() { onAdd?() }
    @objc private func selectTab(_ sender: TabButton) {
        sender.state = sender.id == selected ? .on : .off
        onSelect?(sender.id)
    }
    @objc private func showAllTabs(_ sender: NSButton) {
        let menu = NSMenu()
        let titleCounts = Dictionary(grouping: items, by: \.title)
        for item in items {
            let othersHaveSameTitle = (titleCounts[item.title]?.count ?? 0) > 1
            let title = othersHaveSameTitle ? item.path ?? item.title : item.title
            let entry = menu.addItem(withTitle: title, action: #selector(chooseTab(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = item.id
            entry.state = item.id == selected ? .on : .off
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.isFlipped ? sender.bounds.maxY : 0), in: sender)
    }
    @objc private func chooseTab(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { onSelect?(id) }
    }
    @objc private func closeTab(_ sender: TabButton) { onClose?(sender.id) }
    @objc private func moveTabLeft(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { onMove?(id, -1) }
    }
    @objc private func moveTabRight(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { onMove?(id, 1) }
    }
}

private final class TabGroup: NSStackView {
    let tab: TabButton
    private let close: TabButton
    private var hovering = false
    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            tab.state = isSelected ? .on : .off
            paint()
        }
    }

    init(tab: TabButton, close: TabButton) {
        self.tab = tab
        self.close = close
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 4
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        setHuggingPriority(.required, for: .horizontal)
        tab.setButtonType(.onOff)
        tab.setAccessibilityRole(.radioButton)
        close.contentTintColor = .secondaryLabelColor
        close.toolTip = "Close Tab"
        addArrangedSubview(tab)
        addArrangedSubview(close)
        close.isHidden = true
        NSLayoutConstraint.activate([
            close.widthAnchor.constraint(equalToConstant: 22),
            close.heightAnchor.constraint(equalTo: heightAnchor),
            tab.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            tab.widthAnchor.constraint(lessThanOrEqualToConstant: 160),
            tab.heightAnchor.constraint(equalTo: heightAnchor),
            heightAnchor.constraint(equalToConstant: 24),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self))
        paint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(title: String, path: String?, canClose: Bool) {
        tab.title = title
        tab.toolTip = path ?? title
        tab.setAccessibilityHelp(path)
        close.isHidden = !canClose
        close.setAccessibilityLabel("Close \(title) tab")
        edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: canClose ? 4 : 8)
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; paint() }
    override func mouseExited(with event: NSEvent) { hovering = false; paint() }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    private func paint() {
        let accent = Chrome.Palette.window.accent
        let color = isSelected ? accent.withAlphaComponent(hovering ? 0.21 : 0.15)
            : NSColor.labelColor.withAlphaComponent(hovering ? 0.08 : 0.035)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = Chrome.resolve(color, in: self)
        layer?.borderWidth = isSelected ? 1 : 0
        layer?.borderColor = isSelected ? Chrome.resolve(accent.withAlphaComponent(0.3), in: self) : nil
        CATransaction.commit()
    }
}

private final class TabButton: NSButton {
    let id: UUID

    init(id: UUID, title: String, target: AnyObject, action: Selector) {
        self.id = id
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        controlSize = .small
        font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        lineBreakMode = .byTruncatingMiddle
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
