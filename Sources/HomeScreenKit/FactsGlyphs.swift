import AppKit
import HomeScreenModel

/// A photo's exposure as ProCam draws it (board «Эскизы файлов» B): a glyph before each value instead of words —
/// the aperture, the shutter, ISO in a frame, the focal length. One attributed line, so a label draws it in one go.
enum FactsGlyphs {
    /// The line with as many of its values as fit `maxWidth` (whole values, the focal length first to go), nil when
    /// not even the first fits.
    static func exposure(_ f: FileFacts, font: NSFont, color: NSColor, maxWidth: CGFloat) -> NSAttributedString? {
        var count = 4
        while count > 0 {
            guard let line = exposure(f, font: font, color: color, limit: count) else { return nil }
            if line.size().width <= maxWidth { return line }
            count -= 1
        }
        return nil
    }

    static func exposure(_ f: FileFacts, font: NSFont, color: NSColor, limit: Int = 4) -> NSAttributedString? {
        var parts: [(symbol: String?, text: String)] = []
        if let a = f.aperture, a > 0 { parts.append(("camera.aperture", FileFactsText.number(a))) }
        if let e = f.exposure, e > 0 { parts.append(("timer", FileFactsText.shutter(e))) }
        if let iso = f.iso, iso > 0 { parts.append((nil, "\(iso)")) }
        if let mm = f.focalLength, mm > 0 { parts.append(("scope", FileFactsText.number(mm))) }
        parts = Array(parts.prefix(limit))
        guard !parts.isEmpty else { return nil }
        let text = NSMutableAttributedString()
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        for (i, part) in parts.enumerated() {
            if i > 0 { text.append(NSAttributedString(string: "   ", attributes: attributes)) }
            if let name = part.symbol, let glyph = symbol(name, size: font.pointSize * 0.9, color: color) {
                let attachment = NSTextAttachment()
                attachment.image = glyph
                // Centred on the digits' height, not hanging below the baseline into the strip's edge.
                let y = ((font.capHeight - glyph.size.height) / 2).rounded()
                attachment.bounds = CGRect(x: 0, y: y, width: glyph.size.width, height: glyph.size.height)
                text.append(NSAttributedString(attachment: attachment))
                text.append(NSAttributedString(string: "\u{2009}", attributes: attributes))
            } else {
                // ISO: the word small and bold, as a camera's display shows it.
                let small = NSFont.systemFont(ofSize: font.pointSize * 0.8, weight: .heavy)
                text.append(NSAttributedString(string: "ISO\u{2009}", attributes: [.font: small, .foregroundColor: color]))
            }
            text.append(NSAttributedString(string: part.text, attributes: attributes))
        }
        return text
    }

    /// SF Symbols by name and size, tinted: made once each.
    private static var symbols: [String: NSImage] = [:]

    private static func symbol(_ name: String, size: CGFloat, color: NSColor) -> NSImage? {
        let key = "\(name)/\(size)/\(color.description)"
        if let image = symbols[key] { return image }
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
            .applying(.init(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        else { return nil }
        symbols[key] = image
        return image
    }
}
