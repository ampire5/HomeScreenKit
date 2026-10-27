import AppKit

/// The apps' line icons in the set the user picked (the apps' `icon-set` key): Lucide (`Lucide`, the default since
/// 2026-10-27) or SF Symbols. Callers name an icon as an SF Symbol (`folder`, `play.fill`); in the Lucide set a name
/// Lucide has no icon for keeps its SF Symbol.
public enum Icons {
    public enum Set: String, CaseIterable, Sendable {
        case lucide, sf

        public var title: String {
            switch self {
            case .lucide: "Lucide"
            case .sf: "SF Symbols"
            }
        }
    }

    /// Set by the app at launch, before its first window: an image already made keeps its set.
    public static var set = Set.lucide

    /// Lucide's box drawn this many times the point size asked of an SF Symbol: an SF Symbol at 16 pt is about 20 pt
    /// across, as Lucide's box at 20 is with its point of room each side.
    public static let lucideScale: CGFloat = 1.25

    /// The icon `symbol` at the size an SF Symbol of `pointSize` has (a template image).
    public static func symbol(_ symbol: String, pointSize: CGFloat, weight: NSFont.Weight = .regular,
                              description: String? = nil, in set: Set = set) -> NSImage? {
        if set == .lucide, let name = Lucide.symbols[symbol] {
            return Lucide.image(name, size: (pointSize * lucideScale).rounded(), description: description)
        }
        return NSImage(systemSymbolName: symbol, accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight))
    }

    /// The icon `symbol` in a line of text of `size`, in `color`, a space after it: a Lucide glyph a point larger
    /// than the text and lowered onto the digits, or the SF Symbol as an attachment.
    public static func inline(_ symbol: String, size: CGFloat, color: NSColor, shadow: NSShadow? = nil,
                              space: String = " ", in set: Set = set) -> NSAttributedString {
        var text: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color]
        if let shadow { text[.shadow] = shadow }
        let result = NSMutableAttributedString()
        if set == .lucide, let glyph = Lucide.symbols[symbol].flatMap(Lucide.glyph) {
            let font = Lucide.font(ofSize: size + 1)
            var attributes = text
            attributes[.font] = font
            attributes[.baselineOffset] = -(font.pointSize * 0.14).rounded()
            result.append(NSAttributedString(string: glyph, attributes: attributes))
        } else {
            let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
            guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) else { return result }
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = NSRect(x: 0, y: -size * 0.22, width: image.size.width, height: image.size.height)
            result.append(NSAttributedString(attachment: attachment))
        }
        result.append(NSAttributedString(string: space, attributes: text))
        return result
    }
}
