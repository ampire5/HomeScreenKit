# File cards: a file's facts on its card

The owner's request of 2026-10-27: a file's card shows what was learned when its picture was made (a video's stream,
a photo's EXIF), cached with the picture; the Cards style (⌥⌘2) applies to files too. Decided with the owner the same
day (all four proposals taken as given):

1. **Video card:** the length as a chip on the poster (as now), under the poster `1080p · HEVC · 60 fps · 1.2 GB`,
   and the progress track.
2. **Photo card:** the camera and the lens, `1/250 · f/2.8 · ISO 400`, the date taken and the size in pixels.
3. **Cards style for files:** like a folder's compact card (mockup B): the picture at the left, the facts in rows at
   the right.
4. (FrameScrub) the player's content no longer under the title bar after Home and full screen (done separately).

## 1. The facts (HomeScreenModel)

`FileFacts`, every field optional, filled by the app from the read it does for the picture anyway:

- both: `width`, `height` (pixels);
- video: `duration` (s), `codec` (`HEVC`, `H.264`, `AV1`, `ProRes`…), `fps`, `bitrate` (bit/s), `hdr`;
- photo: `camera` (make and model, the make dropped when the model starts with it), `lens`, `exposure` (s),
  `aperture` (f-number), `iso`, `focalLength` (mm), `taken` (DateTimeOriginal).

`FileFactsText` formats them (pure, tested): `resolution` (`720p`, `1080p`, `1440p`, `4K`, `8K` by the shorter
side for video; `4032 × 3024` for a photo), `stream` (`1080p · HEVC · 60 fps`, `HDR` appended), `exposureLine`
(`1/250 · f/2.8 · ISO 400`, `24 mm` when known), `cameraLine` (`Sony ILCE-7M4 · FE 24-70mm F2.8 GM II`).

`BrowserEntry.facts` and `HomeCardItem.facts` carry them; nil draws the cards as before.

**Since the style guide (2026-10-27, «Media UI Iconography» v1.0, taken by the owner):** the words follow its sections
D and E. `hdr` became `transfer` (`SDR`, `HLG`, `HDR10`) and `exposureBias` (EV) was added. Classes by the long side
(`FHD`, `UHD` for 3840, `4K` for 4096, `6K`, `8K`); rates unrounded with `p` (`23.976p`); `stream` in the guide's order
`UHD · 25p · HEVC · HLG`; `exposureLine` `1/250 · f/2.8 · ISO 800 · 35 mm · −0.3 EV`; a non-breaking space between a
number and its unit; decimal sizes, one decimal under 100 (`24.6 MB`, `148 MB`). Badges are the guide's `MediaBadge`
(text on the HUD scrim, no colour per kind; the metal plates are gone), at most two: `UHD HLG`, `FHD 59.94p`,
`RAW 24 MP`. The hover strip's exposure is monospaced text, no glyphs (`FactsGlyphs` is gone).

## 2. The cards (HomeScreenKit)

- **Posters (`PhotoCard`), names below:** a second line under the name, secondary colour, 11 pt: video
  `stream · size`; photo `exposureLine` or, without EXIF, `resolution · size`. The grid reserves it only when the
  app's `FileStyle.factsLine` is on (`GridMetrics.belowFacts`, 15 pt), so photo apps without facts keep their grid.
  The length chip takes `facts.duration` when the entry has no line of its own. The hover strip of a photo shows
  `exposureLine` (else the format) at the left and the size at the right.
- **Cards (`FileCard`, new):** the compact card's plate (300 × 92, radius 12, ring, padding 8). The picture fitted in
  a box 76 pt tall and `FileStyle.aspect` × 76 wide (a photo's square, a video's 135 × 76), radius 8, the length chip
  and progress on it for video. Four rows at the right, spread like the compact card's:
  1. the name (13.5 semibold);
  2. video `stream`; photo `cameraLine` (else the format);
  3. video the length and the size; photo `exposureLine` (else `resolution`);
  4. video the progress track and `12:30 / 1:02:10`, else the date and the size; photo the date taken (else
     modified), `resolution` and the size.
- **List:** unchanged (format, date, size).

`GridLayout` puts files on card slots in the Cards style; the folder sections keep their own cards.

## 3. The apps

- **FrameScrub:** `KeyframeThumbnail` already opens the file with FFmpeg for the poster; it returns the stream's
  codec, size, rate, bitrate and HDR with the duration. They are kept in `FileFactsStore` (what `DurationStore` was,
  keyed by path, as the durations were). A card whose poster comes from the cache without facts gets a probe without a
  decode (`avformat_find_stream_info`), on the poster queue, visible cards first.
- **Loupe:** the generator has the photo's bytes for the thumbnail already; `PhotoFacts` reads their properties and
  the EXIF goes into the catalog next to the thumbnail (`file_facts`, by file id, gone when the file changes). A thumbnail made before has no facts: its properties are read once (the header only), on
  the thumbnail queue, visible cards first.

No file is read for facts alone beyond that one header read, and none for a card off screen.

## 4. Speed

Facts are a few scalars per file; formatting happens when a card is bound (O(1)). The extra probe runs at `.utility`
and pauses with the posters. The store saves in bursts like the durations do.

## 5. Tests

- `FileFactsText`: resolution names, stream line with and without fps / HDR, exposure fractions (1/250, 0.5 s, 2 s),
  camera without a repeated make.
- `GridLayout`: the facts line reserved only with `belowFacts`; files on card slots in the Cards style.
- `FileCard`: rows filled for a video and a photo; no facts draws the format, date and size.
- Apps: the probe's facts from a fixture (FrameScrub), the EXIF of a fixture JPEG (Loupe), the stores' round trip.
