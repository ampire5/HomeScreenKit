import AppKit

/// The apps' line icons: Lucide (lucide.dev, ISC, `LICENSE-lucide`) as a font, chosen over SF Symbols by the owner on
/// 2026-10-27 for its heavier line. A glyph is a character: it takes the text's colour and sits in a line of text (the
/// exposure's `⏱ 1/250  ◎ f/2.8`), and `image` draws it as a template image for buttons and image views. The font
/// is cut down to the icons the apps use (`scripts/lucide-names.txt`, `LucideFont.swift`); its line is Lucide's own,
/// 2 on 24, at every size, and it has no filled variants.
///
/// The apps still name their icons as SF Symbols (`folder`, `play.fill`): `icon(_:pointSize:)` draws the Lucide icon
/// standing for that name (`symbols`), and the SF Symbol itself for a name it has none for.
public enum Lucide {
    /// The font, made from the embedded data, not registered with the system: nothing outside the app sees it.
    private static let graphicsFont: CGFont? = {
        guard let data = Data(base64Encoded: fontData, options: .ignoreUnknownCharacters),
              let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGFont(provider)
    }()

    /// The font at `size`: a glyph's 24-unit box is `size` square, standing on the baseline.
    public static func font(ofSize size: CGFloat) -> NSFont {
        guard let graphicsFont else { return .systemFont(ofSize: size) }
        return CTFontCreateWithGraphicsFont(graphicsFont, size, nil, nil) as NSFont
    }

    /// The character of the icon `name` (Lucide's name: `aperture`, `hard-drive`), nil for one the font lacks.
    public static func glyph(_ name: String) -> String? {
        codepoints[name].flatMap(Unicode.Scalar.init).map { String(Character($0)) }
    }

    private static var images: [String: NSImage] = [:]

    /// The icon `name` as a template image `size` points square (its box: the line keeps a point of room inside),
    /// drawn at whatever scale the screen asks.
    public static func image(_ name: String, size: CGFloat, description: String? = nil) -> NSImage? {
        let key = "\(name)@\(size)"
        if let image = images[key] { return image }
        guard let glyph = glyph(name) else { return nil }
        let font = font(ofSize: size)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            NSAttributedString(string: glyph, attributes: [.font: font, .foregroundColor: NSColor.black]).draw(at: .zero)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description
        images[key] = image
        return image
    }

    /// Lucide's box drawn this many times the point size asked of an SF Symbol: an SF Symbol at 16 pt is about 20 pt
    /// across, as Lucide's box at 20 is with its point of room each side.
    public static let symbolScale: CGFloat = 1.25

    /// The icon for the SF Symbol name `symbol` at the size an SF Symbol of `pointSize` would have: Lucide's when
    /// `symbols` has one, else the SF Symbol in `weight`.
    public static func icon(_ symbol: String, pointSize: CGFloat, weight: NSFont.Weight = .regular,
                            description: String? = nil) -> NSImage? {
        if let name = symbols[symbol] {
            return image(name, size: (pointSize * symbolScale).rounded(), description: description)
        }
        return NSImage(systemSymbolName: symbol, accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight))
    }

    /// The Lucide icon standing for each SF Symbol name the apps use. A filled SF Symbol (`play.fill`, `pin.fill`)
    /// has the line icon: Lucide has no filled ones, a lit button says what the fill said.
    public static let symbols: [String: String] = [
        "arrow.backward": "arrow-left",
        "arrow.down.right.and.arrow.up.left": "minimize-2",
        "arrow.left.and.right": "move-horizontal",
        "arrow.turn.left.up": "corner-left-up",
        "arrow.up.and.down": "move-vertical",
        "arrow.up.left.and.arrow.down.right": "maximize-2",
        "arrow.uturn.backward": "undo-2",
        "backward.end.fill": "skip-back",
        "backward.fill": "rewind",
        "calendar": "calendar",
        "camera": "camera",
        "camera.aperture": "aperture",
        "chevron.backward.2": "chevrons-left",
        "chevron.down": "chevron-down",
        "chevron.forward.2": "chevrons-right",
        "chevron.left": "chevron-left",
        "chevron.right": "chevron-right",
        "chevron.up": "chevron-up",
        "circle.lefthalf.filled": "contrast",
        "clock": "clock",
        "doc": "file",
        "doc.richtext": "file-image",
        "doc.zipper": "file-archive",
        "drop.halffull": "droplet",
        "ellipsis.circle": "circle-ellipsis",
        "externaldrive": "hard-drive",
        "eye": "eye",
        "film": "film",
        "folder": "folder",
        "forward.end.fill": "skip-forward",
        "forward.fill": "fast-forward",
        "house": "house",
        "info.circle": "info",
        "internaldrive": "hard-drive",
        "link": "link",
        "list.bullet": "list",
        "lock": "lock",
        "magnifyingglass": "search",
        "minus": "minus",
        "minus.magnifyingglass": "zoom-out",
        "multiply": "x",
        "pause": "pause",
        "pause.fill": "pause",
        "photo": "image",
        "pin": "pin",
        "pin.fill": "pin",
        "play": "play",
        "play.fill": "play",
        "plus": "plus",
        "plus.magnifyingglass": "zoom-in",
        "plusminus.circle": "contrast",
        "radio": "radio",
        "rectangle.arrowtriangle.2.inward": "shrink",
        "rectangle.arrowtriangle.2.outward": "expand",
        "rectangle.bottomthird.inset.filled": "panel-bottom",
        "rectangle.grid.1x2": "rows-2",
        "rectangle.stack": "layers",
        "repeat": "repeat",
        "scope": "focus",
        "server.rack": "server",
        "slider.horizontal.3": "sliders-horizontal",
        "speaker.fill": "volume",
        "speaker.slash.fill": "volume-x",
        "speaker.wave.1.fill": "volume-1",
        "speaker.wave.2.fill": "volume-2",
        "speaker.wave.3.fill": "volume-2",
        "speedometer": "gauge",
        "square.grid.2x2": "layout-grid",
        "square.grid.3x3": "grid-3x3",
        "square.stack": "copy",
        "star": "star",
        "stop": "square",
        "stop.fill": "square",
        "text.alignleft": "align-left",
        "timer": "timer",
        "trash": "trash-2",
        "video": "video",
        "wand.and.stars": "wand-sparkles",
        "xmark": "x",
    ]
}
