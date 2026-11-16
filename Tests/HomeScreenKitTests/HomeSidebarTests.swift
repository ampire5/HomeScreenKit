import AppKit
import Testing
@testable import HomeScreenKit
@testable import HomeScreenModel

@MainActor @Suite struct HomeSidebarTests {
    private func url(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }

    private var tree: SidebarTree {
        var t = SidebarTree(sections: [
            HomeSidebarSection(id: "library", title: nil, rows: [
                HomeSidebarRow(id: "recent", title: "Recent", symbol: "clock", location: .source("recent")),
            ]),
            HomeSidebarSection(id: "places", title: "Places", rows: [
                HomeSidebarRow(id: "/Volumes/T", title: "T", symbol: "externaldrive", location: .folder(url("/Volumes/T")),
                               expandable: true),
            ]),
        ])
        _ = t.expand(url("/Volumes/T"))
        t.setChildren([BrowserEntry(url: url("/Volumes/T/a"), name: "a", kind: .folder, count: 12)], of: url("/Volumes/T"))
        return t
    }

    private func sidebar(_ tree: SidebarTree) -> HomeSidebar {
        let view = HomeSidebar()
        view.frame = CGRect(x: 0, y: 0, width: HomeSidebar.width, height: 600)
        view.tree = tree
        view.layoutSubtreeIfNeeded()
        return view
    }

    @Test func scrollingALargeSidebarKeepsOnlyViewportRowsAttached() throws {
        let rows = (0..<2_500).map { i in
            HomeSidebarRow(id: "row-\(i)", title: "Folder \(i)", symbol: "folder", location: .source("row-\(i)"))
        }
        let view = sidebar(SidebarTree(sections: [.init(id: "folders", title: nil, rows: rows)]))
        let scroll = try #require(view.subviews.first as? NSScrollView)
        let document = try #require(scroll.documentView)
        let maximumRows = Int(ceil(scroll.contentSize.height / HomeSidebar.rowHeight)) + 4
        #expect(document.subviews.count <= maximumRows)
        scroll.contentView.scroll(to: CGPoint(x: 0, y: 2_400 * HomeSidebar.rowHeight))
        scroll.reflectScrolledClipView(scroll.contentView)
        view.layoutSubtreeIfNeeded()
        let visible = scroll.documentVisibleRect
        #expect(document.subviews.count <= maximumRows)
        #expect(document.subviews.contains { $0.tag == 2_401 && visible.intersects($0.frame) })
    }

    /// Compact indent: the levels past the third step 6 pt, with a guide per level above the row; even: 14 pt, none.
    @Test func compactIndentStepsLessDeepDown() {
        var t = tree
        _ = t.follow(.folder(url("/Volumes/T/a/b/c/d/e")))
        t.options.compactChains = false
        let view = sidebar(t)
        #expect(view.titles == ["Recent", "Places", "T", "a", "b", "c", "d", "e"])
        let x = view.titleFrames.map(\.minX)
        #expect(x[4] - x[3] == 12)
        #expect(x[5] - x[4] == 12)
        #expect(x[6] - x[5] == 8)
        #expect(x[7] - x[6] == 8)
        #expect(view.guideCounts[2...7] == [0, 1, 2, 3, 4, 5])
        view.compactIndent = false
        view.layoutSubtreeIfNeeded()
        let even = view.titleFrames.map(\.minX)
        #expect(even[7] - even[6] == 12)
        #expect(view.guideCounts.allSatisfy { $0 == 0 })
    }

    /// The tree set again (the browser moved, a reply came) redraws only the lines whose row changed: unchanged ones
    /// keep their symbol, title and count as they are (each redraw makes their images again at the next commit).
    @Test func treeAgainRedrawsOnlyChangedLines() {
        var t = tree
        let view = sidebar(t)
        let drawn = view.lineRedraws
        view.tree = t
        #expect(view.lineRedraws == drawn)
        t.setChildren([BrowserEntry(url: url("/Volumes/T/a"), name: "a", kind: .folder, count: 13)], of: url("/Volumes/T"))
        view.tree = t
        #expect(view.lineRedraws == drawn + 1)
        #expect(view.countTexts[3] == "13")
    }

    /// A name too long for the row loses its end, not its middle: the start says which folder it is.
    @Test func longNamesTruncateAtTheEnd() {
        let view = sidebar(tree)
        #expect(view.titleBreakModes.allSatisfy { $0 == .byTruncatingTail })
    }

