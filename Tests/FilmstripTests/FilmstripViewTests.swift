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

@MainActor @Test func hoverLabelKeepsClearOfTheTrailingInset() {
    let view = FilmstripView(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
    view.setLayout(FilmstripLayout(itemCount: 10, length: 400, thickness: 68, maxAspect: 1.5, aspects: []), animated: false)
    view.show(offset: view.layout.centre(of: 9), current: 9, expansion: 1, animated: false)
    view.labelTrailingInset = 100
    view.showLabel(item: 9, text: "10 / 10 · a rather long photo name.jpg")
    let label = view.labelFrame
    #expect(!label.isEmpty)
    #expect(label.maxX <= 400 - 100)
    #expect(!label.intersects(CGRect(x: 300, y: 0, width: 100, height: 200)))
    view.labelTrailingInset = 0
    #expect(view.labelFrame.maxX > 300)
}

@MainActor @Test func revealAndToolsAreDarkChrome() {
    #expect(FilmstripRevealView(frame: .zero).appearance?.name == .darkAqua)
    #expect(FilmstripToolsView(frame: .zero).appearance?.name == .darkAqua)
}
