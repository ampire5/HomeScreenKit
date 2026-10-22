import AppKit
@testable import HomeScreenKit

/// A source the tests drive by hand: listings go out through `yield`, everything asked for is recorded.
@MainActor final class FakeHomeSource: HomeSource {
    var placesList: [BrowserEntry] = []
    private(set) var continuations: [String: AsyncThrowingStream<BrowserListing, Error>.Continuation] = [:]
    private(set) var listed: [URL] = []
    private(set) var terminated: [URL] = []
    var sorts: [String: BrowserSort] = [:]
    private(set) var setSorts: [(BrowserSort, URL)] = []
    private(set) var wanted: [[String]] = []
    private(set) var opened: [(BrowserEntry, HomeClick)] = []
    private(set) var performed: [(String, String)] = []
    var menuItems = [HomeMenuItem(id: "reveal", title: "Show in Finder")]
    var renamer: ((BrowserEntry, String) throws -> BrowserEntry)?
    private(set) var renamed: [(String, String)] = []
    var trashError: Error?
    private(set) var trashed: [String] = []

    /// What `info(for:)` gives by source id, what `sidebar()` gives, the page filters chosen, the sources listed.
    var infos: [String: HomeSourceInfo] = [:]
    var sidebarSections: [HomeSidebarSection] = []
    private(set) var pageFiltersChosen: [(Int, String)] = []
    private(set) var listedSources: [String] = []
    private(set) var setSourceSorts: [(BrowserSort, String)] = []

    func places() async -> [BrowserEntry] { placesList }

    func list(_ location: BrowserLocation) -> AsyncThrowingStream<BrowserListing, Error> {
        switch location {
        case .places:
            // The places come at once, complete, as `places()` gave them.
            let entries = placesList
            return AsyncThrowingStream { $0.yield(BrowserListing(entries: entries, complete: true)) }
        case .source(let id):
            listedSources.append(id)
            return AsyncThrowingStream { continuation in
                continuations["source:" + id] = continuation
            }
        case .folder(let folder):
            return list(folder)
        }
    }

    /// A source's listing (Recent, Sessions): `yieldSource("recent", …)`.
    func yieldSource(_ id: String, _ entries: [BrowserEntry], complete: Bool = true) {
        continuations["source:" + id]?.yield(BrowserListing(entries: entries, complete: complete))
    }

    /// Every move the browser made, from and to.
    private(set) var moves: [(BrowserLocation?, BrowserLocation)] = []
    func moved(from old: BrowserLocation?, to new: BrowserLocation) { moves.append((old, new)) }

    func info(for source: String) -> HomeSourceInfo { infos[source] ?? HomeSourceInfo(title: source) }
    func sidebar() async -> [HomeSidebarSection] { sidebarSections }
    func pageFilterChosen(_ index: Int, in source: String) { pageFiltersChosen.append((index, source)) }

