import Foundation
import Testing
@testable import FilmstripModel

@Suite struct FilmstripResizeDragTests {
    /// The grabbed top is the band's top: the thickness follows the cursor 1:1, back to the press point is back to the
    /// start thickness; past the range it goes on 1:1 (the caller clamps it).
    @Test func thicknessFollowsTheCursorOneToOne() {
        let drag = FilmstripResizeDrag(startThickness: 68)
        #expect(drag.startThickness == 68)
        for d in stride(from: -200.0, through: 200, by: 7) { #expect(drag.thickness(forDrag: d) == 68 + d) }
        #expect(drag.thickness(forDrag: 0) == 68)
    }
}
