import Foundation
import Testing
@testable import HomeScreenModel

@Suite struct FolderPlaylistTests {
    private let folder = URL(fileURLWithPath: "/f")

    private func entry(_ name: String, _ kind: BrowserEntry.Kind = .file, date: Double? = nil,
                       size: Int64? = nil) -> BrowserEntry {
        BrowserEntry(url: folder.appendingPathComponent(name), name: name, kind: kind,
                     date: date.map { Date(timeIntervalSinceReferenceDate: $0) }, size: size)
    }

    private func url(_ name: String) -> URL { folder.appendingPathComponent(name) }

    private var mixed: [BrowserEntry] {
        [entry("img10", date: 5, size: 3), entry("img2", date: 9), entry("Img1", size: 7), entry("b", date: 5, size: 3),
         entry("a", date: 5, size: 3), entry("n"), entry("sub", .folder, date: 1), entry("x.zip", .archive, date: 2)]
    }

    @Test func orderIsTheGridsForEverySort() {
        for text in ["name", "name-desc", "date", "date-desc", "size", "size-desc"] {
            let sort = BrowserSort(text: text)!
            let list = FolderPlaylist(folder: folder, entries: mixed, sort: sort, current: url("a"))
            #expect(list.urls == sort.order(mixed).filter(\.isFile).map(\.url), "\(text)")
            #expect(list.current.url == url("a"))
        }
    }

    @Test func namesOnlyByDateGoByName() {   // the first listing has no dates: the grid shows it by name
        let names = [entry("c"), entry("a"), entry("b")]
        let list = FolderPlaylist(folder: folder, entries: names, sort: BrowserSort(text: "date-desc")!, current: url("b"))
        #expect(list.files.map(\.name) == ["a", "b", "c"])
        #expect(list.index == 1)
    }

    @Test func currentOutsideEntriesIsKept() {
        let list = FolderPlaylist(folder: folder, entries: [entry("a"), entry("c")], sort: .standard, current: url("b.odd"))
        #expect(list.files.map(\.name) == ["a", "b.odd", "c"])
        #expect(list.current.url == url("b.odd"))
        #expect(list.current.isFile)
    }

    @Test func urlsAreStandardized() {
        let list = FolderPlaylist(folder: folder, entries: [entry("a"), entry("b")], sort: .standard,
                                  current: URL(fileURLWithPath: "/f/./b"))
        #expect(list.files.count == 2)
        #expect(list.index == 1)
    }

    @Test func resortKeepsCurrent() {
        var list = FolderPlaylist(folder: folder, entries: mixed, sort: .standard, current: url("img2"))
        list.resort(BrowserSort(text: "date-desc")!)
        #expect(list.current.url == url("img2"))
        #expect(list.index == 0)
        #expect(list.sort == BrowserSort(text: "date-desc")!)
    }

    @Test func replaceKeepsCurrentByURL() {
        var list = FolderPlaylist(folder: folder, entries: [entry("b"), entry("c")], sort: .standard, current: url("c"))
        list.replace(entries: [entry("a"), entry("b"), entry("c")])
        #expect(list.current.url == url("c"))
        #expect(list.index == 2)
    }

    @Test func replaceWithoutCurrentKeepsIndex() {
        var middle = FolderPlaylist(folder: folder, entries: [entry("a"), entry("b"), entry("c"), entry("d")],
                                    sort: .standard, current: url("c"))
        middle.replace(entries: [entry("a"), entry("b"), entry("d")])
        #expect(middle.current.url == url("d"))
        var end = FolderPlaylist(folder: folder, entries: [entry("a"), entry("b")], sort: .standard, current: url("b"))
        end.replace(entries: [entry("a")])
        #expect(end.current.url == url("a"))
    }

    @Test func replaceWithNothingKeepsCurrent() {
        var list = FolderPlaylist(folder: folder, entries: [entry("a"), entry("b")], sort: .standard, current: url("b"))
        list.replace(entries: [])
        #expect(list.urls == [url("b")])
    }

    @Test func moveStopsAtEnds() {
        var list = FolderPlaylist(folder: folder, entries: [entry("a"), entry("b")], sort: .standard, current: url("a"))
        let moves = [list.move(by: -1), list.move(by: 1), list.move(by: 1), list.move(by: .max)]
        #expect(moves == [false, true, false, false])
        #expect(list.current.url == url("b"))
    }

    @Test func moveTo() {
        var list = FolderPlaylist(folder: folder, entries: [entry("a"), entry("b")], sort: .standard, current: url("a"))
        let found = list.move(to: URL(fileURLWithPath: "/f/./b"))
        #expect(found && list.index == 1)
        let unknown = list.move(to: url("zz"))
        #expect(!unknown && list.index == 1)
    }
}
