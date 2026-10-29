import AppKit
import Testing
@testable import HomeScreenKit
@testable import HomeScreenModel

/// The Photos-style grid in the browser: sections, cards, footer and column steps.
@MainActor @Suite struct HomeBrowserGridTests {
    let x = URL(fileURLWithPath: "/Volumes/T/x")

    func shown(_ source: FakeHomeSource, _ entries: [BrowserEntry], width: CGFloat = 1200,
               complete: Bool = true) async -> HomeBrowserView {
        let view = HomeBrowserView(source: source)
        view.frame = CGRect(x: 0, y: 0, width: width, height: 800)
        view.show(.folder(x), selecting: nil)
        view.layoutSubtreeIfNeeded()
        source.yield(x, entries, complete: complete)
        await settle(seconds: 5) { view.entries.count == entries.count }
        view.layoutSubtreeIfNeeded()
        return view
    }

    private var mixed: [BrowserEntry] { (0..<3).map { BrowserFixtures.folder("f\($0)") } + BrowserFixtures.files(20) }

    @Test func lastOpenedSurvivesHoverSelection() async {
        let view = await shown(FakeHomeSource(), BrowserFixtures.files(5))
        let first = view.entries[0].id, next = view.entries[1].id
        view.lastOpenedID = first
        view.select(id: next, scrolls: false)
        #expect(view.card(for: first)?.isLastOpened == true)
        #expect(view.card(for: next)?.isLastOpened == false)
        let marked = view.card(for: first) as? PhotoCard
        #expect(marked?.ring.isHidden == true)
        #expect(marked?.lastOpenedHighlight?.isHidden == false)
        #expect((view.card(for: next) as? PhotoCard)?.ring.isHidden == false)
        view.select(id: first, scrolls: false)
        #expect(marked?.ring.isHidden == false)
        #expect(marked?.lastOpenedHighlight?.isHidden == false)
        view.lastOpenedID = next
        #expect(marked?.ring.isHidden == false)
        #expect(marked?.lastOpenedHighlight?.isHidden == true)
        #expect(view.card(for: first)?.isLastOpened == false)
        #expect(view.card(for: next)?.isLastOpened == true)
    }
    @Test func gridFillsWidth() async {
        let view = await shown(FakeHomeSource(), BrowserFixtures.files(50), width: 1203)
        let lastOfRow = view.card(for: view.entries[view.columns - 1].id)!
        // The clip view's width: 1203 with overlay scrollers, less a legacy scroller's width otherwise.
        #expect(view.gridContentWidth > 1180)
        // the photos on the headings' line: 20 pt in from either side
        #expect(abs(lastOfRow.frame.maxX - (view.gridContentWidth - 20)) <= 0.5)
    }

    @Test func mixedFolderHasTwoSections() async {
        let view = await shown(FakeHomeSource(), mixed)
        #expect(view.headerTitles == ["Folders", "Photos · 20"])
        #expect(view.card(for: view.entries[0].id) is PosterCard)
        #expect(view.card(for: view.entries[3].id) is PhotoCard)
    }

    @Test func singleKindHasNoHeader() async {
        let view = await shown(FakeHomeSource(), BrowserFixtures.files(10))
        #expect(view.headerTitles.isEmpty)
    }

    @Test func placesAreCollections() async {
        let source = FakeHomeSource()
        source.placesList = [BrowserEntry(url: URL(fileURLWithPath: "/Volumes/T"), name: "T", kind: .place)]
        let view = HomeBrowserView(source: source)
        view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        view.show(.places, selecting: nil)
        await settle { !view.entries.isEmpty }
        view.layoutSubtreeIfNeeded()
        #expect(view.card(for: view.entries[0].id) is CollectionCard)
        #expect(view.headerTitles.isEmpty)
    }

    /// A saved sort by date shows the names' sections in Finder's order while the dates are listed, then the same
    /// sections in date order.
    @Test func sectionsShowWhileADateSortWaits() async {
        let source = FakeHomeSource()
        source.sorts[x.path] = BrowserSort(text: "date-desc")
        let view = HomeBrowserView(source: source)
        view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        view.show(.folder(x), selecting: nil)
        source.yieldPartial(x, mixed.map { BrowserEntry(url: $0.url, name: $0.name, kind: $0.kind) })
        await settle { !view.entries.isEmpty }
        view.layoutSubtreeIfNeeded()
        #expect(view.entries.count == mixed.count)
        #expect(view.headerTitles == ["Folders", "Photos · 20"])
        source.yield(x, mixed)
        await settle { !view.footerLines.isEmpty && view.footerLines.count == 1 }
        view.layoutSubtreeIfNeeded()
        #expect(view.headerTitles == ["Folders", "Photos · 20"])
        #expect(view.footerLines.first?.hasPrefix("20 photos · 3 folders") == true)
    }

    @Test func styleAndNamesReachCards() async {
        let view = await shown(FakeHomeSource(), BrowserFixtures.files(5))
        let id = view.entries[0].id
        let picture = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        view.setImage(picture, for: id)
        view.style = .square
        view.names = .below
        view.layoutSubtreeIfNeeded()
        let card = view.card(for: id) as? PhotoCard
        #expect(card?.style == .square)
        // Square fills the tile: the name goes on the picture's bottom line, not under it, and no slot room is kept.
        #expect(card?.names == .photo)
        #expect(card?.image != nil)
        #expect(!view.grid.namesBelow(inSection: 0))
        view.style = .aspect
        view.layoutSubtreeIfNeeded()
        #expect((view.card(for: id) as? PhotoCard)?.names == .below)
    }

