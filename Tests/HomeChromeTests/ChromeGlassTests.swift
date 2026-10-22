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

    @Test func contentFollowsFrameAtOnce() {
        let glass = ChromeGlass(style: .overMedia(.regular), cornerRadius: 10)
        glass.frame = NSRect(x: 0, y: 0, width: 120, height: 50)
        #expect(glass.contentView.bounds.size == glass.bounds.size)
        glass.setFrameSize(NSSize(width: 80, height: 30))
        #expect(glass.contentView.bounds.size == glass.bounds.size)
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

    @Test func toastSizesFromText() {
        let toast = ChromeToastView(style: .window)
        toast.show("Some text", for: 5)
        let short = toast.fittingSize.width
        #expect(short > 0)
        toast.show("Some much longer text than before", for: 5)
        #expect(toast.fittingSize.width > short)
        toast.hide()
    }

    @Test func rimIsOnePoint() {
        let glass = ChromeGlass(style: .overMedia(.regular), cornerRadius: 10)
        #expect(glass.rimLayer.borderWidth == 1)
    }

    @Test func tintAlphaFollowsWeight() {
        let regular = ChromeGlass(style: .overMedia(.regular), cornerRadius: 10)
        let light = ChromeGlass(style: .overMedia(.light), cornerRadius: 10)
        let a = regular.glassView.tintColor?.usingColorSpace(.sRGB)?.alphaComponent ?? -1
        let b = light.glassView.tintColor?.usingColorSpace(.sRGB)?.alphaComponent ?? -1
        #expect(abs(a - 0.62) < 0.001)
        #expect(abs(b - 0.55) < 0.001)
        #expect(ChromeGlass(style: .window, cornerRadius: 10).glassView.tintColor == nil)
    }

    @Test func windowRimFollowsAppearance() {
        let glass = ChromeGlass(style: .window, cornerRadius: 10)
        let window = windowWith(glass, appearance: .aqua)
        let light = glass.rimLayer.borderColor
        window.appearance = NSAppearance(named: .darkAqua)
        glass.viewDidChangeEffectiveAppearance()
        let dark = glass.rimLayer.borderColor
        #expect(light != nil && dark != nil && light != dark)
    }
}
