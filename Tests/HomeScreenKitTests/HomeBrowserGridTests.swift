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

    @Test func gridFillsWidth() async {
        let view = await shown(FakeHomeSource(), BrowserFixtures.files(50), width: 1203)
        let lastOfRow = view.card(for: view.entries[view.columns - 1].id)!
        // The clip view's width: 1203 with overlay scrollers, less a legacy scroller's width otherwise.
        #expect(view.gridContentWidth > 1180)
        #expect(abs(lastOfRow.frame.maxX - view.gridContentWidth) <= 0.5)
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

    @Test func sectionsWaitForCompleteDateSort() async {
        let source = FakeHomeSource()
        source.sorts[x.path] = BrowserSort(text: "date-desc")
        let view = HomeBrowserView(source: source)
        view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        view.show(.folder(x), selecting: nil)
        source.yieldPartial(x, mixed.map { BrowserEntry(url: $0.url, name: $0.name, kind: $0.kind) })
        await settle()
        view.layoutSubtreeIfNeeded()
        #expect(view.entries.isEmpty)
        #expect(view.headerTitles.isEmpty)
        #expect(view.footerLines.isEmpty)
        source.yield(x, mixed)
        await settle { !view.entries.isEmpty }
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
        #expect(card?.names == .below)
        #expect(card?.image != nil)
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
