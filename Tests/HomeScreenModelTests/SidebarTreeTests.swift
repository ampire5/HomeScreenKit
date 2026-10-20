import Foundation
import Testing
@testable import HomeScreenModel

@Suite struct SidebarTreeTests {
    private func url(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }

    private func row(_ title: String, _ path: String, expandable: Bool = true) -> HomeSidebarRow {
        HomeSidebarRow(id: path, title: title, symbol: "folder", location: .folder(url(path)), expandable: expandable)
    }

    private var library: HomeSidebarSection {
        HomeSidebarSection(id: "library", title: nil, rows: [
            HomeSidebarRow(id: "recent", title: "Recent", symbol: "clock", location: .source("recent")),
            HomeSidebarRow(id: "sessions", title: "Sessions", symbol: "rectangle.stack", location: .source("sessions")),
        ])
    }
    private var places: HomeSidebarSection {
        HomeSidebarSection(id: "places", title: "Places", rows: [
            row("u", "/Users/u"), row("T", "/Volumes/T"), row("Best", "/Volumes/T/Photos/Best"),
        ])
    }
    private var stash: HomeSidebarSection {
        HomeSidebarSection(id: "stash", title: "Stash", rows: [
            HomeSidebarRow(id: "stash", title: "Library", symbol: "server.rack", location: .source("stash")),
        ])
    }
    private var tree: SidebarTree { SidebarTree(sections: [library, places, stash]) }

    private func folder(_ name: String, in parent: String, kind: BrowserEntry.Kind = .folder) -> BrowserEntry {
        BrowserEntry(url: url(parent).appendingPathComponent(name), name: name, kind: kind)
    }

    /// The titles and depths of the rows, headings as "# title".
    private func shape(_ t: SidebarTree) -> [String] {
        t.lines.map {
            switch $0 {
            case .heading(_, let title, let collapsed): "# \(title)\(collapsed ? " (collapsed)" : "")"
            case .row(let row, let depth, let expanded, _): String(repeating: "  ", count: depth) + row.title + (expanded ? " ▾" : "")
            }
        }
    }

    private func line(_ t: SidebarTree, _ title: String) -> Int {
        t.lines.firstIndex { if case .row(let r, _, _, _) = $0 { r.title == title } else { false } }!
    }

    @Test func linesListHeadingsAndRoots() {
        #expect(shape(tree) == ["Recent", "Sessions", "# Places", "u", "T", "Best", "# Stash", "Library"])
        #expect(tree.currentLine == nil)
    }

    @Test func expandAsksOnceThenShowsChildren() {
        var t = tree
        let asked = t.expand(url("/Volumes/T"))
        #expect(asked)
        guard case .row(_, _, true, true) = t.lines[line(t, "T")] else { Issue.record("T not expanded and loading"); return }
        t.setChildren([folder("B", in: "/Volumes/T"), folder("a", in: "/Volumes/T"),
                       folder("x.zip", in: "/Volumes/T", kind: .archive), folder("f.jpg", in: "/Volumes/T", kind: .file)],
                      of: url("/Volumes/T"))
        #expect(shape(t) == ["Recent", "Sessions", "# Places", "u", "T ▾", "  a", "  B", "  x.zip", "Best", "# Stash", "Library"])
        guard case .row(let zip, _, _, false) = t.lines[line(t, "x.zip")] else { Issue.record("zip row"); return }
        #expect(!zip.expandable)
        #expect(zip.symbol == "doc.zipper")
        t.collapse(url("/Volumes/T"))
        #expect(shape(t).contains("T"))
        let again = t.expand(url("/Volumes/T"))
        #expect(!again)
        #expect(shape(t).contains("  a"))
    }

    @Test func followPicksLongestRoot() {
        var t = tree
        let unknown = t.follow(.folder(url("/Volumes/T/Photos/Best/2026")))
        #expect(unknown == [url("/Volumes/T/Photos/Best")])
        let current = t.currentLine
        #expect(current == line(t, "2026"))
        guard let current, case .row(_, 1, _, _) = t.lines[current] else { Issue.record("2026 not at depth 1"); return }
        #expect(shape(t).contains("Best ▾"))
        #expect(shape(t).contains("T"))   // T itself stays closed
    }

