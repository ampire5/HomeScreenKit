import AppKit
import HomeScreenModel

/// A badge on a picture as the Media UI Iconography style guide draws it (B «Типографика», I «badge»): the value as
/// text, 10 pt semibold with 0.04 em tracking, 16 pt tall, 4 pt padding, radius 3, in the colour of what it says
/// (`MediaPalette`, style A of 2026-10-27): the text and a 1 pt ring inside the edge in that colour on a dark plate.
/// Monochrome: light text on the HUD scrim (black at 55 %), no ring. Takes no clicks.
final class MediaBadge: NSView {
    static let height: CGFloat = 16
    private static let padding: CGFloat = 4
    private static let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
    private static let tinted = MediaPalette.rgb(0x0E0F11, 0.72)
    private static let scrim = NSColor(white: 0, alpha: 0.55)

    private let text = CATextLayer()
    private(set) var badge: FileFactsText.Badge?
    private var colored: NSColor??
    private var textSize = CGSize.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 3
        layer?.cornerCurve = .continuous
        text.contentsScale = 2
        text.alignmentMode = .left
        text.truncationMode = .none
        layer?.addSublayer(text)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        text.contentsScale = window?.backingScaleFactor ?? 2
    }

    var label: String { badge?.text ?? "" }

    func show(_ badge: FileFactsText.Badge) {
        let color = MediaPalette.color(badge.kind)
        guard badge != self.badge || color != colored else { return }
        self.badge = badge
        colored = color
        layer?.backgroundColor = (color == nil ? Self.scrim : Self.tinted).cgColor
        layer?.borderWidth = color == nil ? 0 : 1
        layer?.borderColor = color?.withAlphaComponent(0.6).cgColor
        let value = NSAttributedString(string: badge.text, attributes: [
            .font: Self.font, .foregroundColor: color ?? MediaPalette.text, .kern: 0.4,
        ])
        text.string = value
        textSize = value.size()
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(textSize.width) + 2 * Self.padding, height: Self.height)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The line centred on the badge: its height is the font's line.
        let line = ceil(Self.font.ascender - Self.font.descender)
        text.frame = CGRect(x: Self.padding, y: ((bounds.height - line) / 2).rounded(), width: bounds.width - 2 * Self.padding,
                            height: line)
        CATransaction.commit()
    }
}
