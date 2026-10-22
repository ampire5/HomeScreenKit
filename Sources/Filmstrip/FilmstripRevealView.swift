import AppKit

/// The glass nub that brings a hidden strip back: a pill with a thin chevron, 40 × 18 on the bottom edge (chevron up)
/// or 18 × 40 on the trailing edge (chevron left). Hidden, it takes no clicks. The reveal zone it sits in is the
/// app's business.
@MainActor public final class FilmstripRevealView: NSView {
    /// The edge of the window the nub sits on, which sets its shape and the chevron's direction.
    public enum Edge: Sendable { case bottom, trailing }

    /// The bottom nub's size; `size(for:)` has the other edge's.
    public static let size = size(for: .bottom)
    static let fade: TimeInterval = 0.15

    public static func size(for edge: Edge) -> NSSize {
        edge == .bottom ? NSSize(width: 40, height: 18) : NSSize(width: 18, height: 40)
    }

    public let edge: Edge

    public var onReveal: (() -> Void)?

    private let glass = NSGlassEffectView()
    private let rim = NSView()
    private let image = NSImageView()
    private var shown = true

    public init(frame: NSRect = .zero, edge: Edge = .bottom) {
        self.edge = edge
        super.init(frame: frame)
        appearance = NSAppearance(named: .darkAqua)   // chrome over photos is always dark
        let size = Self.size(for: edge)
        glass.cornerRadius = min(size.width, size.height) / 2
        glass.tintColor = NSColor(srgbRed: 22 / 255, green: 24 / 255, blue: 29 / 255, alpha: 0.55)
        glass.contentView = rim
        rim.wantsLayer = true
        rim.layer?.cornerRadius = min(size.width, size.height) / 2
        rim.layer?.borderWidth = 1                     // the 1 px inner light hairline
        rim.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        addSubview(glass)
        image.image = NSImage(systemSymbolName: edge == .bottom ? "chevron.up" : "chevron.left",
                              accessibilityDescription: "Show filmstrip")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        image.contentTintColor = NSColor(srgbRed: 0xe8 / 255, green: 0xea / 255, blue: 0xee / 255, alpha: 1)
        image.imageScaling = .scaleNone
        image.alphaValue = 0.85
        rim.addSubview(image)
    }

    public override convenience init(frame: NSRect) { self.init(frame: frame, edge: .bottom) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var intrinsicContentSize: NSSize { Self.size(for: edge) }

    public override var fittingSize: NSSize { Self.size(for: edge) }

    /// Fades the nub in or out (0.15 s); hidden, it takes no clicks.
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

    /// The nub itself takes the click, not its image.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        shown && frame.contains(point) ? self : nil
    }

    public override func mouseDown(with event: NSEvent) { onReveal?() }

    public override func layout() {
        super.layout()
        glass.frame = bounds
        rim.frame = bounds
        image.frame = rim.bounds
    }
}
