import AppKit
import Foundation
import HomeScreenModel

/// What the app says about one of its sources (`BrowserLocation.source`): a list the browser draws on its grid (Recent,
/// Sessions), or a page of the app's own under the toolbar (Stash).
public struct HomeSourceInfo {
    public var title: String
    /// The sort capsule's fields, in order (⌥1 is the first); none hides it.
    public var sortKeys: [BrowserSort.Key]
    /// Sorted by date, the cards fall into Today, Yesterday, This Week and Earlier.
    public var groupsByDate: Bool
    /// What the footer counts (`3 sessions`).
    public var noun: String
    /// Shown in the middle while the list is empty.
    public var emptyHint: String
    /// The app's view in place of the grid; nil: a list on the grid.
    public var page: NSView?
    /// The page's filter in the toolbar's middle (`pageFilterChosen` gets the index).
    public var pageFilters: [String]

    public init(title: String, sortKeys: [BrowserSort.Key] = [], groupsByDate: Bool = false, noun: String = "item",
                emptyHint: String = "", page: NSView? = nil, pageFilters: [String] = []) {
        self.title = title
        self.sortKeys = sortKeys
        self.groupsByDate = groupsByDate
        self.noun = noun
        self.emptyHint = emptyHint
        self.page = page
        self.pageFilters = pageFilters
    }
}

/// What the app gives Home: the sidebar, the places, the listings of folders and of its own sources, the pictures and
/// what is done to files. The browser sorts, keeps the history and the selection, and draws; it never touches a file
/// itself.
@MainActor public protocol HomeSource: AnyObject {
    /// The top level: the home folder, the volumes, pinned folders (the Places crumb's menu).
    func places() async -> [BrowserEntry]
    /// A location's listings, as they come: the places, a folder, or a list source; the browser stops iterating when it
    /// leaves the location.
    func list(_ location: BrowserLocation) -> AsyncThrowingStream<BrowserListing, Error>
    /// The folders and archives in `folder` (names are enough), for the path's sibling menus and the sidebar's tree: from
    /// the source's cache when it has the listing, so the menu fills at once.
    func folders(in folder: URL) async -> [BrowserEntry]
    /// Where Up goes from `folder`: its parent, or the places from a volume's root.
    func parent(of folder: URL) -> BrowserLocation
    /// The SF Symbol on a card that has no picture yet.
    func symbol(for entry: BrowserEntry) -> String
    /// The cards on screen want pictures, those in view first; they come back through `HomeBrowserView.setImage`.
    func wantImages(_ ids: [String], width: CGFloat)
    /// The same, told how many of `ids` (the first `visible`) are in view now; the rest is the margin around the view,
    /// sent once scrolling has stopped. The default forwards to `wantImages(_:width:)`.
    func wantImages(_ ids: [String], visible: Int, width: CGFloat)
    func menu(for entry: BrowserEntry, in location: BrowserLocation) -> [HomeMenuItem]
    func perform(_ item: String, on entry: BrowserEntry, in location: BrowserLocation)
    /// A sidebar row's context menu, as `menu(for:in:)` is a card's (a folder's or an archive's Show in Finder and
    /// Copy Path); the default is none, and a row without items shows no menu.
    func sidebarMenu(for row: HomeSidebarRow) -> [HomeMenuItem]
    /// An item of `sidebarMenu(for:)` chosen on `row`.
    func performSidebar(_ item: String, on row: HomeSidebarRow)
    /// A file or a collection opened (a folder or an archive is entered by the browser itself).
    func open(_ entry: BrowserEntry, in location: BrowserLocation, sort: BrowserSort, how: HomeClick)
    func rename(_ entry: BrowserEntry, to name: String) async throws -> BrowserEntry
    func trash(_ entry: BrowserEntry) async throws
    func sort(for location: BrowserLocation) -> BrowserSort
    func setSort(_ sort: BrowserSort, for location: BrowserLocation)
    /// How the folders and archives of `location` are drawn (posters, cards, list); like the sort, a folder's own or
    /// the one it inherits.
    func cardStyle(for location: BrowserLocation) -> CardStyle
    func setCardStyle(_ style: CardStyle, for location: BrowserLocation)
    func info(for source: String) -> HomeSourceInfo
    /// The sidebar's sections: the sources, the places, the app's others.
    func sidebar() async -> [HomeSidebarSection]
    /// A segment of a page's filter was chosen.
    func pageFilterChosen(_ index: Int, in source: String)
    /// The browser went from `old` (nil: the first location) to `new`: what was read for `old` alone can stop.
    func moved(from old: BrowserLocation?, to new: BrowserLocation)
    /// Whether the source sends folder and archive cards their facts and covers after the listing
    /// (`HomeBrowserView.setSummary`, `setImage`): their cards then wait for them, shimmering, until they come or the
    /// source gives up (`HomeBrowserView.stopWaiting`). False by default: the cards show their subtitle as before.
    var sendsCardFacts: Bool { get }
    /// The progress popover's Pause (true) or Resume (false): the user's pause of the work ahead, asked in `location`.
    /// The default does nothing.
    func pauseThumbs(_ on: Bool, in location: BrowserLocation)
    /// The progress popover's Prepare subfolders: the subtree of `location` to be prepared. The default does nothing.
    func prepareSubtree(of location: BrowserLocation)
}

public extension HomeSource {
    func sidebarMenu(for row: HomeSidebarRow) -> [HomeMenuItem] { [] }
    func performSidebar(_ item: String, on row: HomeSidebarRow) {}
    func cardStyle(for location: BrowserLocation) -> CardStyle { .posters }
    func setCardStyle(_ style: CardStyle, for location: BrowserLocation) {}
    func wantImages(_ ids: [String], visible: Int, width: CGFloat) { wantImages(ids, width: width) }
    func moved(from old: BrowserLocation?, to new: BrowserLocation) {}
    var sendsCardFacts: Bool { false }
    func pauseThumbs(_ on: Bool, in location: BrowserLocation) {}
    func prepareSubtree(of location: BrowserLocation) {}
}
