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
