import AppKit
import HomeScreenModel

/// A badge on a picture as the Media UI Iconography style guide draws it (B «Типографика», I «badge»): the value as
/// text on the HUD scrim (black at 55 %), 10 pt semibold with 0.04 em tracking, 16 pt tall, 4 pt padding, radius 3.
/// Its colour says nothing: `HLG` looks like `UHD` (the owner's choice of 2026-10-27, over the metal plates). Takes no
/// clicks.
final class MediaBadge: NSView {
    static let height: CGFloat = 16
    private static let padding: CGFloat = 4
    private static let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: NSColor(srgbRed: 0xE6 / 255, green: 0xE8 / 255, blue: 0xEB / 255, alpha: 1),
        .kern: 0.4,
    ]

    private let text = CATextLayer()
    private(set) var label = ""
    private var textSize = CGSize.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.55).cgColor
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

    func show(_ label: String) {
        guard label != self.label else { return }
        self.label = label
        let value = NSAttributedString(string: label, attributes: Self.attributes)
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
