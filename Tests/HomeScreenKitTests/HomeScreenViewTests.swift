import AppKit
import Testing
@testable import HomeScreenKit

@MainActor @Suite struct HomeScreenViewTests {
    func card(_ id: String) -> HomeCardItem {
        HomeCardItem(id: id, title: id, tooltip: id, symbol: "folder")
    }

    func make(background: CGColor? = CGColor(gray: 0, alpha: 1), ids: [String] = []) -> HomeScreenView {
        let view = HomeScreenView(background: background)
        view.frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
        if !ids.isEmpty { view.sections = [HomeSection(title: "Recent", items: ids.map(card))] }
        view.layoutSubtreeIfNeeded()
        return view
    }

    static func image() -> CGImage {
        let c = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return c.makeImage()!
    }

    @Test func emptyHintOnlyOnRecent() {
        let view = make()
        view.tabs = ["Recent", "Stash"]
        #expect(view.showsEmptyHint)
        view.selectedTab = 1
        #expect(!view.showsEmptyHint)
        view.selectedTab = 0
        #expect(view.showsEmptyHint)
        view.sections = [HomeSection(title: nil, items: [card("a")])]
        #expect(!view.showsEmptyHint)
    }

    @Test func staleImageIgnored() {
        let view = make(ids: ["a"])
        view.sections = [HomeSection(title: nil, items: [card("b")])]
        view.setImage(Self.image(), for: "a")
        #expect(view.cardView(for: "a") == nil)
        #expect(view.cardView(for: "b")?.image == nil)
        view.setImage(Self.image(), for: "b")
        #expect(view.cardView(for: "b")?.image != nil)
    }

    @Test func transparentHitTest() {
        let view = make(background: nil, ids: ["a"])
        let card = view.cardView(for: "a")!
        let centre = card.convert(CGPoint(x: card.bounds.midX, y: card.bounds.midY), to: view)
        #expect(view.hitTest(centre) is HomeCard)
        #expect(view.hitTest(CGPoint(x: 995, y: 5)) == nil)
        let opaque = make(ids: ["a"])
        #expect(opaque.hitTest(CGPoint(x: 995, y: 5)) != nil)
    }

    @Test func returnOpensSelected() throws {
        let view = make(ids: ["first", "second"])
        var got: (String, HomeClick)?
        view.onCard = { got = ($0, $1) }
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
                                                  windowNumber: 0, context: nil, characters: "\r",
                                                  charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        view.supportsTabs = true
        #expect(view.handleKey(event))
        #expect(got?.0 == "first" && got?.1 == .openNewTab)
        view.supportsTabs = false
        #expect(view.handleKey(event))
        #expect(got?.1 == .open)
    }

    @Test func singleClickSelectsAndDoubleClickOpens() {
        let view = make(ids: ["first", "second"])
        var got: (String, HomeClick)?
        view.onCard = { got = ($0, $1) }
        let second = view.cardView(for: "second")!
        second.onClick?(false, [], 1)
        #expect(second.isSelected)
        #expect(got == nil)
        second.onClick?(false, [], 2)
        #expect(got?.0 == "second" && got?.1 == .open)
    }

    @Test func messageHidesGrid() {
        let view = make(ids: ["a"])
        view.showMessage(title: "Cannot open a.mp4", reason: "No video", detail: "-", hints: ["⌘O — open"])
        #expect(view.isShowingMessage)
        #expect(view.cardView(for: "a")?.isHiddenOrHasHiddenAncestor == true)
        view.showGrid()
        #expect(!view.isShowingMessage)
        #expect(view.cardView(for: "a")?.isHiddenOrHasHiddenAncestor == false)
    }

    @Test func mosaicSizes() {
        #expect(HomeMosaic.make([]) == nil)
        for n in [1, 2, 4] {
            let m = HomeMosaic.make(Array(repeating: Self.image(), count: n))
            #expect(m?.width == 600 && m?.height == 400)
        }
    }

    @Test func dropsOnlyWithAHandler() {
        let view = make(background: nil)
        #expect(!view.registeredDraggedTypes.contains(.fileURL))   // a transparent screen lets drops reach what is under it
        view.onDrop = { _ in }
        #expect(view.registeredDraggedTypes.contains(.fileURL))
        view.onDrop = nil
        #expect(!view.registeredDraggedTypes.contains(.fileURL))
    }

    @Test func settingTabsKeepsTheSwitch() {
        let view = make()
        view.tabs = ["Recent", "Stash"]
        let control = view.switcher
        view.tabs = ["Recent", "Stash"]
        #expect(view.switcher === control)
        view.tabs = ["Recent", "Library"]
        #expect(view.switcher === control && control.label(forSegment: 1) == "Library")
        view.tabs = []
        #expect(view.switcher.isHidden)
    }

    @Test func transparentScrollModeWithRoomLetsClicksThrough() {
        let view = make(background: nil, ids: ["a"])
        view.layoutMode = .scroll
        view.layoutSubtreeIfNeeded()
        #expect(view.hitTest(CGPoint(x: 995, y: 5)) == nil)
    }

    @Test func sameCardsAreUpdatedInPlace() {
        let view = make(ids: ["a", "b"])
        let first = view.cardView(for: "a")
        view.setImage(Self.image(), for: "a")
        var changed = card("a")
        changed.subtitle = "0:42"
        view.sections = [HomeSection(title: "Recent", items: [changed, card("b")])]
        #expect(view.cardView(for: "a") === first)
        #expect(view.cardView(for: "a")?.item.subtitle == "0:42")
        #expect(view.cardView(for: "a")?.image != nil)
    }

    func key(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags = [.command]) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false,
                         keyCode: code)!
    }

    func wheel(_ dy: Int32, _ dx: Int32 = 0, command: Bool = false) -> NSEvent {
        let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)!
        if command { e.flags = .maskCommand }
        return NSEvent(cgEvent: e)!
    }

    @Test func browserZoomKeysResizeTheCards() {
        let view = make(ids: ["a"])
        var got: [HomeResize] = []
        view.onResize = { got.append($0) }
        #expect(view.handleKey(key(24, "=")))
        #expect(view.handleKey(key(27, "-")))
        #expect(view.handleKey(key(29, "0")))
        #expect(!view.handleKey(key(24, "=", [])))   // a plain = is not a resize
        #expect(got == [.largerSize, .smallerSize, .reset])
    }

    @Test func resizeKeysWorkWithNoCards() {
        let view = make()
        var got: [HomeResize] = []
        view.onResize = { got.append($0) }
        #expect(view.handleKey(key(24, "=")))
        #expect(got == [.largerSize])
    }

    @Test func notchesAccumulate() {
        let view = make(ids: ["a"])
        var got: [HomeResize] = []
        view.onResize = { got.append($0) }
        view.resize(notches: 0.5)
        view.resize(notches: 0.6)
        view.resize(notches: -2.1)
        #expect(got == [.larger, .smaller, .smaller])
    }

    @Test func commandWheelAndSideWheelResize() {
        let view = make(ids: ["a"])
        var got: [HomeResize] = []
        view.onResize = { got.append($0) }
        view.gridScrollView.scrollWheel(with: wheel(1, command: true))
        view.gridScrollView.scrollWheel(with: wheel(-1, command: true))
        view.gridScrollView.scrollWheel(with: wheel(0, -1))   // the side wheel turned right
        view.gridScrollView.scrollWheel(with: wheel(-1))      // a plain wheel scrolls
        #expect(got == [.larger, .smaller, .larger])
    }
}
