# HomeScreenKit

Home as Photos draws it, shared by Loupe (Home) and, later, FrameScrub: a sidebar of sources and places beside a browser
of folders and the app's own lists. Only the view: each app keeps its own files, recent list and sessions and hands
them over through `HomeSource`.

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

## Tests

    swift test

## License

MIT — see [LICENSE](LICENSE).
