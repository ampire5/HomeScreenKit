import Foundation

/// Where the browser is: the top level (`places`: the home folder, the volumes, pinned folders), a folder, or one of
/// the app's sources by its id (`source`: a list the app gives, as Recent, or a page of its own, as Stash). A zip is a
/// folder too: its path, with the app listing what is inside.
public enum BrowserLocation: Hashable, Sendable {
    case places
    case folder(URL)
    case source(String)

    /// The same folder however its URL is spelled ("/x/" from `deletingLastPathComponent`, "/x/./y").
    private var key: String? {
        switch self {
        case .places: nil
        case .folder(let url): url.standardizedFileURL.path
        case .source(let id): "source:" + id
        }
    }

    public static func == (a: BrowserLocation, b: BrowserLocation) -> Bool { a.key == b.key }
    public func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

/// One card of the browser: a folder, an archive, a file, a place, or a collection of the app's (a recent folder, a
/// session). The app fills it; the view sorts and draws it.
public struct BrowserEntry: Equatable, Sendable {
    public enum Kind: Sendable {
        /// `collection`: a card the app opens itself; the browser never enters it.
        case folder, archive, file, place, collection
    }

    /// The card's key: `key`, else the path.
    public var id: String { key ?? url.path }
    /// The app's own key, for a card whose URL is not unique or not a path (a session).
    public var key: String?
    public var url: URL
    public var name: String
    public var kind: Kind
    /// Nil until the listing with attributes has come (the first one has names only).
    public var date: Date?
    public var size: Int64?
    /// Photos in a folder, when the app knows it.
    public var count: Int?
    /// Drawn faint: the place cannot be reached now.
    public var isDimmed: Bool
    public var canRename: Bool
    public var canTrash: Bool
    /// The card's line, in place of the one the browser would make (a count, a date).
    public var subtitle: String?
    /// 0…1: a bar along the picture's bottom edge (how far the folder was viewed); nil draws none.
    public var progress: Double?
    /// A label on the picture ("Stash", "Last"); nil: the browser's own (`ZIP` on an archive).
    public var badge: String?
    /// Kept first whatever the sort (Last Session).
    public var leads: Bool
    /// The facts of a folder or archive card (counts, dates, how much was seen); nil until the app knows them.
    public var summary: CardSummary?

    /// Folders, archives and places open as folders in the browser; the rest open in the app.
    public var isContainer: Bool { kind == .folder || kind == .archive || kind == .place }
    public var isFile: Bool { kind == .file }

    public init(url: URL, name: String, kind: Kind, date: Date? = nil, size: Int64? = nil, count: Int? = nil,
                isDimmed: Bool = false, canRename: Bool = false, canTrash: Bool = false, key: String? = nil,
                subtitle: String? = nil, progress: Double? = nil, badge: String? = nil, leads: Bool = false,
                summary: CardSummary? = nil) {
        self.summary = summary
        self.key = key
        self.subtitle = subtitle
        self.progress = progress
        self.badge = badge
        self.leads = leads
        self.url = url
        self.name = name
        self.kind = kind
        self.date = date
        self.size = size
        self.count = count
        self.isDimmed = isDimmed
        self.canRename = canRename
        self.canTrash = canTrash
    }
}

/// One listing of a folder. The first ones may have names only (`date` and `size` nil, `complete` false), and on a
/// slow share come in parts (`more`: further names follow, each listing has all names so far); the full one follows,
/// then a new one whenever the folder changes while it is open.
public struct BrowserListing: Sendable {
    public var entries: [BrowserEntry]
    public var complete: Bool
    public var more: Bool

    public init(entries: [BrowserEntry], complete: Bool, more: Bool = false) {
        self.entries = entries
        self.complete = complete
        self.more = more
    }
}