    @Test func followShowsChainAtOnce() {
        var t = tree
        let unknown = t.follow(.folder(url("/Volumes/T/Photos/2026/10")))
        #expect(unknown == [url("/Volumes/T"), url("/Volumes/T/Photos"), url("/Volumes/T/Photos/2026")])
        #expect(shape(t) == ["Recent", "Sessions", "# Places", "u", "T ▾", "  Photos ▾", "    2026 ▾", "      10",
                             "Best", "# Stash", "Library"])
        #expect(t.currentLine == line(t, "10"))
        t.setChildren([folder("Photos", in: "/Volumes/T"), folder("Albums", in: "/Volumes/T")], of: url("/Volumes/T"))
        #expect(shape(t) == ["Recent", "Sessions", "# Places", "u", "T ▾", "  Albums", "  Photos ▾", "    2026 ▾",
                             "      10", "Best", "# Stash", "Library"])
        #expect(t.currentLine == line(t, "10"))
    }

    @Test func followOutsideRoots() {
        var t = tree
        let before = shape(t)
        let outside = t.follow(.folder(url("/private/tmp/x")))
        #expect(outside == [])
        #expect(t.currentLine == nil)
        #expect(shape(t) == before)
    }

    @Test func followRootItself() {
        var t = tree
        let root = t.follow(.folder(url("/Volumes/T")))
        #expect(root == [])
        #expect(t.currentLine == line(t, "T"))
        #expect(shape(t).contains("T"))
    }

    @Test func followSourceLightsItsRow() {
        var t = tree
        let none = t.follow(.source("stash"))
        #expect(none == [])
        #expect(t.currentLine == line(t, "Library"))
        _ = t.follow(.places)
        #expect(t.currentLine == nil)
    }

    @Test func collapsedSectionHidesRowsButFollowOpensIt() {
        var t = tree
        t.toggleSection("places")
        #expect(shape(t) == ["Recent", "Sessions", "# Places (collapsed)", "# Stash", "Library"])
        _ = t.follow(.folder(url("/Volumes/T/Photos")))
        #expect(shape(t).contains("# Places"))
        #expect(t.currentLine == line(t, "Photos"))
    }

    @Test func setSectionsDropsGoneRoots() {
        var t = tree
        _ = t.expand(url("/Users/u"))
        t.setChildren([folder("Pictures", in: "/Users/u")], of: url("/Users/u"))
        _ = t.follow(.folder(url("/Volumes/T/Photos")))
        t.setSections([library, HomeSidebarSection(id: "places", title: "Places", rows: [row("u", "/Users/u")]), stash])
        #expect(shape(t) == ["Recent", "Sessions", "# Places", "u ▾", "  Pictures", "# Stash", "Library"])
        #expect(t.currentLine == nil)
        // T comes back unexpanded: what was under it was forgotten.
        t.setSections([library, places, stash])
        #expect(shape(t).contains("T"))
    }

    @Test func keysMoveAsFinder() {
        var t = tree
        let tLine = line(t, "T")
        #expect(t.move(.right, from: tLine) == .expand(url("/Volumes/T")))
        _ = t.expand(url("/Volumes/T"))
        t.setChildren([folder("a", in: "/Volumes/T")], of: url("/Volumes/T"))
        let aLine = line(t, "a")
        #expect(t.move(.right, from: tLine) == .select(aLine))
        #expect(t.move(.left, from: aLine) == .select(tLine))
        #expect(t.move(.left, from: tLine) == .collapse(url("/Volumes/T")))
        #expect(t.move(.down, from: line(t, "Sessions")) == .select(line(t, "u")))
        #expect(t.move(.up, from: line(t, "u")) == .select(line(t, "Sessions")))
        #expect(t.move(.up, from: line(t, "Recent")) == .none)
        #expect(t.move(.down, from: line(t, "Library")) == .none)
        #expect(t.move(.open, from: aLine) == .open(.folder(url("/Volumes/T/a"))))
        #expect(t.move(.left, from: line(t, "Recent")) == .none)
    }

    // MARK: Deep trees

    /// /Volumes/T/a/b/c/d/e/f/g, each listed with the next folder only (and `side` beside `b`).
    private func deep(_ t: inout SidebarTree, listed: [String] = ["/Volumes/T", "/Volumes/T/a", "/Volumes/T/a/b",
                                                                  "/Volumes/T/a/b/c", "/Volumes/T/a/b/c/d",
                                                                  "/Volumes/T/a/b/c/d/e", "/Volumes/T/a/b/c/d/e/f"]) {
        for parent in listed {
            let next = ["a", "b", "c", "d", "e", "f", "g"][parent.split(separator: "/").count - 2]
            var entries = [folder(next, in: parent)]
            if parent == "/Volumes/T/a" { entries.append(folder("side", in: parent)) }
            t.setChildren(entries, of: url(parent))
        }
    }

    /// A folder holding one folder shows with it on one row; the row is the deepest one; a fork ends the chain, and so
    /// does the current folder.
    @Test func singleFolderChainsShareARow() {
        var t = tree
        _ = t.follow(.folder(url("/Volumes/T/a/b/c/d")))
        deep(&t)
        #expect(Array(shape(t)[4...8]) == ["T ▾", "  a ▾", "    b › c › d", "    side", "Best"])
        let joined = line(t, "b › c › d")
        guard case .row(let row, _, _, _) = t.lines[joined] else { Issue.record("no b › c › d"); return }
        #expect(row.location == .folder(url("/Volumes/T/a/b/c/d")))
        #expect(t.currentLine == joined)
        _ = t.follow(.folder(url("/Volumes/T/a/b/c")))
        #expect(Array(shape(t)[4...8]) == ["T ▾", "  a ▾", "    b › c ▾", "      d", "    side"])
        t.options.compactChains = false
        #expect(Array(shape(t)[4...9]) == ["T ▾", "  a ▾", "    b ▾", "      c ▾", "        d", "    side"])
    }

    /// Unlisted folders (the path shown before its listing) do not join: their one child is only the path's.
    @Test func unlistedFoldersDoNotJoin() {
        var t = tree
        _ = t.follow(.folder(url("/Volumes/T/a/b/c")))
        #expect(Array(shape(t)[4...7]) == ["T ▾", "  a ▾", "    b ▾", "      c"])
    }

    /// Deep enough, the tree starts again under one row of the folders left out; it stays while the current folder
    /// moves within reach, and the row opens the last folder left out.
    @Test func deepCurrentFolderRestartsTheTree() {
        var t = tree
        t.options = .init(compactChains: false, rerootDepth: 4)
        _ = t.follow(.folder(url("/Volumes/T/a/b/c")))
        #expect(Array(shape(t)[4...8]) == ["T ▾", "  a ▾", "    b ▾", "      c", "Best"])
        _ = t.follow(.folder(url("/Volumes/T/a/b/c/d/e")))
        deep(&t)
        #expect(Array(shape(t)[4...8]) == ["T ▾", "  a › b › c", "  d ▾", "    e", "Best"])
        guard case .row(let trail, 1, false, false) = t.lines[5] else { Issue.record("no trail row"); return }
        #expect(trail.location == .folder(url("/Volumes/T/a/b/c")))
        #expect(t.currentLine == 7)
        _ = t.follow(.folder(url("/Volumes/T/a/b/c/d/e/f")))
        #expect(shape(t)[5] == "  a › b › c")
        #expect(t.currentLine == 8)
        _ = t.follow(.folder(url("/Volumes/T/a/b/c/d/e/f/g")))
        #expect(shape(t)[5] == "  a › b › c › d › e")
        #expect(shape(t)[6] == "  f ▾")
        _ = t.follow(.folder(url("/Volumes/T/a/b")))
        #expect(Array(shape(t)[4...7]) == ["T ▾", "  a ▾", "    b ▾", "      c ▾"])
        t.options.rerootDepth = 0
        _ = t.follow(.folder(url("/Volumes/T/a/b/c/d/e/f/g")))
        #expect(shape(t)[5] == "  a ▾")
    }
}