    @Test func drawsLines() {
        let view = sidebar(tree)
        #expect(view.titles == ["Recent", "Places", "T", "a"])
        #expect(view.titleFrames[3].minX - view.titleFrames[2].minX == 12)
        #expect(view.lineFrames[0].height == 32)   // Photos' 32 pt lines
        #expect(view.lineFrames[1].height == 32)
        #expect(view.countTexts[3] == "12")
    }

    @Test func clickOpens() {
        let view = sidebar(tree)
        var opened: [BrowserLocation] = []
        view.onOpen = { opened.append($0) }
        view.click(line: 0)
        view.click(line: 3)
        #expect(opened == [.source("recent"), .folder(url("/Volumes/T/a"))])
    }

    @Test func favoriteAndPlaceWithSamePathHaveDistinctSelection() {
        let location = BrowserLocation.folder(url("/Volumes/T"))
        let row = HomeSidebarRow(id: "T", title: "T", symbol: "folder", location: location, expandable: true)
        let favorites = HomeSidebarSection.favorites([row])
        let places = HomeSidebarSection(id: "places", title: "Places", rows: [row])
        var tree = SidebarTree(sections: [favorites, places])
        let favorite = tree.root(at: 1)
        let place = tree.root(at: 3)
        #expect(favorite != place)
        _ = tree.follow(location, preferredRoot: favorite)
        #expect(tree.currentLine == 1)
        _ = tree.follow(location, preferredRoot: place)
        #expect(tree.currentLine == 3)
        tree.setSections([favorites])
        _ = tree.follow(location)
        #expect(tree.currentLine == 1)
    }

    @Test func moveDownTargetsAfterNextFavoriteAndLeavesChildrenAlone() throws {
        let folders = ["B", "A", "C"].map { url("/Volumes/T/" + $0) }
        var tree = SidebarTree(sections: [.favorites(folders.map {
            HomeSidebarRow(id: $0.path, title: $0.lastPathComponent, symbol: "folder",
                           location: .folder($0), expandable: true)
        })])
        _ = tree.expand(folders[0])
        tree.setChildren([BrowserEntry(url: url("/Volumes/T/B/child"), name: "child", kind: .folder)], of: folders[0])
        let view = sidebar(tree)
        #expect(view.titles == ["Favorites", "B", "child", "A", "C"])
        #expect(view.menu(forLine: 2) == nil)
        var moved: URL?
        var before: URL?
        view.onMoveFavorite = { moved = $0; before = $1 }
        let item = try #require(view.menu(forLine: 1)?.item(withTitle: "Move Down"))
        let action = try #require(item.action)
        _ = NSApp.sendAction(action, to: item.target, from: item)
        #expect(moved == folders[0])
        #expect(before == folders[2])
    }

    @Test func disclosureExpandsAndCollapses() {
        var t = tree
        let view = sidebar(t)
        var expanded: [URL] = [], collapsed: [URL] = []
        view.onExpand = { expanded.append($0) }
        view.onCollapse = { collapsed.append($0) }
        view.clickDisclosure(line: 2)
        #expect(collapsed == [url("/Volumes/T")])
        t.collapse(url("/Volumes/T"))
        view.tree = t
        view.clickDisclosure(line: 2)
        #expect(expanded == [url("/Volumes/T")])
        var toggled: [String] = []
        view.onToggleSection = { toggled.append($0) }
        view.click(line: 1)
        #expect(toggled == ["places"])
    }

    @Test func keysWalkTheTree() {
        let view = sidebar(tree)
        var opened: [BrowserLocation] = [], collapsed: [URL] = []
        view.onOpen = { opened.append($0) }
        view.onCollapse = { collapsed.append($0) }
        _ = view.handleKey(keyEvent(code: 125, chars: ""))   // ↓ from nothing: the first row
        #expect(view.highlightedLine == 0)
        _ = view.handleKey(keyEvent(code: 125, chars: ""))   // ↓ skips the heading
        #expect(view.highlightedLine == 2)
        _ = view.handleKey(keyEvent(code: 124, chars: ""))   // → into the open folder
        #expect(view.highlightedLine == 3)
        #expect(opened.isEmpty)
        _ = view.handleKey(keyEvent(code: 36, chars: "\r"))
        #expect(opened == [.folder(url("/Volumes/T/a"))])
        _ = view.handleKey(keyEvent(code: 123, chars: ""))   // ← to the parent
        _ = view.handleKey(keyEvent(code: 123, chars: ""))   // ← closes it
        #expect(collapsed == [url("/Volumes/T")])
    }

    @Test func tabEndsKeys() {
        let view = sidebar(tree)
        var ended = 0
        view.onEndKeys = { ended += 1 }
        #expect(view.handleKey(keyEvent(code: 48, chars: "\t")))
        #expect(ended == 1)
    }

