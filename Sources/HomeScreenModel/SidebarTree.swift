import Foundation

/// One row of the sidebar: a source (Recent), a place (a volume, a pinned folder) or a folder of the tree under it.
public struct HomeSidebarRow: Equatable, Sendable {
    public var id: String
    public var title: String
    public var symbol: String
    public var location: BrowserLocation
    /// A folder whose subfolders can be shown under it (a triangle).
    public var expandable: Bool
    /// Drawn faint: the place cannot be reached now.
    public var isDimmed: Bool
    /// Photos in the folder, when the app knows it.
    public var count: Int?

    public init(id: String, title: String, symbol: String, location: BrowserLocation, expandable: Bool = false,
                isDimmed: Bool = false, count: Int? = nil) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.location = location
        self.expandable = expandable
        self.isDimmed = isDimmed
        self.count = count
    }
}

/// A run of sidebar rows under a heading that folds them away; a nil title has no heading.
public struct HomeSidebarSection: Equatable, Sendable {
    public var id: String
    public var title: String?
    public var rows: [HomeSidebarRow]

    public init(id: String, title: String?, rows: [HomeSidebarRow]) {
        self.id = id
        self.title = title
        self.rows = rows
    }
}

/// The sidebar as data: the app's sections, the folded headings, the folders opened as a tree
/// and the subfolders known for each, and the row of what the browser shows. Following a folder opens the path to it
/// at once, from the path's own components, so the row lights before any listing; which ancestors still need their
/// subfolders listed is handed back for the view to ask, after the folder's own listing.
public struct SidebarTree: Sendable {
    public enum Line: Equatable, Sendable {
        case heading(section: String, title: String, collapsed: Bool)
        case row(HomeSidebarRow, depth: Int, expanded: Bool, loading: Bool)
    }

    /// The folders whose subfolders are being asked (their rows spin).
    public var loadingPaths: Set<String> { loading }

    public enum Key: Sendable {
        case up, down, left, right, open
    }

    public enum Move: Equatable, Sendable {
        case select(Int), expand(URL), collapse(URL), open(BrowserLocation), none
    }

    /// How deep trees are fitted into the sidebar's width.
    public struct Options: Equatable, Sendable {
        /// A folder whose only subfolder is a folder shows with it on one row, `a › b › c`, as in VS Code (the
        /// deepest one is the row: it opens, closes and lights). The current folder always ends its row.
        public var compactChains: Bool
        /// The current folder this many levels under its root or deeper (0: never; 3 or more): the tree starts again
        /// further down, under one row of the folders left out, which opens the last of them.
        public var rerootDepth: Int

        public init(compactChains: Bool = true, rerootDepth: Int = 0) {
            self.compactChains = compactChains
            self.rerootDepth = rerootDepth
        }
    }

    public var options = Options() {
        didSet { if options != oldValue { updateReroot() } }
    }

    public private(set) var sections: [HomeSidebarSection]
    private var collapsed: Set<String> = []
    /// Folders opened, by standardized path.
    private var expanded: Set<String> = []
    /// Each folder's subfolders: the listed ones, or the path's member alone until it is listed.
    private var children: [String: [HomeSidebarRow]] = [:]
    /// Folders whose subfolders were listed.
    private var known: Set<String> = []
    private var loading: Set<String> = []
    private var current: BrowserLocation?
    /// The root the current folder was followed under (a folder can be under a volume and under a pin in it).
    private var currentRoot: String?
    /// Where the tree under `root` starts again (`Options.rerootDepth`).
    private var reroot: (root: String, at: String)?

    public init(sections: [HomeSidebarSection]) {
        self.sections = sections
    }

    // MARK: Lines

    public var lines: [Line] { build().lines }

    public var currentLine: Int? {
        guard let current else { return nil }
        let built = build()
        return built.lines.indices.first { i in
            guard case .row(let row, _, _, _) = built.lines[i], row.location == current else { return false }
            return currentRoot == nil || built.roots[i] == currentRoot
        }
    }

