import Foundation

/// The recursive listing's portable SQLite payload, relative to its root.
public enum RecursiveListingSnapshot {
    public static let capacity = 32
    public static let maxBytes = 2 * 1024 * 1024

    private struct Row: Codable {
        var path: [String]
        var date: Date?
        var size: Int64?
    }

    public static func encode(_ entries: [BrowserEntry], in folder: URL) -> Data? {
        let root = folder.standardizedFileURL.pathComponents
        let rows = entries.compactMap { entry -> Row? in
            let parts = entry.url.standardizedFileURL.pathComponents
            guard entry.isFile, parts.count > root.count, parts.starts(with: root) else { return nil }
            return Row(path: Array(parts.dropFirst(root.count)), date: entry.date, size: entry.size)
        }
        guard let data = try? JSONEncoder().encode(rows), data.count <= maxBytes else { return nil }
        return data
    }

    public static func decode(_ data: Data, in folder: URL) -> [BrowserEntry]? {
        guard data.count <= maxBytes, let rows = try? JSONDecoder().decode([Row].self, from: data) else { return nil }
        return rows.compactMap { row in
            guard let name = row.path.last, row.path.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") })
            else { return nil }
            let url = row.path.reduce(folder) { $0.appendingPathComponent($1) }
            return BrowserEntry(url: url, name: name, kind: .file, date: row.date, size: row.size)
        }
    }
}
