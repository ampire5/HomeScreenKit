import AppKit
import Testing
@testable import HomeScreenKit

@MainActor @Suite struct HomeBrowserRenameTests {
    let x = URL(fileURLWithPath: "/Volumes/T/x")

    func key(_ code: UInt16, _ chars: String = "", _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false,
                         keyCode: code)!
    }

    func shown(_ source: FakeHomeSource, _ entries: [BrowserEntry]) async -> HomeBrowserView {
        let view = HomeBrowserView(source: source)
        view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        view.show(.folder(x), selecting: nil)
        view.layoutSubtreeIfNeeded()
        source.yield(x, entries)
        await settle { !view.entries.isEmpty }
        view.layoutSubtreeIfNeeded()
        return view
    }

    @Test func nameRangeLeavesExtension() {
        #expect(BrowserRenameField.nameRange(for: "IMG_1.jpg", isFile: true) == NSRange(location: 0, length: 5))
        #expect(BrowserRenameField.nameRange(for: "noext", isFile: true) == NSRange(location: 0, length: 5))
        #expect(BrowserRenameField.nameRange(for: "a.b.zip", isFile: false) == NSRange(location: 0, length: 7))
    }

    @Test func f2OpensFieldOnSelected() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.file("IMG_1.jpg")])
        #expect(view.handleKey(key(120)))
        #expect(view.renameField?.stringValue == "IMG_1.jpg")
        #expect(view.renameField?.entryID == view.entries[0].id)
        #expect(view.renameField?.selection == NSRange(location: 0, length: 5))
    }

    @Test func returnCommits() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.file("a.jpg"), BrowserFixtures.file("c.jpg")])
        view.beginRename()
        view.renameField?.stringValue = "d.jpg"
        view.renameField?.onCommit?()
        await settle { view.renameField == nil }
        #expect(source.renamed.first?.1 == "d.jpg")
        #expect(view.entries.map(\.name) == ["c.jpg", "d.jpg"])
        #expect(view.selectedID == "/Volumes/T/x/d.jpg")
    }

    @Test func unchangedNameJustCloses() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.file("a.jpg")])
        view.beginRename()
        view.renameField?.onCommit?()
        await settle { view.renameField == nil }
        #expect(source.renamed.isEmpty)
    }

    @Test func escapeCancels() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.file("a.jpg")])
        view.beginRename()
        view.renameField?.stringValue = "zzz"
        view.renameField?.onCancel?()
        #expect(view.renameField == nil)
        #expect(source.renamed.isEmpty)
        #expect(view.entries.map(\.name) == ["a.jpg"])
    }

    @Test func errorKeepsFieldWithReason() async {
        let source = FakeHomeSource()
        source.renamer = { _, _ in throw CocoaError(.fileWriteFileExists) }
        let view = await shown(source, [BrowserFixtures.file("a.jpg")])
        view.beginRename()
        view.renameField?.stringValue = "b.jpg"
        view.renameField?.onCommit?()
        await settle { view.renameField?.reason != nil }
        #expect(view.renameField?.stringValue == "b.jpg")
        #expect(view.renameField?.reason == CocoaError(.fileWriteFileExists).localizedDescription)
        #expect(view.entries.map(\.name) == ["a.jpg"])
    }

    @Test func disabledWhenCannotRename() async {
        let source = FakeHomeSource()
        var locked = BrowserFixtures.file("a.jpg")
        locked.canRename = false
        let view = await shown(source, [locked])
        #expect(view.handleKey(key(120)))
        #expect(view.renameField == nil)
    }

    @Test func relistKeepsRenameField() async {
        let source = FakeHomeSource()
        let view = await shown(source, BrowserFixtures.files(3))
        view.select(id: view.entries[1].id)
        view.beginRename()
        source.yield(x, [BrowserFixtures.file("aaa.jpg")] + BrowserFixtures.files(3))
        await settle { view.entries.count == 4 }
        view.layoutSubtreeIfNeeded()
        let id = "/Volumes/T/x/img1.jpg"
        #expect(view.renameField?.entryID == id)
        #expect(view.renameField.map { view.card(for: id)!.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) } == true)
    }

    @Test func relistClosesFieldOfVanishedEntry() async {
        let source = FakeHomeSource()
        let view = await shown(source, BrowserFixtures.files(3))
        view.select(id: view.entries[1].id)
        view.beginRename()
        source.yield(x, [BrowserFixtures.file("img0.jpg")])
        await settle { view.entries.count == 1 }
        #expect(view.renameField == nil)
    }

    @Test func trashCallsSourceAndRemoves() async {
        let source = FakeHomeSource()
        let view = await shown(source, BrowserFixtures.files(3))
        view.select(id: view.entries[1].id)
        #expect(view.handleKey(key(51, "\u{7f}", [.command])))
        await settle { view.entries.count == 2 }
        #expect(source.trashed == ["/Volumes/T/x/img1.jpg"])
        #expect(view.selectedID == "/Volumes/T/x/img2.jpg")
    }

    @Test func trashErrorToasts() async {
        let source = FakeHomeSource()
        source.trashError = CocoaError(.fileWriteNoPermission)
        let view = await shown(source, BrowserFixtures.files(2))
        view.trashSelected()
        await settle { view.toastText != nil }
        #expect(view.toastText == CocoaError(.fileWriteNoPermission).localizedDescription)
        #expect(view.entries.count == 2)
    }

    @Test func listErrorShowsMessage() async {
        let source = FakeHomeSource()
        let view = HomeBrowserView(source: source)
        view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        view.show(.places, selecting: nil)
        view.show(.folder(x), selecting: nil)
        source.fail(x, CocoaError(.fileReadNoPermission))
        await settle { view.isShowingMessage }
        #expect(view.messageTexts.contains(x.path))
        #expect(view.messageTexts.contains(CocoaError(.fileReadNoPermission).localizedDescription))
        #expect(view.messageTexts.contains("⌘↑ Up   ·   ⌘[ Back"))
        #expect(view.handleKey(key(33, "[", [.command])))
        #expect(view.location == .places)
        #expect(!view.isShowingMessage)
    }
}

@MainActor @Suite struct HomeBrowserSmallTests {
    @Test func declinedTrashShowsNoToast() async {
        let source = FakeHomeSource()
        source.trashError = CancellationError()
        let x = URL(fileURLWithPath: "/Volumes/T/x")
        let view = HomeBrowserView(source: source)
        view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        view.show(.folder(x), selecting: nil)
        source.yield(x, BrowserFixtures.files(2))
        await settle { !view.entries.isEmpty }
        view.trashSelected()
        await settle()
        #expect(view.toastText == nil)
        #expect(view.entries.count == 2)
    }

    @Test func notchesResize() {
        let view = HomeBrowserView(source: FakeHomeSource())
        var steps: [HomeResize] = []
        view.onResize = { steps.append($0) }
        view.resize(notches: 0.6)
        view.resize(notches: 0.6)
        view.resize(notches: -1.3)
        #expect(steps == [.larger, .smaller])
    }
}
