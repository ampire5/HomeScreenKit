import AppKit
import HomeChrome
import HomeScreenModel

/// The toolbar's pill for the thumbnails being prepared (thumbs-ahead spec, "Пилюля в тулбаре"; the progress board's
/// button): a glass capsule 28 pt high with a 20 pt ring that fills by the current stage's share, a pause glyph in it
/// while the work runs (play while paused, the ring grey), and the app's text in 12 pt tabular digits. A click opens a
/// popover with the stages' bars, the pause note and the buttons. One view, so it can become an `NSToolbarItem`'s view.
final class ThumbsProgressPill: NSView, NSPopoverDelegate {
    enum Glyph: Equatable { case pause, play }

    static let height: CGFloat = 28
    /// The paused ring: the board's #8E8E94, the same grey in both appearances.
    static let pausedRing = NSColor(srgbRed: 0x8E / 255, green: 0x8E / 255, blue: 0x94 / 255, alpha: 1)
    /// The board's button: padding 0 12 0 6, gap 8 between the ring and the text.
    private static let leading: CGFloat = 6
    private static let gap: CGFloat = 8
    private static let trailing: CGFloat = 12
    /// The ring: a 20 pt box, radius 8, stroke 2.5.
    private static let ringBox: CGFloat = 20
    private static let ringRadius: CGFloat = 8
    private static let ringWidth: CGFloat = 2.5
    /// The inset highlight along the top edge (`inset 0 0.5px 0 rgba(255,255,255,.35)`), both appearances.
    private static let highlightColor = NSColor(white: 1, alpha: 0.35)
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

    /// The popover's Pause (true) or Resume (false).
    var onPause: ((Bool) -> Void)?
    /// The popover's Prepare subfolders.
    var onPrepare: (() -> Void)?

    private(set) var state: ThumbsProgressState?
    private(set) var ringColor = Chrome.Palette.card.accent
    private(set) var glyph = Glyph.pause
    var text: String { label.stringValue }
    /// The ring's fill, 0…1 (the model value; the layer animates to it).
    var ringEnd: CGFloat { fill.strokeEnd }
    var textWidth: CGFloat { ceil((text as NSString).size(withAttributes: [.font: Self.font]).width) }

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

