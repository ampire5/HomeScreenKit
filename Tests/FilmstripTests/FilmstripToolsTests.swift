import AppKit
import HomeChrome
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
    // 3 pt padding inside a 1 pt border, buttons 2 pt apart: the sketch's `.cap`
    let width: CGFloat = 2 * 28 + 2 + 2 * (3 + 1), height: CGFloat = 32
    #expect(view.intrinsicContentSize == NSSize(width: width, height: height))
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
        FilmstripTool(symbol: "strip.beside", help: "a", isOn: false, action: {}),
        FilmstripTool(symbol: "pin", help: "b", isOn: true, action: {}),
    ])
    let off = view.buttons[0], on = view.buttons[1]
    #expect(off.pillAlpha == 0 && off.symbolAlpha == 0.6)
    #expect(on.pillAlpha == 0.22 && on.symbolAlpha == 1)
    #expect(off.pillColor == nil && on.pillColor == FilmstripToolsView.pressed)
    off.setHovered(true)   // brighter glyph, no pill
    #expect(off.pillAlpha == 0 && off.symbolAlpha == 1 && off.pillColor == nil)
    off.setHovered(false)
    #expect(off.symbolAlpha == 0.6)
}

/// The capsule's own glyphs are drawn from the sketch's paths, the others are SF Symbols.
@MainActor @Test func capsuleGlyphsAreTheSketchs() {
    let view = toolsView([FilmstripTool(symbol: "strip.over", help: "a", action: {}),
                          FilmstripTool(symbol: "eye", help: "b", action: {})])
    let glyph = view.buttons[0].subviews.compactMap { $0 as? GlyphView }.first
    #expect(glyph != nil && glyph!.frame.size == NSSize(width: 16, height: 14))
    #expect(view.buttons[1].image != nil)
    #expect(view.buttons[0].hitTest(NSPoint(x: view.buttons[0].frame.midX, y: view.buttons[0].frame.midY)) === view.buttons[0])
    #expect(FilmstripGlyph.allCases.map(\.rawValue) == ["strip.beside", "strip.over", "pin", "pin.fill", "chevron.down"])
}

/// Muted at rest, at full strength under the pointer.
@MainActor @Test func capsuleIsMutedAtRest() {
    let view = toolsView([FilmstripTool(symbol: "pin", help: "a", action: {})])
    #expect(view.subviews.first?.alphaValue == FilmstripToolsView.restAlpha && FilmstripToolsView.restAlpha == 0.7)
    view.setHovered(true)
    #expect(view.subviews.first?.alphaValue == 1)
    view.setShown(false, animated: false)
    #expect(view.subviews.first?.alphaValue == 0.7)
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

@MainActor private func glasses(in view: NSView) -> [ChromeGlass] {
    view.subviews.compactMap { $0 as? ChromeGlass }
}

/// The reveal chevron keeps its light glass; the capsule is the sketch's flat dark plate with its border.
@MainActor @Test func filmstripChromeSurfaces() {
    let tools = toolsView([FilmstripTool(symbol: "eye", help: "a", action: {})])
    let reveal = FilmstripRevealView(frame: NSRect(x: 0, y: 0, width: 40, height: 18))
    #expect(glasses(in: tools).isEmpty)
    let plate = tools.subviews.first?.layer
    #expect(plate?.borderWidth == 1 && plate?.backgroundColor == FilmstripToolsView.plate.cgColor)
    #expect(plate?.cornerRadius == 16)
    #expect(glasses(in: reveal).count == 1 && glasses(in: reveal).first?.style == .overMedia(.light))
}

@MainActor @Test func revealChevronIsLaidOutOnTheFirstPass() {
    let view = FilmstripRevealView(frame: NSRect(x: 0, y: 0, width: 40, height: 18))
    view.layoutSubtreeIfNeeded()
    let chevron = view.subviews.compactMap { $0 as? ChromeGlass }.first?.contentView.subviews.first
    #expect(chevron != nil && chevron!.frame.width > 0 && chevron!.frame.height > 0)
}
