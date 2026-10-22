import Foundation
import Testing
@testable import FilmstripModel

@Suite struct FilmstripHitZoneTests {
    /// A 1000 pt wide band 80 pt tall (68 pt cells, 6 pt padding).
    private let zone = FilmstripHitZone(length: 1000, thickness: 80, padding: 6)

    @Test func theBandIsTheZoneAndItsTopIsTheGrabBand() {
        #expect(zone.inHoverZone(along: 250, across: 30) && !zone.inResizeBand(along: 250, across: 30))
        #expect(zone.inResizeBand(along: 250, across: 77) && !zone.inHoverZone(along: 250, across: 77))
        #expect(!zone.inHoverZone(along: 250, across: 100) && !zone.inResizeBand(along: 250, across: 100))   // above the band
    }

    @Test func grabBandIsTheTopPadding() {
        #expect(zone.inResizeBand(along: 250, across: 74) && zone.inResizeBand(along: 250, across: 79.5))
        #expect(!zone.inResizeBand(along: 250, across: 73.9) && !zone.inResizeBand(along: 250, across: 80))
        #expect(zone.inResizeBand(along: 0, across: 75) && !zone.inResizeBand(along: 1000, across: 75) && !zone.inResizeBand(along: -1, across: 75))
    }

    @Test func cellBodyNeverGrab() {
        for y in stride(from: 0.0, to: 74, by: 0.5) {
            #expect(!zone.inResizeBand(along: 250, across: y) && zone.inHoverZone(along: 250, across: y))
        }
        #expect(!zone.inHoverZone(along: -5, across: 30) && !zone.inHoverZone(along: 1000, across: 30) && !zone.inHoverZone(along: 250, across: -1))
    }
}
