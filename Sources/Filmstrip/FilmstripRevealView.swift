import AppKit

/// The bare chevron (`chevron.up`, 18 × 9) that brings a hidden strip back. Hidden, it takes no clicks. The reveal
/// zone it sits in is the app's business.
@MainActor public final class FilmstripRevealView: NSView {
    public static let size = NSSize(width: 18, height: 9)
    static let fade: TimeInterval = 0.15

    public var onReveal: (() -> Void)?

    private let image = NSImageView()
    private var shown = true

    public override init(frame: NSRect) {
        super.init(frame: frame)
        image.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Show filmstrip")?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        image.contentTintColor = .secondaryLabelColor
        image.imageScaling = .scaleProportionallyUpOrDown
        addSubview(image)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var intrinsicContentSize: NSSize { Self.size }

    public override var fittingSize: NSSize { Self.size }

    /// Fades the chevron in or out (0.15 s); hidden, it takes no clicks.
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

    /// The chevron itself takes the click, not its image.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        shown && frame.contains(point) ? self : nil
    }

    public override func mouseDown(with event: NSEvent) { onReveal?() }

    public override func layout() {
        super.layout()
        image.frame = bounds
    }
}
