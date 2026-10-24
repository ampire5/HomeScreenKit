import AppKit

/// The kit's one glass background. Over media it is always dark (tinted glass, light rim); in an ordinary window it
/// follows the window's appearance (untinted glass, separator rim). Put content in `contentView`.
@MainActor public final class ChromeGlass: NSView {
    public enum Style: Equatable {
        case overMedia(Weight), window
        public enum Weight { case regular, light }
    }

    public let style: Style
    /// The content sits here, on top of the glass (below the rim).
    public let contentView = NSView()
    public var cornerRadius: CGFloat { didSet { applyRadius() } }
    /// How strongly an over-media glass is tinted, 0...1: the tint's own opacity (the default is the palette's). Has no
    /// effect on a window glass, which is not tinted.
    public var tintOpacity: CGFloat? {
        didSet { applyTint() }
    }

    let glassView = NSGlassEffectView()
    private let rim = RimView()
    var rimLayer: CALayer { rim.rimLayer }

    public init(style: Style, cornerRadius: CGFloat) {
        self.style = style
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        switch style {
        case .overMedia(let weight):
            Chrome.Palette.overMedia.apply(to: self)
            glassView.tintColor = weight == .regular ? Chrome.Palette.overMedia.glassTint
                                                     : Chrome.Palette.overMedia.glassTintLight
        case .window:
            break
        }
        glassView.contentView = contentView
        rimLayer.borderWidth = 1
        addSubview(glassView)
        addSubview(rim)   // above the glass and its content; takes no clicks
        applyRadius()
        applyColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private func applyTint() {
        guard case .overMedia(let weight) = style else { return }
        let base = weight == .regular ? Chrome.Palette.overMedia.glassTint : Chrome.Palette.overMedia.glassTintLight
        glassView.tintColor = tintOpacity.map { base.withAlphaComponent(min(max($0, 0), 1)) } ?? base
    }

    private func applyRadius() {
        glassView.cornerRadius = cornerRadius
        rimLayer.cornerRadius = cornerRadius
    }

    private func applyColors() {
        let color: NSColor = switch style {
        case .overMedia: Chrome.Palette.overMedia.rim
        case .window: Chrome.Palette.window.separator
        }
        rimLayer.borderColor = Chrome.resolve(color, in: self)
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    /// The glass, its content and the rim follow the frame at once, so callers can read `contentView.bounds` right
    /// after setting the frame, without waiting for a layout pass.
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncChildren()
    }

    private func syncChildren() {
        glassView.frame = bounds
        glassView.layoutSubtreeIfNeeded()
        rim.frame = bounds
    }

    public override func layout() {
        super.layout()
        syncChildren()
    }
}

/// The rim overlay: draws a hairline and never takes a click.
private final class RimView: NSView {
    let rimLayer = CALayer()

    init() {
        super.init(frame: .zero)
        layer = rimLayer
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
