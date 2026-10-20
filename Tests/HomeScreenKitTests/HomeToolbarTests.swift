import AppKit
import Testing
@testable import HomeScreenKit
@testable import HomeScreenModel

@MainActor @Suite struct HomeToolbarTests {
    private let x = URL(fileURLWithPath: "/Volumes/T/x")

    private func toolbar() -> HomeToolbar {
        let bar = HomeToolbar()
        bar.frame = CGRect(x: 0, y: 0, width: 1200, height: HomeToolbar.height)
        bar.layoutSubtreeIfNeeded()
        return bar
    }

    @Test func crumbsLastBold() {
        let bar = toolbar()
        bar.show(path: [("Places", .places), ("T", .folder(x.deletingLastPathComponent())), ("x", .folder(x))],
                 canBack: true, canForward: false, canUp: true)
        #expect(bar.crumbTitles == ["Places", "T", "x"])
        #expect(bar.crumbFonts.last?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(bar.crumbFonts.first?.fontDescriptor.symbolicTraits.contains(.bold) == false)
        var went: [BrowserLocation] = []
        bar.onCrumb = { went.append($0) }
        bar.clickCrumb(1)
        #expect(went == [.folder(x.deletingLastPathComponent())])
        bar.show(subtitle: "2 photos")
        #expect(bar.subtitleText == "2 photos")
    }

    @Test func sortTitlesShowDirection() {
        let bar = toolbar()
        bar.show(sort: BrowserSort(key: .date, ascending: false), keys: [.name, .date, .size])
        #expect(bar.sortTitles == ["Name", "Date ↓", "Size"])
        bar.show(sort: BrowserSort(key: .name, ascending: true), keys: [.name, .date, .size])
        #expect(bar.sortTitles == ["Name ↑", "Date", "Size"])
    }

    @Test func sortClickCallsKey() {
        let bar = toolbar()
        var keys: [BrowserSort.Key] = []
        bar.onSortKey = { keys.append($0) }
        bar.clickSort(2)
        bar.clickSort(0)
        #expect(keys == [.size, .name])
    }

    @Test func kindClickCallsBack() {
        let bar = toolbar()
        var kinds: [BrowserKindFilter] = []
        bar.onKind = { kinds.append($0) }
        bar.clickKind(2)
        #expect(kinds == [.photos])
    }

    @Test func filterHiddenOnPlaces() {
        let bar = toolbar()
        bar.show(filter: .all, visible: false)
        #expect(!bar.isFilterVisible)
        bar.show(filter: .folders, visible: true)
        #expect(bar.isFilterVisible)
    }

