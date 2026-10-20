import AppKit
import Testing
@testable import HomeScreenKit
@testable import HomeScreenModel

@MainActor @Suite struct HomeBrowserSourcesTests {
    let x = URL(fileURLWithPath: "/Volumes/T/x")
    let page = NSView()

    func source() -> FakeHomeSource {
        let source = FakeHomeSource()
        source.infos["recent"] = HomeSourceInfo(title: "Recent", sortKeys: [.date, .name], groupsByDate: true, noun: "item",
                                                emptyHint: "Nothing yet")
        source.infos["stash"] = HomeSourceInfo(title: "Stash", page: page, pageFilters: ["Scenes", "Images", "Galleries"])
        return source
    }

    func make(_ source: FakeHomeSource, at location: BrowserLocation) -> HomeBrowserView {
        let view = HomeBrowserView(source: source)
        view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        view.show(location, selecting: nil)
        view.layoutSubtreeIfNeeded()
        return view
    }

    @Test func sourceShowsTitleAndCollections() async {
        let source = source()
        let view = make(source, at: .source("recent"))
        source.yieldSource("recent", ["a", "b", "c"].map { BrowserFixtures.collection($0) })
        await settle { view.entries.count == 3 }
        view.layoutSubtreeIfNeeded()
        #expect(view.toolbar.crumbTitles == ["Recent"])
        #expect(!view.toolbar.isNavVisible)
        #expect(view.toolbar.sortTitles == ["Date ↓", "Name"])
        #expect(!view.toolbar.isFilterVisible)
        #expect(view.liveIDs.allSatisfy { id in view.card(for: id) is CollectionCard })
        #expect(view.liveCardCount == 3)
        #expect(view.footerLines == ["3 items"])
    }

    @Test func recentGroupsByDate() async {
        let source = source()
        let view = make(source, at: .source("recent"))
        let now = Date()
        source.yieldSource("recent", [BrowserFixtures.collection("a", now: now), BrowserFixtures.collection("b", now: now),
                                      BrowserFixtures.collection("c", daysAgo: 40, now: now)])
        await settle { view.entries.count == 3 }
        view.layoutSubtreeIfNeeded()
        #expect(view.headerTitles == ["Today", "Earlier"])
        // ⌥2: the source's second field, Name.
        _ = view.handleKey(keyEvent(code: 19, chars: "2", flags: .option))
        await settle { view.headerTitles.isEmpty }
        view.layoutSubtreeIfNeeded()
        #expect(view.headerTitles.isEmpty)
        #expect(source.setSourceSorts.last?.0.key == .name)
        #expect(source.setSourceSorts.last?.1 == "recent")
    }

    @Test func sourceGoesIntoHistory() async {
        let source = source()
        let view = make(source, at: .folder(x))
        source.yield(x, BrowserFixtures.files(3))
        await settle { view.entries.count == 3 }
        view.select(id: view.entries[2].id)
        view.show(.source("recent"), selecting: nil)
        #expect(view.lastBrowsed == .folder(x))
        view.goBack()
        source.yield(x, BrowserFixtures.files(3))
        await settle { view.entries.count == 3 }
        #expect(view.location == .folder(x))
        #expect(view.selectedID == view.entries[2].id)
        #expect(view.lastBrowsed == .folder(x))
    }

    @Test func pageSourceShowsAppView() async {
        let source = source()
        let view = make(source, at: .source("stash"))
        view.layoutSubtreeIfNeeded()
        #expect(page.superview === view)
        #expect(!page.isHidden)
        #expect(page.frame.maxY <= view.bounds.height - HomeToolbar.height + 0.5)
        #expect(view.isGridHidden)
        #expect(source.listedSources.isEmpty)
        #expect(view.toolbar.kindTitles == ["Scenes", "Images", "Galleries"])
        view.toolbar.clickKind(1)
        #expect(source.pageFiltersChosen.map(\.0) == [1])
        #expect(source.pageFiltersChosen.map(\.1) == ["stash"])
        view.show(.folder(x), selecting: nil)
        #expect(page.isHidden)
        #expect(!view.isGridHidden)
        #expect(view.toolbar.kindTitles == ["All", "Folders", "Photos"])
    }

    @Test func sourceSwitchDropsStaleListing() async {
        let source = source()
        let view = make(source, at: .source("recent"))
        view.show(.source("stash"), selecting: nil)
        source.yieldSource("recent", ["a", "b"].map { BrowserFixtures.collection($0) })
        await settle()
        #expect(view.entries.isEmpty)
        #expect(source.wanted.isEmpty)
    }

    @Test func emptySourceShowsHint() async {
        let source = source()
        let view = make(source, at: .source("recent"))
        source.yieldSource("recent", [])
        await settle { view.hintText != nil }
        #expect(view.hintText == "Nothing yet")
        #expect(!view.isShowingSkeleton)
        source.yieldSource("recent", [BrowserFixtures.collection("a")])
        await settle { !view.entries.isEmpty }
        #expect(view.hintText == nil)
    }

    @Test func reloadKeepsSelection() async {
        let source = source()
        let view = make(source, at: .source("recent"))
        let items = ["a", "b", "c"].map { BrowserFixtures.collection($0) }
        source.yieldSource("recent", items)
        await settle { view.entries.count == 3 }
        view.select(id: view.entries[1].id)
        let selected = view.selectedID
        view.reload()
        source.yieldSource("recent", items)
        await settle { view.entries.count == 3 }
        #expect(view.selectedID == selected)
        #expect(source.listedSources == ["recent", "recent"])
    }

    @Test func collectionClickGoesToSource() async {
        let source = source()
        let view = make(source, at: .source("recent"))
        source.yieldSource("recent", [BrowserFixtures.collection("a")])
        await settle { !view.entries.isEmpty }
        _ = view.handleKey(keyEvent(code: 36, chars: "\r"))
        #expect(source.opened.map(\.0.name) == ["a"])
        #expect(view.location == .source("recent"))
    }

    @Test func listingCompleteIsReported() async {
        let source = source()
        var completed: [BrowserLocation] = []
        let view = make(source, at: .folder(x))
        view.onListingComplete = { completed.append($0) }
        source.yieldPartial(x, BrowserFixtures.files(2))
        await settle()
        #expect(completed.isEmpty)
        source.yield(x, BrowserFixtures.files(2))
        source.yield(x, BrowserFixtures.files(3))
        await settle { view.entries.count == 3 }
        #expect(completed == [.folder(x)])
    }

    /// Pictures asked while only names had come are asked again with the complete listing: the app makes thumbnails
    /// only for files it knows the date and size of.
    @Test func completeListingAsksPicturesAgain() async {
        let source = source()
        let view = make(source, at: .folder(x))
        let names = BrowserFixtures.files(3).map { var e = $0; e.date = nil; e.size = nil; return e }
        source.yield(x, names, complete: false)
        await settle { !source.wanted.isEmpty }
        let asked = source.wanted.count
        source.yield(x, BrowserFixtures.files(3))
        await settle { source.wanted.count > asked }
        #expect(source.wanted.count == asked + 1)
        #expect(Set(source.wanted.last ?? []) == Set(view.entries.map(\.id)))
    }
}
