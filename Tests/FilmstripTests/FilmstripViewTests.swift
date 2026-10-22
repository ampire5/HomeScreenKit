import AppKit
import Testing
import FilmstripModel
@testable import Filmstrip

@MainActor private func scrollEvent() -> NSEvent {
    NSEvent(cgEvent: CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: -10, wheel3: 0)!)!
}

@MainActor private func otherMouseEvent(_ type: NSEvent.EventType) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                       eventNumber: 0, clickCount: 1, pressure: 0)!
}

@MainActor @Test func scrollGoesWhereTheOwnerSays() {
    let view = FilmstripView(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
    var strip = 0, owner = 0
    view.onStripScroll = { _ in strip += 1 }
    view.onScroll = { _ in owner += 1 }
    view.scrollWheel(with: scrollEvent())                       // no router: the strip's
    view.routeScroll = { _ in .owner }; view.scrollWheel(with: scrollEvent())
    view.routeScroll = { _ in .ignore }; view.scrollWheel(with: scrollEvent())
    #expect(strip == 1 && owner == 1)
}

@MainActor @Test func otherButtonsGoToTheOwner() {
    let view = FilmstripView(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
    var downs: [Bool] = []
    view.onOtherMouse = { _, down in downs.append(down); return true }
    view.otherMouseDown(with: otherMouseEvent(.otherMouseDown)); view.otherMouseUp(with: otherMouseEvent(.otherMouseUp))
    #expect(downs == [true, false])
}

@MainActor @Test func showsOnlyVisibleCells() {
    let view = FilmstripView(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
    view.setLayout(FilmstripLayout(itemCount: 10_000, length: 400, thickness: 68, maxAspect: 1.5, aspects: []), animated: false)
    view.show(offset: view.layout.centre(of: 5_000), current: 5_000, expansion: 1, animated: false)
    #expect(!view.visibleItems.isEmpty && view.visibleItems.count <= 49 && view.visibleItems.contains(5_000))
}

/// Two current items (two pages side by side): both on screen first, then the rest from the pair outwards.
@MainActor @Test func showsARunOfCurrentItems() {
    let view = FilmstripView(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
    view.setLayout(FilmstripLayout(itemCount: 100, length: 400, thickness: 68, maxAspect: 1.5, aspects: []), animated: false)
    view.show(offset: view.layout.centre(of: 40..<42), current: 40..<42, expansion: 1, animated: false)
    #expect(Set(view.visibleItems.prefix(2)) == [40, 41])
    #expect(Set(view.visibleItems.dropFirst(2).prefix(2)) == [39, 42])
}

@MainActor private func labelledStrip() -> FilmstripView {
    let view = FilmstripView(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
    view.setLayout(FilmstripLayout(itemCount: 10, length: 400, thickness: 68, maxAspect: 1.5, aspects: []), animated: false)
    view.show(offset: view.layout.centre(of: 4), current: 4, expansion: 1, animated: false)
    return view
}

/// The capsule stands where the pointer entered the strip: the label over a cell under it goes beside it, on the
/// side its cell is on.
@MainActor @Test func hoverLabelStepsAsideFromTheAvoidedSpan() {
    let view = labelledStrip()
    view.showLabel(item: 4, text: "5 / 10 · a.jpg")
    let free = view.labelFrame, centre = free.midX
    #expect(!free.isEmpty)
    view.labelAvoid = (centre - 10)...(centre + 60)        // most of it to the right of the cell: the label goes left
    #expect(view.labelFrame.maxX <= centre - 10)
    #expect(view.labelFrame.width == free.width)
    view.labelAvoid = (centre - 60)...(centre + 10)        // to the left: the label goes right
    #expect(view.labelFrame.minX >= centre + 10)
    view.labelAvoid = 0...(centre + 10)                    // no room on the left: the right whatever the side
    #expect(view.labelFrame.minX >= centre + 10)
    view.labelAvoid = nil
    #expect(view.labelFrame == free)
}

@MainActor @Test func hoverLabelAwayFromTheSpanStaysOverItsCell() {
    let view = labelledStrip()
    view.showLabel(item: 4, text: "5 / 10 · a.jpg")
    let free = view.labelFrame
    view.labelAvoid = (free.maxX + 40)...(free.maxX + 120)
    #expect(view.labelFrame == free)
}

/// A capsule on the strip that stays under the label's bottom (the label sits above the cells) does not push it
/// aside; one reaching up to it does.
@MainActor @Test func hoverLabelStepsAsideOnlyFromWhatReachesIt() {
    let view = labelledStrip()
    view.showLabel(item: 4, text: "5 / 10 · a.jpg")
    let free = view.labelFrame, centre = free.midX
    view.labelAvoid = (centre - 10)...(centre + 60)
    view.labelAvoidTop = free.minY - 1                      // below the label: it stays over its cell
    #expect(view.labelFrame == free)
    view.labelAvoidTop = free.minY + 1                      // up into it: aside
    #expect(view.labelFrame.maxX <= centre - 10)
}

@MainActor @Test func revealAndToolsAreDarkChrome() {
    #expect(FilmstripRevealView(frame: .zero).appearance?.name == .darkAqua)
    #expect(FilmstripToolsView(frame: .zero).appearance?.name == .darkAqua)
}
