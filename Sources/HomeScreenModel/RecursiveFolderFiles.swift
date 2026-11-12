import Foundation

/// Files beneath a real folder, using the host's supported media extensions.
/// The caller runs this blocking walk on a background worker.
public enum RecursiveFolderFiles {
    public static func read(in folder: URL, extensions: Set<String>,
                            cancelled: () -> Bool = { false }) throws -> [BrowserEntry] {
        let root = folder.resolvingSymlinksInPath()
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]
        var rootError: Error?
        guard let walk = manager.enumerator(at: root, includingPropertiesForKeys: Array(keys),
                                            options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                            errorHandler: { url, error in
            guard url.resolvingSymlinksInPath().standardizedFileURL.path == root.standardizedFileURL.path else { return true }
            rootError = error
            return false
        }) else { throw CocoaError(.fileReadUnknown) }

        var entries: [BrowserEntry] = []
        while !cancelled(), let url = walk.nextObject() as? URL {
            guard extensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let relative = url.pathComponents.suffix(walk.level)
            let visibleURL = relative.reduce(folder) { $0.appendingPathComponent($1) }
            entries.append(BrowserEntry(url: visibleURL, name: url.lastPathComponent, kind: .file,
                                        date: values.contentModificationDate, size: values.fileSize.map(Int64.init),
                                        canRename: true, canTrash: true))
        }
        if cancelled() { throw CancellationError() }
        if let rootError { throw rootError }
        return entries
    }
}
