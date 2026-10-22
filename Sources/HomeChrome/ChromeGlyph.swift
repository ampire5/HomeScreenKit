import AppKit

/// A small line icon drawn from SVG path data on a square (or given) view box, the way the mockups draw their glyphs:
/// the cards' ⧉, ✓, photo, folder, cloud and warning marks, and the strip capsule's buttons. Drawn in the view's
/// colour at any size; the line width is in view-box units, so it scales with the glyph as an SVG's does.
public struct ChromeGlyph {
    public enum Fill {
        case none
        /// Filled with the glyph's colour.
        case ink
        /// Filled with a fixed colour (a shape that hides what is behind it, such as a front window).
        case color(NSColor)
    }

    public struct Part {
        public let path: CGPath
        public let stroke: Bool
        public let fill: Fill

        public init(_ path: CGPath, stroke: Bool = true, fill: Fill = .none) {
            self.path = path
            self.stroke = stroke
            self.fill = fill
        }
    }

    public let viewBox: CGSize
    public let parts: [Part]
    /// Round caps and joins (the strip's glyphs) rather than the SVG defaults.
    public let round: Bool

    public init(viewBox: CGSize = CGSize(width: 16, height: 16), round: Bool = false, _ parts: [Part]) {
        self.viewBox = viewBox
        self.round = round
        self.parts = parts
    }

    /// Draws the glyph scaled into `rect` (top-down: the context must be flipped, as a flipped view's is).
    public func draw(in rect: CGRect, context: CGContext, color: CGColor, lineWidth: CGFloat) {
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        context.saveGState()
        context.translateBy(x: rect.midX - viewBox.width * scale / 2, y: rect.midY - viewBox.height * scale / 2)
        context.scaleBy(x: scale, y: scale)
        context.setLineWidth(lineWidth)
        context.setLineCap(round ? .round : .butt)
        context.setLineJoin(round ? .round : .miter)
        context.setStrokeColor(color)
        for part in parts {
            switch part.fill {
            case .none: break
            case .ink:
                context.setFillColor(color)
                context.addPath(part.path)
                context.fillPath()
            case .color(let fill):
                context.setFillColor(fill.cgColor)
                context.addPath(part.path)
                context.fillPath()
            }
            if part.stroke {
                context.addPath(part.path)
                context.strokePath()
            }
        }
        context.restoreGState()
    }

    // MARK: Shapes

