import AppKit
import HomeScreenModel

/// A grid's scroll view (the home screen's and the browser's): a resize gesture becomes `onResize`, anything else
/// scrolls. ⌘ + wheel (up larger), a mouse's side wheel (right larger; a trackpad's sideways swipe has a phase and is
/// left alone) and a pinch; a precise wheel moves a step every 40 points, a pinch every 0.15 of magnification.
final class GridScrollView: NSScrollView {
    var onResize: ((HomeResize) -> Void)?
    /// The user scrolled (a wheel or a trackpad, not a resize step).
    var onUserScroll: (() -> Void)?
    /// Wheel and pinch travel not yet a whole step.
    private var pendingNotches = 0.0
    private var pendingMagnification: CGFloat = 0

    override func scrollWheel(with event: NSEvent) {
        guard !resizeWheel(event) else { return }
        onUserScroll?()
        super.scrollWheel(with: event)
    }

    override func magnify(with event: NSEvent) {
        if event.phase == .began { pendingMagnification = 0 }
        pendingMagnification += event.magnification
        while pendingMagnification >= 0.15 { pendingMagnification -= 0.15; onResize?(.larger) }
        while pendingMagnification <= -0.15 { pendingMagnification += 0.15; onResize?(.smaller) }
    }

    /// Size steps from a wheel or a mouse's side wheel: positive larger; a step for each whole notch.
    func resize(notches: Double) {
        pendingNotches += notches
        while pendingNotches >= 1 { pendingNotches -= 1; onResize?(.larger) }
        while pendingNotches <= -1 { pendingNotches += 1; onResize?(.smaller) }
    }

    private func resizeWheel(_ event: NSEvent) -> Bool {
        let scale = event.hasPreciseScrollingDeltas ? 1.0 / 40 : 1
        if event.modifierFlags.contains(.command) {
            resize(notches: Double(event.scrollingDeltaY) * scale)
            return true
        }
        let sideways = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        if sideways, event.phase.isEmpty, event.momentumPhase.isEmpty {
            resize(notches: -Double(event.scrollingDeltaX) * scale)
            return true
        }
        return false
    }
}
