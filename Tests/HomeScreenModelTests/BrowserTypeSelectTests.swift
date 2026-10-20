import CoreGraphics
import Testing
@testable import HomeScreenModel

@Suite struct BrowserTypeSelectTests {
    @Test func prefixCaseInsensitive() {
        #expect(BrowserTypeSelect.match("im", in: ["a", "IMG_1", "img_2"], from: 0) == 1)
        #expect(BrowserTypeSelect.match("x", in: ["a", "b"], from: 0) == nil)
    }

    @Test func wrapsFromStart() {
        #expect(BrowserTypeSelect.match("a", in: ["a1", "b", "a2"], from: 2) == 2)
        #expect(BrowserTypeSelect.match("a", in: ["a1", "b", "c"], from: 1) == 0)
    }

    @Test func bufferResetsAfterOneSecond() {
        var t = BrowserTypeSelect()
        #expect(t.type("a", at: 0) == "a")
        #expect(t.type("b", at: 0.5) == "ab")
        #expect(t.type("c", at: 1.6) == "c")
    }

    @Test func typeSelectMatchesDecomposedNames() {
        #expect(BrowserTypeSelect.match("\u{e9}c", in: ["abc", "e\u{301}clair"], from: 0) == 1)
        #expect(BrowserTypeSelect.match("ec", in: ["e\u{301}clair"], from: 0) == nil)
    }
}
