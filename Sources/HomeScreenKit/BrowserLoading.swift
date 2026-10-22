import AppKit
import HomeChrome
import HomeScreenModel

/// A thin accent line under the path bar while a folder loads: a glint runs along it (still, at half strength, with
/// Reduce motion).
final class LoadingLine: NSView {
    private let glint = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        let accent = NSColor.controlAccentColor
        glint.colors = [accent.withAlphaComponent(0).cgColor, accent.cgColor, accent.withAlphaComponent(0).cgColor]
        glint.startPoint = CGPoint(x: 0, y: 0.5)
        glint.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(glint)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var isRunning: Bool { !isHidden }

    func run(_ on: Bool) {
        guard on != isRunning else { return }
        isHidden = !on
        glint.removeAllAnimations()
        guard on else { return }
        needsLayout = true
        layoutSubtreeIfNeeded()
        if Chrome.Motion.duration(1) == 0 {   // Reduce motion
            glint.colors = [NSColor.controlAccentColor.withAlphaComponent(0.5).cgColor,
                            NSColor.controlAccentColor.withAlphaComponent(0.5).cgColor]
            return
        }
        let sweep = CABasicAnimation(keyPath: "position.x")
        sweep.fromValue = -bounds.width * 0.2
        sweep.toValue = bounds.width * 1.2
        sweep.duration = 1.4
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        sweep.repeatCount = .infinity
        glint.add(sweep, forKey: "sweep")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glint.frame = Chrome.Motion.duration(1) == 0 ? bounds : CGRect(x: 0, y: 0, width: bounds.width * 0.4, height: bounds.height)
        CATransaction.commit()
    }
}

/// Grey cards where a folder's cards will be, with a slow shine across them (still with Reduce motion), while nothing
/// of the folder has come yet; and, once it is slow, a calm line in the middle saying what it waits for.
final class BrowserSkeleton: NSView {
    private let shapes = CALayer()
    private let shine = CAGradientLayer()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private var plate: NSView?
    /// The wanted slot width: the skeleton lays its slots out at its own width, as the grid will.
    var cardSize: CGFloat = 220 { didSet { if cardSize != oldValue { needsLayout = true } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        shine.colors = [NSColor(white: 0.14, alpha: 1).cgColor, NSColor(white: 0.21, alpha: 1).cgColor,
                        NSColor(white: 0.14, alpha: 1).cgColor]
        shine.locations = [0, 0.5, 1]
        shine.startPoint = CGPoint(x: 0, y: 0.3)
        shine.endPoint = CGPoint(x: 1, y: 0.7)
        shine.mask = shapes
        layer?.addSublayer(shine)
        title.font = Chrome.Text.font(.heading, weight: .medium)
        title.textColor = NSColor(white: 0.92, alpha: 1)
        detail.font = Chrome.Text.digits(.body, weight: .regular)
        detail.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, detail])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        // A dark plate under the words: they sit over the grey cards.
        let plate = NSView()
        plate.wantsLayer = true
        plate.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.92).cgColor
        plate.layer?.cornerRadius = Chrome.Radius.panel
        plate.layer?.cornerCurve = .continuous
        plate.translatesAutoresizingMaskIntoConstraints = false
        plate.addSubview(stack)
        self.plate = plate
        addSubview(plate)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: plate.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: plate.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: plate.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: plate.bottomAnchor, constant: -14),
            plate.centerXAnchor.constraint(equalTo: centerXAnchor),
            plate.topAnchor.constraint(equalTo: topAnchor, constant: 120),
        ])
        show(title: nil, detail: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(title text: String?, detail more: String?) {
        title.stringValue = text ?? ""
        detail.stringValue = more ?? ""
        title.isHidden = text == nil
        detail.isHidden = more == nil
        plate?.isHidden = text == nil
    }

    var captionText: String? {
        title.isHidden ? nil : [title.stringValue, detail.stringValue].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    func start() {
        shine.removeAllAnimations()
        guard Chrome.Motion.duration(1) > 0 else { return }   // Reduce motion
        let move = CABasicAnimation(keyPath: "locations")
        move.fromValue = [-1, -0.5, 0]
        move.toValue = [1, 1.5, 2]
        move.duration = 1.8
        move.repeatCount = .infinity
        shine.add(move, forKey: "shine")
    }

    func stop() { shine.removeAllAnimations() }

    /// The pictures' places, for tests.
    var pictureFrames: [CGRect] { (shapes.sublayers ?? []).filter { $0.name == "picture" }.map(\.frame) }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shine.frame = bounds
        shapes.frame = bounds
        shapes.sublayers = nil
        if bounds.width > 0 {
            // As many as fill the view: the real ones take their places as they come.
            let row = GridLayout(sections: [GridSection(kind: .photos, count: 1)], width: bounds.width, target: cardSize,
                                 names: .off)
            let columns = row.columns(inSection: 0), pitch = row.slotWidth(inSection: 0) + GridMetrics().photoGap
            let slots = columns * max(1, Int((bounds.height / pitch).rounded(.up)))
            let full = GridLayout(sections: [GridSection(kind: .photos, count: slots)], width: bounds.width,
                                  target: cardSize, names: .off)
            for i in 0..<slots {
                let picture = CALayer()
                picture.name = "picture"
                picture.backgroundColor = NSColor.black.cgColor
                picture.cornerRadius = 1
                picture.frame = full.pictureFrame(of: i)
                shapes.addSublayer(picture)
            }
        }
        CATransaction.commit()
    }
}
