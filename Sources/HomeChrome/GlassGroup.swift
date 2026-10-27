import AppKit

/// A capsule of icon buttons on glass (− | +, or the browser's aspect, filter and more controls).
@MainActor public final class GlassGroup: NSView {
    public static let height: CGFloat = 28
    private static let buttonWidth: CGFloat = 30

    public var onPress: ((Int) -> Void)?

    private let glass = NSGlassEffectView()
    private let content = NSView()
    private var buttons: [NSButton] = []
    private var menus: [Int: NSMenu] = [:]
    private let light = NSView()
    /// The button that is lit, as the choice of a segmented control; nil lights none.
    public var selected: Int? {
        didSet {
            guard selected != oldValue else { return }
            needsLayout = true
        }
    }

    public init(items: [(symbol: String, tip: String)]) {
        super.init(frame: .zero)
        glass.cornerRadius = Chrome.Radius.capsule(Self.height)
        glass.contentView = content
        addSubview(glass)
        light.wantsLayer = true
        light.layer?.cornerRadius = Chrome.Radius.capsule(Self.height - 4)
        light.isHidden = true
        content.addSubview(light)
        paintLight()
        buttons = items.enumerated().map { i, item in
            let b = NSButton(image: Self.image(item.symbol, item.tip), target: self, action: #selector(clicked(_:)))
            b.isBordered = false
            b.toolTip = item.tip
            b.setAccessibilityLabel(item.tip)
            b.tag = i
            content.addSubview(b)
            return b
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// What a click on button `i` does: nothing when it is disabled.
    public func press(_ i: Int) {
        guard buttons.indices.contains(i), buttons[i].isEnabled else { return }
        onPress?(i)
    }

    public func setEnabled(_ on: Bool, at i: Int) {
        guard buttons.indices.contains(i) else { return }
        buttons[i].isEnabled = on
    }

    public func setHidden(_ hidden: Bool, at i: Int) {
        guard buttons.indices.contains(i), buttons[i].isHidden != hidden else { return }
        buttons[i].isHidden = hidden
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    public func setSymbol(_ symbol: String, at i: Int) {
        guard buttons.indices.contains(i) else { return }
        buttons[i].image = Self.image(symbol, buttons[i].toolTip ?? "")
    }

    public func setToolTip(_ tip: String, at i: Int) {
        guard buttons.indices.contains(i) else { return }
        buttons[i].toolTip = tip
        buttons[i].setAccessibilityLabel(tip)
    }

    public func setMenu(_ menu: NSMenu?, at i: Int) {
        guard buttons.indices.contains(i) else { return }
        menus[i] = menu
    }

    private static func image(_ symbol: String, _ tip: String) -> NSImage {
        Icons.symbol(symbol, pointSize: 14, description: tip) ?? NSImage()
    }

    private func paintLight() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        light.layer?.backgroundColor = Chrome.resolve(NSColor.controlAccentColor.withAlphaComponent(dark ? 0.25 : 0.18),
                                                      in: self)
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paintLight()
    }

    @objc private func clicked(_ sender: NSButton) {
        guard sender.isEnabled else { return }
        if let menu = menus[sender.tag] {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY), in: sender)
        } else {
            press(sender.tag)
        }
    }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: CGFloat(buttons.filter { !$0.isHidden }.count) * Self.buttonWidth + 4, height: Self.height)
    }

    public override func layout() {
        super.layout()
        glass.frame = bounds
        content.frame = bounds
        var visibleIndex = 0
        for button in buttons where !button.isHidden {
            button.frame = NSRect(x: 2 + CGFloat(visibleIndex) * Self.buttonWidth, y: 2,
                                  width: Self.buttonWidth, height: bounds.height - 4)
            visibleIndex += 1
        }
        if let s = selected, buttons.indices.contains(s), !buttons[s].isHidden {
            light.frame = buttons[s].frame
            light.isHidden = false
        } else {
            light.isHidden = true
        }
    }
}