    @Test func currentLineIsLit() {
        var t = tree
        _ = t.follow(.folder(url("/Volumes/T/a")))
        let view = sidebar(t)
        #expect(view.highlightedLine == 3)
    }

    @Test func spinnerAfterDelay() async {
        var t = tree
        t.collapse(url("/Volumes/T"))
        let view = HomeSidebar()
        view.slowAfter = .milliseconds(50)
        view.frame = CGRect(x: 0, y: 0, width: HomeSidebar.width, height: 600)
        _ = t.expand(url("/Volumes/T/a"))   // not a root: asks, but shows only once T is open
        _ = t.expand(url("/Volumes/T"))
        t.setLoading(true, of: url("/Volumes/T"))
        view.tree = t
        view.layoutSubtreeIfNeeded()
        #expect(!view.isSpinning(line: 2))
        await settle(seconds: 10) { view.isSpinning(line: 2) }
        #expect(view.isSpinning(line: 2))
    }

    /// The lit row stays in view as the tree follows and fills (the path of a deep folder under a long list).
    @Test func currentLineScrolledIntoView() {
        let rows = (0..<60).map { i in
            HomeSidebarRow(id: "/V\(i)", title: "V\(i)", symbol: "externaldrive", location: .folder(url("/V\(i)")))
        }
        var t = SidebarTree(sections: [HomeSidebarSection(id: "places", title: "Places", rows: rows)])
        _ = t.follow(.folder(url("/V55")))
        let view = HomeSidebar()
        view.frame = CGRect(x: 0, y: 0, width: HomeSidebar.width, height: 300)
        view.tree = t
        view.layoutSubtreeIfNeeded()
        let line = view.highlightedLine!
        #expect(view.visibleLineRect.contains(view.lineFrames[line]))
    }

    /// A folder opened above the current row stays where it was: its many folders push the current row down, and the
    /// list does not run after it (it jumped there, the opened folder far off).
    @Test func openingAFolderAboveTheCurrentRowKeepsTheList() {
        let rows = (0..<40).map { i in
            HomeSidebarRow(id: "/V\(i)", title: "V\(i)", symbol: "externaldrive", location: .folder(url("/V\(i)")),
                           expandable: true)
        }
        var t = SidebarTree(sections: [HomeSidebarSection(id: "places", title: "Places", rows: rows)])
        _ = t.follow(.folder(url("/V35")))
        let view = HomeSidebar()
        view.frame = CGRect(x: 0, y: 0, width: HomeSidebar.width, height: 300)
        view.onExpand = { folder in
            _ = t.expand(folder)
            t.setChildren((0..<50).map { BrowserEntry(url: self.url("/V30/\($0)"), name: "\($0)", kind: .folder) },
                          of: folder)
            view.tree = t
        }
        view.tree = t
        view.layoutSubtreeIfNeeded()
        let line = view.titles.firstIndex(of: "V30")!
        let before = view.lineFrames[line].minY - view.visibleLineRect.minY
        view.clickDisclosure(line: line)
        view.layoutSubtreeIfNeeded()
        #expect(view.titles[line + 1] == "0")
        #expect(view.lineFrames[line].minY - view.visibleLineRect.minY == before)
    }

    /// A row's context menu: what the app gives for it (a folder's Show in Finder, Copy Path), the item chosen going
    /// back with the row; a heading has none.
    @Test func rowMenuComesFromTheApp() throws {
        let view = sidebar(tree)
        var asked: [String] = [], chosen: [(String, String)] = []
        view.menuItems = { row in
            asked.append(row.id)
            guard case .folder = row.location else { return [] }
            return [HomeMenuItem(id: "reveal", title: "Show in Finder"), HomeMenuItem(id: "copyPath", title: "Copy Path")]
        }
        view.onMenu = { item, row in chosen.append((item, row.id)) }
        let menu = try #require(view.menu(forLine: 3))
        #expect(menu.items.map(\.title) == ["Show in Finder", "Copy Path"])
        let copy = try #require(menu.items.last)
        _ = (copy.target as? NSObject)?.perform(copy.action, with: copy)
        #expect(chosen.map(\.0) == ["copyPath"] && chosen.map(\.1) == [url("/Volumes/T/a").path])
        #expect(view.menu(forLine: 0) == nil)   // Recent: the app gives none
        #expect(view.menu(forLine: 1) == nil)   // a heading: never asked
        #expect(asked == [url("/Volumes/T/a").path, "recent"])
    }
}
