import Foundation

/// One entry of a card's right-click menu: what the app gets back (`id`) and what the menu shows.
public struct HomeMenuItem: Equatable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// One card on the home screen: a picture (set apart, by `id`), a title and a line under it. The app decides what
/// each field holds; the view only draws it.
public struct HomeCardItem: Equatable, Sendable {
    /// The app's key for the card: clicks, menus and pictures come back with it.
    public var id: String
    public var title: String
    public var subtitle: String?
    public var tooltip: String
    /// The SF Symbol on the grey box while the card has no picture.
    public var symbol: String
    /// 0…1: a bar along the picture's bottom edge (how much is watched or viewed); nil draws none.
    public var progress: Double?
    /// A small label on the picture ("Stash"); nil draws none.
    public var badge: String?
    /// Drawn faint: the path cannot be reached now.
    public var isDimmed: Bool
    public var menu: [HomeMenuItem]
    /// The symbol on a glass tile in place of a picture (a place: a volume, the home folder); no picture is asked.
    /// Only the browser's collection cards draw it.
    public var glassSymbol: Bool
    /// The facts of a folder or archive card; nil draws the subtitle and `count` as before.
    public var summary: CardSummary?
    /// Photos in a folder, when the app knows it (the narrow poster's number).
    public var count: Int?
    /// What a row of the list shows for a file (or for a folder without a summary): the format (the extension, in
    /// capitals), the date and the size in bytes.
    public var format: String?
    public var date: Date?
    public var bytes: Int64?
    /// The source may still send this card's facts or cover (`HomeSource.sendsCardFacts`): set while it has no
    /// facts, or while its facts expect a cover (no problem, photos here or inside), and the source has not given up
    /// on it (`HomeBrowserView.stopWaiting`). The card shimmers while the facts or the cover are missing: a
    /// placeholder cover until the picture, two lines until the facts.
    public var waiting: Bool = false

    public init(id: String, title: String, subtitle: String? = nil, tooltip: String, symbol: String,
                progress: Double? = nil, badge: String? = nil, isDimmed: Bool = false, menu: [HomeMenuItem] = [],
                glassSymbol: Bool = false, summary: CardSummary? = nil, count: Int? = nil, format: String? = nil,
                date: Date? = nil, bytes: Int64? = nil, waiting: Bool = false) {
        self.waiting = waiting
        self.format = format
        self.date = date
        self.bytes = bytes
        self.summary = summary
        self.count = count
        self.glassSymbol = glassSymbol
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.tooltip = tooltip
        self.symbol = symbol
        self.progress = progress
        self.badge = badge
        self.isDimmed = isDimmed
        self.menu = menu
    }
}

/// A run of cards under a heading; a nil title draws no heading.
public struct HomeSection: Equatable, Sendable {
    public var title: String?
    public var items: [HomeCardItem]

    public init(title: String?, items: [HomeCardItem]) {
        self.title = title
        self.items = items
    }
}

/// How the grid fits the window (`home-layout`): `fit` shrinks the cards so that all of them show, then scrolls;
/// `scroll` keeps the card size and scrolls; `fixed` never scrolls.
public enum HomeLayoutMode: String, CaseIterable, Sendable {
    case fit, scroll, fixed
}
