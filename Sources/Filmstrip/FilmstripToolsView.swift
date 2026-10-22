import AppKit
import HomeChrome

/// One button of the strip's tool capsule: the app supplies the symbol, the tip, whether it is lit and what it does.
public struct FilmstripTool {
    public var symbol: String
    public var help: String
    public var isOn: Bool
    /// A thin separator is drawn before this button (to group the buttons).
    public var separatorBefore: Bool
    public var action: @MainActor () -> Void

    public init(symbol: String, help: String, isOn: Bool = false, separatorBefore: Bool = false,
                action: @escaping @MainActor () -> Void) {
        self.symbol = symbol
        self.help = help
        self.isOn = isOn
        self.separatorBefore = separatorBefore
        self.action = action
    }
}

/// One tool button: a light-line symbol at 0.7, 1 with a `overMedia.hover` pill under the pointer, and an `overMedia.pressed` pill
/// while it is on. No accent tint.
@MainActor final class FilmstripToolButton: NSButton {
    private var hovered = false { didSet { refresh() } }
    private var area: NSTrackingArea?

    override var state: NSControl.StateValue { didSet { refresh() } }

    /// The pill's white level: 20 % on, 10 % hovered, none otherwise (`pillColor` is the same as a colour).
    var pillAlpha: CGFloat { state == .on ? 0.2 : hovered ? 0.1 : 0 }
    /// The pill's colour: `overMedia.pressed` on, `overMedia.hover` hovered, none otherwise.
    var pillColor: NSColor? {
        state == .on ? Chrome.Palette.overMedia.pressed : hovered ? Chrome.Palette.overMedia.hover : nil
    }
    var symbolAlpha: CGFloat { state == .on || hovered ? 1 : 0.7 }

    func setHovered(_ hovered: Bool) { self.hovered = hovered }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(a)
        area = a
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    func refresh() {
        wantsLayer = true
        layer?.cornerRadius = Chrome.Radius.capsule(bounds.height)
        layer?.backgroundColor = pillColor?.cgColor ?? NSColor.clear.cgColor
        alphaValue = symbolAlpha
    }

    override func layout() { super.layout(); refresh() }
}

/// The glass capsule of the strip's tools: a row of borderless light-line symbol buttons (28 × 24 cells, 1 pt apart,
/// 3 pt padding) on dark glass with a light hairline. Hidden, it takes no clicks. Where it sits is the app's business.
@MainActor public final class FilmstripToolsView: NSView {
    static let cell = NSSize(width: 28, height: 24)
    static let gap: CGFloat = 1
    static let padding: CGFloat = 3
    static let height: CGFloat = cell.height + 2 * padding
    /// A separator: 1 pt wide, 14 pt tall, 3 pt each side (beyond the gap).
    static let separatorWidth: CGFloat = 1
    static let separatorMargin: CGFloat = 3
    static let symbolSize: CGFloat = 16

    public var tools: [FilmstripTool] = [] { didSet { rebuild() } }

    private let glass = ChromeGlass(style: .overMedia(.regular), cornerRadius: Chrome.Radius.capsule(height))
    private(set) var buttons: [FilmstripToolButton] = []
    private var separators: [NSView] = []
    private var shown = true

    public override init(frame: NSRect) {
        super.init(frame: frame)
        Chrome.Palette.overMedia.apply(to: self)   // chrome over photos is always dark
        addSubview(glass)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var intrinsicContentSize: NSSize {
        let seps = CGFloat(tools.indices.filter { $0 > 0 && tools[$0].separatorBefore }.count)
        let n = CGFloat(tools.count)
        let gaps = max(0, n - 1) * Self.gap
        return NSSize(width: Self.cell.width * n + gaps + seps * (Self.separatorWidth + 2 * Self.separatorMargin)
                      + 2 * Self.padding, height: Self.height)
    }

    public override var fittingSize: NSSize { intrinsicContentSize }

    /// Fades the capsule in (`Chrome.Motion.show`) or out (`Chrome.Motion.hide`); hidden, it takes no clicks.
    public func setShown(_ shown: Bool, animated: Bool) {
        self.shown = shown
        let alpha: CGFloat = shown ? 1 : 0
        let duration = Chrome.Motion.duration(shown ? Chrome.Motion.show : Chrome.Motion.hide)
        if animated, duration > 0 {
            NSAnimationContext.runAnimationGroup { c in
                c.duration = duration
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
        separators.forEach { $0.removeFromSuperview() }
        separators = []
        buttons = tools.enumerated().map { i, tool in
            let image = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: tool.help)?
                .withSymbolConfiguration(.init(pointSize: Self.symbolSize, weight: .light))   // thin line icons
            let b = FilmstripToolButton(image: image ?? NSImage(), target: self, action: #selector(clicked(_:)))
            b.isBordered = false
            b.imagePosition = .imageOnly
            b.toolTip = tool.help
            b.state = tool.isOn ? .on : .off
            b.contentTintColor = Chrome.Palette.overMedia.text
            b.tag = i
            glass.contentView.addSubview(b)
            if i > 0, tool.separatorBefore {
                let sep = NSView()
                sep.wantsLayer = true
                sep.layer?.backgroundColor = Chrome.Palette.overMedia.separator.cgColor
                glass.contentView.addSubview(sep)
                separators.append(sep)
            }
            b.refresh()
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
        glass.layoutSubtreeIfNeeded()
        var x = Self.padding
        var sepIndex = 0
        for (i, b) in buttons.enumerated() {
            if i > 0 {
                x += Self.gap
                if tools[i].separatorBefore {
                    x += Self.separatorMargin
                    separators[sepIndex].frame = NSRect(x: x, y: (bounds.height - 14) / 2, width: Self.separatorWidth, height: 14)
                    sepIndex += 1
                    x += Self.separatorWidth + Self.separatorMargin
                }
            }
            b.frame = NSRect(x: x, y: (bounds.height - Self.cell.height) / 2, width: Self.cell.width, height: Self.cell.height)
            x += Self.cell.width
        }
    }
}
