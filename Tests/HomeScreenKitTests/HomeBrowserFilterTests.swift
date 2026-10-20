import AppKit
import Testing
@testable import HomeScreenKit
@testable import HomeScreenModel

/// The kind capsule and the name field in the browser.
@MainActor @Suite struct HomeBrowserFilterTests {
    let x = URL(fileURLWithPath: "/Volumes/T/x")
    let y = URL(fileURLWithPath: "/Volumes/T/x/f0")

    func shown(_ source: FakeHomeSource, _ entries: [BrowserEntry]) async -> HomeBrowserView {
        let view = HomeBrowserView(source: source)
        view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        view.show(.folder(x), selecting: nil)
        source.yield(x, entries)
        await settle(seconds: 5) { view.entries.count == entries.count }
        view.layoutSubtreeIfNeeded()
        return view
    }

    private var mixed: [BrowserEntry] { (0..<3).map { BrowserFixtures.folder("f\($0)") } + BrowserFixtures.files(20) }

    private func type(_ text: String, in view: HomeBrowserView) {
        view.toolbar.field.stringValue = text
        view.toolbar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: view.toolbar.field))
    }

    @Test func kindFilterKeepsSelection() async {
        let view = await shown(FakeHomeSource(), mixed)
        view.select(id: view.entries[5].id)
        let selected = view.selectedID
        view.toolbar.clickKind(2)   // Photos
        await settle { view.entries.count == 20 }
        #expect(view.entries.allSatisfy { !$0.isContainer })
        #expect(view.selectedID == selected)
        view.toolbar.clickKind(1)   // Folders
        await settle { view.entries.count == 3 }
        #expect(view.selectedID == view.entries.last?.id)   // the nearest still shown
    }

    @Test func kindFilterResetOnMove() async {
        let source = FakeHomeSource()
        let view = await shown(source, mixed)
        view.toolbar.clickKind(2)
        await settle { view.entries.count == 20 }
        view.show(.folder(y), selecting: nil)
        #expect(view.filter.kind == .all)
        view.show(.places, selecting: nil)
        #expect(!view.toolbar.isFilterVisible)
    }

    @Test func nameFilterNarrows() async {
        let view = await shown(FakeHomeSource(), mixed)
        type("img1", in: view)
        await settle { view.entries.count == 11 }   // img1, img10…img19
        #expect(view.entries.allSatisfy { $0.name.hasPrefix("img1") })
        #expect(view.footerLines.last == "Filter: 11 of 23")
    }

    @Test func nameFilterClearedOnMove() async {
        let view = await shown(FakeHomeSource(), mixed)
        type("img1", in: view)
        await settle { view.entries.count == 11 }
        view.show(.folder(y), selecting: nil)
        #expect(view.filter.text.isEmpty)
        #expect(view.toolbar.filterText.isEmpty)
    }

    @Test func escapeClearsAndReturnsKeys() async {
        let view = await shown(FakeHomeSource(), mixed)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1200, height: 800), styleMask: [.titled],
                              backing: .buffered, defer: true)
        window.contentView = view
        view.toolbar.focusFilter()
        type("img1", in: view)
        await settle { view.entries.count == 11 }
        _ = view.toolbar.control(view.toolbar.field, textView: NSTextView(),
                                 doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        await settle { view.entries.count == 23 }
        #expect(view.entries.count == 23)
        #expect(window.firstResponder === view)
    }

    @Test func filterFollowsStreamingNames() async {
        let source = FakeHomeSource()
        let view = HomeBrowserView(source: source)
        view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        view.show(.folder(x), selecting: nil)
        let names = (0..<300).map { BrowserEntry(url: x.appendingPathComponent("img\($0).jpg"), name: "img\($0).jpg", kind: .file) }
        source.yieldPartial(x, Array(names.prefix(100)))
        await settle { view.entries.count == 100 }
        type("7", in: view)
        let first = names.prefix(100).filter { $0.name.contains("7") }.count
        await settle { view.entries.count == first }
        #expect(view.entries.count == first)
        view.select(id: view.entries[2].id)
        let selected = view.selectedID
        source.yieldPartial(x, names)
        let all = names.filter { $0.name.contains("7") }.count
        await settle { view.entries.count == all }
        #expect(view.entries.count == all)
        #expect(view.selectedID == selected)
        #expect(view.footerLines.last == "Listing is slow — 300 so far")
        source.yield(x, BrowserFixtures.files(300))
        await settle { view.footerLines.last?.hasPrefix("Filter:") == true }
        #expect(view.footerLines.last == "Filter: \(all) of 300")
    }

    @Test func typingCancelsPreviousFilter() async {
        let source = FakeHomeSource()
        let view = await shown(source, BrowserFixtures.files(50_000))
        type("1", in: view)
        type("12", in: view)
        await settle(seconds: 10) { view.entries.count < 50_000 && view.entries.allSatisfy { $0.name.contains("12") } }
        try? await Task.sleep(for: .milliseconds(500))
        #expect(!view.entries.isEmpty)
        #expect(view.entries.allSatisfy { $0.name.contains("12") })
    }
}
