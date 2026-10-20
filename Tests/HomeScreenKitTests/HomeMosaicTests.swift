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
}
