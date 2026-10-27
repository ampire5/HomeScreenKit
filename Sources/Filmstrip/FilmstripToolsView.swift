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

/// The capsule's own glyphs (the strip sketch's `.cap`), by the name a `FilmstripTool` gives as its `symbol`; any
/// other name is an SF Symbol.
public enum FilmstripGlyph: String, CaseIterable, Sendable {
    /// "Where the strip is", while it is beside the photo: a window with its bottom band filled.
    case beside = "strip.beside"
    /// The same button while the strip floats: a window in front of another.
    case over = "strip.over"
    case pin = "pin"
    case pinFilled = "pin.fill"
    /// Hide the strip.
    case hide = "chevron.down"

    @MainActor var glyph: ChromeGlyph {
        switch self {
        case .beside: ChromeGlyph.stripBeside
        case .over: ChromeGlyph.stripOver(behind: FilmstripToolsView.glyphBehind)
        case .pin: ChromeGlyph.pin
        case .pinFilled: ChromeGlyph.pinFilled
        case .hide: ChromeGlyph.chevronDown
        }
    }

    /// The glyph's size in the 28 × 24 button and its line width (the sketch's `stroke-width`).
    var size: NSSize { self == .beside || self == .over ? NSSize(width: 16, height: 14) : NSSize(width: 14, height: 14) }
    var lineWidth: CGFloat { self == .hide ? 1.6 : 1.4 }
}

/// One tool button (the sketch's `.cap span`): 28 × 24, fully rounded; its thin-line glyph in #E8E8EA at 0.6 at
/// rest and at 1 under the pointer; on (lit), a neutral light pill under it (white 22 %), never the accent.
@MainActor final class FilmstripToolButton: NSButton {
    private var hovered = false { didSet { refresh() } }
    private var area: NSTrackingArea?

    override var state: NSControl.StateValue { didSet { refresh() } }

    /// The pill's white level: 22 % on, none otherwise (`pillColor` is the same as a colour).
    var pillAlpha: CGFloat { state == .on ? 0.22 : 0 }
    var pillColor: NSColor? { state == .on ? FilmstripToolsView.pressed : nil }
    var symbolAlpha: CGFloat { state == .on || hovered ? 1 : 0.6 }

    func setHovered(_ hovered: Bool) { self.hovered = hovered }

    /// The glyph inside is drawing only: a click on it is the button's.
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }

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
        // The pill stays whole; only the glyph dims.
        (subviews.first { $0 is GlyphView })?.alphaValue = symbolAlpha
        if image != nil { alphaValue = symbolAlpha }
    }

    override func layout() {
        super.layout()
        if let glyph = subviews.first(where: { $0 is GlyphView }) as? GlyphView, let size = glyphSize {
            glyph.frame = NSRect(x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded(),
                                 width: size.width, height: size.height)
        }
        refresh()
    }

    var glyphSize: NSSize?
}

/// The strip's tool capsule (the strip sketch's `.cap`): a row of 28 × 24 buttons 2 pt apart, 3 pt padding, on a
/// dark plate (rgba 44, 44, 48, .86) with a 1 pt white 18 % border, fully rounded; a 1 × 14 pt divider of the
/// border's white between groups. At rest the whole capsule is at 0.7, under the pointer at 1. Hidden, it takes no
/// clicks. Where it sits is the app's business.
@MainActor public final class FilmstripToolsView: NSView {
    static let cell = NSSize(width: 28, height: 24)
    static let gap: CGFloat = 2
    static let padding: CGFloat = 3
    static let border: CGFloat = 1
    static let height: CGFloat = cell.height + 2 * (padding + border)
    /// A divider: 1 pt wide, 14 pt tall, 3 pt each side (beyond the gap).
    static let separatorWidth: CGFloat = 1
    static let separatorMargin: CGFloat = 3
    static let symbolSize: CGFloat = 15
    /// The capsule at rest; under the pointer it is at 1.
    static let restAlpha: CGFloat = 0.7

