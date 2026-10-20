import Testing
@testable import HomeScreenModel

@Suite struct HomeClickTests {
    @Test func shiftIsANewWindow() {
        #expect(HomeClick.from(shift: true, command: true, middle: false, supportsTabs: true) == .openNewWindow)
        #expect(HomeClick.from(shift: true, command: false, middle: true, supportsTabs: true) == .openNewWindow)
    }

    @Test func commandOrMiddleIsANewTab() {
        #expect(HomeClick.from(shift: false, command: true, middle: false, supportsTabs: true) == .openNewTab)
        #expect(HomeClick.from(shift: false, command: false, middle: true, supportsTabs: true) == .openNewTab)
    }

    @Test func plainClickOpensHere() {
        #expect(HomeClick.from(shift: false, command: false, middle: false, supportsTabs: true) == .open)
    }

    @Test func withoutTabsEveryClickOpensHere() {
        for shift in [false, true] {
            for command in [false, true] {
                for middle in [false, true] {
                    #expect(HomeClick.from(shift: shift, command: command, middle: middle, supportsTabs: false) == .open)
                }
            }
        }
    }
}
