import AppKit
import HomeChrome
import HomeScreenModel

/// The exposure as a line on a card (the hover strip, Loupe's facts row): each value after its glyph, two spaces
/// between the values. The glyphs are in one quiet colour, the numbers in the text's: the Media UI Iconography style
/// guide's single accent leaves colour to selection, recording and errors (the owner, 2026-10-27).
public enum ExposureLine {
    /// The icon (an SF Symbol name, `Icons` draws it in the set picked) in front of a value of `kind`.
    public static func symbol(_ kind: FileFactsText.ExposureKind) -> String {
        switch kind {
        case .shutter: "timer"
        case .aperture: "camera.aperture"
        case .iso: "camera"
        case .focalLength: "scope"
        case .bias: "plusminus.circle"
        }
    }

    public static func text(_ values: [FileFactsText.ExposureValue], font: NSFont, color: NSColor,
                            glyphColor: NSColor, shadow: NSShadow? = nil) -> NSAttributedString {
        var base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if let shadow { base[.shadow] = shadow }
        let line = NSMutableAttributedString()
        for (i, value) in values.enumerated() {
            if i > 0 { line.append(NSAttributedString(string: "  ", attributes: base)) }
            line.append(Icons.inline(symbol(value.kind), size: font.pointSize, color: glyphColor, shadow: shadow,
                                     space: "\u{2009}"))
            line.append(NSAttributedString(string: value.text, attributes: base))
        }
        return line
    }
}
