import Foundation
import Testing
@testable import HomeScreenModel

@Suite struct BrowserHistoryTests {
    private let x = BrowserLocation.folder(URL(fileURLWithPath: "/x"))
    private let y = BrowserLocation.folder(URL(fileURLWithPath: "/y"))
    private let xy = BrowserLocation.folder(URL(fileURLWithPath: "/x/y"))

    @Test func goClearsForward() {
        var h = BrowserHistory(start: .places)
        h.go(to: x)
        let r1 = h.back()
        #expect(r1)
        #expect(h.canGoForward)
        h.go(to: y)
        #expect(!h.canGoForward)
        #expect(h.current == y)
    }

    @Test func backAndForwardRestoreSelectionAndScroll() {
        var h = BrowserHistory(start: x)
        h.remember(selection: "a.jpg", scroll: 300)
        h.go(to: y)
        let r2 = h.back()
        #expect(r2)
        #expect(h.current == x)
        #expect(h.selection(for: x) == "a.jpg")
        #expect(h.scroll(for: x) == 300)
        let r3 = h.forward()
        #expect(r3)
        #expect(h.current == y)
        let r4 = h.forward()
        #expect(!r4)
    }

    @Test func upSelectsFolderLeft() {
        var h = BrowserHistory(start: xy)
        let r5 = h.up(parent: x)
        #expect(r5 == "/x/y")
        #expect(h.current == x)
        #expect(h.canGoBack)
        let r6 = h.back()
        #expect(r6)
        #expect(h.current == xy)
    }

    @Test func upFromPlacesIsNil() {
        var h = BrowserHistory(start: .places)
        let r7 = h.up(parent: nil)
        #expect(r7 == nil)
        #expect(h.current == .places)
        #expect(!h.canGoBack)
    }

    @Test func upFromVolumeRootToPlacesSelectsIt() {
        var h = BrowserHistory(start: x)
        let r8 = h.up(parent: .places)
        #expect(r8 == "/x")
        #expect(h.current == .places)
    }

    @Test func goToSameLocationIsNoOp() {
        var h = BrowserHistory(start: x)
        h.go(to: x)
        #expect(!h.canGoBack)
    }

    @Test func backAtStartIsFalse() {
        var h = BrowserHistory(start: x)
        let r9 = h.back()
        #expect(!r9)
        #expect(h.current == x)
    }

    @Test func locationsCompareByPath() {
        let slash = BrowserLocation.folder(URL(fileURLWithPath: "/x/y/z").deletingLastPathComponent())
        #expect(slash == xy)
        #expect(Set([slash, xy]).count == 1)
        #expect(BrowserLocation.folder(URL(fileURLWithPath: "/x/./y")) == xy)
    }
}