    @Test func theCardSizePicksTheCardsAndRowsStep() async {
        let view = await shown(FakeHomeSource(), BrowserFixtures.files(5))
        view.cardSize = 360
        view.layoutSubtreeIfNeeded()
        #expect(view.grid.metrics.listRow == 56 && view.grid.metrics.cardHeight == 110)   // its top is the view's inset
        view.cardSize = 120
        view.layoutSubtreeIfNeeded()
        #expect(view.grid.metrics.listRow == 34 && view.grid.metrics.cardHeight == 80)
    }

    // MARK: Photo marks (photo-cards spec §2)

    private func photo(_ view: HomeBrowserView, _ i: Int) -> PhotoCard? { view.card(for: view.entries[i].id) as? PhotoCard }

    @Test func photoMarksReachLiveCards() async {
        let view = await shown(FakeHomeSource(), BrowserFixtures.files(20))
        view.setPhotoMarks(unseen: [view.entries[1].id, view.entries[2].id], paired: [view.entries[2].id])
        #expect(photo(view, 0)?.isUnseen == false && photo(view, 0)?.isPaired == false)
        #expect(photo(view, 1)?.isUnseen == true && photo(view, 1)?.isPaired == false)
        #expect(photo(view, 2)?.isUnseen == true && photo(view, 2)?.isPaired == true)
        view.setPhotoMarks(unseen: [], paired: [])
        #expect(photo(view, 1)?.isUnseen == false && photo(view, 2)?.isPaired == false)
    }

    @Test func photoMarksBindOnScroll() async {
        let view = await shown(FakeHomeSource(), BrowserFixtures.files(5_000))
        let last = view.entries.count - 1
        #expect(photo(view, last) == nil)
        view.setPhotoMarks(unseen: [view.entries[last].id], paired: [view.entries[last].id])
        view.scrollGrid(to: view.gridContentHeight)
        #expect(photo(view, last)?.isUnseen == true)
        #expect(photo(view, last)?.isPaired == true)
        #expect(photo(view, last - 1)?.isUnseen == false)
    }

    @Test func photoMarksForgottenOnPlaceChange() async {
        let source = FakeHomeSource()
        let view = await shown(source, BrowserFixtures.files(20))
        let id = view.entries[0].id
        view.setPhotoMarks(unseen: [id], paired: [id])
        // Away and back: the same ids, the marks of the earlier visit gone.
        let y = URL(fileURLWithPath: "/Volumes/T/y")
        view.show(.folder(y), selecting: nil)
        source.yield(y, BrowserFixtures.files(20, in: y.path), complete: true)
        await settle(seconds: 5) { view.location == .folder(y) && view.entries.first?.id != id }
        view.show(.folder(x), selecting: nil)
        source.yield(x, BrowserFixtures.files(20), complete: true)
        await settle(seconds: 5) { view.entries.first?.id == id }
        view.layoutSubtreeIfNeeded()
        #expect(photo(view, 0)?.isUnseen == false)
        #expect(photo(view, 0)?.isPaired == false)
    }

    @Test func columnStepTargets() async {
        let view = await shown(FakeHomeSource(), BrowserFixtures.files(100))
        let m = GridMetrics()
        view.cardSize = GridLayout.target(columns: 6, width: 1200, gap: m.photoGap, edge: m.photoEdge)
        view.layoutSubtreeIfNeeded()
        #expect(view.columns == 6)
        let larger = view.cardSize(after: .larger, range: 60...480)!
        let smaller = view.cardSize(after: .smaller, range: 60...480)!
        #expect(GridLayout.columns(width: 1200, target: larger, gap: m.photoGap, edge: m.photoEdge) == 5)
        #expect(GridLayout.columns(width: 1200, target: smaller, gap: m.photoGap, edge: m.photoEdge) == 7)
        #expect(view.cardSize(after: .reset, range: 60...480) == nil)
    }

    @Test func footerSummary() async {
        let view = await shown(FakeHomeSource(), mixed, complete: false)
        #expect(view.footerLines == ["20 photos · 3 folders"])
        let complete = await shown(FakeHomeSource(), mixed)
        #expect(complete.footerLines.first?.hasPrefix("20 photos · 3 folders · ") == true)
    }

    @Test func poolBoundedAtSmallestSize() async {
        let source = FakeHomeSource()
        let view = HomeBrowserView(source: source)
        view.frame = CGRect(x: 0, y: 0, width: 3000, height: 800)
        view.cardSize = 60
        view.show(.folder(x), selecting: nil)
        source.yield(x, BrowserFixtures.files(10_000))
        await settle(seconds: 5) { view.entries.count == 10_000 }
        view.layoutSubtreeIfNeeded()
        let perRow = view.columns, rows = Int((800 / (3000 / CGFloat(perRow))).rounded(.up)) + 1
        #expect(view.liveCardCount <= perRow * rows * 3)
        #expect(view.liveCardCount > 0)
    }
}
