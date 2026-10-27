import AppKit
import Testing
@testable import HomeChrome

@Suite struct LucideTests {
    @Test func everySymbolHasItsIconInTheFont() {
        for (symbol, name) in Lucide.symbols {
            #expect(Lucide.glyph(name) != nil, "\(symbol) → \(name) is not in LucideFont.swift (scripts/lucide-names.txt)")
        }
    }

    @Test func theFontLoadsFromTheEmbeddedData() {
        let font = Lucide.font(ofSize: 20)
        #expect(font.fontName.lowercased().contains("lucide"))
        // Every icon has an outline in it, not the empty glyph.
        for (name, code) in Lucide.codepoints {
            var unichar = UniChar(code)
            var glyph = CGGlyph(0)
            #expect(CTFontGetGlyphsForCharacters(font, &unichar, &glyph, 1) && glyph != 0, "\(name)")
        }
    }

    @Test func anIconIsATemplateOfItsSize() throws {
        let image = try #require(Lucide.image("folder", size: 20, description: "Folder"))
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 20, height: 20))
        #expect(image.accessibilityDescription == "Folder")
        // An SF Symbol name Lucide stands for is drawn by Lucide, 1.25 times its point size.
        #expect(Icons.symbol("folder", pointSize: 16, in: .lucide)?.size == NSSize(width: 20, height: 20))
        #expect(Lucide.image("no-such-icon", size: 20) == nil)
    }

    @Test func aNameLucideLacksKeepsItsSFSymbol() {
        #expect(Icons.symbol("person.crop.circle", pointSize: 16, in: .lucide)?.isTemplate == true)
    }

    @Test func theSFSetDrawsTheSymbolsThemselves() throws {
        let sf = try #require(Icons.symbol("folder", pointSize: 16, in: .sf))
        #expect(sf.size != NSSize(width: 20, height: 20))   // an SF Symbol's own size, not Lucide's box
        // In a line: Lucide is a character of its font, an SF Symbol an attachment.
        let lucide = Icons.inline("timer", size: 11, color: .white, in: .lucide)
        #expect(lucide.attribute(.attachment, at: 0, effectiveRange: nil) == nil)
        #expect(Icons.inline("timer", size: 11, color: .white, in: .sf).attribute(.attachment, at: 0, effectiveRange: nil) != nil)
    }
}

extension LucideTests {
    /// The ink's middle, in points from the image's middle, of `name` drawn `size` square at 2×.
    private func inkOffset(_ name: String, size: CGFloat = 24) throws -> CGPoint {
        let image = try #require(Lucide.image(name, size: size))
        let px = Int(size * 2)
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        var minX = px, maxX = 0, minY = px, maxY = 0
        for y in 0..<px { for x in 0..<px where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        return CGPoint(x: (CGFloat(minX + maxX + 1) / 2 - CGFloat(px) / 2) / 2,
                       y: (CGFloat(minY + maxY + 1) / 2 - CGFloat(px) / 2) / 2)
    }

    @Test func anIconIsCentredByItsDrawingNotByLucidesBox() throws {
        for name in ["play", "volume-2", "volume", "house", "chevron-left", "file-image", "pin"] {
            let offset = try inkOffset(name)
            #expect(abs(offset.x) <= 0.5 && abs(offset.y) <= 0.5, "\(name) off by \(offset)")
        }
    }
}
