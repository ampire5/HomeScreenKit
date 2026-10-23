import AppKit
import Testing
@testable import HomeScreenKit

/// A session's tab comes back scrolled as it was: the first fully visible card and its offset (`anchor`), restored by
/// `show(_:selecting:anchor:)` once the listing has it.
@MainActor @Suite struct HomeBrowserAnchorTests {
    let x = URL(fileURLWithPath: "/Volumes/T/x")

    func make(_ source: FakeHomeSource, selecting: String? = nil, anchor: BrowserAnchor? = nil) -> HomeBrowserView {
        let view = HomeBrowserView(source: source)
        view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        view.show(.folder(x), selecting: selecting, anchor: anchor)
        view.layoutSubtreeIfNeeded()
        return view
    }

    /// An anchor taken from a grid scrolled into a long folder.
    func taken() async -> BrowserAnchor? {
        let source = FakeHomeSource()
        let view = make(source)
        source.yield(x, BrowserFixtures.files(2000))
        await settle(seconds: 5) { !view.entries.isEmpty }
        view.layoutSubtreeIfNeeded()
        #expect(view.anchor == nil)                        // at the top: none
        view.scrollGrid(to: 1000)
        return view.anchor
    }

    @Test func anchorIsTheFirstFullyVisibleCard() async throws {
        let source = FakeHomeSource()
        let view = make(source)
        source.yield(x, BrowserFixtures.files(2000))
        await settle(seconds: 5) { !view.entries.isEmpty }
        view.layoutSubtreeIfNeeded()
        view.scrollGrid(to: 1000)
        let anchor = try #require(view.anchor)
        let i = try #require(view.entries.firstIndex { $0.id == anchor.id })
        #expect(anchor.index == i)
        #expect(anchor.offset >= 0)
        #expect(view.grid.frame(of: i).minY - 1000 == CGFloat(anchor.offset))
        #expect(view.grid.frame(of: i - 1).minY < 1000 || view.grid.frame(of: i - 1).minY == view.grid.frame(of: i).minY)
    }

    @Test func entryPresentComesBackAtTheSameOffset() async throws {
        let anchor = try #require(await taken())
        let source = FakeHomeSource()
        let selected = BrowserFixtures.files(2000)[3].id
        let view = make(source, selecting: selected, anchor: anchor)
        source.yield(x, BrowserFixtures.files(2000))
        await settle(seconds: 5) { !view.entries.isEmpty }
        #expect(view.anchor == anchor)
        #expect(view.selectedID == selected)              // selected, without scrolling to it
    }

    @Test func entryGoneTakesTheNearest() async throws {
        let anchor = try #require(await taken())
        let source = FakeHomeSource()
        let view = make(source, anchor: anchor)
        source.yield(x, BrowserFixtures.files(2000).filter { $0.id != anchor.id })
        await settle(seconds: 5) { !view.entries.isEmpty }
        #expect(view.anchor?.id == view.entries[anchor.index].id)
        #expect(view.scrollOffset > 0)
    }

    @Test func emptyStaysAtTheTop() async throws {
        let anchor = try #require(await taken())
        let source = FakeHomeSource()
        let view = make(source, anchor: anchor)
        source.yield(x, [])
        try? await Task.sleep(for: .milliseconds(50))
        #expect(view.scrollOffset == 0)
        source.yield(x, BrowserFixtures.files(2000))       // a later listing does not jump to the old anchor
        await settle(seconds: 5) { !view.entries.isEmpty }
        #expect(view.scrollOffset == 0)
    }

    @Test func namesStillComingWaitForTheAnchor() async throws {
        let anchor = try #require(await taken())
        let source = FakeHomeSource()
        let view = make(source, anchor: anchor)
        source.yieldPartial(x, Array(BrowserFixtures.files(2000).prefix(5)))
        await settle(seconds: 5) { !view.entries.isEmpty }
        #expect(view.scrollOffset == 0)                    // not there yet, more names follow: no jump
        source.yield(x, BrowserFixtures.files(2000))
        await settle(seconds: 5) { view.entries.count == 2000 }
        #expect(view.anchor == anchor)
    }
}
