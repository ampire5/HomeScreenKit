import AppKit
import HomeScreenModel

/// A badge as a name plate on a camera's body (the owner's wish of 2026-10-27: «шильдики», not white text on black):
/// a small metal plate with a soft gradient and a light top edge, the value engraved in it — dark text with a light
/// line under it — and its unit smaller after it (`30 FPS`, `24 MP`). The plate's metal says what the value is:
/// silver for the size, the rate and the megapixels, gold for HDR, graphite for RAW. Takes no clicks.
final class BadgePlate: NSView {
    static let height: CGFloat = 16
    private static let padding: CGFloat = 5
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .heavy)
    private static let unitFont = NSFont.systemFont(ofSize: 7, weight: .bold)

    private let plate = CAGradientLayer()
    private let edge = CALayer()
    private let text = CATextLayer()
    private(set) var badge = FileFactsText.Badge(text: "", kind: .resolution)
    private var textSize = CGSize.zero

    var label: String { badge.label }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        plate.cornerRadius = 3.5
        plate.cornerCurve = .continuous
        plate.masksToBounds = true
        // A drop shadow under the plate, so it reads on a light picture as on a dark one.
        plate.shadowOpacity = 0
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.45
        layer?.shadowRadius = 1.5
        layer?.shadowOffset = CGSize(width: 0, height: -0.5)
        edge.borderWidth = 0.5
        edge.cornerRadius = 3.5
        edge.cornerCurve = .continuous
        text.contentsScale = 2
        text.alignmentMode = .left
        text.truncationMode = .none
        // Engraved: a light line under the dark letters.
        text.shadowColor = NSColor.white.cgColor
        text.shadowOffset = CGSize(width: 0, height: -0.6)
        text.shadowRadius = 0
        text.shadowOpacity = 0.55
        layer?.addSublayer(plate)
        plate.addSublayer(edge)
        plate.addSublayer(text)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        text.contentsScale = window?.backingScaleFactor ?? 2
    }

    func show(_ badge: FileFacts.Badge) {
        guard badge != self.badge else { return }
        self.badge = badge
        let metal = Self.metal(badge.kind)
        plate.colors = [metal.top.cgColor, metal.bottom.cgColor]
        edge.borderColor = metal.edge.cgColor
        text.shadowOpacity = metal.engraveLight
        let value = NSMutableAttributedString(string: badge.text, attributes: [.font: Self.valueFont, .foregroundColor: metal.ink])
        if let unit = badge.unit {
            value.append(NSAttributedString(string: "\u{2009}" + unit, attributes: [
                .font: Self.unitFont, .foregroundColor: metal.ink.withAlphaComponent(0.8),
                .baselineOffset: 0.5,
            ]))
        }
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
        plate.frame = bounds
        edge.frame = plate.bounds
        // The value's line centred on the plate: its height is the value font's line, the unit sits on its baseline.
        let line = ceil(Self.valueFont.ascender - Self.valueFont.descender)
        text.frame = CGRect(x: Self.padding, y: ((bounds.height - line) / 2).rounded(), width: bounds.width - 2 * Self.padding,
                            height: line)
        CATransaction.commit()
    }

    private struct Metal {
        var top: NSColor, bottom: NSColor, edge: NSColor, ink: NSColor
        var engraveLight: Float
    }

    private static func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    private static func metal(_ kind: FileFacts.Badge.Kind) -> Metal {
        switch kind {
        case .resolution, .rate, .megapixels:   // brushed silver
            Metal(top: rgb(0xEDEDF0), bottom: rgb(0xB4B5BA), edge: rgb(0xFFFFFF, 0.7), ink: rgb(0x2B2C30), engraveLight: 0.6)
        case .hdr:   // gold
            Metal(top: rgb(0xF6DE8D), bottom: rgb(0xC39A3A), edge: rgb(0xFFF4C8, 0.8), ink: rgb(0x3A2A08), engraveLight: 0.5)
        case .raw:   // graphite, the letters light and cut in
            Metal(top: rgb(0x55565C), bottom: rgb(0x2E2F33), edge: rgb(0xFFFFFF, 0.25), ink: rgb(0xE6E6EA), engraveLight: 0.0)
        }
    }
}

extension FileFacts {
    typealias Badge = FileFactsText.Badge
}
