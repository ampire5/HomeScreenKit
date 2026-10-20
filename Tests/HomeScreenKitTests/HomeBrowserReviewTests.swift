import AppKit
import Testing
@testable import HomeScreenKit

/// The final review's findings, each pinned.
@MainActor @Suite struct HomeBrowserReviewTests {
    let x = URL(fileURLWithPath: "/Volumes/T/x")

    func key(_ code: UInt16, _ chars: String = "", _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false,
                         keyCode: code)!
    }

    func shown(_ source: FakeHomeSource, _ entries: [BrowserEntry], complete: Bool = true) async -> HomeBrowserView {
        let view = HomeBrowserView(source: source)
        view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        view.show(.folder(x), selecting: nil)
        view.layoutSubtreeIfNeeded()
        source.yield(x, entries, complete: complete)
        await settle { !view.entries.isEmpty }
        view.layoutSubtreeIfNeeded()
        return view
    }

    @Test func countsReachLiveCards() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.folder("a")], complete: false)
        var counted = BrowserFixtures.folder("a")
        counted.count = 3
        source.yield(x, [counted])
        await settle { view.card(for: counted.id)?.item.subtitle == "3 photos" }
        #expect(view.card(for: counted.id)?.item.subtitle == "3 photos")
    }

    @Test func dateSubtitleAfterSortChange() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.file("a.jpg", date: 1), BrowserFixtures.file("b.jpg", date: 2)])
        #expect(view.card(for: view.entries[0].id)?.item.subtitle == nil)
        view.toolbar.clickSort(1)
        #expect(view.card(for: view.entries[0].id)?.item.subtitle != nil)
    }

    @Test func namesAfterCompleteAreIgnored() async {
        let source = FakeHomeSource()
        source.sorts[x.path] = BrowserSort(text: "date-desc")
        let view = await shown(source, [BrowserFixtures.file("a.jpg", date: 1), BrowserFixtures.file("b.jpg", date: 2)])
        #expect(view.entries.map(\.name) == ["b.jpg", "a.jpg"])
        source.yield(x, [BrowserFixtures.file("a.jpg"), BrowserFixtures.file("b.jpg")], complete: false)
        await settle()
        #expect(view.entries.map(\.name) == ["b.jpg", "a.jpg"])
        #expect(view.entries.allSatisfy { $0.date != nil })
    }

    @Test func shiftedCommandBracketsAreTheMenus() async {
        let source = FakeHomeSource()
        let view = HomeBrowserView(source: source)
        view.show(.places, selecting: nil)
        view.show(.folder(x), selecting: nil)
        #expect(!view.handleKey(key(33, "{", [.command, .shift])))
        #expect(!view.handleKey(key(30, "}", [.command, .shift])))
        #expect(!view.handleKey(key(126, "", [.command, .option])))
        #expect(view.location == .folder(x))
    }

    @Test func stopEndsTheListing() async {
        let source = FakeHomeSource()
        let view = HomeBrowserView(source: source)
        view.show(.folder(x), selecting: nil)
        view.stop()
        await settle { source.terminated.contains(x) }
        #expect(source.terminated.contains(x))
    }

    @Test func renamedCardAsksForItsPicture() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.file("a.jpg")])
        view.beginRename()
        view.renameField?.stringValue = "b.jpg"
        view.renameField?.onCommit?()
        await settle { view.renameField == nil }
        view.layoutSubtreeIfNeeded()
        #expect(source.wanted.last?.contains("/Volumes/T/x/b.jpg") == true)
    }
}
