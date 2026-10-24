# HomeScreenKit

Home as Photos draws it, shared by Loupe (Home) and, later, FrameScrub: a sidebar of sources and places beside a browser
of folders and the app's own lists. Only the view: each app keeps its own files, recent list and sessions and hands
them over through `HomeSource`.

Requirements: macOS 26+, swift-tools 6.2 (the targets build in the Swift 5 language mode).

![Home in Loupe: the sidebar's folder tree beside the browser](https://raw.githubusercontent.com/ampire5/Loupe/main/docs/images/sidebar.webp)

Three libraries:

- `HomeScreenModel` (Foundation and CoreGraphics only): the browser's data and rules — `BrowserLocation` (the places,
  a folder, or an app source by id), `BrowserEntry`, `BrowserSort` / `BrowserSortChoice`, `BrowserFilter`,
  `BrowserSummary`, `BrowserHistory`, `GridLayout`, `DateGroups` (Recent's Today · Yesterday · This Week · Earlier),
  `SidebarTree` (the sidebar's sections, folded headings, the folder tree and the path to the current folder) — and the
  start screen's `HomeCardItem`, `HomeSection`, `HomeLayout`, `HomeClick`.
- `HomeChrome` (AppKit only): the glass capsule, button group and pill.
- `HomeScreenKit`: `HomeView` (sidebar and browser side by side; ⌃⌘S through the app, Tab between them, the tree
  following the browser), `HomeBrowserView` (the glass toolbar over a virtualized grid of photo and collection cards,
  with history, sort, filters, footer, rename and Trash; an app source shows as a list of collection cards or as the
  app's page under the toolbar), `HomeSource` / `HomeSourceInfo` (what the app gives), and `HomeMosaic`.
  `HomeScreenView` is FrameScrub's start screen until it moves to `HomeView`.

`homescreen-demo` shows Home on made-up data: Recent, Sessions, a disk with a folder of 10 000 files, an unplugged
place and a page for Stash. `HOMESCREEN_SNAPSHOT=<png>` writes it to a file without showing a window, with
`HOMESCREEN_SOURCE` = `recent` | `sessions` | `places` | `stash` | `tree` | a folder path (`/Demo/Mixed`),
`HOMESCREEN_NOSIDEBAR`, `HOMESCREEN_STYLE`, `HOMESCREEN_NAMES`, `HOMESCREEN_WIDTH`. `HOMESCREEN_SCREEN=start` shows the
old start screen (its View menu switches the layout, the picture shape, the tabs and the message). A snapshot leaves
the pictures held in layers (collection cards' mosaics) out; the window shows them.

## Using it: `HomeSource`

`HomeSource` (`@MainActor`, class-bound) is the whole integration surface: the app answers what is where, the views ask
for it. The browser sorts, keeps the history and the selection, and draws; it never touches a file itself. `HomeView`
and `HomeBrowserView` hold their source weakly, so the app keeps it alive.

| Requirement | What the app gives |
|---|---|
| `places() async -> [BrowserEntry]` | the top level: home folder, volumes, pinned folders |
| `list(_:) -> AsyncThrowingStream<BrowserListing, Error>` | a location's listings as they come (names first, then attributes, then updates) |
| `folders(in:) async -> [BrowserEntry]` | the subfolders, for the path menus and the sidebar tree |
| `parent(of:) -> BrowserLocation` | where Up goes |
| `symbol(for:)`, `wantImages(_:width:)` | a card's placeholder symbol; pictures, returned via `HomeBrowserView.setImage(_:for:)` |
| `menu(for:in:)`, `perform(_:on:in:)` | a card's context menu (`HomeMenuItem`) and its action |
| `open(_:in:sort:how:)` | a file or collection opened (`HomeClick`: here, new tab, new window) |
| `rename(_:to:) async throws`, `trash(_:) async throws` | F2 / ⌘⌫ |
| `sort(for:)`, `setSort(_:for:)` | the per-location sort the app keeps |
| `info(for:) -> HomeSourceInfo`, `pageFilterChosen(_:in:)` | an app source (Recent, Sessions) or an app page (Stash) |
| `sidebar() async -> [HomeSidebarSection]` | the sidebar's sections and rows |
| `moved(from:to:)` | optional (has a default): the browser left a location |

A minimal source over the home folder, with no app sources:

```swift
import AppKit
import HomeScreenKit
import HomeScreenModel

@MainActor final class FolderSource: HomeSource {
    weak var browser: HomeBrowserView?
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var sorts: [BrowserLocation: BrowserSort] = [:]

    func places() async -> [BrowserEntry] { [BrowserEntry(url: home, name: "Home", kind: .place)] }

    func list(_ location: BrowserLocation) -> AsyncThrowingStream<BrowserListing, Error> {
        AsyncThrowingStream { continuation in
            do {
                switch location {
                case .places:
                    continuation.yield(BrowserListing(entries: [BrowserEntry(url: home, name: "Home", kind: .place)],
                                                      complete: true))
                case .folder(let url):
                    continuation.yield(BrowserListing(entries: try entries(in: url), complete: true))
                case .source:
                    continuation.yield(BrowserListing(entries: [], complete: true))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    func folders(in folder: URL) async -> [BrowserEntry] { ((try? entries(in: folder)) ?? []).filter(\.isContainer) }
    func parent(of folder: URL) -> BrowserLocation {
        folder.standardizedFileURL == home.standardizedFileURL ? .places : .folder(folder.deletingLastPathComponent())
    }
    func symbol(for entry: BrowserEntry) -> String { entry.isContainer ? "folder" : "photo" }
    func wantImages(_ ids: [String], width: CGFloat) {
        // Make thumbnails off the main actor, then hand each back: browser?.setImage(cgImage, for: id)
    }
    func menu(for entry: BrowserEntry, in location: BrowserLocation) -> [HomeMenuItem] {
        [HomeMenuItem(id: "finder", title: "Show in Finder")]
    }
    func perform(_ item: String, on entry: BrowserEntry, in location: BrowserLocation) {
        if item == "finder" { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
    }
    func open(_ entry: BrowserEntry, in location: BrowserLocation, sort: BrowserSort, how: HomeClick) {
        NSWorkspace.shared.open(entry.url)
    }
    func rename(_ entry: BrowserEntry, to name: String) async throws -> BrowserEntry {
        let url = entry.url.deletingLastPathComponent().appendingPathComponent(name)
        try FileManager.default.moveItem(at: entry.url, to: url)
        var renamed = entry
        renamed.url = url
        renamed.name = name
        return renamed
    }
    func trash(_ entry: BrowserEntry) async throws {
        try FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)
    }
    func sort(for location: BrowserLocation) -> BrowserSort { sorts[location] ?? .standard }
    func setSort(_ sort: BrowserSort, for location: BrowserLocation) { sorts[location] = sort }
    func info(for source: String) -> HomeSourceInfo { HomeSourceInfo(title: source) }
    func sidebar() async -> [HomeSidebarSection] {
        [HomeSidebarSection(id: "places", title: "Places", rows: [
            HomeSidebarRow(id: "home", title: "Home", symbol: "house", location: .folder(home), expandable: true),
        ])]
    }
    func pageFilterChosen(_ index: Int, in source: String) {}

    private func entries(in folder: URL) throws -> [BrowserEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                           options: .skipsHiddenFiles).map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return BrowserEntry(url: url, name: url.lastPathComponent,
                                kind: values?.isDirectory == true ? .folder : .file,
                                date: values?.contentModificationDate, size: values?.fileSize.map(Int64.init),
                                canRename: true, canTrash: true)
        }
    }
}
```

And in the window controller:

```swift
let source = FolderSource()                     // keep a strong reference
let home = HomeView(source: source)
source.browser = home.browser
home.browser.onResize = { [weak home] step in   // ⌘= / ⌘− / ⌘0, ⌘ + wheel, pinch
    guard let browser = home?.browser else { return }
    browser.cardSize = browser.cardSize(after: step, range: 60...480) ?? 220
}
home.onSidebarToggle = { [weak home] in home?.isSidebarVisible.toggle() }
window.contentView = home
home.browser.show(.folder(FileManager.default.homeDirectoryForCurrentUser), selecting: nil)
```

`homescreen-demo`'s `DemoBrowserSource` is a fuller example: app sources with date groups, an app page with filters,
slow listings in parts.

### What the browser does for you

- **Type-to-select**: typing a name's first letters selects it, as in Finder (letters add up within a second; case is
  ignored, accents count) — `BrowserTypeSelect` in `HomeScreenModel`.
- **Card size steps**: ⌘= / ⌘− / ⌘0, ⌘ + wheel, a pinch or a mouse's side wheel arrive as `onResize(HomeResize)`; the
  app stores the size and sets `cardSize` (`cardSize(after:range:)` gives one photo column more or fewer;
  `HomeResize.size(from:range:)` steps by 20 pt). `resize(notches:)` feeds a wheel the app routes itself.
- **Programmatic navigation** on `HomeBrowserView`: `show(_:selecting:)`, `goBack()`, `goForward()`, `goUp()`,
  `reload()` (keeps selection, scroll and filter), `reloadPlaces()`, `beginRename()`, `trashSelected()`, `filterText`,
  `handleKey(_:)` for keys the app forwards; `location`, `lastBrowsed` and `onLocation` to remember where it was.
- **Toasts**: `showToast(_:)` shows a short line at the bottom for 3 s (an action that failed).
- Style and names (`style`, `names`, `onStyle`, `onNames`: ⌥T / ⌥N), the sort segments in the toolbar (Name / Date / Size; a click on the active one reverses it) and ⌥1…⌥3, a mouse's other buttons
  (`onOtherMouse`), drops on Home (`HomeView.onDrop`), the sidebar's width and tree options (one-folder chains on one
  row, restarting deep trees, subfolders before archives).

## Tests

    swift test

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/ampire5/HomeScreenKit.git", from: "0.1.0"),
],
// in your target:
dependencies: [
    .product(name: "HomeScreenKit", package: "HomeScreenKit"),
    .product(name: "HomeScreenModel", package: "HomeScreenKit"),
    .product(name: "HomeChrome", package: "HomeScreenKit"),   // only if you use the glass controls directly
]
```

Used by [Loupe](https://github.com/ampire5/Loupe) and [FrameScrub](https://github.com/ampire5/FrameScrub).

## Issues and contributions

Bug reports and pull requests are welcome at [github.com/ampire5/HomeScreenKit/issues](https://github.com/ampire5/HomeScreenKit/issues).
Please run `swift test` before sending a change.

## License

MIT — see [LICENSE](LICENSE).
