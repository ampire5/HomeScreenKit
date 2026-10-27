import AppKit
import HomeChrome
import HomeScreenModel

/// The colours of what a card says about its picture, by kind (the owner's choice of 2026-10-27, board «Цвет бейджей
/// и значков», style A): a badge's text and ring in the colour of what it says (the frame blue, the rate teal, HDR
/// amber, RAW violet, megapixels green), an exposure value's glyph in its own colour and the number light. Red is not
/// among them: it stays for errors and recording. `monochrome` (the apps' `monochrome` key) leaves them light grey.
public enum MediaPalette {
    /// Set by the app from its `monochrome` key; cards read it as they lay out.
    public static var monochrome = false

    /// The numbers and a monochrome badge's text.
    public static let text = rgb(0xE6E8EB)
    /// A monochrome glyph.
    static let quietGlyph = rgb(0xC9CDD2)

    /// The colour of a badge saying `kind`; nil when monochrome.
    public static func color(_ kind: FileFactsText.BadgeKind) -> NSColor? {
        guard !monochrome else { return nil }
        switch kind {
        case .resolution: return rgb(0x5AB0FF)
        case .rate: return rgb(0x3CCFB8)
        case .transfer: return rgb(0xF5B83D)
        case .raw: return rgb(0xB79CFF)
        case .megapixels: return rgb(0x8FD46A)
        }
    }

    /// The colour of the glyph in front of an exposure value of `kind`.
    public static func color(_ kind: FileFactsText.ExposureKind) -> NSColor {
        guard !monochrome else { return quietGlyph }
        switch kind {
        case .shutter: return rgb(0xFF9F43)
        case .aperture: return rgb(0x3CCFB8)
        case .iso: return rgb(0xFF7AA8)
        case .focalLength: return rgb(0xB79CFF)
        case .bias: return rgb(0xF5B83D)
        }
    }

    /// The Lucide icon in front of an exposure value of `kind`.
    public static func glyph(_ kind: FileFactsText.ExposureKind) -> String {
        switch kind {
        case .shutter: "timer"
        case .aperture: "aperture"
        case .iso: "camera"
        case .focalLength: "focus"
        case .bias: "contrast"
        }
    }

    /// The exposure as a line: each value after its glyph in its colour (a Lucide glyph a point larger than the text,
    /// set on the text's baseline), the numbers in `color`, two spaces between the values.
    public static func exposure(_ values: [FileFactsText.ExposureValue], font: NSFont, color: NSColor = text,
                                shadow: NSShadow? = nil) -> NSAttributedString {
        let glyphFont = Lucide.font(ofSize: font.pointSize + 1)
        var base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if let shadow { base[.shadow] = shadow }
        let line = NSMutableAttributedString()
        for (i, value) in values.enumerated() {
            if i > 0 { line.append(NSAttributedString(string: "  ", attributes: base)) }
            if let glyph = Lucide.glyph(glyph(value.kind)) {
                var attributes = base
                attributes[.font] = glyphFont
                attributes[.foregroundColor] = Self.color(value.kind)
                // The box stands on the baseline: lowered by the text's descent, it centres on the digits.
                attributes[.baselineOffset] = -(glyphFont.pointSize * 0.14).rounded()
                line.append(NSAttributedString(string: glyph, attributes: attributes))
                line.append(NSAttributedString(string: "\u{2009}", attributes: base))
            }
            line.append(NSAttributedString(string: value.text, attributes: base))
        }
        return line
    }

    static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
