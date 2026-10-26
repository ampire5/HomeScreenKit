# Unreadable Files Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. (User's choice: executed inline, no subagents.)

**Goal:** One run-long knowledge of files the decoders cannot read, shared by Home's grid, Loupe's strip and viewer and FrameScrub's player; steps go past them.

**Architecture:** `UnreadableFiles` (HomeScreenModel, main actor, keyed by URL with date/size) is fed by decoder failures; `HomeBrowserView` dims from it, `FolderPlaylist.index(from:step:skipping:)` steps past it.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing, AppKit.

**Spec:** `HomeScreenKit/docs/superpowers/specs/2026-10-27-unreadable-files-design.md`

## Global Constraints

- `polish-2` branches, local commits only; kit in `swift package edit` mode in both apps; Package.resolved not committed.
- Ping the other session (uds:/tmp/cc-socks/4750.sock) before installing a build; Loupe label `P2-4`.
- No config keys added or renamed.
- Main thread: store operations are O(changed) or O(entries) per change, no I/O.

## Review Focus

- A share that drops mid-folder: thumbnails fail with read errors — cards must not dim, steps must not skip (Task 2 test `readFailureIsNotUnavailable`).
- A broken file replaced by a good one with the same name: different size/date → not skipped (Task 1 `otherVersionIsUnknown`).
- All files after the current one broken: step at the end does nothing, no loop (Task 1 `nothingAheadGivesNil`).
- Broken file opened by name: error shown, not skipped (Loupe `skipBroken` guards kept; FrameScrub `stepDirection == nil`).
- Unreadable mark with unknown stamp (names-only listing) still matches later entry with stamp (Task 1 `withoutDateMatchesByURL`).

---

### Task 1: Kit — `UnreadableFiles`, `FolderPlaylist.index(from:step:skipping:)`, grid dimming

**Files:** Create `Sources/HomeScreenModel/UnreadableFiles.swift`, `Tests/HomeScreenModelTests/UnreadableFilesTests.swift`; modify `Sources/HomeScreenModel/FolderPlaylist.swift`, `Tests/HomeScreenModelTests/FolderPlaylistTests.swift`, `Sources/HomeScreenKit/HomeBrowserView.swift` (`unreadable` property, `isUnavailable(_:)` used by item dimming and arrow keys).

- [ ] Tests: `markedIsContained`, `clearForgets`, `otherVersionIsUnknown`, `withoutDateMatchesByURL`, `urlsAreStandardized`, `observerGetsOnlyChanges`, `droppedObservationIsSilent`; `skippingIndex` (`indexFromSkipsForwardAndBack`, `nothingAheadGivesNil`, `fromItselfWhenGood`).
- [ ] Run → fail; implement; run `swift test` → pass.
- [ ] Commit `UnreadableFiles: the files the decoders could not read, for the grid's dimming and the steps past them`.

### Task 2: Loupe — thumbnails split, one store for grid, strip and viewer (stage 4a)

**Files:** `Sources/LoupeCore/ThumbnailStore+Generator.swift` (`Outcome.failed(broken: Bool)`, `readFailed` set), `Sources/LoupeCore/ThumbnailStore.swift` (`readFailed` reset with `unavailable`, skip set), `Sources/LoupeCore/Playlist.swift` (`index(from:step:skipping:)` passthrough), `Sources/Loupe/AppDelegate.swift` (store), `Sources/Loupe/FolderBrowserSource.swift`, `Sources/Loupe/StripController.swift`, `Sources/Loupe/ViewerSession.swift` (+ where windows are made, to pass the store).
- [ ] Test `readFailureIsNotUnavailable` / `decodeFailureIsUnavailable` in ThumbnailStore tests (use existing fake reader/decoder hooks).
- [ ] Implement; `scripts/test.sh` → pass.
- [ ] Commit; ping peer; `scripts/make-app.sh --install --label P2-4`.

### Task 3: FrameScrub — marks from open failures, steps past them (stage 4b)

**Files:** `Sources/FrameScrubCore/OpenFailure.swift` (`marksUnreadable: Bool` — `.damaged`, `.noVideo`), `Sources/FrameScrubCore/Playlist.swift` (`skipping:` on init or `next/previous(skipping:)`), `Sources/FrameScrub/AppDelegate.swift`, `Sources/FrameScrub/FrameScrubHomeSource.swift` (`view.unreadable`), `Sources/FrameScrub/PlayerWindowController.swift` (mark on failure; skip when the open was a folder step; clear on success).
- [ ] Tests: `damagedAndNoVideoMarkUnreadable`, `playlistStepsPastUnreadable`.
- [ ] Implement; `scripts/test.sh` → pass.
- [ ] Commit; ping peer; `scripts/make-app.sh --install`.