    private func list(_ folder: URL) -> AsyncThrowingStream<BrowserListing, Error> {
        listed.append(folder)
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.terminated.append(folder) }
            }
            continuations[folder.standardizedFileURL.path] = continuation
        }
    }

    func yield(_ folder: URL, _ entries: [BrowserEntry], complete: Bool = true) {
        continuations[folder.standardizedFileURL.path]?.yield(BrowserListing(entries: entries, complete: complete))
    }

    /// Names still coming (a slow share): more of them follow.
    func yieldPartial(_ folder: URL, _ entries: [BrowserEntry]) {
        continuations[folder.standardizedFileURL.path]?.yield(BrowserListing(entries: entries, complete: false, more: true))
    }

    func fail(_ folder: URL, _ error: Error) {
        continuations[folder.standardizedFileURL.path]?.finish(throwing: error)
    }

    /// `folders(in:)`'s replies by path; with `holdsFolders` the reply waits for `answerFolders`.
    var folderReplies: [String: [BrowserEntry]] = [:]
    var holdsFolders = false
    private var heldFolders: [CheckedContinuation<[BrowserEntry], Never>] = []
    private(set) var foldersAsked: [URL] = []

    func folders(in folder: URL) async -> [BrowserEntry] {
        foldersAsked.append(folder)
        let reply = folderReplies[folder.standardizedFileURL.path] ?? []
        guard holdsFolders else { return reply }
        return await withCheckedContinuation { heldFolders.append($0) }
    }

    func answerFolders(_ entries: [BrowserEntry]) {
        heldFolders.forEach { $0.resume(returning: entries) }
        heldFolders = []
    }

    func parent(of folder: URL) -> BrowserLocation {
        folder.path == "/" || folder.deletingLastPathComponent().path == "/Volumes"
            ? .places : .folder(folder.deletingLastPathComponent())
    }

    func symbol(for entry: BrowserEntry) -> String { entry.isContainer ? "folder" : "photo" }
    private(set) var visibleCounts: [Int] = []
    func wantImages(_ ids: [String], width: CGFloat) { wanted.append(ids) }
    func wantImages(_ ids: [String], visible: Int, width: CGFloat) {
        visibleCounts.append(visible)
        wanted.append(ids)
    }
    func menu(for entry: BrowserEntry, in location: BrowserLocation) -> [HomeMenuItem] { menuItems }
    func perform(_ item: String, on entry: BrowserEntry, in location: BrowserLocation) {
        performed.append((item, entry.id))
    }
    /// The sidebar rows' menu: `menuItems` for folders, none for the rest.
    func sidebarMenu(for row: HomeSidebarRow) -> [HomeMenuItem] {
        if case .folder = row.location { return menuItems }
        return []
    }
    private(set) var sidebarPerformed: [(String, String)] = []
    func performSidebar(_ item: String, on row: HomeSidebarRow) { sidebarPerformed.append((item, row.id)) }
    func open(_ entry: BrowserEntry, in location: BrowserLocation, sort: BrowserSort, how: HomeClick) {
        opened.append((entry, how))
    }

    func rename(_ entry: BrowserEntry, to name: String) async throws -> BrowserEntry {
        renamed.append((entry.id, name))
        if let renamer { return try renamer(entry, name) }
        var new = entry
        new.url = entry.url.deletingLastPathComponent().appendingPathComponent(name)
        new.name = name
        return new
    }

    func trash(_ entry: BrowserEntry) async throws {
        if let trashError { throw trashError }
        trashed.append(entry.id)
    }

    func sort(for location: BrowserLocation) -> BrowserSort {
        switch location {
        case .places: .standard
        case .folder(let folder): sorts[folder.standardizedFileURL.path] ?? .standard
        case .source(let id): sorts["source:" + id] ?? BrowserSort(key: .date, ascending: false)
        }
    }

    var cardStyles: [BrowserLocation: CardStyle] = [:]
    private(set) var setCardStyles: [(CardStyle, BrowserLocation)] = []
    func cardStyle(for location: BrowserLocation) -> CardStyle { cardStyles[location] ?? .posters }
    func setCardStyle(_ style: CardStyle, for location: BrowserLocation) {
        cardStyles[location] = style
        setCardStyles.append((style, location))
    }

    func setSort(_ sort: BrowserSort, for location: BrowserLocation) {
        switch location {
        case .places: break
        case .folder(let folder):
            sorts[folder.standardizedFileURL.path] = sort
            setSorts.append((sort, folder))
        case .source(let id):
            sorts["source:" + id] = sort
            setSourceSorts.append((sort, id))
        }
    }
}

enum BrowserFixtures {
    static func files(_ count: Int, in folder: String = "/Volumes/T/x") -> [BrowserEntry] {
        (0..<count).map { file("img\($0).jpg", in: folder, date: Double($0)) }
    }

    static func file(_ name: String, in folder: String = "/Volumes/T/x", date: Double? = nil) -> BrowserEntry {
        BrowserEntry(url: URL(fileURLWithPath: folder).appendingPathComponent(name), name: name, kind: .file,
                     date: date.map { Date(timeIntervalSinceReferenceDate: $0) }, size: 1, canRename: true,
                     canTrash: true)
    }

    static func folder(_ name: String, in folder: String = "/Volumes/T/x") -> BrowserEntry {
        BrowserEntry(url: URL(fileURLWithPath: folder).appendingPathComponent(name), name: name, kind: .folder,
                     canRename: true, canTrash: true)
    }
}

/// Waits until `condition` holds. `seconds` is a floor: a loaded machine (a 3-core CI runner running the suites in
/// parallel) gets at least 30 s, and the passing path returns as soon as the condition holds.
@MainActor func settle(seconds: Double, _ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(max(seconds, 30))
    while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
}

/// Without a condition: lets queued main-actor work run (200 yields). With one: yields until it holds, then keeps
/// polling for up to 30 s, so a slow machine is not taken for a failure.
@MainActor func settle(_ condition: (() -> Bool)? = nil) async {
    for _ in 0..<200 {
        if condition?() == true { return }
        await Task.yield()
    }
    guard let condition else { return }
    await settle(seconds: 30, condition)
}

extension BrowserFixtures {
    /// A collection card (a recent folder), opened `daysAgo` before `now`.
    static func collection(_ name: String, daysAgo: Double = 0, now: Date = Date()) -> BrowserEntry {
        BrowserEntry(url: URL(fileURLWithPath: "/r/\(name)"), name: name, kind: .collection,
                     date: now.addingTimeInterval(-daysAgo * 86_400), key: "recent:/r/\(name)")
    }
}

/// A key press as the view gets it.
@MainActor func keyEvent(code: UInt16, chars: String, flags: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                     characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
}
