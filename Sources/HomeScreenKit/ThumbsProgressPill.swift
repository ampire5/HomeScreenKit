import AppKit
import HomeChrome
import HomeScreenModel

/// The toolbar's pill for the thumbnails being prepared (thumbs-ahead spec, "Пилюля в тулбаре"; the progress board's
/// button): a glass capsule 28 pt high with a 20 pt ring that fills by the current stage's share, a pause glyph in it
/// while the work runs (play while paused, the ring grey), and the app's text in 12 pt tabular digits. A click opens a
/// popover with the stages' bars, the pause note and the buttons (`ThumbsProgressPanel`). Compact (a narrow toolbar): the
/// ring alone in a 28 pt capsule, the text in the tooltip. One view, so it can become an `NSToolbarItem`'s view.
final class ThumbsProgressPill: NSView, NSPopoverDelegate {
    enum Glyph: Equatable { case pause, play }

    static let height: CGFloat = 28
    /// The board's button: padding 0 12 0 6, gap 8 between the ring and the text.
    private static let leading: CGFloat = 6
    private static let gap: CGFloat = 8
    private static let trailing: CGFloat = 12
    /// The ring: a 20 pt box, radius 8, stroke 2.5.
    private static let ringBox: CGFloat = 20
    private static let ringRadius: CGFloat = 8
    private static let ringWidth: CGFloat = 2.5
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

    /// The popover's Pause (true) or Resume (false).
    var onPause: ((Bool) -> Void)?
    /// The popover's Prepare subfolders.
    var onPrepare: (() -> Void)?
    /// The popover's Stop preparing (while a subtree is being prepared).
    var onStopSubtree: (() -> Void)?

