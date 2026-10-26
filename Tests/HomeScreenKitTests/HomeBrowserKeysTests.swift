import AppKit
import Testing
@testable import HomeScreenKit

@MainActor @Suite struct HomeBrowserKeysTests {
    let x = URL(fileURLWithPath: "/Volumes/T/x")

    func key(_ code: UInt16, _ chars: String = "", _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false,
                         keyCode: code)!
    }

    func shown(_ source: FakeHomeSource, _ entries: [BrowserEntry], at folder: URL? = nil) async -> HomeBrowserView {
        let folder = folder ?? x
        let view = HomeBrowserView(source: source)
        view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        view.show(.folder(folder), selecting: nil)
        view.layoutSubtreeIfNeeded()
        source.yield(folder, entries)
        await settle(seconds: 5) { !view.entries.isEmpty }
        view.layoutSubtreeIfNeeded()
        return view
    }

    @Test func arrowsMoveSelection() async {
        let source = FakeHomeSource()
        let view = await shown(source, BrowserFixtures.files(50))
        #expect(view.selectedID == view.entries[0].id)
        #expect(view.handleKey(key(124)))
        #expect(view.selectedID == view.entries[1].id)
        #expect(view.handleKey(key(125)))
        #expect(view.selectedID == view.entries[1 + view.columns].id)
        #expect(view.handleKey(key(126)))
        #expect(view.handleKey(key(123)))
        #expect(view.selectedID == view.entries[0].id)
        #expect(view.handleKey(key(123)))   // at the first card: stays
        #expect(view.selectedID == view.entries[0].id)
    }

    /// A photo whose picture cannot be made keeps its card, faint, but the arrow keys go past it (and Return on it opens).
    @Test func arrowsGoPastPhotosThatCannotBeShown() async {
        let source = FakeHomeSource()
        let view = await shown(source, BrowserFixtures.files(6))
        view.setUnavailable(true, for: view.entries[1].id)
        view.setUnavailable(true, for: view.entries[2].id)
        #expect(view.card(for: view.entries[1].id)?.item.isDimmed == true)
        #expect(view.handleKey(key(124)))
        #expect(view.selectedID == view.entries[3].id)
        #expect(view.handleKey(key(123)))
        #expect(view.selectedID == view.entries[0].id)
        view.setUnavailable(false, for: view.entries[1].id)
        #expect(view.card(for: view.entries[1].id)?.item.isDimmed == false)
        #expect(view.handleKey(key(124)))
        #expect(view.selectedID == view.entries[1].id)
        // Every one beyond is unavailable: the selection stays.
        for entry in view.entries[2...] { view.setUnavailable(true, for: entry.id) }
        #expect(view.handleKey(key(124)))
        #expect(view.selectedID == view.entries[1].id)
    }

    @Test func returnOnFolderEnters() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.folder("sub"), BrowserFixtures.file("a.jpg")])
        #expect(view.handleKey(key(36)))
        #expect(view.location == .folder(x.appendingPathComponent("sub")))
        #expect(source.listed.last == x.appendingPathComponent("sub"))
    }

    @Test func returnOnFileCallsOpen() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.file("a.jpg")])
        #expect(view.handleKey(key(36)))
        #expect(source.opened.last?.0.name == "a.jpg")
        #expect(source.opened.last?.1 == .open)
    }

    @Test func commandReturnNewTab() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.file("a.jpg")])
        #expect(view.handleKey(key(36, "\r", [.command])))
        #expect(source.opened.last?.1 == .openNewTab)
    }

    @Test func shiftReturnNewWindow() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.folder("sub")])
        #expect(view.handleKey(key(36, "\r", [.shift])))
        #expect(source.opened.last?.1 == .openNewWindow)   // a folder in a new window opens in the app
        #expect(view.location == .folder(x))
    }

    @Test func commandDownOpens() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.folder("sub")])
        #expect(view.handleKey(key(125, "", [.command])))
        #expect(view.location == .folder(x.appendingPathComponent("sub")))
    }

    @Test func commandUpSelectsFolderLeft() async {
        let source = FakeHomeSource()
        let y = x.appendingPathComponent("y")
        let view = await shown(source, [BrowserFixtures.file("a.jpg", in: y.path)], at: y)
        #expect(view.handleKey(key(126, "", [.command])))
        #expect(view.location == .folder(x))
        source.yield(x, [BrowserFixtures.folder("a"), BrowserFixtures.folder("y")])
        await settle { !view.entries.isEmpty }
        #expect(view.selectedID == y.path)
    }

    @Test func backForwardRestoreScroll() async {
        let source = FakeHomeSource()
        let view = await shown(source, BrowserFixtures.files(2000))
        view.scrollGrid(to: 3000)
        view.select(id: view.entries[700].id, scrolls: false)
        let b = URL(fileURLWithPath: "/Volumes/T/b")
        view.show(.folder(b), selecting: nil)
        #expect(view.handleKey(key(33, "[", [.command])))
        #expect(view.location == .folder(x))
        source.yield(x, BrowserFixtures.files(2000))
        await settle { !view.entries.isEmpty }
        view.layoutSubtreeIfNeeded()
        #expect(view.scrollOffset == 3000)
        #expect(view.selectedID == view.entries[700].id)
        #expect(view.handleKey(key(30, "]", [.command])))
        #expect(view.location == .folder(b))
    }

    @Test func typingSelectsByPrefix() async {
        let source = FakeHomeSource()
        let view = await shown(source, ["a.jpg", "img.jpg", "zz.jpg"].map { BrowserFixtures.file($0) })
        #expect(view.handleKey(key(34, "i")))
        #expect(view.selectedID == view.entries[1].id)
        #expect(view.handleKey(key(6, "z")))   // "iz" matches nothing: stays
        #expect(view.selectedID == view.entries[1].id)
    }

    @Test func rightClickMenuFromSource() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.file("a.jpg")])
        let card = view.card(for: view.entries[0].id)!
        #expect(card.item.menu.map(\.title) == ["Show in Finder"])
        card.onMenu?("reveal")
        #expect(source.performed.first?.0 == "reveal")
        #expect(source.performed.first?.1 == view.entries[0].id)
    }

    @Test func hoverSelectsWithoutScroll() async {
        let source = FakeHomeSource()
        let view = await shown(source, BrowserFixtures.files(5))
        view.card(for: view.entries[3].id)!.onHover?()
        #expect(view.selectedID == view.entries[3].id)
    }

    @Test func singleClickSelectsAndDoubleClickOpens() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.file("a.jpg"), BrowserFixtures.folder("sub")])
        let folderID = view.entries.first { $0.name == "sub" }!.id
        view.card(for: folderID)!.onClick?(false, [], 1)
        #expect(view.selectedID == folderID)
        #expect(view.location == .folder(x))
        view.card(for: folderID)!.onClick?(false, [], 2)
        #expect(view.location == .folder(x.appendingPathComponent("sub")))
    }

    @Test func modifiedAndMiddleClicksKeepOpeningNewTabs() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.file("a.jpg"), BrowserFixtures.folder("sub")])
        let fileID = view.entries.first { $0.name == "a.jpg" }!.id
        view.card(for: view.entries.first { $0.name == "sub" }!.id)!.onClick?(true, [], 1)
        #expect(source.opened.last?.1 == .openNewTab)
        view.card(for: fileID)!.onClick?(false, [.command], 1)
        #expect(source.opened.last?.0.name == "a.jpg")
        #expect(source.opened.last?.1 == .openNewTab)
    }

    @Test func resizeKeysCallOnResize() async {
        let source = FakeHomeSource()
        let view = await shown(source, BrowserFixtures.files(3))
        var steps: [HomeResize] = []
        view.onResize = { steps.append($0) }
        #expect(view.handleKey(key(24, "=", [.command])))
        #expect(view.handleKey(key(27, "-", [.command])))
        #expect(view.handleKey(key(29, "0", [.command])))
        #expect(steps == [.largerSize, .smallerSize, .reset])
    }

    @Test func otherKeysAreNotTaken() async {
        let source = FakeHomeSource()
        let view = await shown(source, BrowserFixtures.files(3))
        #expect(!view.handleKey(key(53, "\u{1b}")))   // Esc
        #expect(!view.handleKey(key(13, "w", [.command])))
    }

    func sized(_ view: HomeBrowserView, width: CGFloat, cardSize: CGFloat) {
        view.frame.size.width = width
        view.cardSize = cardSize
        view.layoutSubtreeIfNeeded()
    }

    @Test func columnStepTargets() async {
        let source = FakeHomeSource()
        let view = await shown(source, BrowserFixtures.files(100))
        sized(view, width: 1400, cardSize: 260)
        #expect(view.columns == 5)
        let larger = view.cardSize(after: .larger, range: 140...480)!
        let smaller = view.cardSize(after: .smaller, range: 140...480)!
        #expect(view.cardSize(after: .reset, range: 140...480) == nil)
        view.cardSize = larger
        #expect(view.columns == 4)
        view.cardSize = smaller
        #expect(view.columns == 6)
    }

    @Test func columnStepClamps() async {
        let source = FakeHomeSource()
        let view = await shown(source, BrowserFixtures.files(100))
        sized(view, width: 1400, cardSize: 140)
        #expect(view.cardSize(after: .smaller, range: 140...480) == 140)
        sized(view, width: 500, cardSize: 480)
        #expect(view.columns == 1)
        #expect(view.cardSize(after: .larger, range: 140...480) == 480)
        sized(view, width: 500, cardSize: 200)
        #expect((140...480).contains(view.cardSize(after: .smaller, range: 140...480)!))
    }

    @Test func optionDigitsSortAndReverse() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.file("a.jpg", date: 1), BrowserFixtures.file("b.jpg", date: 2)])
        #expect(view.handleKey(key(19, "2", [.option])))
        #expect(view.entries.map(\.name) == ["b.jpg", "a.jpg"])
        #expect(view.handleKey(key(19, "2", [.option])))
        #expect(view.entries.map(\.name) == ["a.jpg", "b.jpg"])
        #expect(source.setSorts.map(\.0) == [BrowserSort(text: "date-desc"), BrowserSort(text: "date")])
        #expect(view.handleKey(key(20, "3", [.option])))
        #expect(view.handleKey(key(18, "1", [.option])))
        #expect(source.setSorts.map(\.0).suffix(2) == [BrowserSort(text: "size-desc"), BrowserSort(text: "name")])
        #expect(!view.handleKey(key(19, "2", [.option, .shift])))
    }

    @Test func optionCommandDigitsSwitchStyle() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.folder("a"), BrowserFixtures.file("a.jpg", date: 1)])
        #expect(view.handleKey(key(19, "2", [.option, .command])))
        #expect(view.handleKey(key(20, "3", [.option, .command])))
        #expect(view.handleKey(key(18, "1", [.option, .command])))
        #expect(source.setCardStyles.map(\.0) == [.cards, .list, .posters])
        #expect(view.toolbar.cardSwitchSelection == 0)
        // ⌘ digits are the app's (a window's tabs by number); ⌥1 is still the sort; ⇧⌥⌘ digits and ⌃⌘ digits are not the switch
        #expect(!view.handleKey(key(19, "2", [.command])))
        #expect(!view.handleKey(key(18, "1", [.command])))
        #expect(view.handleKey(key(18, "1", [.option])))
        #expect(source.setSorts.count == 1)
        #expect(!view.handleKey(key(19, "2", [.option, .command, .shift])))
        #expect(!view.handleKey(key(19, "2", [.control, .command])))
        #expect(source.setCardStyles.count == 3)
    }

    @Test func optionTFlipsStyle() async {
        let view = await shown(FakeHomeSource(), BrowserFixtures.files(3))
        var asked: [GridStyle] = []
        view.onStyle = { asked.append($0) }
        view.style = .aspect
        #expect(view.handleKey(key(17, "t", [.option])))
        view.style = .square
        #expect(view.handleKey(key(17, "t", [.option])))
        #expect(asked == [.square, .aspect])
    }

    @Test func optionNCyclesNames() async {
        let view = await shown(FakeHomeSource(), BrowserFixtures.files(3))
        var asked: [GridNames] = []
        view.onNames = { asked.append($0); view.names = $0 }
        for _ in 0..<4 { #expect(view.handleKey(key(45, "n", [.option]))) }
        #expect(asked == [.photo, .below, .auto, .off])
    }

    @Test func commandFFocusesField() async {
        let view = await shown(FakeHomeSource(), BrowserFixtures.files(3))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1200, height: 800), styleMask: [.titled],
                              backing: .buffered, defer: true)
        window.contentView = view
        window.isReleasedWhenClosed = false
        window.toolbar = view.nsToolbar   // the field is the toolbar's
        window.orderFront(nil)
        defer { window.close() }
        await settle { view.toolbar.searchField.window != nil }   // the toolbar puts its items in the window a turn later
        #expect(view.handleKey(key(3, "f", [.command])))
        await settle { view.toolbar.searchField.currentEditor() != nil }
        #expect(view.toolbar.searchField.currentEditor() != nil)
    }

    @Test func optionKeysNeverTypeSelect() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.file("a.jpg"), BrowserFixtures.file("b.jpg")])
        #expect(view.selectedID == view.entries[0].id)
        #expect(!view.handleKey(key(11, "b", [.option])))
        #expect(!view.handleKey(key(23, "5", [.option])))
        #expect(view.selectedID == view.entries[0].id)
        #expect(view.handleKey(key(11, "b")))
        #expect(view.selectedID == view.entries[1].id)
    }
}

