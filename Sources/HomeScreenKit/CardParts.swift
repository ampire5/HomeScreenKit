import AppKit
import CoreText
import HomeChrome

/// The cards' fonts: the system font at the mockups' point sizes, digits tabular (the mockups' `.num`).
enum CardFont {
    static func text(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    /// The height of a line of `font` as the mockups' CSS lays it (`line-height: normal`): ascender and descender.
    static func lineHeight(_ font: NSFont) -> CGFloat { font.ascender - font.descender }
}

/// One line of text drawn with Core Text: the baseline where CSS puts it in a line box as tall as the view (the
/// half-leading model), cut with "…" at the end when it is wider than the view. Cheaper than a text field, and its
/// baseline is exact.
final class CardText: NSView {
    var stringValue = "" { didSet { if stringValue != oldValue { changed() } } }
    /// Overrides `stringValue`'s look when set (a part at another opacity); `stringValue` stays the plain text.
    var attributedValue: NSAttributedString? { didSet { if attributedValue != oldValue { changed() } } }
    var font = CardFont.text(11.5) { didSet { if font != oldValue { changed() } } }
    var textColor: NSColor = Chrome.Palette.card.secondary { didSet { needsDisplay = true } }
    var alignRight = false { didSet { needsDisplay = true } }
    var kern: CGFloat = 0 { didSet { changed() } }

    private var line: CTLine?

    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    /// The text's natural width, rounded up.
    var textWidth: CGFloat {
        guard !stringValue.isEmpty || attributedValue != nil else { return 0 }
        return ceil(CTLineGetTypographicBounds(makeLine(), nil, nil, nil))
    }

    var lineHeight: CGFloat { ceil(CardFont.lineHeight(font)) }

    private func changed() {
        line = nil
        needsDisplay = true
    }

    private func attributed() -> NSAttributedString {
        if let attributedValue { return attributedValue }
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        if kern != 0 { attributes[.kern] = kern }
        return NSAttributedString(string: stringValue, attributes: attributes)
    }

    private func makeLine() -> CTLine {
        if let line { return line }
        let made = CTLineCreateWithAttributedString(attributed())
        line = made
        return made
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        changed()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !stringValue.isEmpty || attributedValue != nil, let context = NSGraphicsContext.current?.cgContext else { return }
        // The colours resolve in this view's appearance: the line is made here, not kept across appearances.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            line = nil
            var drawn = makeLine()
            var width = CGFloat(CTLineGetTypographicBounds(drawn, nil, nil, nil))
            if width > bounds.width + 0.5 {
                var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
                if let a = attributedValue, a.length > 0 { attributes = a.attributes(at: a.length - 1, effectiveRange: nil) }
                let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
                if let cut = CTLineCreateTruncatedLine(drawn, Double(bounds.width), .end, token) {
                    drawn = cut
                    width = CGFloat(CTLineGetTypographicBounds(drawn, nil, nil, nil))
                }
            }
            let baseline = (bounds.height - CardFont.lineHeight(font)) / 2 + font.ascender
            context.saveGState()
            context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            context.textPosition = CGPoint(x: alignRight ? bounds.width - width : 0, y: baseline)
            CTLineDraw(drawn, context)
            context.restoreGState()
        }
    }
}

/// A small label on a plate: the cover's `ZIP`, the `RTL` chip with its border, the `+12` pill. Drawn as one view.
final class TextChip: NSView {
    struct Style {
        var font: NSFont
        var kern: CGFloat = 0
        var padX: CGFloat
        var padY: CGFloat
        /// nil: fully rounded.
        var radius: CGFloat?
        var fill: NSColor?
        var border: NSColor?
        var text: NSColor
    }

    var text = "" { didSet { if text != oldValue { invalidateIntrinsicContentSize(); needsDisplay = true } } }
    var style: Style { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }

    init(_ style: Style) {
        self.style = style
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    private var borderWidth: CGFloat { style.border == nil ? 0 : 1 }

    private func attributed() -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: style.font, .foregroundColor: style.text]
        if style.kern != 0 { attributes[.kern] = style.kern }
        return NSAttributedString(string: text, attributes: attributes)
    }

    override var intrinsicContentSize: NSSize {
        let line = CTLineCreateWithAttributedString(attributed())
        var width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        if style.kern != 0 { width -= style.kern }   // CSS letter-spacing trails the last letter too; keep it tight
        return NSSize(width: ceil(width + 2 * (style.padX + borderWidth)),
                      height: (CardFont.lineHeight(style.font) + 2 * (style.padY + borderWidth)).rounded())
    }

    override var fittingSize: NSSize { intrinsicContentSize }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty, let context = NSGraphicsContext.current?.cgContext else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let radius = min(style.radius ?? bounds.height / 2, bounds.height / 2)
            if let fill = style.fill {
                context.setFillColor(fill.cgColor)
                context.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
                context.fillPath()
            }
            if let border = style.border {
                let r = bounds.insetBy(dx: 0.5, dy: 0.5)
                context.setStrokeColor(border.cgColor)
                context.setLineWidth(1)
                context.addPath(CGPath(roundedRect: r, cornerWidth: max(0, radius - 0.5), cornerHeight: max(0, radius - 0.5),
                                       transform: nil))
                context.strokePath()
            }
            let line = CTLineCreateWithAttributedString(attributed())
            var width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            if style.kern != 0 { width -= style.kern }
            let font = style.font
            let baseline = (bounds.height - CardFont.lineHeight(font)) / 2 + font.ascender
            context.saveGState()
            context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            context.textPosition = CGPoint(x: (bounds.width - width) / 2, y: baseline)
            CTLineDraw(line, context)
            context.restoreGState()
        }
    }
}

