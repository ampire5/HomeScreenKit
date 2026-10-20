import AppKit

/// A capsule of icon buttons on glass (− | +, the style button).
@MainActor public final class GlassGroup: NSView {
    public static let height: CGFloat = 28
    private static let buttonWidth: CGFloat = 30

    public var onPress: ((Int) -> Void)?

    private let glass = NSGlassEffectView()
    private let content = NSView()
    private var buttons: [NSButton] = []

    public init(items: [(symbol: String, tip: String)]) {
        super.init(frame: .zero)
        glass.cornerRadius = Self.height / 2
        glass.contentView = content
        addSubview(glass)
        buttons = items.enumerated().map { i, item in
            let b = NSButton(image: Self.image(item.symbol, item.tip), target: self, action: #selector(clicked(_:)))
            b.isBordered = false
            b.toolTip = item.tip
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

    public func setSymbol(_ symbol: String, at i: Int) {
        guard buttons.indices.contains(i) else { return }
        buttons[i].image = Self.image(symbol, buttons[i].toolTip ?? "")
    }

    private static func image(_ symbol: String, _ tip: String) -> NSImage {
        NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage()
    }

    @objc private func clicked(_ sender: NSButton) { press(sender.tag) }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: CGFloat(buttons.count) * Self.buttonWidth + 4, height: Self.height)
    }

    public override func layout() {
        super.layout()
        glass.frame = bounds
        content.frame = bounds
        for (i, b) in buttons.enumerated() {
            b.frame = NSRect(x: 2 + CGFloat(i) * Self.buttonWidth, y: 2, width: Self.buttonWidth, height: bounds.height - 4)
        }
    }
}