    /// The lines, and for each row line the path of its root (nil for headings and non-folder rows).
    private func build() -> (lines: [Line], roots: [String?]) {
        var lines: [Line] = [], roots: [String?] = []
        let currentPath = current.flatMap(Self.path)
        func add(_ first: HomeSidebarRow, depth: Int, root: String?) {
            var row = first
            var path = Self.path(row.location)
            if options.compactChains, depth > 0 {
                // Down the chain while a listed, opened folder holds one folder only (not past the current one).
                var titles = [row.title]
                while let p = path, row.expandable, expanded.contains(p), known.contains(p), p != currentPath,
                      let only = children[p], only.count == 1, only[0].expandable {
                    row = only[0]
                    path = Self.path(row.location)
                    titles.append(row.title)
                }
                row.title = titles.joined(separator: " › ")
            }
            let open = row.expandable && path.map { expanded.contains($0) } == true
            lines.append(.row(row, depth: depth, expanded: open, loading: path.map { loading.contains($0) } == true))
            roots.append(root)
            guard open, let path else { return }
            if depth == 0, let reroot, reroot.root == path {
                // The folders left out on one row, then the tree from where it starts again.
                let left = Self.components(of: reroot.at, under: path).dropLast()
                let parent = (reroot.at as NSString).deletingLastPathComponent
                lines.append(.row(HomeSidebarRow(id: "trail:" + parent, title: left.joined(separator: " › "),
                                                 symbol: "arrow.turn.left.up",
                                                 location: .folder(URL(fileURLWithPath: parent, isDirectory: true))),
                                  depth: 1, expanded: false, loading: false))
                roots.append(root)
                let start = children[parent]?.first { $0.id == reroot.at }
                    ?? HomeSidebarRow(id: reroot.at, title: (reroot.at as NSString).lastPathComponent, symbol: "folder",
                                      location: .folder(URL(fileURLWithPath: reroot.at, isDirectory: true)), expandable: true)
                add(start, depth: 1, root: root)
                return
            }
            for child in children[path] ?? [] { add(child, depth: depth + 1, root: root) }
        }
        for section in sections {
            let folded = collapsed.contains(section.id)
            if let title = section.title {
                lines.append(.heading(section: section.id, title: title, collapsed: folded))
                roots.append(nil)
            }
            guard !folded else { continue }
            for row in section.rows { add(row, depth: 0, root: Self.path(row.location)) }
        }
        return (lines, roots)
    }

    // MARK: Changes

    /// New sections (a volume came or went, a pin): what was opened under roots still there stays.
    public mutating func setSections(_ new: [HomeSidebarSection]) {
        sections = new
        let roots = new.flatMap(\.rows).compactMap { Self.path($0.location) }
        func kept(_ path: String) -> Bool { roots.contains { Self.isUnder(path, $0) } }
        expanded = expanded.filter(kept)
        known = known.filter(kept)
        loading = loading.filter(kept)
        children = children.filter { kept($0.key) }
        if let root = currentRoot, !roots.contains(root) {
            current = nil
            currentRoot = nil
        }
        if let reroot, !roots.contains(reroot.root) { self.reroot = nil }
    }

    public mutating func toggleSection(_ id: String) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    /// Opens `folder`; true when its subfolders are not known yet and must be asked (it shows as loading).
    public mutating func expand(_ folder: URL) -> Bool {
        let path = Self.path(folder)
        expanded.insert(path)
        guard !known.contains(path) else { return false }
        loading.insert(path)
        return true
    }

    public mutating func collapse(_ folder: URL) {
        expanded.remove(Self.path(folder))
    }

    /// The subfolders of `folder` as listed: folders that open further, archives that do not; files left out.
    public mutating func setChildren(_ entries: [BrowserEntry], of folder: URL) {
        let path = Self.path(folder)
        known.insert(path)
        loading.remove(path)
        let containers = BrowserSort.standard.order(entries.filter { $0.kind == .folder || $0.kind == .archive })
        var rows = containers.map { e in
            HomeSidebarRow(id: Self.path(e.url), title: e.name, symbol: e.kind == .archive ? "doc.zipper" : "folder",
                           location: .folder(e.url), expandable: e.kind == .folder, isDimmed: e.isDimmed, count: e.count)
        }
        // The path to the current folder stays, even through a folder the listing does not show.
        if let chained = children[path]?.filter({ row in !rows.contains { $0.id == row.id } && isOnCurrentPath(row) }) {
            rows += chained
        }
        children[path] = rows
    }

    public mutating func setLoading(_ isLoading: Bool, of folder: URL) {
        if isLoading { loading.insert(Self.path(folder)) } else { loading.remove(Self.path(folder)) }
    }

