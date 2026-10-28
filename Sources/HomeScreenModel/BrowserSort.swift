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
        // The order is found on small keys, the entries moved once (Loupe, 2026-10-28: sorting the entries themselves
        // moved and compared the large structs through generic code, ~190 ms for 50 000 photos by date).
        let keys = entries.indices.map { i in
            let e = entries[i]
            let value: Double? = switch key {
            case .name: nil
            case .date: e.date?.timeIntervalSinceReferenceDate
            case .size: e.size.map(Double.init)
            }
            return SortKey(index: i, leads: e.leads, isFile: e.isFile, value: value)
        }
        return keys.sorted { a, b in less(a, b, entries) }.map { entries[$0.index] }
    }

    /// What `less` needs of an entry without touching it: the value of the key (a size as a Double is exact far past
    /// any file's size).
    private struct SortKey {
        let index: Int
        let leads: Bool
        let isFile: Bool
        let value: Double?
    }

    private func less(_ a: SortKey, _ b: SortKey, _ entries: [BrowserEntry]) -> Bool {
        if a.leads != b.leads { return a.leads }
        if a.isFile != b.isFile { return !a.isFile }
        switch (key, a.value, b.value) {
        case (.name, _, _):
            let order = Self.compareNames(entries[a.index], entries[b.index])
            return ascending ? order == .orderedAscending : order == .orderedDescending
        case let (_, x?, y?) where x != y: return ascending ? x < y : x > y
        case (_, _?, nil): return true
        case (_, nil, _?): return false
        default: return Self.compareNames(entries[a.index], entries[b.index]) == .orderedAscending
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
