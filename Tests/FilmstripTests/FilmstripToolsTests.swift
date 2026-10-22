import AppKit
import Testing
@testable import Filmstrip

@MainActor private func clickEvent() -> NSEvent {
    NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 5, y: 5), modifierFlags: [], timestamp: 0,
                       windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
}

@MainActor private func toolsView(_ tools: [FilmstripTool]) -> FilmstripToolsView {
    let view = FilmstripToolsView(frame: NSRect(x: 0, y: 0, width: 200, height: 28))
    view.tools = tools
    view.setFrameSize(view.intrinsicContentSize)
    view.layoutSubtreeIfNeeded()
    return view
}

@MainActor @Test func toolsBuildButtons() {
    let view = toolsView([
        FilmstripTool(symbol: "eye", help: "Hide", isOn: false, action: {}),
        FilmstripTool(symbol: "star", help: "Pin", isOn: true, action: {}),
    ])
    #expect(view.buttons.count == 2)
    #expect(view.buttons.map(\.toolTip) == ["Hide", "Pin"])
    #expect(view.buttons.map(\.state) == [.off, .on])
    #expect(view.buttons.allSatisfy { $0.frame.size == NSSize(width: 28, height: 24) })
    #expect(view.intrinsicContentSize.width == 2 * 28 + 1 + 6 && view.intrinsicContentSize.height == 30)
}

@MainActor @Test func toolActionRuns() {
    var runs: [Int] = []
    let view = toolsView([
        FilmstripTool(symbol: "eye", help: "a", isOn: false, action: { runs.append(0) }),
        FilmstripTool(symbol: "star", help: "b", isOn: false, action: { runs.append(1) }),
    ])
    view.buttons[1].performClick(nil)
    #expect(runs == [1])
}

@MainActor @Test func hiddenToolsTakeNoClicks() {
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
    let view = toolsView([FilmstripTool(symbol: "eye", help: "a", isOn: false, action: {})])
    host.addSubview(view)
    let point = NSPoint(x: view.frame.midX, y: view.frame.midY)
    #expect(view.hitTest(point) != nil)
    view.setShown(false, animated: false)
    #expect(view.alphaValue == 0)
    #expect(view.hitTest(point) == nil)
    view.setShown(true, animated: false)
    #expect(view.alphaValue == 1 && view.hitTest(point) != nil)
}

@MainActor @Test func revealCallsBack() {
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
    let view = FilmstripRevealView(frame: NSRect(x: 0, y: 0, width: 40, height: 18))
    host.addSubview(view)
    var calls = 0
    view.onReveal = { calls += 1 }
    let point = NSPoint(x: 20, y: 9)
    view.hitTest(point)?.mouseDown(with: clickEvent())
    #expect(calls == 1)
    view.setShown(false, animated: false)
    #expect(view.hitTest(point) == nil)
}

@MainActor @Test func revealPillSizePerEdge() {
    #expect(FilmstripRevealView.size == NSSize(width: 40, height: 18))
    let bottom = FilmstripRevealView(frame: .zero, edge: .bottom)
    let trailing = FilmstripRevealView(frame: .zero, edge: .trailing)
    #expect(bottom.fittingSize == NSSize(width: 40, height: 18))
    #expect(trailing.fittingSize == NSSize(width: 18, height: 40))
    #expect(FilmstripRevealView(frame: .zero).edge == .bottom)
}

@MainActor @Test func onButtonIsANeutralPillNotAccent() {
    let view = toolsView([
        FilmstripTool(symbol: "eye", help: "a", isOn: false, action: {}),
        FilmstripTool(symbol: "pin", help: "b", isOn: true, action: {}),
    ])
    let off = view.buttons[0], on = view.buttons[1]
    #expect(off.pillAlpha == 0 && off.symbolAlpha == 0.7)
    #expect(on.pillAlpha == 0.2 && on.symbolAlpha == 1)
    #expect(on.contentTintColor != .controlAccentColor && off.contentTintColor == on.contentTintColor)
    off.setHovered(true)
    #expect(off.pillAlpha == 0.1 && off.symbolAlpha == 1)
    off.setHovered(false)
    #expect(off.pillAlpha == 0 && off.symbolAlpha == 0.7)
}

@MainActor @Test func separatorSpacesTheGroups() {
    let plain = toolsView([
        FilmstripTool(symbol: "eye", help: "a", action: {}),
        FilmstripTool(symbol: "star", help: "b", action: {}),
    ])
    let grouped = toolsView([
        FilmstripTool(symbol: "eye", help: "a", action: {}),
        FilmstripTool(symbol: "star", help: "b", separatorBefore: true, action: {}),
    ])
    #expect(grouped.intrinsicContentSize.width == plain.intrinsicContentSize.width + 1 + 6)
    #expect(grouped.buttons[1].frame.minX == plain.buttons[1].frame.minX + 7)
}
