import AppKit
import Testing
@testable import HomeChrome
@testable import HomeScreenKit
@testable import HomeScreenModel

/// Pictures of the folder cards for comparing with the approved mockups (E, B, C), in both appearances, at 2×.
/// Runs only with `HOMESCREEN_SNAPSHOTS=<folder>` set: `HOMESCREEN_SNAPSHOTS=/tmp/x swift test --filter CardSnapshots`.
@MainActor @Suite struct CardSnapshots {
    nonisolated static let folder = ProcessInfo.processInfo.environment["HOMESCREEN_SNAPSHOTS"]

    /// The mockups' five items: a folder with photos and subfolders, an archive of pages read to the end, a folder of
    /// folders, a folder on a volume that is away, a damaged archive. The first two were viewed three days before
    /// `CardTestClock.now`.
    struct Sample {
        var title: String
        var badge: String?
        var summary: CardSummary
        var colors: [UInt32]
    }

    static func date(_ year: Int, _ month: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: 15, hour: 12))!
    }

    static let samples: [Sample] = [
        Sample(title: "Vacation 2024", summary: CardSummary(photos: 248, folders: 3, insidePhotos: 412, bytes: 1_900_000_000,
                                                             first: date(2024, 6), last: date(2024, 8),
                                                             histogram: [1, 3, 8, 10, 7, 4, 2, 1], viewed: 0.62, seen: 153,
                                                             visited: CardTestClock.threeDaysAgo, new: 12),
               colors: [0x3E6E8E, 0xD9B26A, 0x6F8F5A, 0xA5573E]),
        Sample(title: "Scans.zip", badge: "ZIP", summary: CardSummary(photos: 96, bytes: 1_200_000_000, first: date(2023, 3),
                                                                       last: date(2023, 3), histogram: [0, 0, 10, 0, 0, 0, 0, 0],
                                                                       viewed: 1, seen: 96,
                                                                       visited: CardTestClock.threeDaysAgo, done: true, twoPages: true,
                                                                       rightToLeft: true),
               colors: [0xB9AF97, 0xE3DCCB, 0xCFC6B1, 0x9E937B]),
        Sample(title: "Family", summary: CardSummary(photos: 0, folders: 14, insidePhotos: 3860, first: date(2009, 2),
                                                      last: date(2024, 11), histogram: [3, 2, 4, 6, 5, 7, 9, 6]),
               colors: [0x7A5C8C, 0xC98F6B, 0x5E8C86, 0xD8C27A]),
        Sample(title: "Archive on the server", summary: CardSummary(photos: 1120, bytes: 8_400_000_000, first: date(2015, 4),
                                                                     last: date(2019, 9), histogram: [6, 9, 7, 5, 3, 0, 0, 0],
                                                                     viewed: 0.35, seen: 392, problem: .offline),
               colors: [0x4F6A57, 0x8DA36E, 0x3B4E63, 0xB7A27E]),
        Sample(title: "Magazine 07.cbz", badge: "CBZ", summary: CardSummary(bytes: 310_000_000, last: date(2022, 5),
                                                                             histogram: [0, 0, 0, 0, 0, 0, 0, 0], problem: .broken),
               colors: [0x8A8A8E, 0xA6A6AA, 0x7A7A7E, 0xB4B4B8]),
    ]

    static func color(_ hex: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// A flat picture in `hex`; with `hill`, the mockup's hills over it (`0,30 18,14 30,24 44,10 60,30`, 55 %).
    static func picture(_ hex: UInt32, hill: UInt32? = nil, size: CGSize = CGSize(width: 600, height: 300)) -> CGImage {
        let c = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(color(hex))
        c.fill(CGRect(origin: .zero, size: size))
        if let hill {
            let sx = size.width / 60, sy = size.height / 30
            let points = [(0, 30), (18, 14), (30, 24), (44, 10), (60, 30)].map { CGPoint(x: CGFloat($0.0) * sx,
                                                                                         y: size.height - CGFloat($0.1) * sy) }
            c.setFillColor(color(hill).copy(alpha: 0.55)!)
            c.addLines(between: points)
            c.closePath()
            c.fillPath()
        }
        return c.makeImage()!
    }

    static func cover(_ s: Sample, side: CGFloat, layout: HomeMosaic.Layout, compact: Bool = false) -> CGImage? {
        let images = [picture(s.colors[0], hill: s.colors[3])] + s.colors.dropFirst().map { picture($0, size: CGSize(width: 300, height: 300)) }
        return HomeMosaic.make(images, size: CGSize(width: side, height: side), layout: layout, scale: 2, compact: compact)
    }

    static func item(_ s: Sample) -> HomeCardItem {
        HomeCardItem(id: s.title, title: s.title, tooltip: s.title, symbol: s.badge == nil ? "folder" : "doc.zipper",
                     badge: s.badge, summary: s.summary)
    }

    /// Lays `content` out on the window's background in a window of `appearance` and writes it as a 2× PNG.
    static func write(_ name: String, size: CGSize, dark: Bool, _ content: (NSView) -> Void) throws {
        guard let folder else { return }
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        // A plain root (its layer renders upright into the bitmap) holding the flipped canvas the cards go on.
        let host = NSView(frame: CGRect(origin: .zero, size: size))
        host.wantsLayer = true
        window.contentView = host
        host.layer?.backgroundColor = Chrome.resolve(Chrome.Palette.window.background, in: host)
        let canvas = FlippedView(frame: host.bounds)
        host.addSubview(canvas)
        content(canvas)
        host.layoutSubtreeIfNeeded()
        host.display()
        CATransaction.flush()
        let scale: CGFloat = 2
        let c = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                          bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.scaleBy(x: scale, y: scale)
        host.layer!.render(in: c)
        let rep = NSBitmapImageRep(cgImage: c.makeImage()!)
        let url = URL(fileURLWithPath: folder).appendingPathComponent(name + (dark ? "-dark" : "-light") + ".png")
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        window.close()
    }

    final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    @Test(.enabled(if: folder != nil)) func posters() throws {
        FolderCard.now = { CardTestClock.now }   // the samples were viewed three days before it
        for side in [CGFloat(176), 232, 300] {
            let height = side + GridLayout.bandHeight(width: side)
            for dark in [false, true] {
                try Self.write("E-posters-\(Int(side))", size: CGSize(width: 40 + 5 * side + 4 * 16, height: 40 + height), dark: dark) { host in
                    for (i, s) in Self.samples.enumerated() {
                        let card = PosterCard(item: Self.item(s))
                        card.frame = CGRect(x: 20 + CGFloat(i) * (side + 16), y: 20, width: side, height: height)
                        card.image = Self.cover(s, side: side, layout: .hero)
                        host.addSubview(card)
                    }
                }
            }
        }
        // The scale board: one folder at the three sizes, bottoms aligned.
        for dark in [false, true] {
            let sides: [CGFloat] = [176, 232, 300]
            let tallest = 300 + GridLayout.bandHeight(width: 300)
            try Self.write("E-scale", size: CGSize(width: 40 + sides.reduce(0, +) + 48, height: 40 + tallest), dark: dark) { host in
                var x: CGFloat = 20
                for side in sides {
                    let height = side + GridLayout.bandHeight(width: side)
                    let card = PosterCard(item: Self.item(Self.samples[0]))
                    card.frame = CGRect(x: x, y: 20 + tallest - height, width: side, height: height)
                    card.image = Self.cover(Self.samples[0], side: side, layout: .hero)
                    host.addSubview(card)
                    x += side + 24
                }
            }
        }
    }

    @Test(.enabled(if: folder != nil)) func compactCards() throws {
        FolderCard.now = { CardTestClock.now }
        for dark in [false, true] {
            try Self.write("B-cards", size: CGSize(width: 40 + 2 * 300 + 12, height: 40 + 3 * 92 + 2 * 12), dark: dark) { host in
                for (i, s) in Self.samples.enumerated() {
                    let card = CompactCard(item: Self.item(s))
                    card.frame = CGRect(x: 20 + CGFloat(i % 2) * 312, y: 20 + CGFloat(i / 2) * 104, width: 300, height: 92)
                    card.image = Self.cover(s, side: 76, layout: .hero, compact: true)
                    host.addSubview(card)
                }
            }
        }
    }

    @Test(.enabled(if: folder != nil)) func list() throws {
        for dark in [false, true] {
            let width: CGFloat = 620, rows = CGFloat(Self.samples.count)
            let m = GridMetrics()
            try Self.write("C-list", size: CGSize(width: 40 + width, height: 40 + ListHeader.height + rows * m.listRow), dark: dark) { host in
                let plate = ListPlate(frame: CGRect(x: 20, y: 20, width: width, height: ListHeader.height + rows * m.listRow))
                host.addSubview(plate)
                for (i, s) in Self.samples.enumerated() {
                    let row = ListRow(item: Self.item(s))
                    row.frame = CGRect(x: 20, y: 20 + ListHeader.height + CGFloat(i) * m.listRow, width: width, height: m.listRow)
                    row.image = Self.cover(s, side: m.listCover, layout: .quad)
                    row.showsSeparator = i < Self.samples.count - 1
                    host.addSubview(row)
                }
                let header = ListHeader(frame: CGRect(x: 20, y: 20, width: width, height: ListHeader.height))
                header.sort = BrowserSort(text: "name")!
                host.addSubview(header)
            }
        }
    }
}
