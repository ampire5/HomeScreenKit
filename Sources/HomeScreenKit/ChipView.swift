import AppKit
import HomeChrome

/// A small chip on a picture, as a camera's screen marks its modes (`1080p`, `HDR`, `30 fps`, `24 MP`, a length):
/// dark fill, radius 4, the text's baseline set by `CardText` so it sits in the middle of the chip whatever the font,
/// a text field's cell would sit it low. Takes no clicks.
final class ChipView: NSView {
    static let height: CGFloat = 16
    private static let padding: CGFloat = 5
    private let label = CardText()

    var text: String {
        get { label.stringValue }
        set {
            guard newValue != label.stringValue else { return }
            label.stringValue = newValue
            invalidateIntrinsicContentSize()
        }
    }
    var textColor: NSColor {
        get { label.textColor }
        set { label.textColor = newValue }
    }

    init(font: NSFont, fill: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = fill.cgColor
        layer?.cornerRadius = 4
        layer?.cornerCurve = .continuous
        label.font = font
        label.textColor = .white
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The text's width and the padding either side, `height` tall.
    override var intrinsicContentSize: NSSize {
        NSSize(width: label.textWidth + 2 * Self.padding, height: Self.height)
    }

    override func layout() {
        super.layout()
        label.frame = bounds.insetBy(dx: Self.padding, dy: 0)
    }
}