@MainActor @Suite struct HomeBrowserRoutingTests {
    let x = URL(fileURLWithPath: "/Volumes/T/x")

    func mouse(_ type: NSEvent.EventType, button: Int) -> NSEvent {
        let cg = CGEvent(mouseEventSource: nil, mouseType: type == .otherMouseDown ? .otherMouseDown : .otherMouseUp,
                         mouseCursorPosition: .zero, mouseButton: CGMouseButton(rawValue: UInt32(button))!)!
        cg.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
        return NSEvent(cgEvent: cg)!
    }

    @Test func commandKeysBeforeTheMenuOnlyWhenFocused() {
        let source = FakeHomeSource()
        let view = HomeBrowserView(source: source)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled],
                              backing: .buffered, defer: true)
        window.contentView = view
        view.show(.places, selecting: nil)
        view.show(.folder(x), selecting: nil)
        let back = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
                                    windowNumber: 0, context: nil, characters: "[", charactersIgnoringModifiers: "[",
                                    isARepeat: false, keyCode: 33)!
        window.makeFirstResponder(nil)
        #expect(!view.performKeyEquivalent(with: back))
        #expect(view.location == .folder(x))
        window.makeFirstResponder(view)
        #expect(view.performKeyEquivalent(with: back))
        #expect(view.location == .places)
    }

    @Test func sideButtonsGoBackAndForward() {
        let source = FakeHomeSource()
        let view = HomeBrowserView(source: source)
        view.show(.places, selecting: nil)
        view.show(.folder(x), selecting: nil)
        view.otherMouseUp(with: mouse(.otherMouseUp, button: 3))
        #expect(view.location == .places)
        view.otherMouseUp(with: mouse(.otherMouseUp, button: 4))
        #expect(view.location == .folder(x))
    }

    @Test func sideButtonsToTheAppWhenItTakesThem() {
        let source = FakeHomeSource()
        let view = HomeBrowserView(source: source)
        var seen: [(Int, Bool)] = []
        view.onOtherMouse = { event, down in seen.append((event.buttonNumber, down)); return true }
        view.show(.places, selecting: nil)
        view.show(.folder(x), selecting: nil)
        view.otherMouseDown(with: mouse(.otherMouseDown, button: 3))
        view.otherMouseUp(with: mouse(.otherMouseUp, button: 3))
        #expect(seen.map(\.0) == [3, 3] && seen.map(\.1) == [true, false])
        #expect(view.location == .folder(x))
    }
}

final class SideButtonCatcher: NSView {
    var ups: [Int] = []
    override func otherMouseUp(with event: NSEvent) { ups.append(event.buttonNumber) }
}
