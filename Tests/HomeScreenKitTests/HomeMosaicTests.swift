import CoreGraphics
import Testing
@testable import HomeScreenKit

@Suite struct HomeMosaicTests {
    let size = CGSize(width: 300, height: 200)

    @Test func layoutsByCount() {
        #expect(HomeMosaic.cells(count: 1, size: size) == [CGRect(x: 0, y: 0, width: 300, height: 200)])
        let two = HomeMosaic.cells(count: 2, size: size)
        #expect(two.count == 2 && two[0].maxX < two[1].minX && two.allSatisfy { $0.height == 200 })
        // Three: the first large on the left, two stacked on the right.
        let three = HomeMosaic.cells(count: 3, size: size)
        #expect(three.count == 3 && three[0].height == 200 && three[1].height < 100 && three[1].minX > three[0].maxX)
        #expect(HomeMosaic.cells(count: 4, size: size).count == 4)
        #expect(HomeMosaic.cells(count: 7, size: size).count == 4)
    }

    @Test func madeAtTheCardShape() {
        let c = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = c.makeImage()!
        let mosaic = HomeMosaic.make([image, image, image], size: CGSize(width: 400, height: 400))
        #expect(mosaic?.width == 400 && mosaic?.height == 400)
    }

    @Test func heroCells() {
        let c = HomeMosaic.cells(count: 4, layout: .hero, in: CGRect(origin: .zero, size: size))
        #expect(c.count == 4)
        #expect(c[0].minX == 0 && c[0].width == 300 && abs(c[0].height - 200 * 2 / 3) <= 1)
        let small = Array(c.dropFirst())
        #expect(small.allSatisfy { $0.minY > c[0].maxY && abs($0.width - small[0].width) < 0.001 && $0.maxY == 200 })
        #expect(abs(small[1].minX - small[0].maxX - 2) < 0.001 && abs(small[2].minX - small[1].maxX - 2) < 0.001)
        #expect(abs(small[2].maxX - 300) < 0.001)
    }

    @Test func heroDegrades() {
        let r = CGRect(origin: .zero, size: size)
        let three = HomeMosaic.cells(count: 3, layout: .hero, in: r)
        #expect(three.count == 3 && three[0].width == 300 && three[1].width < 150)
        #expect(HomeMosaic.cells(count: 2, layout: .hero, in: r).count == 2)
        #expect(HomeMosaic.cells(count: 1, layout: .hero, in: r) == [r])
    }

    @Test func stackRotations() {
        #expect(HomeMosaic.stackRotations(count: 3) == [-4, 0, 4])
        #expect(HomeMosaic.cells(count: 5, layout: .stack, in: CGRect(origin: .zero, size: size)).count == 3)
    }

    @Test func gridStaysAsBefore() {
        let r = CGRect(origin: .zero, size: size)
        for n in 0...5 {
            #expect(HomeMosaic.cells(count: n, layout: .grid, in: r) == HomeMosaic.cells(count: n, size: size))
        }
        #expect(HomeMosaic.cells(count: 4, layout: .grid, in: r)[3] == CGRect(x: 151, y: 101, width: 149, height: 99))
    }

    @Test func narrowIsSingle() {
        let r = CGRect(x: 0, y: 0, width: 100, height: 70)
        for layout in HomeMosaic.Layout.allCases where layout != .quad {
            #expect(HomeMosaic.cells(count: 4, layout: layout, in: r) == [r])
        }
    }