    static let plate = NSColor(srgbRed: 44 / 255, green: 44 / 255, blue: 48 / 255, alpha: 0.86)
    static let rim = NSColor(white: 1, alpha: 0.18)
    static let ink = NSColor(srgbRed: 0xE8 / 255, green: 0xE8 / 255, blue: 0xEA / 255, alpha: 1)
    static let pressed = NSColor(white: 1, alpha: 0.22)
    /// The fill of a glyph's front window: the plate's colour, opaque.
    static let glyphBehind = NSColor(srgbRed: 0x2C / 255, green: 0x2C / 255, blue: 0x30 / 255, alpha: 1)

    public var tools: [FilmstripTool] = [] { didSet { rebuild() } }

    /// Everything the capsule draws, dimmed together at rest.
    private let content = NSView()
    private(set) var buttons: [FilmstripToolButton] = []
    private var separators: [NSView] = []
    private var shown = true
    private var hoverArea: NSTrackingArea?
    /// The pointer is over the capsule.
    private(set) var isHovered = false { didSet { content.alphaValue = isHovered ? 1 : Self.restAlpha } }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        Chrome.Palette.overMedia.apply(to: self)   // chrome over photos is always dark
        content.wantsLayer = true
        content.layer?.backgroundColor = Self.plate.cgColor
        content.layer?.borderColor = Self.rim.cgColor
        content.layer?.borderWidth = Self.border
        content.alphaValue = Self.restAlpha
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var intrinsicContentSize: NSSize {
        let seps = CGFloat(tools.indices.filter { $0 > 0 && tools[$0].separatorBefore }.count)
        let n = CGFloat(tools.count)
        let gaps = max(0, n - 1) * Self.gap
        return NSSize(width: Self.cell.width * n + gaps + seps * (Self.separatorWidth + 2 * Self.separatorMargin)
                      + 2 * (Self.padding + Self.border), height: Self.height)
    }

    public override var fittingSize: NSSize { intrinsicContentSize }

    /// Fades the capsule in (`Chrome.Motion.show`) or out (`Chrome.Motion.hide`); hidden, it takes no clicks.
    public func setShown(_ shown: Bool, animated: Bool) {
        self.shown = shown
        // Shown right under the pointer, no "entered" comes: lit at once, as if it had.
        if let window, shown {
            setHovered(bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)))
        } else if !shown {
            setHovered(false)
        }
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

    /// The pointer over the capsule brings it to full strength; leaving it, back to `restAlpha`.
    func setHovered(_ hovered: Bool) { if hovered != isHovered { isHovered = hovered } }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(a)
        hoverArea = a
    }

    public override func mouseEntered(with event: NSEvent) { setHovered(shown) }
    public override func mouseExited(with event: NSEvent) { setHovered(false) }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        shown ? super.hitTest(point) : nil
    }

    private func rebuild() {
        buttons.forEach { $0.removeFromSuperview() }
        separators.forEach { $0.removeFromSuperview() }
        separators = []
        buttons = tools.enumerated().map { i, tool in
            let b: FilmstripToolButton
            if let kind = FilmstripGlyph(rawValue: tool.symbol) {
                b = FilmstripToolButton(title: "", target: self, action: #selector(clicked(_:)))
                let glyph = GlyphView(kind.glyph, color: Self.ink, lineWidth: kind.lineWidth)
                glyph.setAccessibilityLabel(tool.help)
                b.addSubview(glyph)
                b.glyphSize = kind.size
            } else {
                let image = Icons.symbol(tool.symbol, pointSize: Self.symbolSize, weight: .light, description: tool.help)
                b = FilmstripToolButton(image: image ?? NSImage(), target: self, action: #selector(clicked(_:)))
                b.imagePosition = .imageOnly
                b.contentTintColor = Self.ink
            }
            b.isBordered = false
            b.title = ""
            b.toolTip = tool.help
            b.setAccessibilityLabel(tool.help)
            b.state = tool.isOn ? .on : .off
            b.tag = i
            content.addSubview(b)
            if i > 0, tool.separatorBefore {
                let sep = NSView()
                sep.wantsLayer = true
                sep.layer?.backgroundColor = Self.rim.cgColor
                content.addSubview(sep)
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
        content.frame = bounds
        content.layer?.cornerRadius = Chrome.Radius.capsule(bounds.height)
        var x = Self.padding + Self.border
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
