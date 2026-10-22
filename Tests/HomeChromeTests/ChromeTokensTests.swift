import AppKit
import Testing
@testable import HomeChrome

@MainActor @Suite struct ChromeTokensTests {
    @Test func radiiAndSpaces() {
        #expect(Chrome.Radius.cell == 3)
        #expect(Chrome.Radius.control == 6)
        #expect(Chrome.Radius.card == 10)
        #expect(Chrome.Radius.panel == 14)
        #expect(Chrome.Radius.capsule(28) == 14)
        #expect(Chrome.Ring.width == 2.5)
        #expect(Chrome.Ring.gap == 2)
        #expect(Chrome.Space.xxs == 2)
        #expect(Chrome.Space.xs == 4)
        #expect(Chrome.Space.s == 6)
        #expect(Chrome.Space.m == 8)
        #expect(Chrome.Space.l == 12)
        #expect(Chrome.Space.xl == 16)
        #expect(Chrome.Space.xxl == 20)
    }

    @Test func textStylesMapToSystem() {
        #expect(Chrome.Text.font(.body).pointSize == NSFont.preferredFont(forTextStyle: .body).pointSize)
        #expect(Chrome.Text.font(.small).pointSize == NSFont.preferredFont(forTextStyle: .subheadline).pointSize)
        #expect(Chrome.Text.font(.label).pointSize == NSFont.preferredFont(forTextStyle: .callout).pointSize)
        #expect(Chrome.Text.font(.badge).pointSize == NSFont.preferredFont(forTextStyle: .caption1).pointSize)
        #expect(Chrome.Text.font(.heading).pointSize == NSFont.preferredFont(forTextStyle: .title2).pointSize)
        #expect(Chrome.Text.font(.hero).pointSize == NSFont.preferredFont(forTextStyle: .title1).pointSize)
        #expect(weight(of: Chrome.Text.font(.title)) == NSFont.Weight.semibold.rawValue)
        #expect(Chrome.Text.font(.title).pointSize == NSFont.preferredFont(forTextStyle: .title3).pointSize)
        #expect(weight(of: Chrome.Text.font(.body)) == NSFont.Weight.regular.rawValue)
        #expect(weight(of: Chrome.Text.font(.body, weight: .bold)) == NSFont.Weight.bold.rawValue)
        let features = Chrome.Text.digits(.label).fontDescriptor.fontAttributes[.featureSettings] as? [Any]
        #expect(features?.isEmpty == false)
    }

    @Test func overMediaValues() {
        typealias P = Chrome.Palette.overMedia
        expectSRGB(P.glassTint, 22 / 255, 24 / 255, 29 / 255, 0.62)
        expectSRGB(P.glassTintLight, 22 / 255, 24 / 255, 29 / 255, 0.55)
        expectSRGB(P.rim, 1, 1, 1, 0.14)
        expectSRGB(P.separator, 1, 1, 1, 0.18)
        expectSRGB(P.text, 1, 1, 1, 0.92)
        expectSRGB(P.secondaryText, 1, 1, 1, 0.7)
        expectSRGB(P.tertiaryText, 1, 1, 1, 0.5)
        expectSRGB(P.pressed, 1, 1, 1, 0.2)
        expectSRGB(P.hover, 1, 1, 1, 0.1)
        expectSRGB(P.scrim, 0, 0, 0, 0.45)
        expectSRGB(P.mediaShadow, 0, 0, 0, 0.55)
    }

    @Test func motionIsInstantWithReduceMotion() {
        #expect(Chrome.Motion.show == 0.15)
        #expect(Chrome.Motion.hide == 0.25)
        #expect(Chrome.Motion.select == 0.2)
        #expect(Chrome.Motion.duration(Chrome.Motion.hide, reduceMotion: true) == 0)
        #expect(Chrome.Motion.duration(Chrome.Motion.hide, reduceMotion: false) == 0.25)
    }

    @Test func resolveFollowsAppearance() {
        let light = NSView()
        light.appearance = NSAppearance(named: .aqua)
        let dark = NSView()
        dark.appearance = NSAppearance(named: .darkAqua)
        let a = Chrome.resolve(.labelColor, in: light)
        let b = Chrome.resolve(.labelColor, in: dark)
        #expect(a != b)
    }

    @Test func overMediaApplyForcesDark() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.appearance = NSAppearance(named: .aqua)
        let view = NSView()
        window.contentView?.addSubview(view)
        #expect(view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
        Chrome.Palette.overMedia.apply(to: view)
        #expect(view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }

    private func weight(of font: NSFont) -> CGFloat {
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        return traits?[.weight] as? CGFloat ?? .nan
    }

    private func expectSRGB(_ color: NSColor, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat,
                            sourceLocation: SourceLocation = #_sourceLocation) {
        guard let c = color.usingColorSpace(.sRGB) else {
            Issue.record("not convertible to sRGB", sourceLocation: sourceLocation)
            return
        }
        #expect(abs(c.redComponent - r) < 0.001 && abs(c.greenComponent - g) < 0.001
                && abs(c.blueComponent - b) < 0.001 && abs(c.alphaComponent - a) < 0.001,
                sourceLocation: sourceLocation)
    }
}