    /// A list row's 32 pt cover is four photos with 1 pt gaps, small as it is.
    @Test func quadKeepsFourCellsWhenSmall() {
        let cells = HomeMosaic.cells(count: 4, layout: .quad, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        #expect(cells == [CGRect(x: 0, y: 0, width: 15.5, height: 15.5), CGRect(x: 16.5, y: 0, width: 15.5, height: 15.5),
                          CGRect(x: 0, y: 16.5, width: 15.5, height: 15.5), CGRect(x: 16.5, y: 16.5, width: 15.5, height: 15.5)])
    }

    @Test func everyLayoutDraws() {
        let c = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = c.makeImage()!
        for layout in HomeMosaic.Layout.allCases {
            let m = HomeMosaic.make([image, image, image, image], size: CGSize(width: 200, height: 130), layout: layout, scale: 2)
            #expect(m?.width == 400 && m?.height == 260)
        }
    }

    /// A solid red picture `width` × `height` pixels.
    private func red(_ width: Int, _ height: Int) -> CGImage {
        let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        c.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return c.makeImage()!
    }

    /// The alpha of the pixel at `x`, `y` (from the top) of `image`.
    private func alpha(_ image: CGImage, _ x: Int, _ y: Int) -> UInt8 {
        let c = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                          bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = c.data!.assumingMemoryBound(to: UInt8.self)
        return bytes[(y * image.width + x) * 4 + 3]
    }

    /// A panorama's thumbnail (a 2880 × 810 photo kept 288 × 81) cannot fill a square cell without being enlarged
    /// several times: it is fitted, whole and sharp, with the card's own fill above and below it.
    @Test func wideThumbnailIsFittedNotStretched() throws {
        let mosaic = try #require(HomeMosaic.make([red(288, 81)], size: CGSize(width: 200, height: 200),
                                                  layout: .single, scale: 2))
        #expect(alpha(mosaic, 200, 200) == 255)   // the picture in the middle
        #expect(alpha(mosaic, 200, 10) == 0)      // nothing above it
        #expect(alpha(mosaic, 200, 390) == 0)     // nor below
        #expect(alpha(mosaic, 2, 200) == 255)     // from edge to edge across
    }

    /// An ordinary photo's thumbnail fills its cell, cropped, as before: enlarged less than twice.
    @Test func ordinaryThumbnailStillFills() throws {
        let mosaic = try #require(HomeMosaic.make([red(300, 200)], size: CGSize(width: 200, height: 200),
                                                  layout: .single, scale: 2))
        #expect(alpha(mosaic, 200, 2) == 255 && alpha(mosaic, 200, 397) == 255 && alpha(mosaic, 2, 2) == 255)
        #expect(HomeMosaic.fills(CGSize(width: 300, height: 200), cell: CGSize(width: 400, height: 400)))
        #expect(!HomeMosaic.fills(CGSize(width: 288, height: 81), cell: CGSize(width: 400, height: 400)))
    }

    /// At the default poster size on a Retina screen a cell is about 704 px, and a 512 px thumbnail of an ordinary
    /// 3:2 or 16:9 photo must be enlarged about 2–2.5 times to fill it: it still fills (cropped), as a photo always
    /// did. Only a picture whose shape is far from the cell's (more than 2:1 apart: the crop would throw away more
    /// than half of it) is fitted, whatever the enlargement.
    @Test func shapeNotEnlargementDecidesFit() throws {
        let cell = CGSize(width: 704, height: 704)
        #expect(HomeMosaic.fills(CGSize(width: 512, height: 341), cell: cell))
        #expect(HomeMosaic.fills(CGSize(width: 512, height: 288), cell: cell))
        #expect(HomeMosaic.fills(CGSize(width: 341, height: 512), cell: cell))
        #expect(!HomeMosaic.fills(CGSize(width: 512, height: 144), cell: cell))   // a 2880 × 810 panorama's thumbnail
        #expect(!HomeMosaic.fills(CGSize(width: 2880, height: 810), cell: cell))
        // a wide cell (a hero's top) takes a wide photo filled
        #expect(HomeMosaic.fills(CGSize(width: 512, height: 144), cell: CGSize(width: 704, height: 234)))
        // drawn: the 3:2 thumbnail reaches the cell's top and bottom edges
        let mosaic = try #require(HomeMosaic.make([red(512, 341)], size: CGSize(width: 352, height: 352),
                                                  layout: .single, scale: 2))
        #expect(alpha(mosaic, 352, 2) == 255 && alpha(mosaic, 352, 701) == 255)
    }

    /// The default hero cover's large cell is about 1.5:1: a portrait photo (3:4, 2:3) fills it, cropped, as photos
    /// always did; a panorama in a square cell is still fitted.
    @Test func portraitsFillTheHeroCell() {
        let hero = HomeMosaic.cells(count: 4, layout: .hero, in: CGRect(x: 0, y: 0, width: 232, height: 232))[0]
        #expect(HomeMosaic.fills(CGSize(width: 384, height: 512), cell: hero.size))
        #expect(HomeMosaic.fills(CGSize(width: 341, height: 512), cell: hero.size))
        #expect(!HomeMosaic.fills(CGSize(width: 2880, height: 810), cell: CGSize(width: 232, height: 232)))
    }

    /// A compact card's 76 pt cover keeps its layout (board B draws the hero there), with 1.5 pt gaps.
    @Test func compactCoverKeepsTheHero() {
        let r = CGRect(x: 0, y: 0, width: 76, height: 76)
        #expect(HomeMosaic.cells(count: 4, layout: .hero, in: r) == [r])   // any other narrow card: one picture
        let cells = HomeMosaic.cells(count: 4, layout: .hero, in: r, compact: true)
        #expect(cells.count == 4 && cells[0].width == 76 && abs(cells[1].minY - cells[0].maxY - 1.5) < 0.001)
        #expect(abs(cells[2].minX - cells[1].maxX - 1.5) < 0.001)
    }
}
