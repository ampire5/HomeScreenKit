import AppKit
import HomeChrome
import HomeScreenModel

/// What every card shares: the whole card is one button, the middle button is a click, a mouse's back and forward go
/// on to the screen, a right click shows the item's menu. Subclasses draw the item, the picture and the selection.
class GridCard: NSView {
    var onClick: ((_ middle: Bool, _ flags: NSEvent.ModifierFlags, _ clickCount: Int) -> Void)?
    var onHover: (() -> Void)?
    var onMenu: ((String) -> Void)?
    var isSelected = false { didSet { selectionChanged() } }
    /// What the files are called in the card's facts (`FileStyle.noun`), set by the browser.
    var fileNoun = "photo" { didSet { if fileNoun != oldValue { itemChanged() } } }
    /// A warm underline is independent of the blue selection ring and never covers the picture.
    private(set) var lastOpenedHighlight: CALayer?
    var lastOpenedHighlightRect: CGRect { bounds }
    var isLastOpened = false {
        didSet {
            guard isLastOpened != oldValue else { return }
            updateLastOpenedHighlight()
            needsLayout = true
        }
    }
    private func updateLastOpenedHighlight() {
        if isLastOpened, lastOpenedHighlight == nil {
            let halo = CALayer()
            let color = NSColor(srgbRed: 1, green: 0.69, blue: 0.25, alpha: 1).cgColor
            halo.backgroundColor = color
            halo.shadowColor = color
            halo.shadowOpacity = 0.65
            halo.shadowRadius = 3
            halo.shadowOffset = .zero
            halo.zPosition = -1
            layer?.addSublayer(halo)
            lastOpenedHighlight = halo
        }
        guard let halo = lastOpenedHighlight else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        halo.isHidden = !isLastOpened
        let rect = lastOpenedHighlightRect
        halo.frame = CGRect(x: rect.minX, y: rect.maxY + 3, width: rect.width, height: 2)
        halo.cornerRadius = 1
        halo.shadowPath = CGPath(roundedRect: halo.bounds, cornerWidth: halo.cornerRadius,
                                 cornerHeight: halo.cornerRadius, transform: nil)
        CATransaction.commit()
    }
    override func layout() {
        super.layout()
        updateLastOpenedHighlight()
    }
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

    /// The appearance changed: layer colours are CGColors, so subclasses recompute them (`Chrome.resolve`).
    func appearanceChanged() {}
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceChanged()
    }

    /// Overridden to draw `item`, `isSelected` and `image`.
    func itemChanged() {}
    func selectionChanged() {}
    /// Where the rename field goes over the name, in the card's coordinates; zero: the browser's own guess.
    var nameFrame: CGRect { .zero }
    func imageChanged() {}

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The whole card is one button; a hidden one (put aside in the pool, still a subview) is none: it would take
        // the clicks meant for the card shown under it.
        !isHidden && frame.contains(point) ? self : nil
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// The press gives the grid the keys (from the filter or the sidebar); the click itself is on the release.
    override func mouseDown(with event: NSEvent) {
        if let browser = sequence(first: self as NSView, next: { $0.superview }).lazy.compactMap({ $0 as? HomeBrowserView }).first {
            window?.makeFirstResponder(browser)
        }
    }
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?(false, event.modifierFlags, event.clickCount)
    }
    /// The middle button is a click; the others (a mouse's back and forward) go on to the screen.
    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber != 2 { super.otherMouseDown(with: event) }
    }
    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2 else { super.otherMouseUp(with: event); return }
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?(true, event.modifierFlags, event.clickCount)
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
        g.colors = [NSColor(white: 0, alpha: 0).cgColor, Chrome.Palette.overMedia.mediaShadow.cgColor]
        g.startPoint = CGPoint(x: 0.5, y: 1)
        g.endPoint = CGPoint(x: 0.5, y: 0)
        return g
    }
}
