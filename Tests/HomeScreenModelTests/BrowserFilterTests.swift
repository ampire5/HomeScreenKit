import Foundation
import Testing
@testable import HomeScreenModel

@Suite struct BrowserFilterTests {
    private func entry(_ name: String, _ kind: BrowserEntry.Kind = .file) -> BrowserEntry {
        BrowserEntry(url: URL(fileURLWithPath: "/f/\(name)"), name: name, kind: kind)
    }

    private var mixed: [BrowserEntry] { [entry("a", .folder), entry("b.zip", .archive), entry("c.jpg"), entry("d.png")] }

    @Test func kindFilters() {
        #expect(BrowserFilter(kind: .all).apply(mixed).map(\.name) == ["a", "b.zip", "c.jpg", "d.png"])
        #expect(BrowserFilter(kind: .folders).apply(mixed).map(\.name) == ["a", "b.zip"])
        #expect(BrowserFilter(kind: .photos).apply(mixed).map(\.name) == ["c.jpg", "d.png"])
        #expect(BrowserKindFilter.allCases.map(\.title) == ["All", "Folders", "Photos"])
    }

    @Test func textIsCaseAndDiacriticInsensitive() {
        let entries = [entry("e\u{301}clair.jpg"), entry("\u{e9}clair.jpg"), entry("other.jpg")]
        #expect(BrowserFilter(text: "ECL").apply(entries).count == 2)
        #expect(BrowserFilter(text: "\u{e9}cl").apply(entries).count == 2)
        #expect(BrowserFilter(text: "e\u{301}cl").apply(entries).count == 2)
    }

    @Test func textKeepsOrder() {
        let entries = [entry("z1"), entry("a1"), entry("m1"), entry("x")]
        #expect(BrowserFilter(text: "1").apply(entries).map(\.name) == ["z1", "a1", "m1"])
    }

    @Test func emptyTextIsInactive() {
        #expect(!BrowserFilter().isActive)
        #expect(!BrowserFilter(text: "  ").isActive)
        #expect(BrowserFilter(text: "a").isActive)
        #expect(BrowserFilter(kind: .photos).isActive)
        #expect(BrowserFilter(text: " ").apply(mixed).count == 4)
    }
}
