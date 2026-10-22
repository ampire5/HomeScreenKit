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
        #expect(view.liveIDs.count == view.liveCardCount && Set(view.visibleIDs).isSubset(of: view.liveIDs))
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
        view.marginDelay = .seconds(3600)                   // the margin is sent only by `sendMarginNow`
        let before = source.wanted.count
        view.scrollGrid(to: 600)
        #expect(source.wanted.count == before + 1)          // the visible ones, at once
        #expect(source.wanted.last?.count == source.visibleCounts.last!)
        await Task.yield()                                  // still scrolling: no margin yet
        #expect(source.wanted.count == before + 1)
        view.scrollGrid(to: 700)
        #expect(source.wanted.count == before + 2)
        let visible = view.visibleIDs.filter { view.card(for: $0)?.image == nil }
        #expect(source.wanted.last == visible)
        view.sendMarginNow()
        #expect(source.wanted.count == before + 3)          // exactly one margin send
        view.sendMarginNow()
        #expect(source.wanted.count == before + 3)          // nothing more waits
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


@MainActor @Suite struct HomeBrowserCardsTests {
    let x = URL(fileURLWithPath: "/Volumes/T/x")

    func make(_ source: FakeHomeSource, at location: BrowserLocation? = nil) -> HomeBrowserView {
        let view = HomeBrowserView(source: source)
        view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        view.show(location ?? .folder(x), selecting: nil)
        view.layoutSubtreeIfNeeded()
        return view
    }

    func shown(_ source: FakeHomeSource, _ entries: [BrowserEntry]) async -> HomeBrowserView {
        let view = make(source)
        source.yield(x, entries)
        await settle(seconds: 5) { !view.entries.isEmpty }
        view.layoutSubtreeIfNeeded()
        return view
    }

    private let summary = CardSummary(photos: 248, folders: 3, bytes: 4_200_000_000)

    @Test func summaryArrivesWithoutRelisting() async {
        let source = FakeHomeSource()
        let folders = (0..<3).map { BrowserFixtures.folder("f\($0)") }
        let view = await shown(source, folders)
        let ids = view.entries.map(\.id)
        let id = ids[1]
        let image = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        view.setImage(image, for: id)
        let listed = source.listed.count
        let before = (view.card(for: ids[0]) as? PosterCard)?.insideLabel.stringValue
        view.setSummary(summary, for: id)
        let card = view.card(for: id) as? PosterCard
        #expect(card?.insideLabel.stringValue == "248 photos · 3 folders · 4.2 GB")
        #expect(card?.image != nil)                                       // the picture stays
        #expect(view.entries.map(\.id) == ids)                            // no reorder
        #expect(source.listed.count == listed)                            // no relisting
        #expect((view.card(for: ids[0]) as? PosterCard)?.insideLabel.stringValue == before)   // the others untouched
        // a later listing of the same folder keeps the facts that arrived
        source.yield(x, folders)
        await settle()
        #expect((view.card(for: id) as? PosterCard)?.insideLabel.stringValue == "248 photos · 3 folders · 4.2 GB")
        view.setSummary(nil, for: id)
        (view.card(for: id) as? PosterCard)?.layoutSubtreeIfNeeded()
        #expect((view.card(for: id) as? PosterCard)?.insideLabel.stringValue == "")   // the subtitle again (none here)
    }

    @Test func cardStyleComesFromTheSource() async {
        let source = FakeHomeSource()
        source.cardStyles[.folder(x)] = .cards
        let view = await shown(source, [BrowserFixtures.folder("a"), BrowserFixtures.file("p.jpg")])
        #expect(view.card(for: view.entries[0].id) is CompactCard)
        #expect(view.card(for: view.entries[0].id)!.frame.width >= 300)
        #expect(view.card(for: view.entries[0].id)?.frame.height == 92)
        view.chooseCardStyle(.list)
        #expect(source.setCardStyles.count == 1)
        #expect(source.setCardStyles[0].0 == .list && source.setCardStyles[0].1 == .folder(x))
        view.chooseCardStyle(.posters)
        await settle()
        #expect(view.card(for: view.entries[0].id) is PosterCard)
    }

