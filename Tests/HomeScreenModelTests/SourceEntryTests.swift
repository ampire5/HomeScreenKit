import Foundation
import Testing
@testable import HomeScreenModel

@Suite struct SourceEntryTests {
    private func collection(_ name: String, date: Double, leads: Bool = false) -> BrowserEntry {
        BrowserEntry(url: URL(fileURLWithPath: "/r/\(name)"), name: name, kind: .collection,
                     date: Date(timeIntervalSinceReferenceDate: date), leads: leads)
    }

    @Test func sourceLocationsEqualByID() {
        #expect(BrowserLocation.source("recent") == .source("recent"))
        #expect(BrowserLocation.source("recent") != .source("sessions"))
        #expect(BrowserLocation.source("recent") != .folder(URL(fileURLWithPath: "/recent")))
        #expect(BrowserLocation.source("recent") != .places)
        let set: Set<BrowserLocation> = [.source("recent"), .source("recent"), .source("sessions")]
        #expect(set.count == 2)
    }

    @Test func keyOverridesPath() {
        let keyed = BrowserEntry(url: URL(string: "loupe-session:5")!, name: "S", kind: .collection, key: "session:5")
        #expect(keyed.id == "session:5")
        let plain = BrowserEntry(url: URL(fileURLWithPath: "/a/b"), name: "b", kind: .folder)
        #expect(plain.id == "/a/b")
    }

    @Test func leadsComeFirst() {
        let items = [collection("b", date: 2), collection("Last", date: 1, leads: true), collection("a", date: 3)]
        #expect(BrowserSort(key: .date, ascending: false).order(items).map(\.name) == ["Last", "a", "b"])
        #expect(BrowserSort(key: .name, ascending: true).order(items).map(\.name) == ["Last", "a", "b"])
        #expect(BrowserSort(key: .name, ascending: false).order(items).map(\.name) == ["Last", "b", "a"])
    }

    @Test func collectionsAreNotEntered() {
        let e = collection("x", date: 0)
        #expect(!e.isContainer)
        #expect(!e.isFile)
        #expect(BrowserEntry(url: URL(fileURLWithPath: "/f.jpg"), name: "f.jpg", kind: .file).isFile)
    }

    @Test func footerWithNoun() {
        let three = (0..<3).map { collection("s\($0)", date: Double($0)) }
        #expect(BrowserSummary.footer(entries: three, filtered: nil, complete: true, more: false, noun: "session").line
                == "3 sessions")
        #expect(BrowserSummary.footer(entries: [three[0]], filtered: nil, complete: true, more: false, noun: "session").line
                == "1 session")
        let mixed = [BrowserEntry(url: URL(fileURLWithPath: "/a"), name: "a", kind: .folder),
                     BrowserEntry(url: URL(fileURLWithPath: "/b"), name: "b", kind: .folder),
                     BrowserEntry(url: URL(fileURLWithPath: "/c.jpg"), name: "c.jpg", kind: .file)]
        #expect(BrowserSummary.footer(entries: mixed, filtered: nil, complete: true, more: false).line == "1 photo · 2 folders")
    }
}
