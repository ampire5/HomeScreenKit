# File cards: scrolling bench (2026-10-27)

`PHOTO_BENCH=cards swift test --filter PhotoCardBench`: a 5 000-file grid in a 1400 × 900 window scrolled top to
bottom in 200 steps; main-thread CPU per step (layout and the Core Animation commit, `CLOCK_THREAD_CPUTIME_ID`).
Cards style (`FileCard`, three columns, every file with EXIF facts) against the plain photo tiles (`PHOTO_BENCH=plain`,
160 pt, no names). Apple M4 Max, debug build, three rounds each.

A step moves ~850 pt: about 8 rows of cards (24 new cards) against ~5 rows of tiles; real scrolling moves a few
points a frame, one or two new cards.

| run | median | p95 | max |
|---|---|---|---|
| photo tiles (baseline) | 4.1 ms | 4.6 ms | 13.8 ms |
| file cards, first version | 13.5 ms | 15.2 ms | 43 ms |
| file cards, chip size and placeholder frame not measured at every layout | 8.9 ms | 10.6 ms | 50 ms |

What the second row cost: `NSImageView.fittingSize` of the placeholder and the length chip's `intrinsicContentSize`
at every layout (~4.5 ms a step for 24 cards). Left: the four Core Text lines each new card draws (~0.35 ms a card).
The max is the first step (the pools filling). Rounds do not grow. The Intel Mac's run is owed (owner's machine).
