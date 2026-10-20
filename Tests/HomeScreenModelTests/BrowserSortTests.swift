import Foundation
import Testing
@testable import HomeScreenModel

@Suite struct BrowserSortTests {
    private func entry(_ name: String, _ kind: BrowserEntry.Kind = .file, date: Double? = nil,
                       size: Int64? = nil) -> BrowserEntry {
        BrowserEntry(url: URL(fileURLWithPath: "/f/\(name)"), name: name, kind: kind,
                     date: date.map { Date(timeIntervalSinceReferenceDate: $0) }, size: size)
    }

    @Test func textRoundTrip() {
        for text in ["name", "name-desc", "date", "date-desc", "size", "size-desc"] {
            #expect(BrowserSort(text: text)?.text == text)
        }
        for bad in ["Name", "date-up", ""] { #expect(BrowserSort(text: bad) == nil) }
        #expect(BrowserSort.standard.text == "name")
    }

    @Test func naturalNames() {
        let sorted = BrowserSort.standard.order([entry("img10"), entry("img2"), entry("Img1")])
        #expect(sorted.map(\.name) == ["Img1", "img2", "img10"])
    }

    @Test func foldersFirst() {
        let items = [entry("b"), entry("z", .folder), entry("a.zip", .archive)]
        #expect(BrowserSort.standard.order(items).map(\.name) == ["a.zip", "z", "b"])
        #expect(BrowserSort(text: "name-desc")!.order(items).map(\.name) == ["z", "a.zip", "b"])
    }

    @Test func dateDescTieByName() {
        let items = [entry("b", date: 5), entry("a", date: 5), entry("c", date: 9), entry("n")]
        #expect(BrowserSort(text: "date-desc")!.order(items).map(\.name) == ["c", "a", "b", "n"])
        #expect(BrowserSort(text: "date")!.order(items).map(\.name) == ["a", "b", "c", "n"])
    }

    @Test func sizeNilLast() {
        let items = [entry("y"), entry("big", size: 10), entry("x"), entry("small", size: 1)]
        #expect(BrowserSort(text: "size")!.order(items).map(\.name) == ["small", "big", "x", "y"])
        #expect(BrowserSort(text: "size-desc")!.order(items).map(\.name) == ["big", "small", "x", "y"])
    }

    @Test func idIsPath() {
        #expect(entry("a.jpg").id == "/f/a.jpg")
    }

    @Test func choiceReversesActiveKey() {
        var choice = BrowserSortChoice(current: BrowserSort(key: .date, ascending: false))
        #expect(choice.choose(.date) == BrowserSort(key: .date, ascending: true))
        #expect(choice.choose(.date) == BrowserSort(key: .date, ascending: false))
        #expect(choice.current == BrowserSort(key: .date, ascending: false))
    }

    @Test func choiceFirstDirections() {
        var choice = BrowserSortChoice(current: BrowserSort(key: .size, ascending: true))
        #expect(choice.choose(.name) == BrowserSort(key: .name, ascending: true))
        #expect(choice.choose(.date) == BrowserSort(key: .date, ascending: false))
        choice = BrowserSortChoice(current: .standard)
        #expect(choice.choose(.size) == BrowserSort(key: .size, ascending: false))
    }

    @Test func choiceRemembersDirectionPerKey() {
        var choice = BrowserSortChoice(current: .standard)
        #expect(choice.choose(.date) == BrowserSort(key: .date, ascending: false))
        #expect(choice.choose(.date) == BrowserSort(key: .date, ascending: true))
        #expect(choice.choose(.name) == BrowserSort(key: .name, ascending: true))
        #expect(choice.choose(.date) == BrowserSort(key: .date, ascending: true))
    }
}
