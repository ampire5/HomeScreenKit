import AppKit

/// Whether animations should be skipped (System Settings › Accessibility › Display › Reduce motion).
@MainActor var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

/// A segmented capsule on glass (the toolbar's kind filter and sort): the lit segment is a tinted inner capsule that
/// slides to the chosen one. `selected` nil lights none.
@MainActor public final class GlassCapsule: NSView {
    public static let height: CGFloat = 28
    private static let padding: CGFloat = 12
    private static let font = NSFont.systemFont(ofSize: 12, weight: .medium)

    public var onChoose: ((Int) -> Void)?
    public var titles: [String] { didSet { rebuild() } }
    public var selected: Int? { didSet { placeLight(animated: true) } }

    private let glass = NSGlassEffectView()
    private let content = NSView()
    private let light = NSView()
    private var buttons: [NSButton] = []

    public init(titles: [String]) {
        self.titles = titles
        super.init(frame: .zero)
        glass.cornerRadius = Self.height / 2
        glass.contentView = content
        addSubview(glass)
        light.wantsLayer = true
        light.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
        light.layer?.cornerRadius = (Self.height - 4) / 2
        light.isHidden = true
        content.addSubview(light)
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// What a click on segment `i` does.
    public func choose(_ i: Int) {
        guard titles.indices.contains(i) else { return }
        selected = i
        onChoose?(i)
    }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: widths.reduce(4, +), height: Self.height)
    }

    private var widths: [CGFloat] {
        titles.map { ceil(($0 as NSString).size(withAttributes: [.font: Self.font]).width) + 2 * Self.padding }
    }

    private func rebuild() {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = titles.enumerated().map { i, title in
            let b = NSButton(title: title, target: self, action: #selector(clicked(_:)))
            b.isBordered = false
            b.font = Self.font
            b.tag = i
            content.addSubview(b)
            return b
        }
        if let s = selected, !titles.indices.contains(s) { selected = nil }
        invalidateIntrinsicContentSize()
        needsLayout = true
        placeLight(animated: false)
    }

    @objc private func clicked(_ sender: NSButton) { choose(sender.tag) }

    public override func layout() {
        super.layout()
        glass.frame = bounds
        content.frame = bounds
        var x: CGFloat = 2
        for (b, w) in zip(buttons, widths) {
            b.frame = NSRect(x: x, y: 2, width: w, height: bounds.height - 4)
            x += w
        }
        placeLight(animated: false)
    }

    private func placeLight(animated: Bool) {
        for (i, b) in buttons.enumerated() {
            b.contentTintColor = i == selected ? .white : .labelColor
        }
        guard let s = selected, buttons.indices.contains(s) else { light.isHidden = true; return }
        let target = buttons[s].frame
        let wasHidden = light.isHidden
        light.isHidden = false
        if animated, !wasHidden, !reducesMotion {
            NSAnimationContext.runAnimationGroup { c in
                c.duration = 0.2
                light.animator().frame = target
            }
        } else {
            light.frame = target
        }
    }
}