    override func accessibilityPerformPress() -> Bool {
        togglePopover()
        return true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.leading + Self.ringBox + Self.gap + textWidth + Self.trailing, height: Self.height)
    }

    /// The state to draw; nil hides the pill (and closes its popover).
    func show(_ p: ThumbsProgressState?) {
        state = p
        guard let p else {
            isHidden = true
            popover?.close()
            return
        }
        isHidden = false
        if label.stringValue != p.text {
            label.stringValue = p.text
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
        setAccessibilityLabel(p.text)
        glyph = p.paused ? .play : .pause
        ringColor = p.paused ? Self.pausedRing : Chrome.Palette.card.accent
        glyphLayer.path = Self.glyphPath(glyph)
        let end = CGFloat(min(1, max(0, p.fraction)))
        if end != fill.strokeEnd {
            CATransaction.begin()
            CATransaction.setAnimationDuration(Chrome.Motion.duration(Chrome.Motion.hide))
            fill.strokeEnd = end
            CATransaction.commit()
        }
        applyColors()
        panel?.show(p)
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
        edge.highlight.fillColor = Chrome.resolve(Self.highlightColor, in: self)
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
        ring.frame = CGRect(x: Self.leading, y: (bounds.height - Self.ringBox) / 2, width: Self.ringBox,
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
        if let state { panel.show(state) }
        self.panel = panel
        return panel
    }

    func togglePopover() {
        if let popover, popover.isShown {
            popover.close()
            return
        }
        guard state != nil, window != nil else { return }
        let panel = makePanel()
        panel.frame.size = panel.fittingSize
        let controller = NSViewController()
        controller.view = panel
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.delegate = self
        self.popover = popover
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
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

/// The pill's popover (the board's «По щелчку»): the title, a line per stage — its name, its tabular count and a 4 pt
/// bar — the pause note, and the buttons Pause / Resume and Prepare subfolders. 13 pt, padding 14, 10 between the parts.
final class ThumbsProgressPanel: NSView {
    static let width: CGFloat = 360
    private static let padding: CGFloat = 14
    private static let gap: CGFloat = 10
    private static let barHeight: CGFloat = 4
    /// Between a line's text and its bar.
    private static let barGap: CGFloat = 4
    private static let font = NSFont.systemFont(ofSize: 13)
    private static let digits = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    /// A label's own inset: its text starts this far in, so a label set 2 pt left lines up with the bars.
    static let textInset: CGFloat = 2

    var onPause: ((Bool) -> Void)?
    var onPrepare: (() -> Void)?

    let pauseButton = PanelButton(title: "Pause")
    let prepareButton = PanelButton(title: "Prepare subfolders")

    private let titleLabel = NSTextField(labelWithString: "Thumbnails")
    private let noteLabel = NSTextField(labelWithString: "")
    private var lines: [Line] = []
    private var pausedByUser = false

    var title: String { titleLabel.stringValue }
    var rowTexts: [String] { lines.map { $0.name.stringValue + " " + $0.count.stringValue } }
    var barFractions: [Double] { lines.map(\.fraction) }
    var note: String? { noteLabel.isHidden ? nil : noteLabel.stringValue }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.width, height: 100))
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        noteLabel.font = NSFont.systemFont(ofSize: 12)
        noteLabel.lineBreakMode = .byTruncatingTail
        noteLabel.isHidden = true
        pauseButton.target = self
        pauseButton.action = #selector(pauseClicked)
        prepareButton.target = self
        prepareButton.action = #selector(prepareClicked)
        for v in [titleLabel, noteLabel, pauseButton, prepareButton] as [NSView] { addSubview(v) }
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func show(_ state: ThumbsProgressState) {
        while lines.count < state.rows.count {
            let line = Line(font: Self.font, digits: Self.digits)
            lines.append(line)
            line.add(to: self)
        }
        while lines.count > state.rows.count { lines.removeLast().remove() }
        for (line, row) in zip(lines, state.rows) {
            line.name.stringValue = row.title
            line.count.stringValue = "\(row.done) / \(row.total)"
            line.fraction = row.fraction
        }
        noteLabel.stringValue = state.pauseNote ?? ""
        noteLabel.isHidden = state.pauseNote == nil
        pausedByUser = state.pausedByUser
        pauseButton.title = state.pausedByUser ? "Resume" : "Pause"
        applyColors()
        needsLayout = true
        invalidateIntrinsicContentSize()
    }

    @objc private func pauseClicked() { onPause?(!pausedByUser) }
    @objc private func prepareClicked() { onPrepare?() }

    private var lineHeight: CGFloat { ceil(titleLabel.intrinsicContentSize.height) }

    override var intrinsicContentSize: NSSize {
        var h = Self.padding + lineHeight
        h += CGFloat(lines.count) * (Self.gap + lineHeight + Self.barGap + Self.barHeight)
        if !noteLabel.isHidden { h += Self.gap + ceil(noteLabel.intrinsicContentSize.height) }
        h += Self.gap + pauseButton.intrinsicContentSize.height + Self.padding
        return NSSize(width: Self.width, height: h)
    }

    override func layout() {
        super.layout()
        let x = Self.padding, w = bounds.width - 2 * Self.padding, inset = Self.textInset
        var y = Self.padding
        titleLabel.frame = CGRect(x: x - inset, y: y, width: w + inset, height: lineHeight)
        y += lineHeight
        for line in lines {
            y += Self.gap
            line.place(x: x, y: y, width: w, lineHeight: lineHeight, barGap: Self.barGap, barHeight: Self.barHeight)
            y += lineHeight + Self.barGap + Self.barHeight
        }
        if !noteLabel.isHidden {
            y += Self.gap
            let h = ceil(noteLabel.intrinsicContentSize.height)
            noteLabel.frame = CGRect(x: x - inset, y: y, width: w + inset, height: h)
            y += h
        }
        y += Self.gap
        let p = pauseButton.intrinsicContentSize, q = prepareButton.intrinsicContentSize
        pauseButton.frame = CGRect(x: x, y: y, width: p.width, height: p.height)
        prepareButton.frame = CGRect(x: pauseButton.frame.maxX + 8, y: y, width: q.width, height: q.height)
    }

    private func applyColors() {
        titleLabel.textColor = Chrome.Palette.card.label
        noteLabel.textColor = Chrome.Palette.card.secondary
        for line in lines { line.applyColors(in: self) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    /// One stage: its name on the left, its count on the right (secondary, tabular), the bar under them — the board's
    /// #0A84FF on rgba(0,0,0,.09), round ends.
    @MainActor private final class Line {
        let name = NSTextField(labelWithString: "")
        let count = NSTextField(labelWithString: "")
        let bar = NSView()
        let barFill = CALayer()
        var fraction: Double = 0

        init(font: NSFont, digits: NSFont) {
            name.font = font
            name.lineBreakMode = .byTruncatingTail
            count.font = digits
            count.alignment = .right
            bar.wantsLayer = true
            bar.layer?.addSublayer(barFill)
        }

        func add(to view: NSView) {
            for v in [name, count, bar] { view.addSubview(v) }
        }

        func remove() {
            for v in [name, count, bar] { v.removeFromSuperview() }
        }

        func place(x: CGFloat, y: CGFloat, width: CGFloat, lineHeight: CGFloat, barGap: CGFloat, barHeight: CGFloat) {
            let c = ceil(count.intrinsicContentSize.width)
            let inset = ThumbsProgressPanel.textInset
            count.frame = CGRect(x: x + width - c + inset, y: y, width: c, height: lineHeight)
            name.frame = CGRect(x: x - inset, y: y, width: max(0, width - c - 8), height: lineHeight)
            bar.frame = CGRect(x: x, y: y + lineHeight + barGap, width: width, height: barHeight)
            bar.layer?.cornerRadius = barHeight / 2
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            barFill.frame = CGRect(x: 0, y: 0, width: (width * CGFloat(fraction)).rounded(), height: barHeight)
            barFill.cornerRadius = barHeight / 2
            CATransaction.commit()
        }

        func applyColors(in view: NSView) {
            name.textColor = Chrome.Palette.card.label
            count.textColor = Chrome.Palette.card.secondary
            bar.layer?.backgroundColor = Chrome.resolve(Chrome.Palette.card.track, in: view)
            barFill.backgroundColor = Chrome.resolve(Chrome.Palette.card.accent, in: view)
        }
    }
}

/// The popover's bordered button, as the board draws it: 12.5 pt, padding 4 × 12, radius 7, a 0.5 pt border at
/// black .2 on white. Dark (not on the board): the card's dark plate under a white .2 border.
final class PanelButton: NSButton {
    private static let font = NSFont.systemFont(ofSize: 12.5)
    private static let border = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.2)
                                                                    : NSColor(white: 0, alpha: 0.2)
    }

    override var title: String {
        didSet { applyTitle() }
    }

    init(title: String) {
        super.init(frame: .zero)
        isBordered = false
        wantsLayer = true
        setButtonType(.momentaryChange)
        layer?.cornerRadius = 7
        layer?.borderWidth = 0.5
        self.title = title
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func applyTitle() {
        attributedTitle = NSAttributedString(string: title, attributes: [.font: Self.font,
                                                                        .foregroundColor: Chrome.Palette.card.label])
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        let s = (title as NSString).size(withAttributes: [.font: Self.font])
        return NSSize(width: ceil(s.width) + 24, height: ceil(s.height) + 8)
    }

    override var isHighlighted: Bool {
        didSet { layer?.opacity = isHighlighted ? 0.7 : 1 }
    }

    private func applyColors() {
        layer?.backgroundColor = Chrome.resolve(Chrome.Palette.card.background, in: self)
        layer?.borderColor = Chrome.resolve(Self.border, in: self)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
        applyTitle()
    }
}
