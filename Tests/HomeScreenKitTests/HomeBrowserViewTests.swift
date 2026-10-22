import AppKit
import Testing
@testable import HomeScreenKit

@MainActor @Suite struct HomeBrowserViewTests {
    let x = URL(fileURLWithPath: "/Volumes/T/x")

    func make(_ source: FakeHomeSource, at location: BrowserLocation? = nil) -> HomeBrowserView {
        let view = HomeBrowserView(source: source)
        view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        view.show(location ?? .folder(x), selecting: nil)
        view.layoutSubtreeIfNeeded()
        return view
    }

    func shown(_ source: FakeHomeSource, _ entries: [BrowserEntry], complete: Bool = true) async -> HomeBrowserView {
        let view = make(source)
        source.yield(x, entries, complete: complete)
        await settle(seconds: 5) { !view.entries.isEmpty }
        view.layoutSubtreeIfNeeded()
        return view
    }

    @Test func poolStaysBounded() async {
        let source = FakeHomeSource()
        let view = await shown(source, BrowserFixtures.files(10_000))
        #expect(view.entries.count == 10_000)
        let live = view.liveCardCount
        #expect(live > 0 && live <= 80)
        view.scrollGrid(to: view.gridContentHeight)
        #expect(view.liveCardCount <= 80)
        #expect(view.liveIDs.contains(view.entries.last!.id))
    }

    @Test func staleListingIsDropped() async {
        let source = FakeHomeSource()
        let view = make(source)
        let b = URL(fileURLWithPath: "/Volumes/T/b")
        view.show(.folder(b), selecting: nil)
        source.yield(x, BrowserFixtures.files(3))
        source.yield(b, [BrowserFixtures.file("b.jpg", in: b.path)])
        await settle { !view.entries.isEmpty && source.terminated.contains(x) }
        #expect(view.entries.map(\.name) == ["b.jpg"])
        #expect(source.terminated.contains(x))
    }

    @Test func namesFirstThenComplete() async {
        let source = FakeHomeSource()
        let names = ["b.jpg", "a.jpg"].map { BrowserFixtures.file($0) }
        let view = await shown(source, names, complete: false)
        #expect(view.entries.map(\.name) == ["a.jpg", "b.jpg"])

        source.sorts[x.path] = BrowserSort(text: "date-desc")
        let waiting = make(source)
        source.yield(x, names, complete: false)
        await settle()
        #expect(waiting.entries.isEmpty)
        source.yield(x, [BrowserFixtures.file("a.jpg", date: 1), BrowserFixtures.file("b.jpg", date: 2)])
        await settle { !waiting.entries.isEmpty }
        #expect(waiting.entries.map(\.name) == ["b.jpg", "a.jpg"])
    }

    @Test func loadingShownAfterDelay() async throws {
        let source = FakeHomeSource()
        let view = make(source)
        #expect(view.toolbar.subtitleText != "Loading…")
        try await Task.sleep(for: .milliseconds(300))
        for _ in 0..<40 where view.toolbar.subtitleText != "Loading…" { try await Task.sleep(for: .milliseconds(50)) }
        #expect(view.toolbar.subtitleText == "Loading…")
        source.yield(x, BrowserFixtures.files(2))
        await settle { !view.entries.isEmpty }
        #expect(view.footerLines.first?.hasPrefix("2 ") == true)
        #expect(view.toolbar.subtitleText.hasPrefix(view.entries[0].name))   // the selected card
    }

    @Test func crumbsForNestedFolder() async {
        let source = FakeHomeSource()
        let view = make(source, at: .folder(URL(fileURLWithPath: "/Volumes/T/x/y")))
        #expect(view.toolbar.crumbTitles == ["Places", "T", "x", "y"])
        view.toolbar.clickCrumb(2)
        #expect(view.location == .folder(x))
        view.toolbar.clickCrumb(0)
        #expect(view.location == .places)
    }

    private var nested: URL { URL(fileURLWithPath: "/Volumes/T/x/b") }
    private var siblings: [BrowserEntry] {
        ["c", "a", "b"].map { BrowserFixtures.folder($0) }
    }

