# Browser table columns

The table keeps its compact Name / Inside / Dates / Viewed / Size defaults. Right-click its header to choose additional columns or restore defaults. The choice is saved in user preferences. Name is always present; custom selections scroll horizontally rather than dropping selected metadata. Only selected optional cells are created, and visible rows continue using the browser's existing bounded row pool.

Available columns cover the source's existing file facts (dimensions, megapixels, capture date, camera, lens, shutter, aperture, ISO, focal length, exposure bias, colour profile, EXIF orientation, progressive encoding and content type), video facts (duration, codec, frame rate, bitrate and dynamic range), and folder summaries (photos, subfolders, photos below, date range, viewed/new counts, last visit, completion and reading direction). Missing facts stay empty. Internal database keys, cache timestamps and binary thumbnails are not presented as columns.

## Reproduce

```sh
HOMESCREEN_TABLE_BENCH=1 swift test --jobs 4 --filter TableColumnsTests
```

The opt-in test opens a real AppKit window at 1400 × 760 with the actual browser and toolbar, fed 2000 synthetic files with metadata. It measures main-thread CPU with `CLOCK_THREAD_CPUTIME_ID`, including synchronous layout, across ten consecutive rounds: choose nine columns, choose all columns, restore defaults. It writes a preview to `/tmp/loupe-table-preview.png`. It does not modify saved column preferences.

2026-10-29, Apple M4 Max, 14 physical cores, debug build, macOS SDK 27:

| Action | First visit, ms | Return visits, ms |
| --- | ---: | ---: |
| Nine columns | 11.63 | 3.44–6.66 |
| All columns | 26.58 | 4.80–6.43 |
| Restore defaults | 2.76 | 2.55–3.05 |

No progressive slowdown across ten rounds. Normal table rows allocate no optional metadata cells. No extra filesystem work or analysis is scheduled by choosing columns; the source supplies facts using its existing thumbnail/catalog pipeline.

These are local Apple Silicon measurements, not an Intel Mac acceptance result. A real Intel Mac remains required for the supported-machine responsiveness check before a distributable build is handed over.

## Media capability filtering (2026-10-30)

The app's `FileStyle.mediaKind` now limits both the column picker and the effective saved selection. Photo browsers exclude stream-only fields; video browsers exclude photo capture/encoding metadata and photo-specific summary fields. Format, dimensions, content type and general folder fields remain shared. Display nouns can change independently of capabilities. Existing saved choices remain stored but incompatible columns do not render or reserve horizontal space.

Repeated the real photo table benchmark on the same Apple M4 Max, 14 physical cores, debug build, SDK 27. This measured the filtered photo selection, including the case where saved choices contain every column:

| Action | First visit, ms | Return visits, ms |
| --- | ---: | ---: |
| Nine columns | 10.83 | 3.32–3.55 |
| All compatible photo columns | 21.22 | 4.62–4.88 |
| Restore defaults | 2.69 | 2.41–2.66 |

No accumulation across ten rounds. This remains a local Apple Silicon result; Intel validation is outstanding.
