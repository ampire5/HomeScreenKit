# FolderPlaylist Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. (User's choice for this plan: executed inline, no subagents.)

**Goal:** Loupe's viewer and FrameScrub's player step through a folder in exactly the order Home's grid shows it.

**Architecture:** A pure `FolderPlaylist` in `HomeScreenModel` orders a folder's file entries with the grid's own `BrowserSort.order` and keeps the position; both apps' `Playlist` types delegate order and position to it. FrameScrub persists each folder's sort so a file opened from Finder gets the same order as Home.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing, AppKit.

**Spec:** `HomeScreenKit/docs/superpowers/specs/2026-10-27-folder-playlist-design.md`

## Global Constraints

- Branch `polish-2` from `origin/main` in each repo; commit locally; never push, tag or open PRs.
- Apps build against the kit's working copy: `swift package edit HomeScreenKit --path ../HomeScreenKit`; Package.resolved is not committed from edit mode (`git checkout Package.resolved`).
- After each stage: `scripts/make-app.sh --install` (Loupe with `--label P2-<n>`).
- Main thread never blocks: no new disk reads on it (FolderSorts loads once at start like FolderColors; writes debounced).
- Comments and names follow each repo's style (short `///` docs, plain English, no ticket refs).

## Review Focus

- A folder of only names (no stamps yet) sorted by date: grid and viewer both fall back to name order — covered by Task 1 order-equality test with nil dates.
- Zip with pages in subfolders: page names are inner paths in both — Task 2 test `archivePagesOrderLikeTheGrid`.
- Current file not in the listing (hidden/odd extension opened from Finder) stays current and in the list — Task 1 `currentOutsideEntriesIsKept`, Loupe existing `relist` keeping tests.
- Current file deleted during a relist: position falls to the old index, clamped — Task 1 `replaceWithoutCurrentKeepsIndex`, Loupe `replacing` tests.
- folder-sorts.json unreadable: set aside, store starts empty, app still opens — Task 4 `brokenFileIsSetAside`.

---

### Task 1: `FolderPlaylist` in HomeScreenModel

**Files:**
- Create: `HomeScreenKit/Sources/HomeScreenModel/FolderPlaylist.swift`
- Test: `HomeScreenKit/Tests/HomeScreenModelTests/FolderPlaylistTests.swift`

**Interfaces:**
- Produces: `public struct FolderPlaylist: Equatable, Sendable` with `folder: URL`, `sort: BrowserSort`, `files: [BrowserEntry]`, `index: Int`, `current: BrowserEntry`, `urls: [URL]`; `init(folder: URL, entries: [BrowserEntry], sort: BrowserSort, current: URL)`; `mutating func move(by: Int) -> Bool`; `mutating func move(to: URL) -> Bool`; `mutating func resort(_: BrowserSort)`; `mutating func replace(entries: [BrowserEntry])`.

- [ ] **Step 1: Tests** — `orderIsTheGridsForEverySort` (entries: img10, img2, Img1, two `same.jpg` in `/f/a` and `/f/b`... same folder path differs only via key? use names `a`, `b` with equal dates, nil dates, nil sizes, a folder and an archive; for each of the six `BrowserSort(text:)`: `urls == sort.order(entries).filter(\.isFile).map(\.url)`), `currentOutsideEntriesIsKept` (current `/f/x.odd` absent → present, `current.url` equal, position by name), `resortKeepsCurrent`, `replaceKeepsCurrentByURL`, `replaceWithoutCurrentKeepsIndex` (current at 2 removed → index 2; at end removed → last), `replaceWithNothingKeepsCurrent`, `moveStopsAtEnds`, `moveToUnknownFails`, `urlsAreStandardized` (current spelled `/f/./b.jpg` finds `/f/b.jpg`).
- [ ] **Step 2:** `swift test --filter FolderPlaylistTests` → fails (type missing).
- [ ] **Step 3: Implement.** Files filtered by `isFile`, URLs standardized on the way in; current added when missing (`BrowserEntry(url:, name: lastPathComponent, kind: .file)`); order via `sort.order`; index by URL.
- [ ] **Step 4:** `swift test --filter FolderPlaylistTests` → pass; `swift test --filter HomeScreenModelTests` → pass.
- [ ] **Step 5:** Commit `FolderPlaylist: a folder's files in the grid's order and the position among them`.

### Task 2: Loupe `Playlist` on `FolderPlaylist` (stage 1)

**Files:**
- Modify: `Loupe/Sources/LoupeCore/Playlist.swift` (init, `replacing`, `reordered`, `move*`, drop `naturalLess`)
- Modify: `Loupe/Sources/LoupeCore/BrowserSortSetting.swift` (`sorted(_:)` → model `resort`)
- Modify: `Loupe/Sources/LoupeCore/BrowserListingSource.swift` (extract `public static func fileEntry(_ url: URL, stamp: FileStamp?) -> BrowserEntry`, used by `entry` and `archiveEntries`)
- Modify callers of `naturalLess` if any remain; `Loupe/Sources/Loupe/ViewerSession.swift` quickList result sorted by the folder's sort.
- Test: `Loupe/Tests/LoupeCoreTests/PlaylistTests.swift`, `Loupe/Tests/LoupeCoreTests/ArchiveFolderTests.swift`

**Interfaces:**
- Consumes: Task 1.
- Produces: `Playlist.init(files:current:stamps:keeping:sort: BrowserSort = .standard)`; `files: [URL]` and `index` unchanged in meaning; `sorted(_:)` kept as API.

