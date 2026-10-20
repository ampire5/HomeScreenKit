import AppKit

/// Under the last row: what the folder holds, and under it a state (a slow listing, a filter), centred.
final class GridFooter: NSView {
    private let line = NSTextField(labelWithString: "")
    private let state = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        line.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        line.textColor = .secondaryLabelColor
        state.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        state.textColor = .tertiaryLabelColor
        for label in [line, state] {
            label.alignment = .center
            addSubview(label)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var lines: [String] { [line, state].filter { !$0.isHidden }.map(\.stringValue) }

    func show(lines: [String]) {
        line.stringValue = lines.first ?? ""
        state.stringValue = lines.count > 1 ? lines[1] : ""
        line.isHidden = lines.isEmpty
        state.isHidden = lines.count < 2
    }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        line.frame = CGRect(x: 0, y: 20, width: bounds.width, height: 16)
        state.frame = CGRect(x: 0, y: 38, width: bounds.width, height: 15)
    }
}