    @Test func fieldTextCallsBack() {
        let bar = toolbar()
        var texts: [String] = []
        bar.onFilterText = { texts.append($0) }
        bar.field.stringValue = "ab"
        bar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: bar.field))
        #expect(texts == ["ab"])
        #expect(bar.filterText == "ab")
    }

    @Test func escapeInFieldEnds() {
        let bar = toolbar()
        var texts: [String] = [], ended = 0
        bar.onFilterText = { texts.append($0) }
        bar.onFilterEnd = { ended += 1 }
        bar.field.stringValue = "ab"
        let handled = bar.control(bar.field, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        #expect(handled)
        #expect(bar.filterText == "")
        #expect(texts == [""])
        #expect(ended == 1)
    }

    @Test func zoomButtonsStep() {
        let bar = toolbar()
        var steps: [HomeResize] = []
        bar.onZoom = { steps.append($0) }
        bar.zoom.press(0)
        bar.zoom.press(1)
        #expect(steps == [.smaller, .larger])
    }

    @Test func styleButtonSymbolFollowsStyle() {
        let bar = toolbar()
        var pressed = 0
        bar.onStyle = { pressed += 1 }
        bar.show(style: .square)
        #expect(bar.styleSymbol == "square.grid.2x2")
        bar.show(style: .aspect)
        #expect(bar.styleSymbol == "rectangle.grid.2x2")
        bar.styleButton.press(0)
        #expect(pressed == 1)
    }

    @Test func siblingArrowCallsBack() {
        let bar = toolbar()
        bar.popUp = { _, _ in }
        bar.show(path: [("Places", .places), ("T", .folder(x.deletingLastPathComponent())), ("x", .folder(x))],
                 canBack: false, canForward: false, canUp: true)
        var asked: [Int] = []
        bar.onSiblings = { asked.append($0) }
        bar.clickSiblings(2)
        #expect(asked == [2])
    }

    @Test func kindCapsuleClearsTheRightGroup() {
        for width: CGFloat in [900, 1100, 1400, 2000] {
            let bar = HomeToolbar()
            bar.frame = CGRect(x: 0, y: 0, width: width, height: HomeToolbar.height)
            bar.show(filter: .all, visible: true)
            bar.layoutSubtreeIfNeeded()
            #expect(bar.kindFrame.maxX <= bar.sortFrame.minX, "width \(width)")
        }
    }

    @Test func sidebarButtonFirst() {
        let bar = toolbar()
        #expect(bar.sidebarButton.frame.maxX <= bar.navFrame.minX)
        var pressed = 0
        bar.onSidebar = { pressed += 1 }
        bar.sidebarButton.press(0)
        #expect(pressed == 1)
    }

    /// The house sits between the sidebar button and ‹ › ↑, and stays with a source's title.
    @Test func homeButtonAfterSidebar() {
        let bar = toolbar()
        #expect(bar.sidebarButton.frame.maxX <= bar.homeButton.frame.minX)
        #expect(bar.homeButton.frame.maxX <= bar.navFrame.minX)
        var pressed = 0
        bar.onHome = { pressed += 1 }
        bar.homeButton.press(0)
        #expect(pressed == 1)
        bar.show(title: "Recent")
        bar.layoutSubtreeIfNeeded()
        #expect(!bar.homeButton.isHidden)
    }

    @Test func titleHidesNav() {
        let bar = toolbar()
        bar.show(title: "Recent")
        #expect(bar.crumbTitles == ["Recent"])
        #expect(!bar.isNavVisible)
        bar.show(path: [("Places", .places), ("x", .folder(x))], canBack: true, canForward: false, canUp: true)
        #expect(bar.isNavVisible)
        #expect(bar.crumbTitles == ["Places", "x"])
    }

    @Test func sortKeysFromSource() {
        let bar = toolbar()
        bar.show(sort: BrowserSort(key: .date, ascending: false), keys: [.date, .name])
        #expect(bar.sortTitles == ["Date ↓", "Name"])
        var keys: [BrowserSort.Key] = []
        bar.onSortKey = { keys.append($0) }
        bar.clickSort(0)
        bar.clickSort(1)
        #expect(keys == [.date, .name])
        bar.show(sort: .standard, keys: [])
        #expect(!bar.isSortVisible)
    }

    @Test func pageFilters() {
        let bar = toolbar()
        bar.show(pageFilters: ["Scenes", "Images", "Galleries"], selected: 2)
        #expect(bar.kindTitles == ["Scenes", "Images", "Galleries"])
        #expect(bar.isFilterVisible)
        var pages: [Int] = [], kinds: [BrowserKindFilter] = []
        bar.onPageFilter = { pages.append($0) }
        bar.onKind = { kinds.append($0) }
        bar.clickKind(0)
        #expect(pages == [0])
        #expect(kinds.isEmpty)
        bar.show(pageFilters: [], selected: nil)
        #expect(bar.kindTitles == ["All", "Folders", "Photos"])
        bar.clickKind(1)
        #expect(kinds == [.folders])
    }

    @Test func pageHidesGridControls() {
        let bar = toolbar()
        bar.show(controls: false)
        #expect(bar.field.isHidden && bar.zoom.isHidden && bar.styleButton.isHidden)
        bar.show(controls: true)
        #expect(!bar.field.isHidden && !bar.zoom.isHidden && !bar.styleButton.isHidden)
    }
}
