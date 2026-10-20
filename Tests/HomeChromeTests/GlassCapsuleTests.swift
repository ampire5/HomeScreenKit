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