    @Test func siblingMenuListsParentFolders() async {
        let source = FakeHomeSource()
        source.folderReplies[x.path] = siblings
        let view = make(source, at: .folder(nested))
        view.toolbar.popUp = { _, _ in }
        view.toolbar.clickSiblings(3)   // the › before "b": the folders in x
        await settle { view.toolbar.siblingTitles == ["a", "b", "c"] }
        #expect(view.toolbar.siblingTitles == ["a", "b", "c"])
        #expect(view.toolbar.siblingChecked == [false, true, false])
        #expect(source.foldersAsked.map(\.standardizedFileURL.path) == [x.path])
        view.toolbar.chooseSibling(2)
        #expect(view.location == .folder(x.appendingPathComponent("c")))
    }

    @Test func siblingReplyAfterMoveDropped() async {
        let source = FakeHomeSource()
        source.holdsFolders = true
        let view = make(source, at: .folder(nested))
        view.toolbar.popUp = { _, _ in }
        view.toolbar.clickSiblings(3)
        await settle { !source.foldersAsked.isEmpty }
        view.show(.places, selecting: nil)
        source.answerFolders(siblings)
        await settle()
        #expect(view.toolbar.siblingTitles != ["a", "b", "c"])
    }

    @Test func siblingMenuOpensBeforeReply() async {
        let source = FakeHomeSource()
        source.holdsFolders = true
        let view = make(source, at: .folder(nested))
        var popped = 0
        view.toolbar.popUp = { _, _ in popped += 1 }
        view.toolbar.clickSiblings(3)
        #expect(popped == 1)
        #expect(view.toolbar.siblingTitles == ["Loading…"])
        await settle { !source.foldersAsked.isEmpty }
        source.answerFolders(siblings)
        await settle { view.toolbar.siblingTitles == ["a", "b", "c"] }
        #expect(view.toolbar.siblingTitles == ["a", "b", "c"])
        view.toolbar.clickSiblings(3)
        await settle { source.foldersAsked.count == 2 }
        view.toolbar.closeSiblings()
        source.answerFolders([BrowserFixtures.folder("z")])
        await settle()
        #expect(view.toolbar.siblingTitles != ["z"])
    }

