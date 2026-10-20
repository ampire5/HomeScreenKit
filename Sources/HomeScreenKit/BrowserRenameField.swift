import AppKit

/// The name field over a card's title while it is renamed: Return commits, Esc or leaving it cancels. A refused name
/// keeps the field open with the reason under it.
final class BrowserRenameField: NSTextField, NSTextFieldDelegate {
    let entryID: String
    /// The part selected when editing starts: the name without its extension for a file.
    let selection: NSRange
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    private let reasonLabel = NSTextField(wrappingLabelWithString: "")
    /// Set while a commit is out: leaving the field then is not a cancel.
    var isCommitting = false

    init(entryID: String, name: String, isFile: Bool) {
        self.entryID = entryID
        selection = Self.nameRange(for: name, isFile: isFile)
        super.init(frame: .zero)
        stringValue = name
        font = .systemFont(ofSize: 13, weight: .medium)
        isBordered = true
        isBezeled = true
        bezelStyle = .roundedBezel
        focusRingType = .none
        lineBreakMode = .byTruncatingMiddle
        cell?.isScrollable = true
        delegate = self
        reasonLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        reasonLabel.textColor = .systemRed
        reasonLabel.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static func nameRange(for name: String, isFile: Bool) -> NSRange {
        let full = (name as NSString).length
        guard isFile else { return NSRange(location: 0, length: full) }
        let ext = (name as NSString).pathExtension
        let base = ext.isEmpty ? full : full - (ext as NSString).length - 1
        return NSRange(location: 0, length: max(0, base))
    }

    var reason: String? { reasonLabel.isHidden ? nil : reasonLabel.stringValue }

    func show(reason text: String) {
        reasonLabel.stringValue = text
        reasonLabel.isHidden = false
        placeReason()
    }

    /// Over `rect` (the card's title, in the superview's coordinates), the reason under it.
    func place(over rect: CGRect) {
        frame = rect.insetBy(dx: -4, dy: -2)
        placeReason()
    }

    private func placeReason() {
        guard let superview else { return }
        if reasonLabel.superview !== superview { superview.addSubview(reasonLabel) }
        let width = frame.width
        let height = reasonLabel.sizeThatFits(CGSize(width: width, height: 200)).height
        reasonLabel.frame = CGRect(x: frame.minX, y: frame.maxY + 2, width: width, height: height)
    }

    /// Starts editing with the name selected (the window's field editor).
    func beginEditing() {
        guard let window, window.makeFirstResponder(self) else { return }
        currentEditor()?.selectedRange = selection
    }

    func remove() {
        reasonLabel.removeFromSuperview()
        removeFromSuperview()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): onCommit?(); return true
        case #selector(NSResponder.cancelOperation(_:)): onCancel?(); return true
        default: return false
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        if !isCommitting { onCancel?() }
    }
}