- [ ] **Step 1: Tests** — `gridAndViewerOrderMatch` (files with stamps incl. equal dates and one without stamp; for six sorts: `Playlist(files:current:stamps:sort:).files == sort.order(files.map { fileEntry($0, stamp:) }).map(\.url)`); `archivePagesOrderLikeTheGrid` (zip URLs `a.zip/sub/b.jpg`, `a.zip/a.jpg`… names by inner path).
- [ ] **Step 2:** `swift package edit HomeScreenKit --path ../HomeScreenKit`; `swift test --filter PlaylistTests` → new tests fail.
- [ ] **Step 3: Implement** — `Playlist` stores `model: FolderPlaylist` and cached `files`; `index` reads `model.index`; `replacing(with:)` = listed's order with `move(to: current)` else clamped old index; `sorted` = `resort`; `naturalLess` removed (callers use `BrowserSort.standard`).
- [ ] **Step 4:** `scripts/test.sh` (or `swift test`) → all LoupeCore tests pass; `git checkout Package.resolved` if rewritten.
- [ ] **Step 5:** Commit `Playlist: order and position from HomeScreenKit's FolderPlaylist, the grid's own order`.
- [ ] **Step 6:** `scripts/make-app.sh --install --label P2-1`; open the app, check About shows P2-1.

### Task 3: FrameScrub `Playlist` on `FolderPlaylist`, listing from `HomeFolders`

**Files:**
- Modify: `FrameScrub/Sources/FrameScrubCore/Playlist.swift` (`Playlist`, `FolderListing`)
- Modify: `FrameScrub/Sources/FrameScrubCore/HomeFolders.swift` (drop `playlistOrder`)
- Modify: `FrameScrub/Sources/FrameScrub/PlayerWindowController.swift` (`rebuildPlaylist`, `folderReturn` loses `order`, `homeOrder` gone)
- Test: `FrameScrub/Tests/FrameScrubCoreTests/PlaylistTests.swift`

**Interfaces:**
- Consumes: Task 1.
- Produces: `Playlist.init(current: URL, sort: BrowserSort = .standard, filter: String = "", listing: FolderListing)`; `FolderListing.read(_:fileManager:)` built on `HomeFolders.entries` (files only, an unreadable folder → empty); `FolderListing.entries: [BrowserEntry]`.

- [ ] **Step 1: Tests** — update existing sort tests to `BrowserSort`; add `orderIsTheGrids` (six sorts, `files == sort.order(listing entries).map(\.url)`), `fileWithoutDateGoesLast` (date-desc).
- [ ] **Step 2:** edit mode for the kit; `swift test --filter PlaylistTests` → fail.
- [ ] **Step 3: Implement.** Filter stays a layer on `model.urls` (current always kept).
- [ ] **Step 4:** `swift test` → pass.
- [ ] **Step 5:** Commit `Playlist: the grid's order through HomeScreenKit's FolderPlaylist; the folder read by HomeFolders`.

### Task 4: FrameScrub folder sorts kept, panel and F9 change the folder's sort (stage 2)

**Files:**
- Create: `FrameScrub/Sources/FrameScrubCore/FolderSorts.swift`
- Modify: `FrameScrub/Sources/FrameScrub/FrameScrubHomeSource.swift` (`sort(for:)` / `setSort` for `.folder` via FolderSorts)
- Modify: `FrameScrub/Sources/FrameScrub/PlayerWindowController.swift` (`setPlaylistSort` sets the folder's sort; panel shows it)
- Modify: `FrameScrub/Sources/FrameScrub/PlaylistPanelView.swift` (shows `BrowserSort.Key`)
- Modify: `FrameScrub/Sources/FrameScrubCore/Playlist.swift` (`PlaylistSort.defaultSort: BrowserSort`)
- Modify: `FrameScrub/Sources/FrameScrub/AppDelegate.swift` (flush on quit)
- Test: `FrameScrub/Tests/FrameScrubCoreTests/FolderSortsTests.swift`

**Interfaces:**
- Produces: `public final class FolderSorts` — `init(url: URL? = defaultURL, writeDelay: Double = 2, schedule:)`, `func sort(for folder: URL) -> BrowserSort?`, `func set(_ sort: BrowserSort, for folder: URL)`, `func flush()`; file `~/Library/Application Support/FrameScrub/folder-sorts.json` (`[path: sort.text]`). `PlaylistSort.defaultSort`: name → name asc, date → date desc, size → size desc.

- [ ] **Step 1: Tests** — `setThenReadBack`, `survivesReload` (write, flush, new instance reads), `brokenFileIsSetAside`, `pathsAreStandardized`, `defaultSortFromPlaylistSort`.
- [ ] **Step 2:** `swift test --filter FolderSortsTests` → fail.
- [ ] **Step 3: Implement** (pattern of `FolderColors`: main thread, debounced write, set-aside on decode failure). Player: folder sort = `folderSorts.sort(for:) ?? config.playlistSort.defaultSort`; panel/F9 choose key via `BrowserSortChoice(current:)`, store, rebuild; message `Folder order: <title>`.
- [ ] **Step 4:** `swift test` → pass.
- [ ] **Step 5:** Commit `Folder order: each folder's sort kept for Home and the player alike; the panel and F9 change it`.
- [ ] **Step 6:** `scripts/make-app.sh --install`; check the manual list from the spec.