    @Test func sortChangeCallsSetSort() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.file("a.jpg", date: 1), BrowserFixtures.file("b.jpg", date: 2)])
        view.toolbar.clickSort(1)
        #expect(source.setSorts.first?.0 == BrowserSort(text: "date-desc"))
        #expect(source.setSorts.first?.1 == x)
        #expect(view.entries.map(\.name) == ["b.jpg", "a.jpg"])
    }

    /// A new order moves each card with its entry: no picture goes back to a symbol, none is asked for again.
    @Test func resortKeepsPictures() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.folder("f0"), BrowserFixtures.folder("f1")]
                                       + BrowserFixtures.files(20))   // all live
        let before = view.entries.map(\.id)
        let pictured = view.liveIDs
        #expect(pictured.count == before.count)
        for id in pictured { view.setImage(HomeScreenViewTests.image(), for: id) }
        let asked = source.wanted.count
        view.toolbar.clickSort(1)   // date ↓
        #expect(view.entries.map(\.id) != before)
        #expect(Set(view.liveIDs) == Set(pictured))
        for id in pictured { #expect(view.card(for: id)?.image != nil, "\(id)") }
        #expect(Set(source.wanted.dropFirst(asked).joined()).isDisjoint(with: pictured))
        // Each card in its new slot: in the entries' order, row by row.
        let frames = view.entries.compactMap { view.card(for: $0.id)?.frame }
        #expect(frames.count == before.count)
        #expect(zip(frames, frames.dropFirst()).allSatisfy { $0.minY < $1.minY || ($0.minY == $1.minY && $0.minX < $1.minX) })
    }

    /// A sort by date chosen while only names are listed keeps the grid as it is, in name order, until the dates come.
    @Test func resortToDateBeforeCompleteKeepsGrid() async {
        let source = FakeHomeSource()
        let names = (0..<12).map { BrowserFixtures.file("img\($0).jpg") }   // no dates yet
        let view = await shown(source, names, complete: false)
        let order = view.entries.map(\.id)
        view.toolbar.clickSort(1)   // date ↓: waits for the dates
        await settle()
        #expect(view.toolbar.sortTitles == ["Name", "Date ↓", "Size"])
        #expect(view.entries.map(\.id) == order)
        #expect(!view.liveIDs.isEmpty)
        #expect(Set(view.liveIDs) == Set(order))
        #expect(view.visibleIDs == Array(order.prefix(view.visibleIDs.count)))
        // More names meanwhile join the grid in its old order.
        source.yield(x, names + [BrowserFixtures.file("aaa.jpg")], complete: false)
        await settle { view.entries.count == 13 }
        #expect(view.entries.first?.name == "aaa.jpg")
        source.yield(x, BrowserFixtures.files(12) + [BrowserFixtures.file("aaa.jpg", date: -1)])
        await settle { view.entries.first?.name == "img11.jpg" }
        let dated = (0..<12).reversed().map { "img\($0).jpg" } + ["aaa.jpg"]
        #expect(view.entries.map(\.name) == dated)
        #expect(Set(view.liveIDs) == Set(view.entries.map(\.id)))
        #expect(view.visibleIDs == Array(view.entries.map(\.id).prefix(view.visibleIDs.count)))
    }

    /// The same over a listing ordered off the main actor: the grid stays, then the dates' order comes.
    @Test func bigResortBeforeCompleteKeepsGrid() async {
        let source = FakeHomeSource()
        let count = HomeBrowserView.orderInlineLimit + 500
        let view = await shown(source, (0..<count).map { BrowserFixtures.file("img\($0).jpg") }, complete: false)
        let order = view.entries.map(\.id)
        #expect(order.count == count)
        view.toolbar.clickSort(1)   // date ↓
        await settle()
        #expect(view.entries.map(\.id) == order)
        #expect(!view.liveIDs.isEmpty)
        source.yield(x, BrowserFixtures.files(count))
        await settle(seconds: 10) { view.entries.first?.name == "img\(count - 1).jpg" }
        #expect(isDateOrdered(view.entries, ascending: false))
        #expect(view.visibleIDs == Array(view.entries.map(\.id).prefix(view.visibleIDs.count)))
    }

    @Test func relistKeepsSelectionById() async {
        let source = FakeHomeSource()
        let view = await shown(source, BrowserFixtures.files(5))
        view.select(id: "/Volumes/T/x/img3.jpg")
        source.yield(x, [BrowserFixtures.file("aaa.jpg")] + BrowserFixtures.files(5))
        await settle { view.entries.count == 6 }
        #expect(view.selectedID == "/Volumes/T/x/img3.jpg")
    }

    @Test func wantImagesVisibleFirst() async {
        let source = FakeHomeSource()
        let view = await shown(source, BrowserFixtures.files(200))
        let asked = source.wanted.last ?? []
        let visible = view.visibleIDs
        #expect(!visible.isEmpty)
        #expect(Array(asked.prefix(visible.count)) == visible)
    }

    @Test func wantImagesTellsVisible() async {
        let source = FakeHomeSource()
        let view = await shown(source, BrowserFixtures.files(200))
        await settle { source.visibleCounts.count >= 2 }
        let visible = view.visibleIDs
        #expect(source.visibleCounts.first == visible.count)
        #expect(source.visibleCounts.last == visible.count && (source.wanted.last?.count ?? 0) > visible.count)
        #expect(Array((source.wanted.last ?? []).prefix(visible.count)) == visible)
    }

    @Test func marginAfterScrollStops() async {
        let source = FakeHomeSource()
        let view = await shown(source, BrowserFixtures.files(200))
        await settle { source.wanted.count >= 2 }
        let before = source.wanted.count
        view.scrollGrid(to: 600)
        #expect(source.wanted.count == before + 1)          // the visible ones, at once
        #expect(source.wanted.last?.count == source.visibleCounts.last!)
        try? await Task.sleep(for: .milliseconds(50))       // still scrolling: no margin yet
        #expect(source.wanted.count == before + 1)
        view.scrollGrid(to: 700)
        #expect(source.wanted.count == before + 2)
        let visible = view.visibleIDs.filter { view.card(for: $0)?.image == nil }
        #expect(source.wanted.last == visible)
        await settle { source.wanted.count >= before + 3 }
        try? await Task.sleep(for: .milliseconds(300))
        #expect(source.wanted.count == before + 3)          // exactly one margin send
        let margin = source.wanted.last ?? []
        #expect(Array(margin.prefix(visible.count)) == visible && margin.count > visible.count)
        #expect(source.visibleCounts.last == visible.count)
    }

    @Test func imagesOnlyForLiveCards() async {
        let source = FakeHomeSource()
        let view = await shown(source, BrowserFixtures.files(2000))
        let first = view.entries[0].id, last = view.entries.last!.id
        view.setImage(HomeScreenViewTests.image(), for: first)
        view.setImage(HomeScreenViewTests.image(), for: last)   // not on screen: dropped
        #expect(view.card(for: first)?.image != nil)
        view.scrollGrid(to: view.gridContentHeight)
        #expect(view.card(for: last)?.image == nil)
    }

    @Test func placesListed() async {
        let source = FakeHomeSource()
        source.placesList = [BrowserEntry(url: URL(fileURLWithPath: "/Users/me"), name: "me", kind: .place)]
        let view = make(source, at: .places)
        await settle { !view.entries.isEmpty }
        #expect(view.entries.map(\.name) == ["me"])
        #expect(view.toolbar.crumbTitles == ["Places"])
    }

    @Test func capsuleLitBeforeListing() async {
        let source = FakeHomeSource()
        let view = await shown(source, BrowserFixtures.files(3), complete: false)
        #expect(view.toolbar.sortTitles == ["Name ↑", "Date", "Size"])
        view.toolbar.clickSort(1)
        #expect(view.toolbar.sortTitles == ["Name", "Date ↓", "Size"])
        #expect(view.entries.map(\.name) == ["img0.jpg", "img1.jpg", "img2.jpg"])   // the grid stays until the dates
        #expect(view.toolbar.subtitleText == "Loading…")
    }

    /// 50 000 files whose dates are a shuffle of their numbers: name, date ↓ and date ↑ orders all differ.
    static let shuffled = (0..<50_000).map { BrowserFixtures.file("img\($0).jpg", date: Double($0 * 7919 % 50_000)) }

    func isDateOrdered(_ entries: [BrowserEntry], ascending: Bool) -> Bool {
        zip(entries, entries.dropFirst()).allSatisfy { ascending ? $0.date! < $1.date! : $0.date! > $1.date! }
    }

    @Test func bigFolderOrdersOffMain() async {
        let source = FakeHomeSource()
        let view = await shown(source, Self.shuffled)
        #expect(view.entries.first?.name == "img0.jpg")
        let started = Date()
        view.toolbar.clickSort(1)
        #expect(Date().timeIntervalSince(started) < 0.1)   // the click returns at once
        #expect(view.toolbar.sortTitles[1] == "Date ↓")
        #expect(view.entries.first?.name == "img0.jpg")   // the old order stays until the new one is ready
        await settle(seconds: 10) { view.entries.first?.name != "img0.jpg" }
        #expect(view.entries.count == 50_000)
        #expect(isDateOrdered(view.entries, ascending: false))
    }

    @Test func staleOrderDropped() async throws {
        let source = FakeHomeSource()
        let view = await shown(source, Self.shuffled)
        view.toolbar.clickSort(1)   // date ↓
        view.toolbar.clickSort(1)   // date ↑
        await settle(seconds: 10) { view.entries[1].name != "img1.jpg" }
        try await Task.sleep(for: .milliseconds(500))
        #expect(isDateOrdered(view.entries, ascending: true))
        #expect(source.setSorts.map(\.0) == [BrowserSort(text: "date-desc"), BrowserSort(text: "date")])
    }

    @Test func partsShowWhileLaterOnesOrder() async {
        let source = FakeHomeSource()
        let view = make(source)
        let all = BrowserFixtures.files(50_000)
        source.yield(x, Array(all.prefix(3_000)), complete: false)
        source.yield(x, all, complete: false)
        var seen: Set<Int> = []
        // Up to 30 s, as `settle`: ordering 50 000 entries alongside the other suites on a CI machine took over 10.
        let deadline = Date().addingTimeInterval(30)
        while view.entries.count != 50_000, Date() < deadline {
            seen.insert(view.entries.count)
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(seen.contains(3_000))   // the first part shows, not dropped for the next one
        #expect(view.entries.count == 50_000)
    }
}

