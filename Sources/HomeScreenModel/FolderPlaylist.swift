import Foundation

/// The files of one folder in its `BrowserSort` order, as Home's grid shows them, and the position among them: what a
/// viewer or a player steps through, so a step goes where the grid's next card is however the file was opened. The
/// app reads the folder (its own file types, its own listing) and keeps the folder's sort; this only orders.
public struct FolderPlaylist: Equatable, Sendable {
    public let folder: URL
    public private(set) var sort: BrowserSort
    /// The listing's files (`isFile`), URLs standardized, in `sort` order.
    public private(set) var files: [BrowserEntry]
    public private(set) var index: Int

    public var current: BrowserEntry { files[index] }
    public var urls: [URL] { files.map(\.url) }

    /// `entries` as the grid has them (folders and archives are left out); `current` is always in the list, with a
    /// name-only entry of its own when the listing does not have it (a hidden or odd file opened by name, a listing
    /// not in yet).
    public init(folder: URL, entries: [BrowserEntry], sort: BrowserSort, current: URL) {
        self.folder = folder.standardizedFileURL
        self.sort = sort
        let me = current.standardizedFileURL
        var files = Self.files(of: entries)
        if !files.contains(where: { $0.url == me }) {
            files.append(BrowserEntry(url: me, name: me.lastPathComponent, kind: .file))
        }
        self.files = sort.order(files)
        index = self.files.firstIndex { $0.url == me } ?? 0
    }

    /// Moves by `step` files; false and no change past either end (no wrapping).
    public mutating func move(by step: Int) -> Bool {
        let (target, overflow) = index.addingReportingOverflow(step)
        guard !overflow, files.indices.contains(target) else { return false }
        index = target
        return true
    }

    /// Moves to `url`; false when it is not in the list.
    public mutating func move(to url: URL) -> Bool {
        let wanted = url.standardizedFileURL
        guard let found = files.firstIndex(where: { $0.url == wanted }) else { return false }
        index = found
        return true
    }

    /// `from`, or the first index beyond it in the direction of `step` whose file `skipping` does not refuse (a file
    /// the decoders cannot read); nil past either end.
    public func index(from: Int, step: Int, skipping: (BrowserEntry) -> Bool) -> Int? {
        let direction = step < 0 ? -1 : 1
        var i = from
        while files.indices.contains(i), skipping(files[i]) { i += direction }
        return files.indices.contains(i) ? i : nil
    }

    /// The same files in `sort`'s order, on the same file.
    public mutating func resort(_ sort: BrowserSort) {
        let me = current.url
        self.sort = sort
        files = sort.order(files)
        index = files.firstIndex { $0.url == me } ?? 0
    }

    /// A newer listing of the folder (the names, then their attributes, then a change): the current file stays by
    /// URL; one that is gone leaves the file now at its index (clamped) current. A listing without files keeps the
    /// current one alone.
    public mutating func replace(entries: [BrowserEntry]) {
        let me = current.url
        let ordered = sort.order(Self.files(of: entries))
        guard !ordered.isEmpty else {
            files = [current]
            index = 0
            return
        }
        files = ordered
        index = files.firstIndex { $0.url == me } ?? min(index, files.count - 1)
    }

    private static func files(of entries: [BrowserEntry]) -> [BrowserEntry] {
        entries.compactMap { entry in
            guard entry.isFile else { return nil }
            var entry = entry
            entry.url = entry.url.standardizedFileURL
            return entry
        }
    }
}
