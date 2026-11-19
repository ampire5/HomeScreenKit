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
    private var buttons: [UUID: TabButton] = [:]
    private let scroll = NSScrollView()
    private let tabs = NSStackView()
    private var tabsWidth: CGFloat = 0
    private lazy var add = NSButton(image: Self.symbol("plus", description: "New Tab"),
                                    target: self, action: #selector(addTab))

    init() {
        super.init(frame: .zero)
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        tabs.orientation = .horizontal
        tabs.alignment = .centerY
        tabs.spacing = 4
        scroll.documentView = tabs

        add.bezelStyle = .accessoryBarAction
        add.controlSize = .small
        add.toolTip = "New Tab"
        add.setAccessibilityLabel("New Tab")
        let line = NSBox()
        line.boxType = .separator

        for view in [scroll, add, line] {
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
        let addWidth: CGFloat = 26
        let controlHeight: CGFloat = 24
        let availableWidth = max(0, bounds.width - 2 * margin - gap - addWidth)
        // The scroll document can grow independently of this view and the window's minimum size.
        scroll.frame = NSRect(x: margin, y: 0, width: min(tabsWidth, availableWidth), height: bounds.height)
        tabs.setFrameSize(NSSize(width: tabsWidth, height: bounds.height))
        add.frame = NSRect(x: scroll.frame.maxX + gap, y: (bounds.height - controlHeight) / 2,
                           width: addWidth, height: controlHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        // AppKit may invalidate outside an unclipped view's bounds.
        dirtyRect.intersection(bounds).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        updateSelection()
    }

    private func updateSelection() {
        let accent = NSColor.controlAccentColor.withAlphaComponent(0.18)
        let inactive = NSColor.labelColor.withAlphaComponent(0.06)
        for (id, button) in buttons {
            button.state = id == selected ? .on : .off
            let color = button.state == .on ? accent : inactive
            if let pair = button.superview {
                pair.layer?.backgroundColor = Chrome.resolve(color, in: pair)
            }
        }
    }

    private static func symbol(_ name: String, description: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold)) ?? NSImage()
    }

    func show(_ tabs: [HomeFileTab], selected: UUID?) {
        let next = tabs.map { tab in
            let folder = tab.navigation.folder
            let title = folder.map { $0.lastPathComponent.isEmpty ? $0.path : $0.lastPathComponent } ?? "Places"
            return Item(id: tab.id, title: title, path: folder?.path)
        }
        guard next != items || selected != self.selected else { return }
        if next != items {
            items = next
            rebuildTabs()
        }
        self.selected = selected
        updateSelection()
        if let selected, let button = buttons[selected] {
            layoutSubtreeIfNeeded()
            if let pair = button.superview { pair.scrollToVisible(pair.bounds) }
        }
    }

    private func rebuildTabs() {
        for view in tabs.arrangedSubviews { view.removeFromSuperview() }
        buttons.removeAll(keepingCapacity: true)
        for (index, item) in items.enumerated() {
            let id = item.id
            let button = TabButton(id: id, title: item.title, target: self, action: #selector(selectTab(_:)))
            button.setButtonType(.onOff)
            button.setAccessibilityRole(.radioButton)
            button.toolTip = item.path ?? item.title
            button.menu = menu(for: id, index: index)
            let pair = NSStackView(views: [button])
            pair.orientation = .horizontal
            pair.alignment = .centerY
            pair.spacing = 4
            pair.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: items.count > 1 ? 4 : 8)
            pair.wantsLayer = true
            pair.layer?.cornerRadius = 7
            pair.layer?.cornerCurve = .continuous
            pair.setHuggingPriority(.required, for: .horizontal)
            if items.count > 1 {
                let close = TabButton(id: id, title: "", target: self, action: #selector(closeTab(_:)))
                close.image = Self.symbol("xmark", description: "Close Tab")
                close.contentTintColor = .secondaryLabelColor
                close.setAccessibilityLabel("Close \(item.title) tab")
                close.toolTip = "Close Tab"
                pair.addArrangedSubview(close)
                close.widthAnchor.constraint(equalToConstant: 20).isActive = true
                close.heightAnchor.constraint(equalTo: pair.heightAnchor).isActive = true
            }
            tabs.addArrangedSubview(pair)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
                button.widthAnchor.constraint(lessThanOrEqualToConstant: 160),
                button.heightAnchor.constraint(equalTo: pair.heightAnchor),
                pair.heightAnchor.constraint(equalToConstant: 24),
            ])
            buttons[id] = button
        }
        tabsWidth = tabs.fittingSize.width
        needsLayout = true
    }

    private func menu(for id: UUID, index: Int) -> NSMenu {
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
        item("Move Tab Right", action: #selector(moveTabRight(_:)), enabled: index + 1 < items.count)
        return menu
    }

    @objc private func addTab() { onAdd?() }
    @objc private func selectTab(_ sender: TabButton) {
        sender.state = .on
        onSelect?(sender.id)
    }
    @objc private func closeTab(_ sender: TabButton) { onClose?(sender.id) }
    @objc private func moveTabLeft(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { onMove?(id, -1) }
    }
    @objc private func moveTabRight(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { onMove?(id, 1) }
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
