import AppKit
import Testing
@testable import HomeChrome

/// The mockups' SVG glyphs read into paths: lines, relative moves and circular arcs.
@Suite struct ChromeGlyphTests {
    @Test func linesAndRelativeSteps() {
        let check = ChromeGlyph.svg("M3.5 8.5l3 3 6-7").boundingBox
        #expect(abs(check.minX - 3.5) < 0.001 && abs(check.maxX - 12.5) < 0.001)
        #expect(abs(check.minY - 4.5) < 0.001 && abs(check.maxY - 11.5) < 0.001)
        let hv = ChromeGlyph.svg("M8 7v3M8 11.6v.4").boundingBox
        #expect(abs(hv.minY - 7) < 0.001 && abs(hv.maxY - 12) < 0.001)
    }

    @Test func arcsStayInsideTheViewBox() {
        // The cloud's arcs (one with a radius too small for its chord, which SVG grows) end where they should.
        let cloud = ChromeGlyph.svg("M4.5 12.5h7a2.5 2.5 0 0 0 .4-5 4 4 0 0 0-7.6-1A3 3 0 0 0 4.5 12.5z").boundingBoxOfPath
        #expect(cloud.minX > 1 && cloud.maxX < 15 && cloud.minY > 2 && cloud.maxY <= 12.51)
        let folder = ChromeGlyph.folder.parts[0].path.boundingBoxOfPath
        #expect(abs(folder.minX - 2) < 0.01 && abs(folder.maxX - 14) < 0.01)
        #expect(abs(folder.minY - 3) < 0.01 && abs(folder.maxY - 13) < 0.01)
    }
}
