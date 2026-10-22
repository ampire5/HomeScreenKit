import AppKit
import Testing
@testable import HomeChrome

@MainActor @Suite struct ChromeGlassTests {
    private func windowWith(_ glass: ChromeGlass, appearance: NSAppearance.Name) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.appearance = NSAppearance(named: appearance)
        glass.frame = NSRect(x: 10, y: 10, width: 100, height: 40)
        window.contentView?.addSubview(glass)
        return window
    }

    @Test func overMediaStaysDarkInLightWindow() {
        let glass = ChromeGlass(style: .overMedia(.regular), cornerRadius: 10)
        let window = windowWith(glass, appearance: .aqua)
        _ = window
        #expect(glass.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }

    @Test func windowGlassFollowsWindow() {
        let glass = ChromeGlass(style: .window, cornerRadius: 10)
        let window = windowWith(glass, appearance: .aqua)
        _ = window
        #expect(glass.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
    }

    @Test func glassKeepsRadius() {
        let glass = ChromeGlass(style: .overMedia(.light), cornerRadius: 4)
        glass.cornerRadius = 10
        #expect(glass.cornerRadius == 10)
        #expect(glass.glassView.cornerRadius == 10)
        #expect(glass.rimLayer.cornerRadius == 10)
    }

    @Test func toastShowsAndHides() async throws {
        let toast = ChromeToastView(style: .overMedia(.regular))
        toast.show("x", for: 0.05)
        #expect(toast.isShowing)
        for _ in 0..<60 where toast.isShowing { try await Task.sleep(for: .milliseconds(50)) }
        #expect(!toast.isShowing)
        toast.show("y", for: 5)
        toast.hide()
        #expect(!toast.isShowing)
    }
}
