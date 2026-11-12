import Foundation

/// The same ordered folders can appear as sidebar shortcuts and as cards in Favorites.
public enum HomeFavorites {
    public static let sourceID = "favorites"

    public static func locationHints(for folders: [URL], volumes: [(url: URL, name: String)],
                              startupDisk: String) -> [URL: String] {
        let names = Dictionary(grouping: folders) { folder in
            folder.path == "/" ? startupDisk : folder.lastPathComponent
        }
        let roots = volumes.filter { $0.url.path != "/" }.map { ($0.url.standardizedFileURL.path, $0.name) }
            .sorted { $0.0.count > $1.0.count }

        var hints: [URL: String] = [:]
        for matches in names.values where matches.count > 1 {
            let byVolume = Dictionary(grouping: matches) { folder in
                let path = folder.standardizedFileURL.path
                if let root = roots.first(where: { path == $0.0 || path.hasPrefix($0.0 + "/") }) { return root.1 }
                let parts = folder.standardizedFileURL.pathComponents
                if parts.count >= 3, parts[1] == "Volumes" { return parts[2] }
                return startupDisk
            }
            for (volume, paths) in byVolume {
                for folder in paths {
                    let suffix = paths.count == 1 ? volume : "\(volume) · \(folder.deletingLastPathComponent().path)"
                    hints[folder] = suffix
                }
            }
        }
        return hints
    }

    public static var sourceRow: HomeSidebarRow {
        HomeSidebarRow(id: sourceID, title: "Favorites", symbol: "star", location: .source(sourceID))
    }

    public static func entries(from rows: [HomeSidebarRow]) -> [BrowserEntry] {
        rows.compactMap { row in
            guard case .folder(let url) = row.location else { return nil }
            return BrowserEntry(url: url, name: row.title, kind: .folder, isDimmed: row.isDimmed,
                                subtitle: row.locationHint)
        }
    }
}
