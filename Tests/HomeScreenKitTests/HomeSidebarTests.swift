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

    /// Compact indent: the levels past the third step 6 pt, with a guide per level above the row; even: 14 pt, none.
    @Test func compactIndentStepsLessDeepDown() {
        var t = tree
        _ = t.follow(.folder(url("/Volumes/T/a/b/c/d/e")))
        t.options.compactChains = false
        let view = sidebar(t)
        #expect(view.titles == ["Recent", "Places", "T", "a", "b", "c", "d", "e"])
        let x = view.titleFrames.map(\.minX)
        #expect(x[4] - x[3] == 14)
        #expect(x[5] - x[4] == 14)
        #expect(x[6] - x[5] == 6)
        #expect(x[7] - x[6] == 6)
        #expect(view.guideCounts[2...7] == [0, 1, 2, 3, 4, 5])
        view.compactIndent = false
        view.layoutSubtreeIfNeeded()
        let even = view.titleFrames.map(\.minX)
        #expect(even[7] - even[6] == 14)
        #expect(view.guideCounts.allSatisfy { $0 == 0 })
    }

    @Test func drawsLines() {
        let view = sidebar(tree)
        #expect(view.titles == ["Recent", "Places", "T", "a"])
        #expect(view.titleFrames[3].minX - view.titleFrames[2].minX == 14)
        #expect(view.lineFrames[0].height == 28)
        #expect(view.lineFrames[1].height == 26)
        #expect(view.countTexts[3] == "12")
        #expect(view.panelFrame == CGRect(x: 8, y: 8, width: 220, height: 584))
    }

    @Test func clickOpens() {
        let view = sidebar(tree)
        var opened: [BrowserLocation] = []
        view.onOpen = { opened.append($0) }
        view.click(line: 0)
        view.click(line: 3)
        #expect(opened == [.source("recent"), .folder(url("/Volumes/T/a"))])
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
}