    /// The browser moved to `location`: its row lights. A folder under a root opens the path to it (the longest root
    /// wins); the ancestors whose subfolders are still unknown come back, top first.
    public mutating func follow(_ location: BrowserLocation) -> [URL] {
        current = location
        currentRoot = nil
        guard case .folder(let url) = location else { return [] }
        let target = Self.path(url)
        let roots = sections.flatMap { section in section.rows.compactMap { row in Self.path(row.location).map { (section.id, $0) } } }
        guard let (section, root) = roots.filter({ Self.isUnder(target, $0.1) }).max(by: { $0.1.count < $1.1.count }) else {
            current = nil
            return []
        }
        currentRoot = root
        collapsed.remove(section)
        guard target != root else { return [] }
        let names = Self.components(of: target, under: root)
        var unknown: [URL] = []
        var parent = root
        for name in names {
            let child = parent == "/" ? "/" + name : parent + "/" + name
            expanded.insert(parent)
            if !known.contains(parent) { unknown.append(URL(fileURLWithPath: parent, isDirectory: true)) }
            if children[parent]?.contains(where: { $0.id == child }) != true {
                let row = HomeSidebarRow(id: child, title: name, symbol: "folder",
                                         location: .folder(URL(fileURLWithPath: child, isDirectory: true)), expandable: true)
                children[parent] = ((children[parent] ?? []) + [row]).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            }
            parent = child
        }
        updateReroot()
        return unknown
    }

    /// The tree starts again when the current folder is `rerootDepth` levels down or deeper, so that it lands on the
    /// second level or halfway, whichever is deeper; it stays put while the current folder moves within reach under it.
    private mutating func updateReroot() {
        let limit = options.rerootDepth
        guard limit >= 3, case .folder(let url)? = current, let root = currentRoot else {
            if options.rerootDepth < 3 || current == nil { reroot = nil }
            return
        }
        let target = Self.path(url)
        let names = Self.components(of: target, under: root)
        if let reroot, reroot.root == root, Self.isUnder(target, reroot.at) {
            let start = Self.components(of: reroot.at, under: root).count
            if names.count - start + 1 < limit { return }
        }
        guard names.count >= limit else {
            reroot = nil
            return
        }
        let start = names.count - max(2, limit / 2) + 1
        guard start >= 2 else {
            reroot = nil
            return
        }
        let at = names.prefix(start).reduce(root) { $0 == "/" ? "/" + $1 : $0 + "/" + $1 }
        reroot = (root, at)
    }

    /// The row is the current folder or one of its ancestors.
    private func isOnCurrentPath(_ row: HomeSidebarRow) -> Bool {
        guard case .folder(let url)? = current, let path = Self.path(row.location) else { return false }
        return Self.isUnder(Self.path(url), path)
    }

    // MARK: Keys

    /// What a key does on line `line`: ↑ ↓ to the rows around it (headings skipped), → opens a folder or goes into it,
    /// ← closes it or goes to its parent, Return opens the row's place in the browser.
    public func move(_ key: Key, from line: Int) -> Move {
        let all = lines
        guard all.indices.contains(line) else { return .none }
        func isRow(_ i: Int) -> Bool { if case .row = all[i] { true } else { false } }
        switch key {
        case .up:
            return (0..<line).reversed().first(where: isRow).map { .select($0) } ?? .none
        case .down:
            return (line + 1 < all.count ? (line + 1)..<all.count : all.count..<all.count).first(where: isRow)
                .map { .select($0) } ?? .none
        case .open:
            guard case .row(let row, _, _, _) = all[line] else { return .none }
            return .open(row.location)
        case .right:
            guard case .row(let row, let depth, let open, _) = all[line], row.expandable,
                  case .folder(let url) = row.location else { return .none }
            if !open { return .expand(url) }
            if line + 1 < all.count, case .row(_, let d, _, _) = all[line + 1], d == depth + 1 { return .select(line + 1) }
            return .none
        case .left:
            guard case .row(let row, let depth, let open, _) = all[line] else { return .none }
            if open, case .folder(let url) = row.location { return .collapse(url) }
            guard depth > 0 else { return .none }
            return (0..<line).reversed().first { i in
                if case .row(_, let d, _, _) = all[i] { d < depth } else { false }
            }.map { .select($0) } ?? .none
        }
    }

    // MARK: Paths

    static func path(_ url: URL) -> String { url.standardizedFileURL.path }

    static func path(_ location: BrowserLocation) -> String? {
        if case .folder(let url) = location { return path(url) }
        return nil
    }

    /// `path` is `root` or inside it, by whole components.
    static func isUnder(_ path: String, _ root: String) -> Bool {
        path == root || root == "/" || path.hasPrefix(root + "/")
    }

    static func components(of path: String, under root: String) -> [String] {
        String(path.dropFirst(root == "/" ? 0 : root.count)).split(separator: "/").map(String.init)
    }
}