/// The bars of a folder's dates: one per bin, bottom-aligned, scaled to the largest bin (the mockups' 1 pt stub for
/// an empty bin keeps the row's baseline visible). The bar size is the style's (2.5 pt wide in a poster, 3 in a
/// compact card, 4 in a large poster).
final class HistogramView: NSView {
    var bins: [UInt8] = [] {
        didSet {
            guard bins != oldValue else { return }
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    var barWidth: CGFloat = 2.5 { didSet { if barWidth != oldValue { invalidateIntrinsicContentSize(); needsDisplay = true } } }
    var barGap: CGFloat = 1.5 { didSet { if barGap != oldValue { invalidateIntrinsicContentSize(); needsDisplay = true } } }
    var radius: CGFloat = 1
    var color: NSColor = Chrome.Palette.card.spark { didSet { needsDisplay = true } }

    /// At least one bin has photos; the card shows the view only then.
    var hasBars: Bool { bins.contains { $0 > 0 } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    /// The bars' width; the height is the view's.
    var barsWidth: CGFloat { bins.isEmpty ? 0 : CGFloat(bins.count) * (barWidth + barGap) - barGap }
    override var intrinsicContentSize: NSSize { NSSize(width: barsWidth, height: NSView.noIntrinsicMetric) }

    /// Bar heights for `bins` in `height` points, as the mockups draw them: the largest bin full height, each bar
    /// rounded to a whole point and at least 1 pt (an empty bin's stub, so all-empty bins are a row of stubs).
    static func heights(_ bins: [UInt8], height: CGFloat) -> [CGFloat] {
        let top = CGFloat(max(1, bins.max() ?? 1))
        return bins.map { max(1, (height * CGFloat($0) / top).rounded()) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let heights = Self.heights(bins, height: bounds.height)
        effectiveAppearance.performAsCurrentDrawingAppearance { context.setFillColor(color.cgColor) }
        for (i, h) in heights.enumerated() where h > 0 {
            let r = CGRect(x: CGFloat(i) * (barWidth + barGap), y: bounds.height - h, width: barWidth, height: h)
            let corner = min(radius, r.width / 2, r.height / 2)
            context.addPath(CGPath(roundedRect: r, cornerWidth: corner, cornerHeight: corner, transform: nil))
        }
        context.fillPath()
    }
}

extension TextChip.Style {
    /// The `+12` pill: 10.5 pt bold white on the pill blue, fully rounded, 1 × 6 padding (the list's: 10 pt, 0 × 5).
    static func newPill(size: CGFloat = 10.5, padX: CGFloat = 6, padY: CGFloat = 1) -> TextChip.Style {
        TextChip.Style(font: CardFont.text(size, .bold), padX: padX, padY: padY, radius: nil,
                       fill: Chrome.Palette.card.pill, border: nil, text: Chrome.Palette.card.pillText)
    }

    /// `RTL` (or the list's `ZIP`): bold secondary text in a 1 pt separator border, radius 4, 0 × 3 padding.
    static func outlined(size: CGFloat) -> TextChip.Style {
        TextChip.Style(font: CardFont.text(size, .bold), padX: 3, padY: 0, radius: 4, fill: nil,
                       border: Chrome.Palette.card.separator, text: Chrome.Palette.card.secondary)
    }

    /// `ZIP` over the cover: bold white on a dark veil, letter-spaced .04 em.
    static func overCover(size: CGFloat, padX: CGFloat, padY: CGFloat, radius: CGFloat, veil: CGFloat) -> TextChip.Style {
        TextChip.Style(font: NSFont.systemFont(ofSize: size, weight: .bold), kern: 0.04 * size, padX: padX, padY: padY,
                       radius: radius, fill: Chrome.Palette.card.coverChip.withAlphaComponent(veil), border: nil,
                       text: Chrome.Palette.card.coverChipText)
    }
}
