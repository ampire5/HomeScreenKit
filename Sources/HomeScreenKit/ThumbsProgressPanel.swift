import AppKit
import HomeChrome
import HomeScreenModel

/// The pill's popover (the board's «По щелчку»): the title, a line per stage — its name, its tabular count and a 4 pt
/// bar — the pause note, and the buttons Pause / Resume and Prepare subfolders (Stop preparing while a subtree is being
/// prepared). 13 pt, padding 14, 10 between the parts.
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
    var onStopSubtree: (() -> Void)?

    let pauseButton = PanelButton(title: "Pause")
    let prepareButton = PanelButton(title: "Prepare subfolders")

    private let titleLabel = NSTextField(labelWithString: "Thumbnails")
    private let noteLabel = NSTextField(labelWithString: "")
    private var lines: [Line] = []
    private var pausedByUser = false
    private var subtreeRunning = false

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
        subtreeRunning = state.subtreeRunning
        prepareButton.title = state.subtreeRunning ? "Stop preparing" : "Prepare subfolders"
        applyColors()
        needsLayout = true
        invalidateIntrinsicContentSize()
    }

    @objc private func pauseClicked() { onPause?(!pausedByUser) }
    @objc private func prepareClicked() {
        if subtreeRunning { onStopSubtree?() } else { onPrepare?() }
    }

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
        layer?.borderColor = Chrome.resolve(Chrome.Palette.progress.buttonBorder, in: self)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
        applyTitle()
    }
}
