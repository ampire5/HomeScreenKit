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

| Scenario | run 1 | run 2 | run 3 | after: the same three runs (NSToolbar) |
|---|---|---|---|---|
| open: build window and `HomeView` | 123 | 133 | 144 | 177 / 178 / 169 |
| open: show and settle | 139 | 209 | 207 | 292 / 283 / 310 |
| hide, first | 125 | 133 | 133 | 169 / 204 / 223 |
| hide, median | 12.8 | 14.3 | 13.8 | 31 / 30 / 29 |
| show, first | 33.6 | 42.9 | 48.8 | 167 / 102 / 155 |
| show, median | 21.4 | 22.8 | 22.9 | 63 / 64 / 62 |
| narrow, per step: median / max | 12.1 / 39 | 13.2 / 51 | 12.4 / 27 | 16 / 58, 13 / 35, 15 / 40 |
| widen, per step: median / max | 13.1 / 65 | 14.1 / 44 | 12.8 / 43 | 16 / 41, 15 / 40, 15 / 37 |
| progress, per call: median / max | 1.4 / 36 | 1.5 / 2.7 | 1.3 / 2.2 | 0.4 / 39, 0.4 / 38, 0.3 / 36 |
| sort, three fields: median / max | 44 / 55 | 47 / 67 | 45 / 48 | 18 / 28, 19 / 28, 17 / 31 |
| siblings menu of 30: median | 1.8 | 1.7 | 1.7 | 2.2 / 2.1 / 1.9 |

Rounds do not grow: hide stays at 11–15 ms and show at 18–23 ms after the first two rounds. The first hide (125–133
ms) and the second (56–68 ms) are the window still settling after opening, not the toolbar; the three runs agree
within ~10 % except the first `show` of the open (139–209 ms), which depends on when the demo listing arrives. The
sort is the cost of re-sorting and tiling 2 000 cards, not of the capsule. The first `progress` call of run 1 (36 ms)
is the pill's first layout; in the other runs it was already warm.

## After: the window's `NSToolbar` (`HomeToolbarController`)

The last column above. Same machine, same bench, release build; in the "after" runs `hide` and `show` also take the
toolbar away from the window and give it back, as Loupe does (the old toolbar was a subview and went with the view for
nothing). The machine was busy with another job (load average 5–9 of 16) during the "after" runs, so the CPU numbers
carry some contention; the three runs agree within ~10 % apart from the cold first rounds.

| Budget (`CLAUDE.md`) | Result |
|---|---|
| Opening a window, 300 ms | **Not met.** Building Home and showing the window: 460–490 ms (before: 260–350). The toolbar is ~+170 ms of it, and a cold first display of it costs ~250 ms on its own (below). |
| Switching a screen, 100 ms | Repeated: **met**, hide 30 ms, show 62–64 ms (before 13 and 22). First round: **not met**, hide 169–223 ms, show 102–167 ms (before 125–133 and 34–49: the first hide was over the budget already, as the window settles after opening). |
| One press, 50 ms | **Met.** Progress ring update 0.3–0.4 ms (the first call, which lights the hidden item, 36–39 ms); View and path menus are filled when first opened (a sort of three fields with the menu opened: 17–19 ms, before 44–47); sibling menu 2 ms; − + and card switch are plain clicks. |
| Rounds do not grow | **Met.** hide stays at 28–33 ms (45 once), show at 56–67 ms (77 and 98 once) over 12 rounds. |

### What the first display of the toolbar costs, and where

Release, a bare window already on screen, the toolbar given to it for the first time (3 runs): the controller made
54–78 ms (of which the first `NSSearchToolbarItem` of the process alone is 42 ms, the next one 5 ms), given to the
window 82–92 ms, then the first layout and drawing 200–211 ms; taken away 12–19 ms and given back 36–49 ms. So the cold
cost is AppKit's first toolbar, not the controller's own code; the second display is cheap. Each item taken out of the
toolbar in turn (first display, attach and settle, 3 runs of the whole, 203 ms): search −60, View −30, − + −20, card
switch −19, the rest −5…−15 each; all of the optional ones together −90 (111 ms left for the bare toolbar).

Options for the owner (the spec leaves the cold first display to this decision): accept it (the first display is once
per window, 250 ms on an Intel Mac); take the card switch off the bar (it is in `View ▾` anyway, −19 ms); give the
search a lighter item (a plain field in an item: no folding into the magnifier, maybe −50 ms, not measured); or make
the toolbar before Home is first asked for, in the idle after the window is up (moves the 250 ms, does not remove it,
and it is one chunk bigger than a frame, so a click can land in it).

### Where items hide (window width in pt, release, `visibleItems` each 20 pt, with the ring lit and a path of three)

| Item | Gone at (first width where it is no longer visible) | Probe, 2026-10-24 |
|---|---|---|
| everything | visible at 1100 and wider | 1120 |
| `View ▾` | 1080 | ≤ 1100 |
| card switch | 1040 | ≤ 1100 |
| − + | 920 | ≤ 980 |
| `All · Folders · Photos` | 840 | ≤ 900 |
| ‹ › | 600 | ≤ 640 |
| Start Page | 520 | ≤ 560 |
| path pill | 480 | ≤ 480 |
| ring | 420 | ≤ 420 |
| sidebar | 380 | (never) |

The order is the spec's; every threshold is 0–60 pt lower than the probe's (the real toolbar is a little narrower).
Window pictures (light and dark, 1200 / 900 / 700 / 560 pt) are made with `HOMESCREEN_SHOTS=<prefix>
.build/debug/homescreen-demo` and kept out of the repository.
