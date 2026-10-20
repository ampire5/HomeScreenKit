import AppKit
import HomeScreenKit

/// A made-up Home for the demo: a disk with a few folders, one of 10 000 files and 30 subfolders, and one that cannot be
/// listed (names come first, dates and sizes half a second later; rename and trash change the tree); Recent over three
/// date groups, Sessions with Last Session first, the places with their free space, and a coloured page for Stash.
@MainActor final class DemoBrowserSource: HomeSource {
    weak var view: HomeBrowserView?
    /// Stash's page: a plain coloured view.
    let page: NSView = {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.2, alpha: 1).cgColor
        return v
    }()
    /// Seconds the huge folder sends nothing (`HOMESCREEN_SLOW_START`).
    static var slowStart = Double(ProcessInfo.processInfo.environment["HOMESCREEN_SLOW_START"] ?? "") ?? 1
    private var tree: [String: [BrowserEntry]] = [:]
    private var sorts: [String: BrowserSort] = [:]
    private let root = URL(fileURLWithPath: "/Demo")

    init() {
        let huge = root.appendingPathComponent("Huge")
        tree[root.path] = ["Huge", "Mixed", "Small", "Broken"].map { folder($0, in: root) }
        // Photos and Aspect's bands: 12 folders and 2 000 photos, landscape, portrait and square.
        let mixed = root.appendingPathComponent("Mixed")
        tree[mixed.path] = (0..<12).map { folder("Album \($0)", in: mixed) } + (0..<2_000).map { file("DSC_\($0).jpg", in: mixed, $0) }
        tree[huge.path] = (0..<30).map { folder("Set \($0)", in: huge) } + (0..<10_000).map { file("IMG_\($0).jpg", in: huge, $0) }
        let small = root.appendingPathComponent("Small")
        tree[small.path] = (0..<12).map { file("photo \($0).jxl", in: small, $0) }
        for i in 0..<30 {
            let set = huge.appendingPathComponent("Set \(i)")
            tree[set.path] = (0..<(i + 1) * 3).map { file("\(i)-\($0).jpg", in: set, $0) }
        }
    }

    private func folder(_ name: String, in parent: URL) -> BrowserEntry {
        BrowserEntry(url: parent.appendingPathComponent(name), name: name, kind: .folder, count: name == "Broken" ? nil : 12,
                     canRename: true, canTrash: true)
    }

    private func file(_ name: String, in parent: URL, _ n: Int) -> BrowserEntry {
        BrowserEntry(url: parent.appendingPathComponent(name), name: name, kind: .file,
                     date: Date(timeIntervalSinceReferenceDate: 700_000_000 + Double(n * 3_600)), size: Int64(1_000_000 + n * 977),
                     canRename: true, canTrash: true)
    }

    func places() async -> [BrowserEntry] {
        [BrowserEntry(url: root, name: "Demo Disk", kind: .place, subtitle: "1.2 TB free"),
         BrowserEntry(url: URL(fileURLWithPath: "/Gone"), name: "Unplugged", kind: .place, isDimmed: true)]
    }

    private var recent: [BrowserEntry] {
        let now = Date()
        return (0..<9).map { i in
            let ago: Double = i < 3 ? Double(i) * 3_600 : i < 5 ? 86_400 + Double(i) * 600 : Double(i) * 7 * 86_400
            return BrowserEntry(url: root.appendingPathComponent("Folder \(i)"), name: "Folder \(i)", kind: .collection,
                                date: now.addingTimeInterval(-ago), isDimmed: i == 4, key: "recent:\(i)",
                                subtitle: "\(i * 13 + 1) / 120 · \(i < 3 ? "\(i) h ago" : "18 Oct")",
                                progress: Double(i * 13 + 1) / 120, badge: i == 2 ? "Stash" : nil)
        }
    }

    private var sessions: [BrowserEntry] {
        ["Last Session", "Work", "Trip"].enumerated().map { i, name in
            BrowserEntry(url: URL(string: "demo-session:\(i)")!, name: name, kind: .collection,
                         date: Date().addingTimeInterval(-Double(i) * 86_400), key: "session:\(i)",
                         subtitle: "\(i + 1) window\(i == 0 ? "" : "s") · \(i + 3) tabs", badge: i == 0 ? "Last" : nil,
                         leads: i == 0)
        }
    }

    func list(_ location: BrowserLocation) -> AsyncThrowingStream<BrowserListing, Error> {
        switch location {
        case .places:
            return AsyncThrowingStream { continuation in
                Task { @MainActor in continuation.yield(BrowserListing(entries: await self.places(), complete: true)) }
            }
        case .source(let id):
            let entries = id == "recent" ? recent : id == "sessions" ? sessions : []
            return AsyncThrowingStream { $0.yield(BrowserListing(entries: entries, complete: true)) }
        case .folder(let folder):
            return list(folder)
        }
    }

    private func list(_ folder: URL) -> AsyncThrowingStream<BrowserListing, Error> {
        let path = folder.standardizedFileURL.path
        let entries = tree[path]
        return AsyncThrowingStream { continuation in
            Task { @MainActor in
                guard let entries, !path.hasSuffix("Broken") else {
                    continuation.finish(throwing: CocoaError(.fileReadNoPermission))
                    return
                }
                let names = entries.map { var e = $0; e.date = nil; e.size = nil; return e }
                // The huge folder comes as a slow share sends it: nothing for a while, then parts.
                if names.count > 1000 {
                    try? await Task.sleep(for: .seconds(DemoBrowserSource.slowStart))
                    for end in stride(from: 1000, to: names.count, by: 1000) {
                        continuation.yield(BrowserListing(entries: Array(names[..<end]), complete: false, more: true))
                        try? await Task.sleep(for: .milliseconds(400))
                    }
                }
                continuation.yield(BrowserListing(entries: names, complete: false))
                try? await Task.sleep(for: .milliseconds(500))
                continuation.yield(BrowserListing(entries: entries, complete: true))
            }
        }
    }

    func folders(in folder: URL) async -> [BrowserEntry] {
        (tree[folder.standardizedFileURL.path] ?? []).filter(\.isContainer)
    }

    func parent(of folder: URL) -> BrowserLocation {
        folder.standardizedFileURL.path == root.path ? .places : .folder(folder.deletingLastPathComponent())
    }

    func symbol(for entry: BrowserEntry) -> String {
        switch entry.kind {
        case .folder: "folder"
        case .archive: "doc.zipper"
        case .file: "photo"
        case .place: "externaldrive"
        case .collection: "rectangle.stack"
        }
    }

    func wantImages(_ ids: [String], width: CGFloat) {
        Task { @MainActor in
            for id in ids {
                let seed = abs(id.hashValue)
                // A folder: a mosaic of as many photos as it has, up to four.
                let shapes = [(300, 200), (200, 300), (240, 240), (320, 180)]
                let shape = shapes[seed % shapes.count]
                if id.contains("DSC_") {
                    view?.setImage(Demo.gradient(seed, width: shape.0, height: shape.1), for: id)
                    continue
                }
                if id.hasPrefix("session:") {
                    let side = CGSize(width: 440, height: 440)
                    view?.setImage(HomeMosaic.make((0..<4).map { Demo.gradient(seed + $0) }, size: side), for: id)
                    continue
                }
                let image = id.hasSuffix("Broken") || id.hasSuffix("Small") || id.contains("IMG_") || id.contains("photo ")
                    ? Demo.gradient(seed)
                    : HomeMosaic.make((0..<(1 + seed % 4)).map { Demo.gradient(seed + $0) }, size: CGSize(width: 440, height: 293))
                view?.setImage(image, for: id)
            }
        }
    }

    func menu(for entry: BrowserEntry, in location: BrowserLocation) -> [HomeMenuItem] {
        [HomeMenuItem(id: "rename", title: "Rename…"), HomeMenuItem(id: "trash", title: "Move to Trash")]
    }

    func perform(_ item: String, on entry: BrowserEntry, in location: BrowserLocation) {
        switch item {
        case "rename": view?.beginRename()
        case "trash": view?.trashSelected()
        default: break
        }
    }

    func open(_ entry: BrowserEntry, in location: BrowserLocation, sort: BrowserSort, how: HomeClick) {
        print("open \(entry.url.path) \(how) sorted \(sort.text)")
    }

    func rename(_ entry: BrowserEntry, to name: String) async throws -> BrowserEntry {
        guard !name.contains("/") else { throw CocoaError(.fileWriteInvalidFileName) }
        let parent = entry.url.deletingLastPathComponent().standardizedFileURL.path
        var new = entry
        new.url = entry.url.deletingLastPathComponent().appendingPathComponent(name)
        new.name = name
        tree[parent] = tree[parent]?.map { $0.id == entry.id ? new : $0 }
        return new
    }

    func trash(_ entry: BrowserEntry) async throws {
        let parent = entry.url.deletingLastPathComponent().standardizedFileURL.path
        tree[parent]?.removeAll { $0.id == entry.id }
    }

    func sort(for location: BrowserLocation) -> BrowserSort {
        if case .source = location { return BrowserSort(key: .date, ascending: false) }
        guard case .folder(let folder) = location else { return .standard }
        return sorts[folder.standardizedFileURL.path] ?? .standard
    }

    func setSort(_ sort: BrowserSort, for location: BrowserLocation) {
        if case .folder(let folder) = location { sorts[folder.standardizedFileURL.path] = sort }
    }

    func info(for source: String) -> HomeSourceInfo {
        switch source {
        case "recent":
            HomeSourceInfo(title: "Recent", sortKeys: [.date, .name], groupsByDate: true, noun: "item",
                           emptyHint: "Open a photo with ⌘O or drop it here")
        case "sessions":
            HomeSourceInfo(title: "Sessions", sortKeys: [.date, .name], noun: "session")
        default:
            HomeSourceInfo(title: "Stash", page: page, pageFilters: ["Scenes", "Images", "Galleries"])
        }
    }

    func sidebar() async -> [HomeSidebarSection] {
        let places = await places().map { e in
            HomeSidebarRow(id: e.id, title: e.name, symbol: "externaldrive", location: .folder(e.url),
                           expandable: !e.isDimmed, isDimmed: e.isDimmed)
        }
        return [HomeSidebarSection(id: "library", title: nil, rows: [
                    HomeSidebarRow(id: "recent", title: "Recent", symbol: "clock", location: .source("recent")),
                    HomeSidebarRow(id: "sessions", title: "Sessions", symbol: "rectangle.stack", location: .source("sessions")),
                ]),
                HomeSidebarSection(id: "places", title: "Places", rows: places),
                HomeSidebarSection(id: "stash", title: "Stash", rows: [
                    HomeSidebarRow(id: "stash", title: "Library", symbol: "server.rack", location: .source("stash")),
                ])]
    }

    func pageFilterChosen(_ index: Int, in source: String) { print("stash filter \(index)") }
}
