import AppKit

/// A small label on glass (a count or a state over the grid).
@MainActor public final class GlassPill: NSView {
    public static let height: CGFloat = 18
    private static let font = Chrome.Text.font(.badge)

    public var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue; invalidateIntrinsicContentSize(); needsLayout = true }
    }

    private let glass = NSGlassEffectView()
    private let label = NSTextField(labelWithString: "")

    public override init(frame: NSRect) {
        super.init(frame: frame)
        glass.cornerRadius = Chrome.Radius.capsule(Self.height)
        addSubview(glass)
        label.font = Self.font
        label.alignment = .center
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(label.intrinsicContentSize.width) + 16, height: Self.height)
    }

    public override func layout() {
        super.layout()
        glass.frame = bounds
        let h = label.intrinsicContentSize.height
        label.frame = NSRect(x: 8, y: (bounds.height - h) / 2, width: max(0, bounds.width - 16), height: h)
    }
}
