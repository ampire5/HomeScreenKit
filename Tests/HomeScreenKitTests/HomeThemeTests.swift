import AppKit
import HomeChrome
import Testing
@testable import HomeScreenKit
@testable import HomeScreenModel

@MainActor @Suite struct HomeThemeTests {
    private func window(_ name: NSAppearance.Name, _ view: NSView) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled],
                              backing: .buffered, defer: true)
        window.appearance = NSAppearance(named: name)
        window.contentView?.addSubview(view)
        return window
    }

    private func differ(_ a: CGColor?, _ b: CGColor?) -> Bool {
        guard let a, let b else { return false }
        return a != b
    }

    @Test func homeIsNotForcedDark() {
        #expect(HomeView(source: FakeHomeSource()).appearance == nil)
        #expect(HomeScreenView(background: nil).appearance == nil)
        #expect(HomeBrowserView(source: FakeHomeSource()).appearance == nil)
    }

    @Test func cardPlaceholderFollowsAppearance() {
        let item = HomeCardItem(id: "a", title: "a", tooltip: "a", symbol: "photo")
        let card = HomeCard(item: item, aspect: 0.7)
        card.frame = CGRect(x: 0, y: 0, width: 200, height: 260)
        let w = window(.aqua, card)
        card.layoutSubtreeIfNeeded()
        let light = card.pictureFill
        w.appearance = NSAppearance(named: .darkAqua)
        card.layoutSubtreeIfNeeded()
        #expect(differ(light, card.pictureFill))
        #expect(card.pictureFill == Chrome.resolve(Chrome.Palette.window.fill, in: card))
    }

    @Test func photoBadgesStayDark() {
        let item = HomeCardItem(id: "z", title: "z.zip", tooltip: "z", symbol: "doc.zipper", badge: "ZIP")
        let card = CollectionCard(item: item)
        let w = window(.aqua, card)
        _ = w
        #expect(card.badgePill.appearance?.name == .darkAqua)
        let photo = PhotoCard(item: item)
        photo.names = .photo
        photo.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        photo.layoutSubtreeIfNeeded()
        #expect(photo.nameLabel.textColor == Chrome.Palette.overMedia.text)
    }

    @Test func backgroundFollowsAppearanceUnlessSet() {
        let view = HomeView(source: FakeHomeSource())
        view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let w = window(.aqua, view)
        let light = view.background
        w.appearance = NSAppearance(named: .darkAqua)
        view.layoutSubtreeIfNeeded()
        #expect(differ(light, view.background))
        #expect(view.layer?.backgroundColor == view.background)
        let custom = CGColor(gray: 0.5, alpha: 1)
        view.background = custom
        w.appearance = NSAppearance(named: .aqua)
        view.layoutSubtreeIfNeeded()
        #expect(view.background == custom)
        #expect(view.layer?.backgroundColor == custom)
    }
}