    /// Compact cards draw their picture in a 76 pt square: that is the width their pictures are asked at (one
    /// picture, not a mosaic made for the whole card), and the cover width the app reads in a folder with photos too.
    @Test func compactCardsAskForTheirSquare() async {
        let source = FakeHomeSource()
        source.cardStyles[.folder(x)] = .cards
        let view = await shown(source, ["a", "b", "c"].map { BrowserFixtures.folder($0) })
        #expect(source.wantedWidths.last == GridMetrics().cardCover)
        #expect(view.slotWidth == 76 && view.coverWidth == 76)
        let mixed = FakeHomeSource()
        mixed.cardStyles[.folder(x)] = .cards
        let both = await shown(mixed, [BrowserFixtures.folder("a"), BrowserFixtures.file("p.jpg")])
        #expect(both.coverWidth == 76)
        #expect(both.slotWidth > 76)   // the photos' cards are asked at their own slot
        let posters = await shown(FakeHomeSource(), [BrowserFixtures.folder("a")])
        #expect(posters.coverWidth == posters.slotWidth && posters.coverWidth > 110)
    }

    @Test func posterIsTheDefaultAndFollowsTheGridsBand() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.folder("a"), BrowserFixtures.folder("z.zip")])
        let card = view.card(for: view.entries[0].id)
        #expect(card is PosterCard)
        #expect(card!.frame.height == card!.frame.width + GridLayout.bandHeight(width: card!.frame.width))
    }

    @Test func narrowColumnKeepsPosters() async {
        let source = FakeHomeSource()
        source.cardStyles[.folder(x)] = .cards
        let view = HomeBrowserView(source: source)
        view.frame = CGRect(x: 0, y: 0, width: 300, height: 800)
        view.show(.folder(x), selecting: nil)
        source.yield(x, [BrowserFixtures.folder("a")])
        await settle(seconds: 5) { !view.entries.isEmpty }
        view.layoutSubtreeIfNeeded()
        #expect(view.card(for: view.entries[0].id) is PosterCard)
    }

    @Test func collectionsStayCollectionCards() async {
        let source = FakeHomeSource()
        source.cardStyles[.source("recent")] = .cards
        let view = make(source, at: .source("recent"))
        source.yieldSource("recent", [BrowserFixtures.collection("a")])
        await settle(seconds: 5) { !view.entries.isEmpty }
        view.layoutSubtreeIfNeeded()
        #expect(view.card(for: view.entries[0].id) is CollectionCard)
    }

    @Test func brokenAndOffline() async {
        let source = FakeHomeSource()
        let view = await shown(source, ["a", "b", "c"].map { BrowserFixtures.folder($0) })
        view.setSummary(CardSummary(photos: 1, problem: .offline), for: view.entries[0].id)
        view.setSummary(CardSummary(photos: 1, problem: .broken), for: view.entries[1].id)
        view.setSummary(CardSummary(photos: 1), for: view.entries[2].id)
        let cards = view.entries.map { view.card(for: $0.id) as? PosterCard }
        // the cover is faint, the band stays readable: the card is not dimmed as a whole
        #expect(cards.map { $0?.alphaValue } == [1, 1, 1])
        #expect(cards.map { $0?.picture.alphaValue } == [0.4, 0.25, 1])
        #expect(cards[0]?.coverAlert.isHidden == false && cards[1]?.coverAlert.isHidden == false)
        #expect(cards[2]?.coverAlert.isHidden == true)
        view.setSummary(CardSummary(photos: 1), for: view.entries[0].id)   // reachable again
        #expect((view.card(for: view.entries[0].id) as? PosterCard)?.picture.alphaValue == 1)
    }
}

@MainActor @Suite struct HomeBrowserListTests {
    let x = URL(fileURLWithPath: "/Volumes/T/x")

    func make(_ source: FakeHomeSource, at location: BrowserLocation? = nil, width: CGFloat = 1200) -> HomeBrowserView {
        let view = HomeBrowserView(source: source)
        view.frame = CGRect(x: 0, y: 0, width: width, height: 800)
        view.show(location ?? .folder(x), selecting: nil)
        view.layoutSubtreeIfNeeded()
        return view
    }

    func shown(_ source: FakeHomeSource, _ entries: [BrowserEntry]) async -> HomeBrowserView {
        source.cardStyles[.folder(x)] = .list
        let view = make(source)
        source.yield(x, entries)
        await settle(seconds: 5) { !view.entries.isEmpty }
        view.layoutSubtreeIfNeeded()
        return view
    }

    private let summary = CardSummary(photos: 248, folders: 3, bytes: 4_200_000_000,
                                      first: Date(timeIntervalSince1970: 1_560_000_000),
                                      last: Date(timeIntervalSince1970: 1_690_000_000),
                                      histogram: [10, 40, 90, 20, 0, 0, 5, 5, 30, 25, 20, 10], viewed: 0.55)

