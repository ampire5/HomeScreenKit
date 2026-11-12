import AppKit
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

    init() {
        super.init(frame: .zero)
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        tabs.orientation = .horizontal
        tabs.alignment = .centerY
        tabs.spacing = 3
        tabs.edgeInsets = NSEdgeInsets(top: 0, left: 5, bottom: 0, right: 5)
        scroll.documentView = tabs

        let add = NSButton(title: "+", target: self, action: #selector(addTab))
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
        tabs.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: add.leadingAnchor, constant: -3),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            tabs.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            tabs.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            tabs.heightAnchor.constraint(equalTo: scroll.contentView.heightAnchor),
            add.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            add.widthAnchor.constraint(equalToConstant: 25),
            add.centerYAnchor.constraint(equalTo: centerYAnchor),
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
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
        for (id, button) in buttons { button.state = id == selected ? .on : .off }
        if let selected, let button = buttons[selected] {
            layoutSubtreeIfNeeded()
            button.scrollToVisible(button.bounds)
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
            let close = TabButton(id: id, title: "×", target: self, action: #selector(closeTab(_:)))
            close.setAccessibilityLabel("Close \(item.title) tab")
            close.toolTip = "Close Tab"
            close.isEnabled = items.count > 1
            let pair = NSStackView(views: [button, close])
            pair.orientation = .horizontal
            pair.alignment = .centerY
            pair.spacing = 0
            pair.setHuggingPriority(.required, for: .horizontal)
            button.widthAnchor.constraint(lessThanOrEqualToConstant: 170).isActive = true
            close.widthAnchor.constraint(equalToConstant: 23).isActive = true
            tabs.addArrangedSubview(pair)
            buttons[id] = button
        }
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
        bezelStyle = .accessoryBar
        controlSize = .small
        font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        lineBreakMode = .byTruncatingMiddle
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
