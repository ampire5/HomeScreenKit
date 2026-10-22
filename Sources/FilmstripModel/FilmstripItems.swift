import Foundation

/// The strip across a change of its items (a listing that arrives in parts, a folder watcher, a re-read).
public enum FilmstripItems {
    /// Each old index's place in the new list, by URL; items that went have none. A list that only grew at its end
    /// maps without hashing.
    public static func indexMap(from old: [URL], to new: [URL]) -> [Int: Int] {
        if new.starts(with: old) { return Dictionary(uniqueKeysWithValues: old.indices.map { ($0, $0) }) }
        var places: [URL: Int] = [:]
        places.reserveCapacity(new.count)
        for (index, url) in new.enumerated() where places[url] == nil { places[url] = index }
        var map: [Int: Int] = [:]
        for (index, url) in old.enumerated() { if let place = places[url] { map[index] = place } }
        return map
    }
}
