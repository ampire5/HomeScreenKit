import AppKit
import HomeChrome

/// One button of the strip's tool capsule: the app supplies the symbol, the tip, whether it is lit and what it does.
public struct FilmstripTool {
    public var symbol: String
    public var help: String
    public var isOn: Bool
    public var action: @MainActor () -> Void

    public init(symbol: String, help: String, isOn: Bool = false, action: @escaping @MainActor () -> Void) {
        self.symbol = symbol
        self.help = help
        self.isOn = isOn
        self.action = action
    }
}

/// The glass capsule of the strip's tools: a row of borderless symbol buttons (28 × 24 cells) on glass. Hidden, it
/// takes no clicks. Where it sits is the app's business.
@MainActor public final class FilmstripToolsView: NSView {
    static let cell = NSSize(width: 28, height: 24)
    static let symbolSize: CGFloat = 16
    static let fade: TimeInterval = 0.15

    public var tools: [FilmstripTool] = [] { didSet { rebuild() } }

    private let glass = GlassCapsule(titles: [])
    private(set) var buttons: [NSButton] = []
    private var shown = true

    public override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(glass)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: Self.cell.width * CGFloat(tools.count) + 4, height: GlassCapsule.height)
    }

    public override var fittingSize: NSSize { intrinsicContentSize }

    /// Fades the capsule in or out (0.15 s); hidden, it takes no clicks.
    public func setShown(_ shown: Bool, animated: Bool) {
        self.shown = shown
        let alpha: CGFloat = shown ? 1 : 0
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { c in
                c.duration = Self.fade
                animator().alphaValue = alpha
            }
        } else {
            alphaValue = alpha
        }
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        shown ? super.hitTest(point) : nil
    }

    private func rebuild() {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = tools.enumerated().map { i, tool in
            let image = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: tool.help)?
                .withSymbolConfiguration(.init(pointSize: Self.symbolSize, weight: .regular))
            let b = NSButton(image: image ?? NSImage(), target: self, action: #selector(clicked(_:)))
            b.isBordered = false
            b.imagePosition = .imageOnly
            b.toolTip = tool.help
            b.state = tool.isOn ? .on : .off
            b.contentTintColor = tool.isOn ? .controlAccentColor : .labelColor
            b.tag = i
            addSubview(b)
            return b
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    @objc private func clicked(_ sender: NSButton) {
        guard tools.indices.contains(sender.tag) else { return }
        tools[sender.tag].action()
    }

    public override func layout() {
        super.layout()
        glass.frame = bounds
        var x: CGFloat = 2
        for b in buttons {
            b.frame = NSRect(x: x, y: (bounds.height - Self.cell.height) / 2, width: Self.cell.width, height: Self.cell.height)
            x += Self.cell.width
        }
    }
}
