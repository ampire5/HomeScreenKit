import AppKit
import Testing
@testable import HomeChrome

@MainActor @Suite struct GlassCapsuleTests {
    @Test func chooseCallsBackAndLights() {
        let capsule = GlassCapsule(titles: ["Name", "Date", "Size"])
        var chosen: [Int] = []
        capsule.onChoose = { chosen.append($0) }
        #expect(capsule.selected == nil)
        capsule.choose(1)
        #expect(chosen == [1])
        #expect(capsule.selected == 1)
    }

    @Test func lightColourFollowsAppearance() {
        func lightColour(_ name: NSAppearance.Name) -> NSColor? {
            let capsule = GlassCapsule(titles: ["A", "B"])
            capsule.selected = 0
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 40), styleMask: [.titled],
                                  backing: .buffered, defer: true)
            window.appearance = NSAppearance(named: name)
            window.contentView?.addSubview(capsule)
            capsule.viewDidChangeEffectiveAppearance()
            let light = capsule.subviews.first { $0 is NSGlassEffectView }.flatMap { ($0 as? NSGlassEffectView)?.contentView }?
                .subviews.first { !($0 is NSButton) }
            return light?.layer?.backgroundColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) }
        }
        let aqua = lightColour(.aqua), dark = lightColour(.darkAqua)
        #expect(aqua != nil && dark != nil)
        #expect(aqua != dark)
    }

    @Test func titlesRebuildSegments() {
        let capsule = GlassCapsule(titles: ["All", "Folders", "Photos"])
        capsule.selected = 2
        capsule.titles = ["A", "B", "C", "D"]
        #expect(capsule.selected == 2)
        capsule.titles = ["A"]
        #expect(capsule.selected == nil)
    }

    @Test func groupPressAndEnable() {
        let group = GlassGroup(items: [(symbol: "minus", tip: "Smaller"), (symbol: "plus", tip: "Larger")])
        var pressed: [Int] = []
        group.onPress = { pressed.append($0) }
        group.press(1)
        group.setEnabled(false, at: 0)
        group.press(0)
        #expect(pressed == [1])
        group.setSymbol("square", at: 1)
    }

    @Test func fittingWidthGrowsWithTitles() {
        let short = GlassCapsule(titles: ["A", "B"]), long = GlassCapsule(titles: ["Alphabetical", "Chronological"])
        #expect(long.fittingSize.width > short.fittingSize.width)
        #expect(short.fittingSize.height == 28)
        let pill = GlassPill()
        pill.text = "Photos"
        #expect(pill.fittingSize.height == 18)
    }
}
