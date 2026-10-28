import Testing
@testable import SlotModel

struct SlotTabStateTests {
    let a = SlotTabID(rawValue: "A"), b = SlotTabID(rawValue: "B"), c = SlotTabID(rawValue: "C")
    @Test func returnPreservesTabOrderAndRotatesSnapshot() {
        var s = SlotTabState(tabs: [a, b, a, c])
        s.select(b)
        #expect(s.tabs == [a, b, c])
        #expect(s.snapshot() == [b, c, a])
        s.select(a)
        #expect(s.snapshot() == [a, b, c])
    }
    @Test func closingSelectsNextThenPrevious() {
        var s = SlotTabState(tabs: [a, b, c])
        s.select(b); s.remove(b)
        #expect(s.selected == c)
        s.remove(c)
        #expect(s.selected == a)
        s.remove(a)
        #expect(s.selected == nil)
    }
}
