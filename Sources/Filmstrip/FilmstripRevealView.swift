import AppKit
import HomeChrome

/// The glass nub that brings a hidden strip back: a pill with a thin chevron, 40 × 18 on the bottom edge (chevron up)
/// or 18 × 40 on the trailing edge (chevron left). Hidden, it takes no clicks. The reveal zone it sits in is the
/// app's business.
@MainActor public final class FilmstripRevealView: NSView {
    /// The edge of the window the nub sits on, which sets its shape and the chevron's direction.
    public enum Edge: Sendable { case bottom, trailing }

    /// The bottom nub's size; `size(for:)` has the other edge's.
    public static let size = size(for: .bottom)

    public static func size(for edge: Edge) -> NSSize {
        edge == .bottom ? NSSize(width: 40, height: 18) : NSSize(width: 18, height: 40)
    }

    public let edge: Edge

    public var onReveal: (() -> Void)?

    private let glass: ChromeGlass
    private let image = NSImageView()
    private var shown = true

    public init(frame: NSRect = .zero, edge: Edge = .bottom) {
        self.edge = edge
        let size = Self.size(for: edge)
        glass = ChromeGlass(style: .overMedia(.light), cornerRadius: Chrome.Radius.capsule(min(size.width, size.height)))
        super.init(frame: frame)
        Chrome.Palette.overMedia.apply(to: self)   // chrome over photos is always dark
        addSubview(glass)
        image.image = Lucide.icon(edge == .bottom ? "chevron.up" : "chevron.left", pointSize: 11,
                                  description: "Show filmstrip")
        image.contentTintColor = Chrome.Palette.overMedia.text
        image.imageScaling = .scaleNone
        image.alphaValue = 0.85
        glass.contentView.addSubview(image)
    }

    public override convenience init(frame: NSRect) { self.init(frame: frame, edge: .bottom) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var intrinsicContentSize: NSSize { Self.size(for: edge) }

    public override var fittingSize: NSSize { Self.size(for: edge) }

    /// Fades the nub in (`Chrome.Motion.show`) or out (`Chrome.Motion.hide`); hidden, it takes no clicks.
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

    /// The nub itself takes the click, not its image.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        shown && frame.contains(point) ? self : nil
    }

    public override func mouseDown(with event: NSEvent) { onReveal?() }

    public override func layout() {
        super.layout()
        glass.frame = bounds
        image.frame = bounds
    }
}
