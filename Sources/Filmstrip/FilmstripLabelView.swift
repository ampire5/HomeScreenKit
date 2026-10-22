import AppKit
import HomeChrome

/// The hover label: "137 / 200 · name" on a glass capsule, 12 pt, digits of one width. Takes no clicks.
@MainActor public final class FilmstripLabelView: NSView {
    private let glass = NSGlassEffectView()
    private let field = NSTextField(labelWithString: "")

    public var text: String {
        get { field.stringValue }
        set { field.stringValue = newValue }
    }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        Chrome.Palette.overMedia.apply(to: self)
        field.font = Chrome.Text.digits(.label, weight: .regular)
        field.textColor = Chrome.Palette.overMedia.text
        field.lineBreakMode = .byTruncatingMiddle
        field.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            field.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        glass.contentView = content
        glass.autoresizingMask = [.width, .height]
        addSubview(glass)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var fittingSize: NSSize {
        let text = field.intrinsicContentSize
        return NSSize(width: ceil(text.width) + 20, height: ceil(text.height) + 6)
    }

    public override func layout() {
        super.layout()
        glass.frame = bounds
        glass.cornerRadius = Chrome.Radius.capsule(bounds.height)
    }

    public override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
