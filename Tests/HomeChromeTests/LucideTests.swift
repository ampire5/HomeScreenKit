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
        #expect(Lucide.icon("folder", pointSize: 16)?.size == NSSize(width: 20, height: 20))
        #expect(Lucide.image("no-such-icon", size: 20) == nil)
    }

    @Test func aNameLucideLacksKeepsItsSFSymbol() {
        #expect(Lucide.icon("person.crop.circle", pointSize: 16) != nil)
    }
}
