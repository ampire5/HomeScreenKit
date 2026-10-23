import AppKit
import Testing
@testable import HomeScreenKit

/// Coming back to a folder (from the viewer, Back, a crumb): what is known shows at once, the listing only refines it.
@MainActor @Suite struct HomeBrowserReturnTests {
    let x = URL(fileURLWithPath: "/Volumes/T/x")
    let b = URL(fileURLWithPath: "/Volumes/T/b")

    func make(_ source: FakeHomeSource) -> HomeBrowserView {
        let view = HomeBrowserView(source: source)
        view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        view.show(.folder(x), selecting: nil)
        view.layoutSubtreeIfNeeded()
        return view
    }

    /// The viewer goes back to the folder on screen (Escape on a photo): the cards stay with their pictures, the photo
    /// is selected, and the folder is listed again behind them; a names-only part of that listing changes nothing.
    @Test func showingSameFolderAgainKeepsEntries() async {
        let source = FakeHomeSource()
        let view = make(source)
        source.yield(x, BrowserFixtures.files(30))
        await settle { view.entries.count == 30 }
        view.layoutSubtreeIfNeeded()
        let live = view.liveIDs
        for id in live { view.setImage(HomeScreenViewTests.image(), for: id) }
        let listed = source.listed.count
        let target = view.entries[7].id

        view.show(.folder(x), selecting: target)
        // In the same turn: nothing wiped, nothing waits.
        #expect(view.entries.count == 30)
        #expect(view.selectedID == target)
        #expect(!view.isShowingSkeleton)
        for id in live { #expect(view.card(for: id)?.image != nil, "\(id)") }
        #expect(source.listed.count == listed + 1)   // listed again in the background
        #expect(view.hasCompleteListing)

        source.yieldPartial(x, BrowserFixtures.files(3))
        await settle()
        #expect(view.entries.count == 30)
        #expect(view.selectedID == target)
        source.yield(x, BrowserFixtures.files(31))
        await settle { view.entries.count == 31 }
        #expect(view.selectedID == target)
        for id in live { #expect(view.card(for: id)?.image != nil, "\(id)") }
    }

    /// A folder visited earlier is drawn from the source's kept listing in the same turn, before its stream has
    /// delivered anything; the stream's copy of it changes nothing.
    @Test func revisitedFolderDrawsAtOnce() async {
        let source = FakeHomeSource()
        let view = make(source)
        source.yield(x, BrowserFixtures.files(12))
        await settle { view.entries.count == 12 }
        view.show(.folder(b), selecting: nil)
        source.yield(b, [BrowserFixtures.file("b.jpg", in: b.path)])
        await settle { view.entries.count == 1 }
        source.kept[.folder(x)] = BrowserListing(entries: BrowserFixtures.files(12), complete: true)

        view.goBack()
        #expect(view.location == .folder(x))
        #expect(view.entries.count == 12)
        #expect(view.hasCompleteListing)
        #expect(!view.isShowingSkeleton)
        #expect(!view.liveIDs.isEmpty)
        let asked = source.wanted.count
        source.yield(x, BrowserFixtures.files(12))
        await settle()
        #expect(view.entries.count == 12)
        #expect(source.wanted.count == asked)   // the same listing again: no new ask
    }
}
