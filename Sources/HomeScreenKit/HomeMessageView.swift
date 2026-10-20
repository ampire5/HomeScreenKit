import AppKit

/// A centred message in place of a grid: a title, why, the details and a line of keys (the home screen's "could not
/// open", the browser's "could not list").
final class HomeMessageView: NSStackView {
    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .centerX
        spacing = 8
        isHidden = true
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(title text: String, reason: String, detail: String, hints keys: [String]) {
        arrangedSubviews.forEach { $0.removeFromSuperview() }
        let title = NSTextField(labelWithString: text)
        title.font = .systemFont(ofSize: 18, weight: .medium)
        title.textColor = .white
        title.lineBreakMode = .byTruncatingMiddle
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let why = NSTextField(wrappingLabelWithString: reason)
        why.textColor = .white
        why.alignment = .center
        let more = NSTextField(wrappingLabelWithString: detail)
        more.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        more.textColor = .secondaryLabelColor
        more.alignment = .center
        let line = NSTextField(labelWithString: keys.joined(separator: "   ·   "))
        line.textColor = .secondaryLabelColor
        for view in [title, why, more, line] { addArrangedSubview(view) }
        setCustomSpacing(16, after: more)
    }

    /// The lines shown, top down.
    var texts: [String] { arrangedSubviews.compactMap { ($0 as? NSTextField)?.stringValue } }
}
