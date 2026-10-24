import Foundation

/// How a folder is ordered (`browser-sort`: `name`, `name-desc`, `date`, `date-desc`, `size`, `size-desc`). Folders and
/// archives (anything but files) always come first, each group ordered by the key; an entry that `leads` comes before
/// all. Names are in Finder order ("img2" before "img10"); equal
/// dates or sizes go by name, ascending whatever the direction, and entries without the value come last, by name.
public struct BrowserSort: Equatable, Sendable {
    public enum Key: String, CaseIterable, Sendable {
        case name, date, size
    }

    public var key: Key
    public var ascending: Bool

    public static let standard = BrowserSort(key: .name, ascending: true)

    public init(key: Key, ascending: Bool) {
        self.key = key
        self.ascending = ascending
    }

    public init?(text: String) {
        let descending = text.hasSuffix("-desc")
        guard let key = Key(rawValue: descending ? String(text.dropLast(5)) : text) else { return nil }
        self.init(key: key, ascending: !descending)
    }

    public var text: String { ascending ? key.rawValue : key.rawValue + "-desc" }

    public func order(_ entries: [BrowserEntry]) -> [BrowserEntry] {
        entries.sorted(by: less)
    }

    private func less(_ a: BrowserEntry, _ b: BrowserEntry) -> Bool {
        if a.leads != b.leads { return a.leads }
        if a.isFile != b.isFile { return !a.isFile }
        switch key {
        case .name:
            let order = Self.compareNames(a, b)
            return ascending ? order == .orderedAscending : order == .orderedDescending
        case .date:
            return valueLess(a.date, b.date, a, b)
        case .size:
            return valueLess(a.size, b.size, a, b)
        }
    }

    /// By the value in this direction; a tie or two missing values by name; a missing value after any present one.
    private func valueLess<T: Comparable>(_ x: T?, _ y: T?, _ a: BrowserEntry, _ b: BrowserEntry) -> Bool {
        switch (x, y) {
        case let (x?, y?) where x != y: return ascending ? x < y : x > y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return Self.compareNames(a, b) == .orderedAscending
        }
    }

    /// Finder order on the name; the full path breaks ties.
    private static func compareNames(_ a: BrowserEntry, _ b: BrowserEntry) -> ComparisonResult {
        let order = a.name.localizedStandardCompare(b.name)
        if order != .orderedSame { return order }
        return a.id < b.id ? .orderedAscending : a.id > b.id ? .orderedDescending : .orderedSame
    }
}

/// The sort controls' memory: choosing the active field reverses it, choosing another field takes that field's
/// last direction in this view, or its first one (name ascending, date and size descending, newest and largest first).
public struct BrowserSortChoice: Equatable, Sendable {
    public private(set) var current: BrowserSort
    private var directions: [BrowserSort.Key: Bool]

    public init(current: BrowserSort) {
        self.current = current
        directions = [current.key: current.ascending]
    }

    public mutating func choose(_ key: BrowserSort.Key) -> BrowserSort {
        let ascending = key == current.key ? !current.ascending : directions[key] ?? (key == .name)
        current = BrowserSort(key: key, ascending: ascending)
        directions[key] = ascending
        return current
    }
}
