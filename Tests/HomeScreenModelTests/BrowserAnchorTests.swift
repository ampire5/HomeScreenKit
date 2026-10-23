import Foundation
import Testing
@testable import HomeScreenModel

@Suite struct BrowserAnchorTests {
    let ids = ["a", "b", "c", "d"]
    func index(_ anchor: BrowserAnchor, _ ids: [String]) -> Int? {
        anchor.target(count: ids.count) { ids.firstIndex(of: $0) }
    }

    @Test func entryPresentIsItsNewIndex() {
        #expect(index(BrowserAnchor(id: "c", offset: 12, index: 0), ids) == 2)
    }

    @Test func entryGoneTakesTheOneAtItsIndex() {
        #expect(index(BrowserAnchor(id: "x", offset: 12, index: 1), ids) == 1)
        #expect(index(BrowserAnchor(id: "x", offset: 12, index: 9), ids) == 3)   // past the end: the last
    }

    @Test func emptyIsNone() {
        #expect(index(BrowserAnchor(id: "a", offset: 0, index: 0), []) == nil)
    }

    @Test func roundTrip() throws {
        let a = BrowserAnchor(id: "/p/x.jpg", offset: 7.5, index: 3)
        #expect(try JSONDecoder().decode(BrowserAnchor.self, from: JSONEncoder().encode(a)) == a)
    }
}
