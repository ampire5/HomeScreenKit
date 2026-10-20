import CoreGraphics

/// Up to four pictures in one, with thin gaps: a session card's picture, and a folder's in the file browser. One fills
/// it, two share it side by side, three put the first large on the left and two stacked on the right, four make a
/// 2×2 grid; each is cropped to its cell.
public enum HomeMosaic {
    public static let gap: CGFloat = 2

    public static func make(_ images: [CGImage], size: CGSize = CGSize(width: 600, height: 400)) -> CGImage? {
        guard !images.isEmpty, size.width >= 1, size.height >= 1 else { return nil }
        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // `cells` is top-down; a CGContext's y goes up.
        for (image, cell) in zip(images, cells(count: images.count, size: CGSize(width: w, height: h))) {
            let flipped = CGRect(x: cell.minX, y: CGFloat(h) - cell.maxY, width: cell.width, height: cell.height)
            let scale = max(flipped.width / CGFloat(image.width), flipped.height / CGFloat(image.height))
            let drawn = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            context.saveGState()
            context.clip(to: flipped)
            context.draw(image, in: CGRect(x: flipped.midX - drawn.width / 2, y: flipped.midY - drawn.height / 2,
                                           width: drawn.width, height: drawn.height))
            context.restoreGState()
        }
        return context.makeImage()
    }

    /// The cells for `count` pictures (four at most), top-down, left to right.
    public static func cells(count: Int, size: CGSize) -> [CGRect] {
        let w = size.width, h = size.height, g = gap / 2
        let left = CGRect(x: 0, y: 0, width: w / 2 - g, height: h)
        let right = CGRect(x: w / 2 + g, y: 0, width: w / 2 - g, height: h)
        func quarter(_ column: Int, _ row: Int) -> CGRect {
            CGRect(x: column == 0 ? 0 : w / 2 + g, y: row == 0 ? 0 : h / 2 + g, width: w / 2 - g, height: h / 2 - g)
        }
        switch count {
        case ..<1: return []
        case 1: return [CGRect(origin: .zero, size: size)]
        case 2: return [left, right]
        case 3: return [left, quarter(1, 0), quarter(1, 1)]
        default: return [quarter(0, 0), quarter(1, 0), quarter(0, 1), quarter(1, 1)]
        }
    }
}
