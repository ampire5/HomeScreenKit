import CoreGraphics
import Foundation

/// Up to four pictures in one, with thin gaps: a session card's picture, and a folder's in the file browser. The
/// layout says how they sit: `grid` (one fills, two side by side, three a large one on the left and two stacked, four
/// 2×2), `hero` (a large one on top, up to three under it), `stack` (three prints with a slight turn and a shadow) or
/// `single` (the first fills). Each picture is cropped to its cell.
public enum HomeMosaic {
    public static let gap: CGFloat = 2

    public enum Layout: String, CaseIterable, Sendable { case grid, hero, stack, single }

    /// A card narrower than this (points) shows one picture in any layout: smaller cells do not read.
    public static let narrowWidth: CGFloat = 110

    /// `size` is in points, the image is `size × scale` pixels.
    public static func make(_ images: [CGImage], size: CGSize = CGSize(width: 600, height: 400),
                            layout: Layout = .grid, scale: CGFloat = 1) -> CGImage? {
        guard !images.isEmpty, size.width >= 1, size.height >= 1, scale > 0 else { return nil }
        let w = Int((size.width * scale).rounded()), h = Int((size.height * scale).rounded())
        guard w >= 1, h >= 1,
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Work in points, top-down: the context's y goes up, so flip once.
        context.scaleBy(x: CGFloat(w) / size.width, y: CGFloat(h) / size.height)
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        let bounds = CGRect(origin: .zero, size: size)
        let cells = cells(count: images.count, layout: layout, in: bounds)
        if effective(layout, width: size.width) == .stack, cells.count > 1 {
            drawStack(Array(images.prefix(cells.count)), cells: cells, in: context)
        } else {
            for (image, cell) in zip(images, cells) { draw(image, in: cell, context) }
        }
        return context.makeImage()
    }

    /// `image` cropped to `cell` (the context is top-down, so the picture is flipped back).
    private static func draw(_ image: CGImage, in cell: CGRect, _ context: CGContext) {
        let scale = max(cell.width / CGFloat(image.width), cell.height / CGFloat(image.height))
        let drawn = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        context.saveGState()
        context.clip(to: cell)
        context.translateBy(x: cell.midX, y: cell.midY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: -drawn.width / 2, y: -drawn.height / 2, width: drawn.width, height: drawn.height))
        context.restoreGState()
    }

    /// Prints piled on a table: the one on top (the first) is straight, the others turned; each has a soft shadow and
    /// a thin light border.
    private static func drawStack(_ images: [CGImage], cells: [CGRect], in context: CGContext) {
        let rotations = stackRotations(count: images.count)
        // The straightest print goes last, on top.
        let order = images.indices.sorted { abs(rotations[$0]) > abs(rotations[$1]) }
        for i in order {
            let cell = cells[i]
            context.saveGState()
            context.translateBy(x: cell.midX, y: cell.midY)
            context.rotate(by: rotations[i] * .pi / 180)
            let local = CGRect(x: -cell.width / 2, y: -cell.height / 2, width: cell.width, height: cell.height)
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -2), blur: 6,
                              color: CGColor(gray: 0, alpha: 0.35))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(local)
            context.restoreGState()
            draw(images[i], in: local, context)
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.7))
            context.setLineWidth(1)
            context.stroke(local.insetBy(dx: 0.5, dy: 0.5))
            context.restoreGState()
        }
    }

    /// The turn of each print of a stack, in degrees, back to front: −4, 0, +4 for three.
    public static func stackRotations(count: Int) -> [CGFloat] {
        switch count {
        case ..<1: return []
        case 1: return [0]
        case 2: return [-4, 4]
        default: return [-4, 0, 4]
        }
    }

    private static func effective(_ layout: Layout, width: CGFloat) -> Layout { width < narrowWidth ? .single : layout }

    /// The cells for `count` pictures in `rect` (a grid takes four at most, a stack three), top-down, left to right.
    /// For a stack these are the prints before the turn.
    public static func cells(count: Int, layout: Layout, in rect: CGRect) -> [CGRect] {
        guard count >= 1 else { return [] }
        let size = rect.size, g = gap / 2
        let local: [CGRect]
        switch effective(layout, width: size.width) {
        case .single: local = [CGRect(origin: .zero, size: size)]
        case .grid: local = cells(count: count, size: size)
        case .hero:
            let w = size.width, h = size.height
            guard count > 1 else { local = [CGRect(origin: .zero, size: size)]; break }
            let top = CGRect(x: 0, y: 0, width: w, height: h * 2 / 3 - g)
            let small = min(count - 1, 3)
            let y = h * 2 / 3 + g, cellW = (w - gap * CGFloat(small - 1)) / CGFloat(small)
            local = [top] + (0..<small).map {
                CGRect(x: CGFloat($0) * (cellW + gap), y: y, width: cellW, height: h - y)
            }
        case .stack:
            guard count > 1 else { local = [CGRect(origin: .zero, size: size)]; break }
            // Inset so the turned corners stay inside the picture.
            local = Array(repeating: CGRect(origin: .zero, size: size).insetBy(dx: size.width * 0.1, dy: size.height * 0.1),
                          count: min(count, 3))
        }
        return local.map { $0.offsetBy(dx: rect.minX, dy: rect.minY) }
    }

    /// The grid's cells for `count` pictures (four at most), top-down, left to right.
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
