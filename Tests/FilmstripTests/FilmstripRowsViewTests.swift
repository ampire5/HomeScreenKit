import AppKit
import Testing
import FilmstripModel
@testable import Filmstrip

@MainActor private func strip(_ count: Int, current: Int) -> FilmstripRowsView {
    let view = FilmstripRowsView(frame: NSRect(x: 0, y: 0, width: 300, height: 600))
    view.layout = FilmstripRows(itemCount: count, aspects: [], length: 600, width: 300, rowPicture: 96,
                                currentPicture: 280, cardHeight: 120)
    view.show(offset: view.layout.centre(of: current), current: current, expansion: 1, animated: false)
    return view
}

@MainActor private func mouse(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                       eventNumber: 0, clickCount: 1, pressure: 1)!
}

/// The rows' layers follow what is on screen, not the list.
@MainActor @Test func poolFollowsWindow() {
    let view = strip(500, current: 0)
    for item in [0, 250, 499] {
        view.show(offset: view.layout.centre(of: item), current: item, expansion: 1, animated: false)
        #expect((view.contentLayer.sublayers?.count ?? 0) < 40)
        #expect(view.visibleItems.first == item)
    }
}

/// A click on the browsed row (at the strip's middle) reports it.
@MainActor @Test func pressReportsItem() {
    let view = strip(20, current: 5)
    var pressed: [Int] = []
    view.onPress = { pressed.append($0) }
    view.mouseDown(with: mouse(.leftMouseDown, at: NSPoint(x: 50, y: 300)))
    view.mouseUp(with: mouse(.leftMouseUp, at: NSPoint(x: 50, y: 300)))
    #expect(pressed == [5])
}

private final class CountingView: NSView {
    var scrolls = 0
    override func scrollWheel(with event: NSEvent) { scrolls += 1 }
}

/// Scrolling over the strip is the strip's: nothing reaches the view under it (the video's zoom).
@MainActor @Test func scrollIsSwallowed() {
    let parent = CountingView(frame: NSRect(x: 0, y: 0, width: 300, height: 600))
    let view = strip(20, current: 5)
    parent.addSubview(view)
    var strips = 0
    view.onStripScroll = { _ in strips += 1 }
    view.scrollWheel(with: NSEvent(cgEvent: CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                                    wheel1: -10, wheel2: 0, wheel3: 0)!)!)
    #expect(strips == 1 && parent.scrolls == 0)
}

/// The owner's card sits under the browsed row's picture.
@MainActor @Test func cardSitsUnderPicture() {
    let view = strip(20, current: 5)
    let card = NSView()
    view.card = card
    let row = view.layout.rows(offset: view.layout.centre(of: 5), current: 5, expansion: 1).first { $0.item == 5 }!
    #expect(card.superview === view)
    #expect(abs(card.frame.minY - (row.start + row.picture.height + FilmstripRowsView.cardGap)) < 0.01)
}

/// Two old rows that map to one new row (the same file twice in a list): what is known of them merges, no trap.
@MainActor @Test func remapMergesDuplicateTargets() {
    let view = strip(20, current: 5)
    for item in 0..<20 { view.setRow(item, title: "\(item)", detail: "", progress: nil) }
    view.remap([3: 3, 4: 3, 5: 4])
    #expect(!view.visibleItems.isEmpty)
}

/// The browsed row changes with the strip's move: the card moves and fades with it, not at once under still rows.
@MainActor @Test func cardAnimatesWithTheRows() {
    let view = strip(20, current: 5)
    let card = NSView()
    card.wantsLayer = true
    view.card = card
    card.layer?.removeAllAnimations()
    view.show(offset: view.layout.centre(of: 6), current: 6, expansion: 1, animated: true)
    let moving = card.layer?.animationKeys() ?? []
    #expect(!moving.isEmpty)
    card.layer?.removeAllAnimations()
    view.show(offset: view.layout.centre(of: 7), current: 7, expansion: 1, animated: false)
    let still = card.layer?.animationKeys() ?? []
    #expect(still.isEmpty)
}

/// A press on the rows is told at once (it stops a glide), before it is known to be a click or a drag.
@MainActor @Test func pressBeganIsReported() {
    let view = strip(20, current: 5)
    var began = 0
    view.onPressBegan = { began += 1 }
    view.mouseDown(with: mouse(.leftMouseDown, at: NSPoint(x: 50, y: 300)))
    let count = began
    #expect(count == 1)
}
