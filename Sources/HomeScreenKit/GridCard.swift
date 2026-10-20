import AppKit
import HomeScreenModel

/// What every card shares: the whole card is one button, the middle button is a click, a mouse's back and forward go
/// on to the screen, a right click shows the item's menu. Subclasses draw the item, the picture and the selection.
class GridCard: NSView {
    var onClick: ((_ middle: Bool, _ flags: NSEvent.ModifierFlags) -> Void)?
    var onHover: (() -> Void)?
    var onMenu: ((String) -> Void)?
    var isSelected = false { didSet { selectionChanged() } }
    private(set) var item: HomeCardItem
    var image: CGImage? { didSet { imageChanged() } }

    init(item: HomeCardItem) {
        self.item = item
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// New text, label or dimming for the same card; the picture stays.
    func show(_ item: HomeCardItem) {
        self.item = item
        toolTip = item.tooltip
        alphaValue = item.isDimmed ? 0.45 : 1
        itemChanged()
        needsLayout = true
    }

    /// Overridden to draw `item`, `isSelected` and `image`.
    func itemChanged() {}
    func selectionChanged() {}
    func imageChanged() {}

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The whole card is one button; a hidden one (put aside in the pool, still a subview) is none: it would take
        // the clicks meant for the card shown under it.
        !isHidden && frame.contains(point) ? self : nil
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?(false, event.modifierFlags)
    }
    /// The middle button is a click; the others (a mouse's back and forward) go on to the screen.
    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber != 2 { super.otherMouseDown(with: event) }
    }
    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2 else { super.otherMouseUp(with: event); return }
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?(true, event.modifierFlags)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard !item.menu.isEmpty else { return nil }
        onHover?()
        let menu = NSMenu()
        for (i, entry) in item.menu.enumerated() {
            let menuItem = menu.addItem(withTitle: entry.title, action: #selector(menuChose(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.tag = i
        }
        return menu
    }

    @objc private func menuChose(_ sender: NSMenuItem) {
        if item.menu.indices.contains(sender.tag) { onMenu?(item.menu[sender.tag].id) }
    }

    /// A bottom band from clear to black 0.55, under names drawn on a picture.
    static func shade() -> CAGradientLayer {
        let g = CAGradientLayer()
        g.colors = [NSColor(white: 0, alpha: 0).cgColor, NSColor(white: 0, alpha: 0.55).cgColor]
        g.startPoint = CGPoint(x: 0.5, y: 1)
        g.endPoint = CGPoint(x: 0.5, y: 0)
        return g
    }
}