    public static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, radius: CGFloat = 0) -> CGPath {
        CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: radius, cornerHeight: radius,
               transform: nil)
    }

    /// An SVG path's `d` (M, L, H, V, A, Z and their relative forms; circular arcs).
    public static func svg(_ d: String) -> CGPath {
        let path = CGMutablePath()
        var tokens = SVGTokens(d)
        var current = CGPoint.zero, start = CGPoint.zero
        var command: Character = "M"
        while let next = tokens.nextCommand(after: command) {
            command = next
            let relative = command.isLowercase
            func point() -> CGPoint {
                let x = tokens.number(), y = tokens.number()
                return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }
            switch command.uppercased() {
            case "M":
                current = point()
                start = current
                path.move(to: current)
                command = relative ? "l" : "L"   // more pairs after a move are lines
            case "L":
                current = point()
                path.addLine(to: current)
            case "H":
                let x = tokens.number()
                current.x = relative ? current.x + x : x
                path.addLine(to: current)
            case "V":
                let y = tokens.number()
                current.y = relative ? current.y + y : y
                path.addLine(to: current)
            case "A":
                let r = tokens.number()
                _ = tokens.number()   // a circle: ry = rx
                _ = tokens.number()   // no rotation for a circle
                let large = tokens.number() != 0, sweep = tokens.number() != 0
                let end = point()
                addArc(path, from: current, to: end, radius: r, large: large, sweep: sweep)
                current = end
            case "Z":
                path.closeSubpath()
                current = start
            default:
                return path
            }
        }
        return path
    }

    /// An SVG circular arc (endpoint form) as a Core Graphics arc: the centre from the end points, the radius grown
    /// when it cannot span them (SVG's rule).
    private static func addArc(_ path: CGMutablePath, from p1: CGPoint, to p2: CGPoint, radius: CGFloat, large: Bool,
                               sweep: Bool) {
        guard radius > 0, p1 != p2 else { path.addLine(to: p2); return }
        let hx = (p1.x - p2.x) / 2, hy = (p1.y - p2.y) / 2
        var r = abs(radius)
        let lambda = (hx * hx + hy * hy) / (r * r)
        if lambda > 1 { r *= sqrt(lambda) }
        let num = max(0, r * r * r * r - r * r * hy * hy - r * r * hx * hx)
        let den = r * r * hy * hy + r * r * hx * hx
        let coef = (large == sweep ? -1 : 1) * sqrt(num / den)
        let centre = CGPoint(x: coef * hy + (p1.x + p2.x) / 2, y: -coef * hx + (p1.y + p2.y) / 2)
        let a1 = atan2(p1.y - centre.y, p1.x - centre.x), a2 = atan2(p2.y - centre.y, p2.x - centre.x)
        path.addArc(center: centre, radius: r, startAngle: a1, endAngle: a2, clockwise: !sweep)
    }

    // MARK: The cards' glyphs (view box 16)

    /// ⧉: two pages side by side.
    public static let twoPages = ChromeGlyph([Part(rect(1.5, 3, 6, 10, radius: 1)), Part(rect(8.5, 3, 6, 10, radius: 1))])
    /// ✓.
    public static let check = ChromeGlyph([Part(svg("M3.5 8.5l3 3 6-7"))])
    public static let photo = ChromeGlyph([Part(rect(2, 3, 12, 10, radius: 2)), Part(svg("M2 11l3.5-3.5 3 3 2-2L14 12"))])
    public static let folder = ChromeGlyph([Part(svg(
        "M2 4.5A1.5 1.5 0 0 1 3.5 3h3l1.5 1.5h4.5A1.5 1.5 0 0 1 14 6v5.5a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 2 11.5z"))])
    /// A cloud struck through: the volume is not there.
    public static let offline = ChromeGlyph([Part(svg("M4.5 12.5h7a2.5 2.5 0 0 0 .4-5 4 4 0 0 0-7.6-1A3 3 0 0 0 4.5 12.5z")),
                                             Part(svg("M2 2l12 12"))])
    /// A warning triangle: the archive cannot be read.
    public static let warning = ChromeGlyph([Part(svg("M8 2.5l6 11H2z")), Part(svg("M8 7v3M8 11.6v.4"))])

    // MARK: The strip capsule's glyphs

    /// "The strip is beside the photo": a window with its bottom band filled (16 × 14).
    public static let stripBeside = ChromeGlyph(viewBox: CGSize(width: 16, height: 14), [
        Part(rect(1, 1, 14, 12, radius: 2)),
        Part(rect(3, 8.5, 10, 2.5, radius: 0.6), stroke: false, fill: .ink),
    ])
    /// "The strip floats over the photo": a window in front of another (16 × 14). The front one hides the back one.
    public static func stripOver(behind: NSColor) -> ChromeGlyph {
        ChromeGlyph(viewBox: CGSize(width: 16, height: 14), [
            Part(rect(4, 1, 11, 8, radius: 1.6)),
            Part(rect(1, 5, 11, 8, radius: 1.6), fill: .color(behind)),
        ])
    }
    /// A pin, in outline (pin the strip) or filled (unpin it) (14 × 14, round strokes).
    public static let pin = ChromeGlyph(viewBox: CGSize(width: 14, height: 14), round: true,
                                        [Part(svg("M5 1.5h4M5.5 1.5v4L3.5 8h7l-2-2.5v-4M7 8v4.5"))])
    public static let pinFilled = ChromeGlyph(viewBox: CGSize(width: 14, height: 14), round: true, [
        Part(svg("M5 1.5h4M5.5 1.5v4L3.5 8h7l-2-2.5v-4z"), fill: .ink),
        Part(svg("M7 8v4.5")),
    ])
    /// A chevron down: hide the strip (14 × 14, round strokes).
    public static let chevronDown = ChromeGlyph(viewBox: CGSize(width: 14, height: 14), round: true,
                                                [Part(svg("M3 5l4 4 4-4"))])
}

/// The number and command reader of `ChromeGlyph.svg`.
private struct SVGTokens {
    private let chars: [Character]
    private var i = 0

    init(_ d: String) { chars = Array(d) }

    private mutating func skipSeparators() {
        while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" || chars[i] == "\t" { i += 1 }
    }

    /// The next command letter, or `previous` again when a number follows (an implicit repeat); nil at the end.
    mutating func nextCommand(after previous: Character) -> Character? {
        skipSeparators()
        guard i < chars.count else { return nil }
        if chars[i].isLetter {
            defer { i += 1 }
            return chars[i]
        }
        return previous
    }

    mutating func number() -> CGFloat {
        skipSeparators()
        var text = ""
        var seenDot = false, seenExponent = false
        while i < chars.count {
            let c = chars[i]
            if c == "-" || c == "+" {
                guard text.isEmpty || text.last == "e" || text.last == "E" else { break }
            } else if c == "." {
                guard !seenDot, !seenExponent else { break }
                seenDot = true
            } else if c == "e" || c == "E" {
                guard !seenExponent, !text.isEmpty else { break }
                seenExponent = true
            } else if !c.isNumber {
                break
            }
            text.append(c)
            i += 1
        }
        return CGFloat(Double(text) ?? 0)
    }
}

/// A view that draws one `ChromeGlyph` in its bounds, in `color` (a dynamic colour follows the appearance).
public final class GlyphView: NSView {
    public var glyph: ChromeGlyph? { didSet { needsDisplay = true } }
    public var color: NSColor = .labelColor { didSet { needsDisplay = true } }
    /// In view-box units, like an SVG's `stroke-width`.
    public var lineWidth: CGFloat = 1.4 { didSet { needsDisplay = true } }

    public init(_ glyph: ChromeGlyph? = nil, color: NSColor = .labelColor, lineWidth: CGFloat = 1.4) {
        self.glyph = glyph
        self.color = color
        self.lineWidth = lineWidth
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var isFlipped: Bool { true }
    public override var isOpaque: Bool { false }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let glyph, let context = NSGraphicsContext.current?.cgContext else { return }
        var cg = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { cg = color.cgColor }
        glyph.draw(in: bounds, context: context, color: cg, lineWidth: lineWidth)
    }
}
