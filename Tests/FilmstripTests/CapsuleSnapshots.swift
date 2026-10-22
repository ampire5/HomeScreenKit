import AppKit
import FilmstripModel
import HomeChrome
import Testing
@testable import Filmstrip

/// Pictures of the strip's tool capsule where the app puts it (on the strip, 14 pt in from its right end, centred on
/// the cells), beside and over the photo, at rest and under the pointer, for comparing with the strip sketch.
/// Runs only with `HOMESCREEN_SNAPSHOTS=<folder>` set.
@MainActor @Suite struct CapsuleSnapshots {
    nonisolated static let folder = ProcessInfo.processInfo.environment["HOMESCREEN_SNAPSHOTS"]

    static func picture(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ size: CGSize) -> CGImage {
        let c = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1))
        c.fill(CGRect(origin: .zero, size: size))
        return c.makeImage()!
    }

    static func scene(over: Bool, hovered: Bool, name: String) throws {
        guard let folder else { return }
        let size = CGSize(width: 640, height: 300)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSView(frame: CGRect(origin: .zero, size: size))
        host.wantsLayer = true
        host.layer?.backgroundColor = CGColor(srgbRed: 0x14 / 255, green: 0x14 / 255, blue: 0x16 / 255, alpha: 1)
        window.contentView = host
        let thickness: CGFloat = 68, band = thickness + 2 * FilmstripView.padding
        // The photo: the whole view over, above the strip beside.
        let photo = NSView(frame: CGRect(x: 0, y: over ? 0 : band, width: size.width, height: over ? size.height : size.height - band))
        photo.wantsLayer = true
        photo.layer?.contents = picture(0x3D / 255, 0x5A / 255, 0x73 / 255, CGSize(width: 8, height: 8))
        host.addSubview(photo)
        if !over {
            let bar = NSView(frame: CGRect(x: 0, y: 0, width: size.width, height: band))
            bar.wantsLayer = true
            bar.layer?.backgroundColor = CGColor(srgbRed: 0x23 / 255, green: 0x23 / 255, blue: 0x25 / 255, alpha: 1)
            host.addSubview(bar)
        }
        let strip = FilmstripView(frame: CGRect(x: 0, y: over ? 8 : 0, width: size.width, height: band))
        strip.isOverlay = over
        host.addSubview(strip)
        strip.setLayout(FilmstripLayout(itemCount: 40, length: Double(size.width), thickness: Double(thickness), maxAspect: 1.5,
                                        aspects: []), animated: false)
        strip.show(offset: strip.layout.centre(of: 20), current: 20, expansion: 1, animated: false)
        let colours: [(CGFloat, CGFloat, CGFloat)] = [(0.43, 0.50, 0.42), (0.48, 0.42, 0.36), (0.36, 0.42, 0.48), (0.42, 0.36, 0.48)]
        for i in 0..<40 {
            let c = colours[i % colours.count]
            strip.setImage(picture(c.0, c.1, c.2, CGSize(width: 8, height: 8)), forItem: i)
        }
        let tools = FilmstripToolsView()
        tools.tools = over
            ? [FilmstripTool(symbol: "strip.over", help: "Keep the strip beside the photo (⇧T)", action: {}),
               FilmstripTool(symbol: "pin", help: "Pin the strip (T)", separatorBefore: true, action: {})]
            : [FilmstripTool(symbol: "strip.beside", help: "Let the strip float over the photo (⇧T)", isOn: true, action: {}),
               FilmstripTool(symbol: "chevron.down", help: "Hide the strip (T)", separatorBefore: true, action: {})]
        let t = tools.fittingSize
        tools.frame = CGRect(x: size.width - 14 - t.width, y: strip.frame.midY - t.height / 2, width: t.width, height: t.height)
        host.addSubview(tools)
        if hovered {
            tools.setHovered(true)
            tools.buttons.last?.setHovered(true)
        }
        host.layoutSubtreeIfNeeded()
        host.display()
        CATransaction.flush()
        let c = CGContext(data: nil, width: Int(size.width * 2), height: Int(size.height * 2), bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.scaleBy(x: 2, y: 2)
        host.layer!.render(in: c)
        let url = URL(fileURLWithPath: folder).appendingPathComponent(name + ".png")
        try NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!.write(to: url)
        window.close()
    }

    @Test(.enabled(if: folder != nil)) func capsule() throws {
        for over in [false, true] {
            for hovered in [false, true] {
                try Self.scene(over: over, hovered: hovered,
                               name: "capsule-\(over ? "over" : "beside")-\(hovered ? "hovered" : "rest")")
            }
        }
    }
}
