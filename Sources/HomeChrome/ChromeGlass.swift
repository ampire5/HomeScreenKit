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

    public override func layout() {
        super.layout()
        glassView.frame = bounds
        rim.frame = bounds
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
