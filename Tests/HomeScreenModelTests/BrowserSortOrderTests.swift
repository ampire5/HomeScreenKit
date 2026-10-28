import Foundation
import Testing
@testable import HomeScreenModel

// `BrowserSort.order` finds the order on small keys (Loupe, 2026-10-28): the same order as comparing the entries.

/// The order as it was found before: the entries compared themselves.
private func reference(_ sort: BrowserSort, _ entries: [BrowserEntry]) -> [BrowserEntry] {
    func names(_ a: BrowserEntry, _ b: BrowserEntry) -> ComparisonResult {
        let order = a.name.localizedStandardCompare(b.name)
        if order != .orderedSame { return order }
        return a.id < b.id ? .orderedAscending : a.id > b.id ? .orderedDescending : .orderedSame
    }
    func value<T: Comparable>(_ x: T?, _ y: T?, _ a: BrowserEntry, _ b: BrowserEntry) -> Bool {
        switch (x, y) {
        case let (x?, y?) where x != y: return sort.ascending ? x < y : x > y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return names(a, b) == .orderedAscending
        }
    }
    return entries.sorted { a, b in
        if a.leads != b.leads { return a.leads }
        if a.isFile != b.isFile { return !a.isFile }
        switch sort.key {
        case .name:
            let order = names(a, b)
            return sort.ascending ? order == .orderedAscending : order == .orderedDescending
        case .date: return value(a.date, b.date, a, b)
        case .size: return value(a.size, b.size, a, b)
        }
    }
}

@Test func theOrderOnKeysIsTheEntriesOrder() {
    var state: UInt64 = 2026_10_28
    func next(_ n: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int(state >> 33) % n
    }
    let kinds: [BrowserEntry.Kind] = [.file, .file, .file, .folder]
    for _ in 0..<40 {
        // Few distinct names, dates and sizes, some missing: ties everywhere.
        let entries = (0..<60).map { i -> BrowserEntry in
            let name = ["img\(next(12)).jpg", "IMG\(next(12)).jpg", "a b.jpg"][next(3)]
            return BrowserEntry(url: URL(fileURLWithPath: "/f/\(i)/\(name)"), name: name, kind: kinds[next(4)],
                                date: next(4) == 0 ? nil : Date(timeIntervalSinceReferenceDate: Double(next(5))),
                                size: next(4) == 0 ? nil : Int64(next(5)), leads: next(20) == 0)
        }
        for sort in BrowserSort.Key.allCases.flatMap({ [BrowserSort(key: $0, ascending: true), BrowserSort(key: $0, ascending: false)] }) {
            #expect(sort.order(entries).map(\.url) == reference(sort, entries).map(\.url))
        }
    }
}

@Test func quicklyStandardizedIsStandardized() {
    let paths = ["/a/b.jpg", "/a/./b.jpg", "/a/../b.jpg", "/a//b.jpg", "/a/b/", "/a/.hidden.jpg", "/a/b.jpg/.",
                 "/a/b.jpg/..", "/Volumes/x y/é.jpg", "/a/b%20c.jpg", "/a/..b.jpg", "/"]
    for path in paths {
        for url in [URL(fileURLWithPath: path), URL(fileURLWithPath: path, isDirectory: false),
                    URL(fileURLWithPath: "/root").appendingPathComponent(String(path.dropFirst()))] {
            #expect(url.quicklyStandardized == url.standardizedFileURL, "\(url)")
        }
    }
    // Under /private, standardizing drops it where the path exists without it.
    let temporary = URL(fileURLWithPath: "/private" + FileManager.default.temporaryDirectory.path).appendingPathComponent("x.jpg")
    #expect(temporary.path.hasPrefix("/private/"))
    try? Data().write(to: temporary)
    defer { try? FileManager.default.removeItem(at: temporary) }
    #expect(temporary.quicklyStandardized == temporary.standardizedFileURL)
    let relative = URL(fileURLWithPath: "b.jpg", relativeTo: URL(fileURLWithPath: "/a/"))
    #expect(relative.quicklyStandardized == relative.standardizedFileURL)
    let web = URL(string: "https://example.com/a/../b")!
    #expect(web.quicklyStandardized == web.standardizedFileURL)
}
