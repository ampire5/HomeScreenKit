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
        for layout in HomeMosaic.Layout.allCases {
            #expect(HomeMosaic.cells(count: 4, layout: layout, in: r) == [r])
        }
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
}
