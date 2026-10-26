import Foundation

/// The files the decoders could not read (not a read that failed: a share that went away is tried again), for this
/// run of the app: Home's grid draws them faint, and steps through a folder go past them. Each is kept with the date
/// and size it had, so a file changed since (replaced, mended) is unknown again. One per app; main thread only.
@MainActor public final class UnreadableFiles {
    /// A watcher of the marks; it is called while its observation is kept.
    public final class Observation {
        fileprivate let id: Int
        fileprivate weak var files: UnreadableFiles?

        fileprivate init(id: Int, files: UnreadableFiles) {
            self.id = id
            self.files = files
        }

        deinit {
            let id = id, files = files
            MainActor.assumeIsolated { files?.observers[id] = nil }
        }
    }

    private struct Version: Equatable {
        var date: Date?
        var size: Int64?
    }

    private var marked: [URL: Version] = [:]
    private var observers: [Int: (Set<URL>) -> Void] = [:]
    private var nextObserver = 0

    public init() {}

    /// `url` cannot be read by the decoders, as it was at `date` and `size` (nil when not known).
    public func mark(_ url: URL, date: Date?, size: Int64?) {
        let url = url.standardizedFileURL, version = Version(date: date, size: size)
        guard marked[url] != version else { return }
        marked[url] = version
        changed([url])
    }

    /// `url` was read after all.
    public func clear(_ url: URL) {
        let url = url.standardizedFileURL
        guard marked.removeValue(forKey: url) != nil else { return }
        changed([url])
    }

    /// Marked, and not changed since: a date or size known on both sides must be the same.
    public func contains(_ url: URL, date: Date?, size: Int64?) -> Bool {
        guard let version = marked[url.standardizedFileURL] else { return false }
        if let a = version.date, let b = date, a != b { return false }
        if let a = version.size, let b = size, a != b { return false }
        return true
    }

    public func contains(_ entry: BrowserEntry) -> Bool {
        entry.isFile && contains(entry.url, date: entry.date, size: entry.size)
    }

    /// `change` gets the URLs whose mark came or went, at once, for as long as the observation is kept.
    public func observe(_ change: @escaping (Set<URL>) -> Void) -> Observation {
        nextObserver += 1
        observers[nextObserver] = change
        return Observation(id: nextObserver, files: self)
    }

    private func changed(_ urls: Set<URL>) {
        for observer in observers.values { observer(urls) }
    }
}
