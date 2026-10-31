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
integration. Filmstrip and slot hosts supply their own items and callbacks; they do not create an app media cache.

Flow: source location → `list` stream → browser sorting/filtering/layout → visible cards → source image requests →
`setImage` delivery. Card reuse and visibility determine picture demand, not the size of the whole collection.
A card selection and a hover are distinct events; inspector consumers must follow the intended selection contract.

## Concurrency and lifetime

View mutations are main-actor work. The browser cancels old listing/order/loading work and uses a generation check
when navigating; sources must likewise stop obsolete reads and watchers. A stream may deliver an answer after
cancellation, so publishing must remain generation-bound. Source I/O/thumbnail decoding belongs off the main actor.
The package's motion/reveal work must stop at rest and honor visibility; do not add perpetual polling to cards.
Slots keep content ownership distinct from reveal and placement. Reusing hidden pages is preferable to rebuilding.

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