    /// The ring alone, the text in the tooltip (and the popover): the toolbar's step before hiding the pill.
    var isCompact = false {
        didSet {
            guard isCompact != oldValue else { return }
            label.isHidden = isCompact
            toolTip = isCompact && state != nil ? text : nil
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    private(set) var state: ThumbsProgressState?
    /// The counts the app gave last, the pill lit or not (`showDetail`).
    private(set) var detail: ThumbsProgressState?
    private(set) var ringColor = Chrome.Palette.card.accent
    private(set) var glyph = Glyph.pause
    var text: String { label.stringValue }
    /// The ring's fill, 0…1 (the model value; the layer animates to it).
    var ringEnd: CGFloat { fill.strokeEnd }
    var textWidth: CGFloat { Self.width(text) }
    /// The text area's width: that of the widest count for the current total and stage word ("Thumbnails 0000 / 1480"
    /// for "Thumbnails 52 / 1480": the digits are tabular, all one width), so the pill keeps its width, and its place
    /// under the pointer, while the count grows; a text with no "n / N" at its end is as wide as itself.
    private(set) var reservedTextWidth: CGFloat = 0

    /// The widest text for `text`'s total: its done count as many digits as the total has.
    static func widestText(_ text: String) -> String {
        guard let slash = text.range(of: " / ", options: .backwards) else { return text }
        let total = text[slash.upperBound...]
        func isDigit(_ c: Character) -> Bool { ("0"..."9").contains(c) }
        guard !total.isEmpty, total.allSatisfy(isDigit) else { return text }
        let head = text[..<slash.lowerBound]
        let digits = head.reversed().prefix(while: isDigit).count
        guard digits > 0 else { return text }
        return head.dropLast(digits) + String(repeating: "0", count: total.count) + " / " + total
    }

    private static func width(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private let glass = NSGlassEffectView()
    private let content = FlippedLayerView()
    private let ring = FlippedLayerView()
    private let track = CAShapeLayer()
    private let fill = CAShapeLayer()
    private let glyphLayer = CAShapeLayer()
    private let label = NSTextField(labelWithString: "")
    private let edge = EdgeView()
    private var panel: ThumbsProgressPanel?
    private var popover: NSPopover?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        isHidden = true
        glass.cornerRadius = Chrome.Radius.capsule(Self.height)
        addSubview(glass)
        // The ring and the text sit over the glass, not in it: their colours are the board's own in each appearance.
        addSubview(content)
        let circle = CGMutablePath()
        // From 12 o'clock, clockwise (the view is flipped: y grows down).
        circle.addArc(center: CGPoint(x: Self.ringBox / 2, y: Self.ringBox / 2), radius: Self.ringRadius,
                      startAngle: -.pi / 2, endAngle: 3 * .pi / 2, clockwise: false)
        for shape in [track, fill] {
            shape.path = circle
            shape.fillColor = nil
            shape.lineWidth = Self.ringWidth
            ring.layer?.addSublayer(shape)
        }
        fill.lineCap = .round
        fill.strokeEnd = 0
        ring.layer?.addSublayer(glyphLayer)
        content.addSubview(ring)
        label.font = Self.font
        label.lineBreakMode = .byClipping
        content.addSubview(label)
        addSubview(edge)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    /// The whole capsule takes the click.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) { togglePopover() }
    /// The click that brings the window forward opens the popover too, as the toolbar's other controls do.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func accessibilityPerformPress() -> Bool {
        togglePopover()
        return true
    }

    override var intrinsicContentSize: NSSize { isCompact ? compactSize : fullSize }

    /// With the text: the board's button.
    var fullSize: NSSize {
        NSSize(width: Self.leading + Self.ringBox + Self.gap + reservedTextWidth + Self.trailing, height: Self.height)
    }

    /// The ring alone, centred in a capsule as wide as it is high.
    var compactSize: NSSize { NSSize(width: Self.height, height: Self.height) }

    /// The state to draw; nil hides the pill (and closes its popover if it points at the pill; one the View menu
    /// opened from the sort stays, with the last counts).
    func show(_ p: ThumbsProgressState?) {
        state = p
        guard let p else {
            isHidden = true
            toolTip = nil
            if isPopoverOnPill { closePopover() }
            updatePanel()
            return
        }
        isHidden = false
        if label.stringValue != p.text {
            label.stringValue = p.text
            let reserved = max(textWidth, Self.width(Self.widestText(p.text)))
            if reserved != reservedTextWidth {
                reservedTextWidth = reserved
                invalidateIntrinsicContentSize()
                needsLayout = true
            }
        }
        setAccessibilityLabel(p.text)
        toolTip = isCompact ? p.text : nil
        glyph = p.paused ? .play : .pause
        ringColor = p.paused ? Chrome.Palette.progress.pausedRing : Chrome.Palette.card.accent
        glyphLayer.path = Self.glyphPath(glyph)
        let end = CGFloat(min(1, max(0, p.fraction)))
        if end != fill.strokeEnd {
            CATransaction.begin()
            CATransaction.setAnimationDuration(Chrome.Motion.duration(Chrome.Motion.hide))
            fill.strokeEnd = end
            CATransaction.commit()
        }
        applyColors()
        updatePanel()
    }

    /// The popover's counts whatever the pill shows (`ThumbsProgressState.working` false: nothing being prepared);
    /// nil: none for this folder yet.
    func showDetail(_ d: ThumbsProgressState?) {
        detail = d
        updatePanel()
    }

    private func updatePanel() {
        guard let panel else { return }
        panel.show(panelState)
        // An open popover follows its content: a note coming or going, rows added or taken away.
        if let popover, popover.isShown { popover.contentSize = panel.fittingSize }
    }

    /// The board's 8×8 glyphs (`M1 1h2v6H1zM5 1h2v6H5z`, `M1.5 1l5 3-5 3z`), centred in the ring.
    private static func glyphPath(_ glyph: Glyph) -> CGPath {
        let path = CGMutablePath()
        let o = (ringBox - 8) / 2
        switch glyph {
        case .pause:
            path.addRect(CGRect(x: o + 1, y: o + 1, width: 2, height: 6))
            path.addRect(CGRect(x: o + 5, y: o + 1, width: 2, height: 6))
        case .play:
            path.addLines(between: [CGPoint(x: o + 1.5, y: o + 1), CGPoint(x: o + 6.5, y: o + 4),
                                    CGPoint(x: o + 1.5, y: o + 7)])
            path.closeSubpath()
        }
        return path
    }

    private func applyColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.strokeColor = Chrome.resolve(Chrome.Palette.card.track, in: self)
        fill.strokeColor = Chrome.resolve(ringColor, in: self)
        glyphLayer.fillColor = Chrome.resolve(Chrome.Palette.card.label, in: self)
        edge.rim.borderColor = Chrome.resolve(Chrome.Palette.card.separator, in: self)
        edge.highlight.fillColor = Chrome.resolve(Chrome.Palette.progress.highlight, in: self)
        CATransaction.commit()
        label.textColor = Chrome.Palette.card.label
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    override func layout() {
        super.layout()
        glass.frame = bounds
        content.frame = bounds
        edge.frame = bounds
        let ringX = isCompact ? (bounds.width - Self.ringBox) / 2 : Self.leading
        ring.frame = CGRect(x: ringX, y: (bounds.height - Self.ringBox) / 2, width: Self.ringBox,
                            height: Self.ringBox)
        let h = label.intrinsicContentSize.height
        let x = ring.frame.maxX + Self.gap
        label.frame = CGRect(x: x, y: ((bounds.height - h) / 2).rounded(), width: max(0, bounds.width - x - Self.trailing + 2),
                             height: h)
        edge.place(radius: Chrome.Radius.capsule(bounds.height))
    }

    // MARK: Popover

    /// The popover's content for the current state, kept up to date by `show(_:)` while it is open.
    func makePanel() -> ThumbsProgressPanel {
        let panel = ThumbsProgressPanel()
        panel.onPause = { [weak self] on in self?.onPause?(on) }
        panel.onPrepare = { [weak self] in self?.onPrepare?() }
        panel.onStopSubtree = { [weak self] in self?.onStopSubtree?() }
        panel.show(panelState)
        self.panel = panel
        return panel
    }

    var isPopoverShown: Bool { popover?.isShown == true }

    /// What the popover shows: the counts the app gave last, else the lit pill's state, else zeros.
    var panelState: ThumbsProgressState { detail ?? state ?? .idle }

    /// The popover's lines, open or not (tests).
    var panelRowTexts: [String] {
        if let panel { return panel.rowTexts }
        let p = ThumbsProgressPanel()
        p.show(panelState)
        return p.rowTexts
    }

    /// The popover goes when the pill does (done, or a narrow toolbar).
    func closePopover() { popover?.close() }
    var popoverContentSize: CGSize { popover?.contentSize ?? .zero }
    var panelFittingSize: CGSize { panel?.fittingSize ?? .zero }

    /// Whether the open popover points at the pill (not at the view the View menu's Thumbnails… chose for a hidden
    /// pill): it then goes when a narrow toolbar hides the pill.
    var isPopoverOnPill: Bool { isPopoverShown && popoverAnchor === self }
    private weak var popoverAnchor: NSView?

    func togglePopover() {
        if let popover, popover.isShown {
            popover.close()
            return
        }
        openPopover(from: self)
    }

    /// The popover pointing at `anchor` (the pill, or the sort while a narrow toolbar hides the pill); one already
    /// open stays as it is.
    func openPopover(from anchor: NSView) {
        guard !isPopoverShown, anchor.window != nil else { return }
        let panel = makePanel()
        panel.frame.size = panel.fittingSize
        let controller = NSViewController()
        controller.view = panel
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.delegate = self
        self.popover = popover
        popoverAnchor = anchor
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    func popoverDidClose(_ notification: Notification) {
        popover = nil
        panel = nil
    }
}

/// A layer-backed view with y growing down, so its sublayers' paths read like the board's SVG.
private final class FlippedLayerView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
}

/// The capsule's edge over the glass: the 0.5 pt separator ring and the inset highlight along the top. Takes no clicks.
private final class EdgeView: NSView {
    let rim = CALayer()
    let highlight = CAShapeLayer()
    private let highlightClip = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        rim.borderWidth = 0.5
        highlight.fillRule = .evenOdd
        highlightClip.masksToBounds = true
        highlightClip.addSublayer(highlight)
        layer?.addSublayer(highlightClip)
        layer?.addSublayer(rim)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The ring round the capsule; the highlight is the capsule less itself moved down 0.5 pt, clipped to the capsule:
    /// a hairline that follows the top edge and thins out down the round ends.
    func place(radius: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rim.frame = bounds
        rim.cornerRadius = radius
        highlightClip.frame = bounds
        highlightClip.cornerRadius = radius
        highlight.frame = bounds
        let path = CGMutablePath()
        path.addRoundedRect(in: bounds, cornerWidth: radius, cornerHeight: radius)
        path.addRoundedRect(in: bounds.offsetBy(dx: 0, dy: 0.5), cornerWidth: radius, cornerHeight: radius)
        highlight.path = path
        CATransaction.commit()
    }
}