    @Test func listHeaderSorts() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.folder("a"), BrowserFixtures.file("p.jpg", date: 1)])
        let header = view.listHeader
        #expect(header != nil && header?.isHidden == false)
        #expect(header?.titles == ["Name ↑", "Inside", "Dates", "Viewed", "Size"])
        header?.click(.dates)
        #expect(source.setSorts.last?.0 == BrowserSort(text: "date-desc"))
        #expect(header?.titles == ["Name", "Inside", "Dates ↓", "Viewed", "Size"])
        header?.click(.dates)
        #expect(source.setSorts.last?.0 == BrowserSort(text: "date"))
        let count = source.setSorts.count
        header?.click(.inside)
        header?.click(.viewed)
        #expect(source.setSorts.count == count)
        header?.click(.size)
        header?.click(.name)
        #expect(source.setSorts.map(\.0).suffix(2) == [BrowserSort(text: "size-desc"), BrowserSort(text: "name")])
    }

    @Test func listHeaderSitsAboveTheRowsAndAlignsWithThem() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.folder("a")])
        let header = view.listHeader!
        let row = view.card(for: view.entries[0].id) as! ListRow
        #expect(header.frame.maxY <= row.frame.minY)
        #expect(header.frame.width == row.frame.width && header.frame.minX == row.frame.minX && row.frame.minX == 20)
        let columns = ListColumns(width: row.frame.width)
        #expect(header.columns == columns)
        #expect(row.frame.height == 44 && row.pictureFrame == CGRect(x: 12, y: 6, width: 32, height: 32))
        // one container under the header and the rows
        let plate = try! #require(view.listPlate)
        #expect(!plate.isHidden && plate.frame.minY == header.frame.minY && plate.frame.maxY == row.frame.maxY)
        #expect(plate.frame.minX == 20 && plate.frame.width == row.frame.width)
    }

    /// The column heads stay at the top of the visible area while the rows scroll under them, over the rows; the
    /// last row has no separator of its own (the container's edge is there).
    @Test func listHeaderStaysOnTopWhileScrolling() async {
        let source = FakeHomeSource()
        source.cardStyles[.folder(x)] = .list
        let view = await shown(source, (0..<200).map { BrowserFixtures.folder("f\($0)") })
        let header = view.listHeader!
        #expect(header.frame.minY == HomeToolbar.height)
        view.scrollGrid(to: 1000)
        #expect(header.frame.minY == view.scrollOffset + HomeToolbar.height)
        #expect(header.superview?.subviews.last === header)
        view.scrollGrid(to: view.gridContentHeight)
        #expect(header.frame.maxY <= view.listPlate!.frame.maxY)
        let last = view.card(for: view.entries.last!.id) as? ListRow
        #expect(last?.showsSeparator == false)
        #expect((view.card(for: view.entries[view.entries.count - 2].id) as? ListRow)?.showsSeparator == true)
    }

    @Test func listShowsFoldersWithFacts() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.folder("a"), BrowserFixtures.folder("b")])
        view.setSummary(summary, for: view.entries[0].id)
        var done = summary
        done.done = true
        view.setSummary(done, for: view.entries[1].id)
        let a = view.card(for: view.entries[0].id) as! ListRow
        let b = view.card(for: view.entries[1].id) as! ListRow
        a.layoutSubtreeIfNeeded()
        #expect(a.insideLabel.stringValue == "248 + 3 folders")
        #expect(a.yearsLabel.stringValue == "2019–2023" && !a.histogram.isHidden)
        #expect(!a.progressTrack.isHidden && a.progressBar.frame.width == (a.progressTrack.frame.width * 0.55).rounded())
        #expect(a.sizeLabel.stringValue == "4.2 GB")
        #expect(b.progressBar.frame.width == b.progressTrack.frame.width || b.summary?.viewed != 1)
        let shown = [a.nameLabel, a.insideLabel, a.histogram, a.yearsLabel, a.progressTrack, a.sizeLabel]
            .filter { !$0.isHidden }.map(\.frame).sorted { $0.minX < $1.minX }
        for (p, q) in zip(shown, shown.dropFirst()) { #expect(p.maxX <= q.minX) }
        #expect(shown.last!.maxX <= a.bounds.width - 12)
    }

    @Test func listShowsFilesInRows() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.folder("a"), BrowserFixtures.file("img.jpg", date: 700_000_000)])
        let row = view.card(for: view.entries[1].id) as? ListRow
        #expect(row != nil)
        #expect(row?.insideLabel.stringValue == "JPG")
        #expect(row?.yearsLabel.stringValue.isEmpty == false)
        #expect(row?.yearsLabel.stringValue == (view.entries[1].date.map { ListRow.dateText($0) }))
        #expect(row?.sizeLabel.stringValue == "1 B")
        #expect(row?.histogram.isHidden == true)
        #expect(row?.frame.height == 44)
        #expect(view.card(for: view.entries[0].id) is ListRow)
    }

    @Test func listRowsReusedWhileScrolling() async {
        let source = FakeHomeSource()
        let view = await shown(source, BrowserFixtures.files(10_000))
        #expect(view.liveCardCount > 0 && view.liveCardCount <= 80)
        view.scrollGrid(to: view.gridContentHeight)
        #expect(view.liveCardCount <= 80)
        #expect(view.liveIDs.contains(view.entries.last!.id))
        #expect(view.liveIDs.count == view.liveCardCount && Set(view.visibleIDs).isSubset(of: view.liveIDs))
    }

    @Test func listArrowsMoveByOneRow() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.folder("a"), BrowserFixtures.folder("b")]
                                       + BrowserFixtures.files(3))
        #expect(view.columns == 1)
        let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                    context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false,
                                    keyCode: 125)!
        let up = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                  context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false,
                                  keyCode: 126)!
        #expect(view.selectedID == view.entries[0].id)
        #expect(view.handleKey(down))
        #expect(view.selectedID == view.entries[1].id)
        #expect(view.handleKey(down))
        #expect(view.selectedID == view.entries[2].id)   // across the folders / photos sections
        #expect(view.handleKey(up))
        #expect(view.selectedID == view.entries[1].id)
    }

    @Test func narrowColumnShowsPostersWhateverTheChoice() async {
        let source = FakeHomeSource()
        source.cardStyles[.folder(x)] = .list
        let view = make(source, width: 300)
        source.yield(x, [BrowserFixtures.folder("a")])
        await settle(seconds: 5) { !view.entries.isEmpty }
        view.layoutSubtreeIfNeeded()
        #expect(view.card(for: view.entries[0].id) is PosterCard)
        #expect(view.listHeader?.isHidden ?? true)
        #expect(view.toolbar.cardSwitchSelection == 2)
    }

    @Test func switchHiddenOnPlaces() async {
        let source = FakeHomeSource()
        source.infos["stash"] = HomeSourceInfo(title: "Stash", page: NSView(), pageFilters: ["Scenes"])
        source.infos["recent"] = HomeSourceInfo(title: "Recent")
        let view = make(source, at: .places)
        #expect(!view.toolbar.isCardSwitchVisible)
        view.show(.source("stash"), selecting: nil)
        #expect(!view.toolbar.isCardSwitchVisible)
        view.show(.source("recent"), selecting: nil)
        #expect(!view.toolbar.isCardSwitchVisible)
        view.show(.folder(x), selecting: nil)
        #expect(view.toolbar.isCardSwitchVisible)
        view.show(.places, selecting: nil)
        #expect(!view.toolbar.isCardSwitchVisible)
    }

    @Test func toolbarSwitchFollowsStyle() async {
        let source = FakeHomeSource()
        source.cardStyles[.folder(x)] = .cards
        let view = make(source)
        #expect(view.toolbar.cardSwitchSelection == 1)
        view.chooseCardStyle(.list)   // as the View menu does
        #expect(view.toolbar.cardSwitchSelection == 2)
        view.chooseCardStyle(.list)   // again: nothing more happens
        #expect(view.toolbar.cardSwitchSelection == 2)
        view.toolbar.clickCardStyle(0)   // the switch itself
        #expect(source.setCardStyles.map(\.0) == [.list, .list, .posters])
        #expect(view.toolbar.cardSwitchSelection == 0)
        view.show(.folder(URL(fileURLWithPath: "/Volumes/T/y")), selecting: nil)   // a folder of its own style
        #expect(view.toolbar.cardSwitchSelection == 0)
        source.cardStyles[.folder(x)] = .cards
        view.show(.folder(x), selecting: nil)
        #expect(view.toolbar.cardSwitchSelection == 1)
    }

    /// ⌃⌘ with a key: the card style's chord.
    private func controlCommand(_ code: UInt16, _ chars: String) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control, .command], timestamp: 0, windowNumber: 0,
                         context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false,
                         keyCode: code)!
    }

    @Test func styleIsForFoldersOnly() async {
        let source = FakeHomeSource()
        source.infos["stash"] = HomeSourceInfo(title: "Stash", page: NSView(), pageFilters: ["Scenes"])
        source.infos["recent"] = HomeSourceInfo(title: "Recent")
        for location in [BrowserLocation.places, .source("recent"), .source("stash")] {
            let view = make(source, at: location)
            #expect(!view.canChooseCardStyle)
            #expect(!view.handleKey(controlCommand(19, "2")))   // the key goes on
            view.chooseCardStyle(.cards)
            #expect(view.cardStyle == .posters)
        }
        #expect(source.setCardStyles.isEmpty)
        let view = make(source)
        #expect(view.canChooseCardStyle)
        #expect(view.handleKey(controlCommand(19, "2")))
        #expect(view.cardStyle == .cards && source.setCardStyles.count == 1)
    }

    @Test func headerOffersOnlyTheSortsThereAre() async {
        let source = FakeHomeSource()
        let view = await shown(source, [BrowserFixtures.folder("a")])
        #expect(view.listHeader?.sortable == [.name, .date, .size])
        view.listHeader?.sortable = [.name]
        let count = source.setSorts.count
        view.listHeader?.click(.dates)
        view.listHeader?.click(.size)
        #expect(source.setSorts.count == count)
        view.listHeader?.click(.name)
        #expect(source.setSorts.count == count + 1)
    }

    @Test func headerClickWhileHeldBehavesLikeTheCapsule() async {
        func run(_ click: (HomeBrowserView) -> Void) async -> ([String], String, [BrowserSort]) {
            let source = FakeHomeSource()
            source.cardStyles[.folder(x)] = .list
            let view = make(source)
            source.yield(x, [BrowserFixtures.file("b.jpg", date: 1), BrowserFixtures.file("a.jpg", date: 2)], complete: false)
            await settle(seconds: 5) { !view.entries.isEmpty }
            view.layoutSubtreeIfNeeded()
            click(view)
            view.layoutSubtreeIfNeeded()
            return (view.entries.map(\.name), view.toolbar.subtitleText, source.setSorts.map(\.0))
        }
        let header = await run { $0.listHeader?.click(.dates) }
        let capsule = await run { $0.toolbar.clickSort(1) }
        #expect(header.0 == capsule.0)       // the grid stays as it is until the complete listing
        #expect(header.1 == capsule.1 && header.1 == "Loading…")
        #expect(header.2 == capsule.2)
    }

    @Test func reusedRowLeavesNothingBehind() {
        let folder = HomeCardItem(id: "a", title: "a", tooltip: "a", symbol: "folder",
                                  summary: CardSummary(photos: 248, folders: 3, bytes: 4_200_000_000,
                                                       first: Date(timeIntervalSince1970: 1_560_000_000),
                                                       last: Date(timeIntervalSince1970: 1_690_000_000),
                                                       histogram: [10, 40, 90, 20, 0, 0, 5, 5, 30, 25, 20, 10],
                                                       viewed: 0.5, new: 4, twoPages: true, rightToLeft: true))
        let file = HomeCardItem(id: "b", title: "b.png", tooltip: "b", symbol: "doc", format: "PNG", bytes: 2_000)
        let row = ListRow(item: folder)
        row.frame = CGRect(x: 0, y: 0, width: 1000, height: 44)
        row.layoutSubtreeIfNeeded()
        #expect(!row.histogram.isHidden && !row.newPill.isHidden && !row.twoPagesIcon.isHidden)
        row.show(file)
        row.layoutSubtreeIfNeeded()
        #expect(row.insideLabel.stringValue == "PNG" && row.sizeLabel.stringValue == "2.0 KB")
        #expect(row.yearsLabel.isHidden && row.yearsLabel.stringValue.isEmpty)
        #expect(row.progressTrack.isHidden && row.histogram.isHidden && row.newPill.isHidden)
        #expect(row.twoPagesIcon.isHidden && row.rtlLabel.isHidden && row.problemIcon.isHidden)
    }

    @Test func styledLayoutFrom320() async {
        for (width, isRow) in [(CGFloat(320), true), (319, false)] {
            let source = FakeHomeSource()
            source.cardStyles[.folder(x)] = .list
            let view = make(source, width: width)
            source.yield(x, [BrowserFixtures.folder("a")])
            await settle(seconds: 5) { !view.entries.isEmpty }
            view.layoutSubtreeIfNeeded()
            #expect((view.card(for: view.entries[0].id) is ListRow) == isRow, "width \(width) -> \(view.gridContentWidth)")
        }
    }
}
