import Foundation
import Testing
@testable import HomeScreenModel

@Suite struct BrowserSummaryTests {
    private func file(_ name: String, size: Int64? = nil, date: Date? = nil) -> BrowserEntry {
        BrowserEntry(url: URL(fileURLWithPath: "/f/\(name)"), name: name, kind: .file, date: date, size: size)
    }

    private func folder(_ name: String) -> BrowserEntry {
        BrowserEntry(url: URL(fileURLWithPath: "/f/\(name)"), name: name, kind: .folder)
    }

    private func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

    @Test func footerCountsAndSize() {
        let entries = [folder("a"), folder("b"), file("1.jpg", size: 1_000_000), file("2.jpg", size: 800_000)]
        let footer = BrowserSummary.footer(entries: entries, filtered: nil, complete: true, more: false)
        #expect(footer.line == "2 photos · 2 folders · \(bytes(1_800_000))")
        #expect(footer.state == nil)
    }

    @Test func footerDropsZeroParts() {
        #expect(BrowserSummary.footer(entries: [folder("a")], filtered: nil, complete: true, more: false).line == "1 folder")
        #expect(BrowserSummary.footer(entries: [file("1", size: 0)], filtered: nil, complete: true, more: false).line == "1 photo")
        #expect(BrowserSummary.footer(entries: [], filtered: nil, complete: true, more: false).line == "")
    }

    @Test func footerSizeOnlyWhenComplete() {
        let entries = [file("1.jpg", size: 5_000)]
        #expect(BrowserSummary.footer(entries: entries, filtered: nil, complete: false, more: false).line == "1 photo")
    }

    @Test func footerStates() {
        let entries = (0..<1200).map { file("\($0).jpg") }
        let n = BrowserSummary.number
        #expect(BrowserSummary.footer(entries: entries, filtered: nil, complete: false, more: true).state
                == "Listing is slow — \(n(1200)) so far")
        #expect(BrowserSummary.footer(entries: entries, filtered: 37, complete: true, more: false).state
                == "Filter: 37 of \(n(1200))")
        #expect(BrowserSummary.footer(entries: entries, filtered: nil, complete: false, more: false).line
                == "\(n(1200)) photos")
    }

    @Test func subtitleSelectedFile() {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour) = (2026, 10, 18, 12)
        let date = Calendar.current.date(from: c)!
        let selected = file("x.jpg", size: 24_000_000, date: date)
        #expect(BrowserSummary.subtitle(selected: selected, entries: [selected], loading: nil)
                == "x.jpg · \(bytes(24_000_000)) · 18 Oct 2026")
        #expect(BrowserSummary.subtitle(selected: folder("a"), entries: [], loading: nil) == "a")
        #expect(BrowserSummary.subtitle(selected: nil, entries: [selected], loading: nil) == "1 photo · \(bytes(24_000_000))")
    }

    @Test func subtitleWhileLoading() {
        #expect(BrowserSummary.subtitle(selected: nil, entries: [], loading: 1200)
                == "Loading… \(BrowserSummary.number(1200))")
    }

    @Test func selectionDetailsIncludeFolderContents() {
        var entry = folder("Album")
        entry.summary = CardSummary(photos: 12, folders: 2, bytes: 12_000)
        #expect(BrowserSummary.selection(entry) == "Album · 12 photos · 2 folders · \(bytes(12_000))")
        #expect(BrowserSummary.selection(nil).isEmpty)
    }

    @Test func pluralForms() {
        #expect(BrowserSummary.footer(entries: [file("1")], filtered: nil, complete: false, more: false).line == "1 photo")
        #expect(BrowserSummary.footer(entries: [file("1"), file("2")], filtered: nil, complete: false, more: false).line
                == "2 photos")
        #expect(BrowserSummary.footer(entries: [folder("a"), folder("b")], filtered: nil, complete: false, more: false).line
                == "2 folders")
    }
}
