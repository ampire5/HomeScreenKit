import AppKit
import HomeChrome

/// A section's heading over its cards: `Folders`, `Photos · 2 719`.
final class GridHeader: NSView {
    private let label = NSTextField(labelWithString: "")

    var title: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = Chrome.Text.font(.title)
        label.textColor = .labelColor
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let h = label.intrinsicContentSize.height
        label.frame = CGRect(x: 20, y: bounds.height - h - 6, width: max(0, bounds.width - 40), height: h)
    }
}
