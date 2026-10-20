import AppKit

/// The sidebar's right edge, dragged to resize it as in Photos: the gap beside its glass panel with a few points of
/// the panel's edge (a press on the edge one sees resizes, it does not open the row under it) and of the grid. A
/// column-resize pointer over it, the width following the pointer while the button is down, the end of the drag
/// reported once.
final class SidebarResizeHandle: NSView {
    /// How far it reaches into the panel and into the grid beside the gap.
    static let inside: CGFloat = 5
    static let outside: CGFloat = 3

    /// The sidebar's width when a drag starts.
    var currentWidth: () -> CGFloat = { 0 }
    /// The width the pointer asks for (the view clamps it).
    var onResize: ((CGFloat) -> Void)?
    /// The button came up after a drag.
    var onEnd: (() -> Void)?

    /// Where the drag started, in the superview, and the width then.
    private var start: (x: CGFloat, width: CGFloat)?

    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Entering sets the resize pointer, leaving sets the arrow back by hand: neither a cursor-update area alone nor
        // cursor rects gave the arrow back over the sidebar.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow,
                                                              .inVisibleRect], owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func cursorUpdate(with event: NSEvent) { NSCursor.columnResize.set() }
    override func mouseEntered(with event: NSEvent) { NSCursor.columnResize.set() }
    override func mouseExited(with event: NSEvent) {
        if start == nil { NSCursor.arrow.set() }
    }

    override func mouseDown(with event: NSEvent) { beginDrag(at: x(of: event)) }
    override func mouseDragged(with event: NSEvent) {
        NSCursor.columnResize.set()
        drag(to: x(of: event))
    }
    override func mouseUp(with event: NSEvent) {
        endDrag()
        if !bounds.contains(convert(event.locationInWindow, from: nil)) { NSCursor.arrow.set() }
    }

    func beginDrag(at x: CGFloat) { start = (x, currentWidth()) }

    func drag(to x: CGFloat) {
        guard let start else { return }
        onResize?(start.width + x - start.x)
    }

    func endDrag() {
        guard start != nil else { return }
        start = nil
        onEnd?()
    }

    private func x(of event: NSEvent) -> CGFloat {
        (superview ?? self).convert(event.locationInWindow, from: nil).x
    }
}
