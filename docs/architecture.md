# HomeScreenKit architecture

Current package map; update with changes to ownership, targets or the HomeSource contract. `Package.swift` is the
authority for dependencies. Applications supply media/filesystem policy; this package supplies reusable UI and models.

## Targets and responsibilities

| Target | Role | Entry points |
|---|---|---|
| HomeScreenModel | Browser entries, locations, sort/filter/history and layout rules | `Sources/HomeScreenModel/BrowserEntry.swift`, `Sources/HomeScreenModel/BrowserHistory.swift` |
| HomeScreenKit | Home/sidebar/browser UI, cards and source contract | `Sources/HomeScreenKit/HomeSource.swift`, `Sources/HomeScreenKit/HomeView.swift`, `Sources/HomeScreenKit/HomeBrowserView.swift` |
| HomeChrome | Shared glass, palette, icons and chrome | `Sources/HomeChrome` |
| FilmstripModel | Layout, scroll, hit and resize policies | `Sources/FilmstripModel` |
| Filmstrip | Strip views and reveal/presentation | `Sources/Filmstrip/FilmstripView.swift`, `Sources/Filmstrip/FilmstripRowsView.swift` |
| SlotModel | Slot/tab geometry, state and timing | `Sources/SlotModel` |
| SlotChrome | Slot capsule UI | `Sources/SlotChrome/SlotCapsuleView.swift` |
| Slots | Slot view/controller lifecycle | `Sources/Slots/SlotsController.swift` |

HomeScreenKit depends on HomeScreenModel/HomeChrome; Filmstrip depends on FilmstripModel/HomeChrome;
Slots depends on SlotModel/SlotChrome/HomeChrome. Models do not depend on the applications. The demo executable
exercises the package with synthetic data.

## Integration and ownership

`HomeSource` is a main-actor, class-bound protocol. The application retains its source; HomeView/HomeBrowserView
hold it weakly. A source produces streamed listings, pictures, menus, open/rename/trash actions and persisted sort
choices. The browser owns selection, local navigation/history, visible cards, layout and its listing subscription.
It delegates actual filesystem/media operations to the source. `HomeView` composes browser/sidebar and inspector
integration. A host can supply a retained AppKit page in `HomeSourceInfo.page`, including a hosted SwiftUI view.
The browser hides the page on navigation and shows the same view on return. A page with ongoing work can use
AppKit visibility callbacks to pause and resume it. Search configuration and result actions belong to the host.
Filmstrip and slot hosts supply their own items and callbacks; they do not create an app media cache.

Hosts supply a Favorites source and an ordered sidebar section from the same saved folders. HomeScreenKit
handles branch selection, drag and menu reordering, and discards replies from superseded sidebar reloads.
When the section changes while the Favorites source is open, HomeView reloads its cards. HomeFavorites
formats duplicate names using mounted volume roots, with a path fallback for offline volumes. The source's
cards request the hosts' folder covers and use a centered folder name while a cover is unavailable.

A folder can opt into HomeSource's recursive listing. HomeBrowserView owns the toolbar toggle and cancels the
current stream when the mode changes. It skips the direct listing cache and leaves sidebar children to the direct
folder source. The hosts persist successful walks in their SQLite catalogs using relative-path snapshots.
The mode starts off for new navigation and sessions. File View tabs retain it in memory.

Apps can opt into multiple card selection through `HomeBrowserView.allowsMultipleSelection`.
The browser owns Command-click toggling, Shift ranges and context-menu selection. The app reads
`selectedEntries` in listing order. Existing card commands still receive the card they were opened on.

With `HomeView.fileTabsEnabled`, `HomeFileTabs` keeps the navigation, selection and scroll for each folder tab
while the same `HomeBrowserView` renders the selected tab or the current app source. A tab switch uses the
browser's listing cancellation and generation guards. The sidebar's Open in New Tab command uses these tabs
or asks the host to open a native window tab. The host owns the lifetime of the versioned
`FileTabSession` snapshot and associates media opens with a tab ID when it wants to return to that tab.
With tabs enabled, the browser’s grid viewport starts below the strip. Document coordinates exclude the strip
and toolbar, while saved session anchors retain their existing offset convention. The sidebar starts below the
toolbar alongside the tabs. Tab controls retain their identity across location and order changes. Overflow keeps
the selected tab in view and offers all tabs through a native menu.

The sidebar keeps the complete logical tree for navigation and reuses row views within the visible range.
It builds the rendered rows, their branch identities and the followed row together when the tree changes.
Scroll geometry uses the uniform row height and does not depend on offscreen views. Visible rows expose opening,
disclosure and context menu actions through AppKit accessibility. The current location remains marked while
keyboard focus moves through the tree. The sidebar width limits the displayed indentation. File URLs already
in standard form bypass Foundation's reachability checks when comparing locations or looking up unreadable files.

Flow: source location → `list` stream → browser sorting/filtering/layout → visible cards → source image requests →
`setImage` delivery. Card reuse and visibility determine picture demand, not the size of the whole collection.
When Date orders folders, all card styles show the entry's sorting date instead of the contents' date span;
summary delivery and card reuse preserve that choice. Other sorts retain the contents' dates and histogram.
A card selection and a hover are distinct events; inspector consumers must follow the intended selection contract.

## Concurrency and lifetime

The package uses Swift 6 language mode with compiler-checked concurrency and no default global-actor isolation.
View mutations and shared prebuilt `ChromeGlyph` values are main-actor work. `Icons.set` and Lucide's font/image
caches use locks so image rendering remains callable from background work; cached font access never escapes
the lock, and font construction returns a fresh caller-owned font. KVO callbacks read split items through their
main-actor view owner; window notifications extract the actor-owned window before entering main-actor work.
The browser cancels old listing/order/loading work and uses a generation check
when navigating; sources must likewise stop obsolete reads and watchers. A stream may deliver an answer after
cancellation, so publishing must remain generation-bound. Source I/O/thumbnail decoding belongs off the main actor.
The package's motion/reveal work must stop at rest and honor visibility; do not add perpetual polling to cards.
Slots keep content ownership distinct from reveal and placement. Reusing hidden pages is preferable to rebuilding.
The app disables `SlotsController.isEnabled` while a browser covers the player. This suspends presentation,
edge reveal, page visibility and layout reservations without changing saved tabs, pinning or shown state.

## Change and verification map

- Listing, selection, rename, navigation: `HomeBrowserView.swift` and `HomeSource.swift`; use
  `Tests/HomeScreenKitTests` and `Tests/HomeScreenModelTests`.
- Grid/card behavior: `Sources/HomeScreenModel/GridLayout.swift` and card views; test large/reused grids.
- Chrome: `Sources/HomeChrome`; tests in `Tests/HomeChromeTests`.
- Filmstrip: `Sources/FilmstripModel` then `Sources/Filmstrip`; matching model/view test targets.
- Slots: `Sources/SlotModel` then `Sources/Slots`; matching model/chrome/controller tests.

Run `swift test --jobs 4`. The `homescreen-demo` supports synthetic data and snapshot/bench options documented in
[README](../README.md); application real-window benches additionally check integration costs. New public API needs
a released kit tag before app pins change. Keep application-specific persistence and media policy outside the kit.
