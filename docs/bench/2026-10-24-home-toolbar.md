# Home browser toolbar: before and after the move to `NSToolbar` (2026-10-24)

`swift run -c release homescreen-demo bench-toolbar [--rounds N] [--settle MS]` — the real window on screen as Loupe
makes it (titled, resizable), `HomeView` over the demo source (made-up data, no disk access) on a folder of 2 000 photo
entries and 12 subfolders. Every action is followed by the run loop alone for `--settle` ms (800): long enough for
layout, the listing and the Core Animation commit. The number is the main thread's CPU time
(`CLOCK_THREAD_CPUTIME_ID`): on the main thread it is also how long the window does not answer. `--rounds` is 12.
The toolbar's internals (progress, sort fields, sibling menu) are reached through `@_spi(Bench)` hooks in
`BenchHooks.swift`, which are not API.

Machine: iMac20,1, Intel Core i7-10700K, 8 cores, macOS 26.7.1, release build. Budgets (`CLAUDE.md`): opening a
window ≤ 300 ms, switching a screen ≤ 100 ms, one press ≤ 50 ms.

Scenarios: **open** — the window and `HomeView` built, then shown (`makeKeyAndOrderFront` and the first settle);
**hide / show** — Home hidden and shown again, as a switch to the viewer and back does (12 rounds, the first apart);
**narrow / widen** — the window 1300 → 420 pt and back in steps of 20 pt, per step (3 passes);
**progress** — the thumbnails' progress shown 100 times with a growing share, per call plus the layout after it;
**sort** — the three sort fields chosen in turn (the source re-sorts, the grid is laid out); **siblings** — a menu of
30 sibling folders built (not shown: showing a menu tracks the mouse).

## Before: the hand-drawn `HomeToolbar` (HomeScreenKit `origin/main`, 6c75286)

ms of main-thread CPU, three runs side by side (first / median of the later ones / max).

| Scenario | run 1 | run 2 | run 3 | after |
|---|---|---|---|---|
| open: build window and `HomeView` | 123 | 133 | 144 | |
| open: show and settle | 139 | 209 | 207 | |
| hide, first | 125 | 133 | 133 | |
| hide, median | 12.8 | 14.3 | 13.8 | |
| show, first | 33.6 | 42.9 | 48.8 | |
| show, median | 21.4 | 22.8 | 22.9 | |
| narrow, per step: median / max | 12.1 / 39 | 13.2 / 51 | 12.4 / 27 | |
| widen, per step: median / max | 13.1 / 65 | 14.1 / 44 | 12.8 / 43 | |
| progress, per call: median / max | 1.4 / 36 | 1.5 / 2.7 | 1.3 / 2.2 | |
| sort, three fields: median / max | 44 / 55 | 47 / 67 | 45 / 48 | |
| siblings menu of 30: median | 1.8 | 1.7 | 1.7 | |

Rounds do not grow: hide stays at 11–15 ms and show at 18–23 ms after the first two rounds. The first hide (125–133
ms) and the second (56–68 ms) are the window still settling after opening, not the toolbar; the three runs agree
within ~10 % except the first `show` of the open (139–209 ms), which depends on when the demo listing arrives. The
sort is the cost of re-sorting and tiling 2 000 cards, not of the capsule. The first `progress` call of run 1 (36 ms)
is the pill's first layout; in the other runs it was already warm.

## After

Filled in when the toolbar is an `NSToolbar` (Task 9 of the plan).
