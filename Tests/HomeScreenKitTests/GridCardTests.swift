import AppKit
import Testing
@testable import HomeScreenKit
@testable import HomeScreenModel

@MainActor @Suite struct GridCardTests {
    private let item = HomeCardItem(id: "a", title: "a.jpg", tooltip: "a", symbol: "photo")

    private func photo(_ style: GridStyle, names: GridNames = .off, size: CGSize = CGSize(width: 200, height: 200)) -> PhotoCard {
        let card = PhotoCard(item: item)
        card.style = style
        card.names = names
        card.frame = CGRect(origin: .zero, size: size)
        card.layoutSubtreeIfNeeded()
        return card
    }

    private func image(_ w: Int, _ h: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    @Test func squareRingInsideSlot() {
        let card = photo(.square)
        #expect(card.ring.frame == card.bounds)
        #expect(card.ring.borderWidth == 3)
        #expect(card.pictureRect == card.bounds)
    }

    @Test func aspectRingHugsFittedImage() {
        let card = photo(.aspect)
        #expect(card.pictureRect == CGRect(x: 8, y: 8, width: 184, height: 184))
        card.image = image(300, 100)
        card.layoutSubtreeIfNeeded()
        let h = 184.0 / 3
        let expected = CGRect(x: 8, y: 8 + (184 - h) / 2, width: 184, height: h)
        #expect(abs(card.pictureRect.minY - expected.minY) < 0.01)
        #expect(abs(card.pictureRect.height - expected.height) < 0.01)
        #expect(card.pictureRect.minX == 8 && card.pictureRect.width == 184)
        #expect(card.ring.frame == card.pictureRect)
        #expect(card.ring.borderWidth == 2)
    }

    @Test func namesModes() {
        let onPhoto = photo(.square, names: .photo)
        #expect(!onPhoto.nameLabel.isHidden)
        #expect(onPhoto.pictureRect.contains(onPhoto.nameLabel.frame))
        let below = photo(.square, names: .below, size: CGSize(width: 200, height: 222))
        #expect(!below.nameLabel.isHidden)
        #expect(below.nameLabel.frame.minY >= 200)
        #expect(photo(.square, names: .off).nameLabel.isHidden)
        for names in [GridNames.photo, .below] {
            let card = photo(.aspect, names: names)
            card.showsNames = false
            card.layoutSubtreeIfNeeded()
            #expect(card.nameLabel.isHidden)
        }
    }

    @Test func collectionTitleOnPicture() {
        let card = CollectionCard(item: HomeCardItem(id: "f", title: "Folder", subtitle: "12 photos", tooltip: "f", symbol: "folder"))
        card.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        card.layoutSubtreeIfNeeded()
        #expect(card.pictureFrame == CGRect(x: 0, y: 0, width: 300, height: 300))
        #expect(card.pictureFrame.contains(card.titleLabel.frame))
        #expect(card.titleLabel.stringValue == "Folder")
        card.names = .below
        card.frame = CGRect(x: 0, y: 0, width: 300, height: 322)
        card.layoutSubtreeIfNeeded()
        #expect(card.titleLabel.frame.minY >= 300)
    }

    @Test func collectionBadgePill() {
        let card = CollectionCard(item: HomeCardItem(id: "z", title: "z.zip", tooltip: "z", symbol: "doc.zipper", badge: "ZIP"))
        card.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        card.layoutSubtreeIfNeeded()
        #expect(!card.badgePill.isHidden)
        #expect(card.badgePill.text == "ZIP")
        card.show(HomeCardItem(id: "z", title: "z", tooltip: "z", symbol: "folder"))
        #expect(card.badgePill.isHidden)
    }

    @Test func cardsPassSideButtonsOn() {
        let keys = HomeBrowserRoutingTests()
        let cards: [GridCard] = [HomeCard(item: item, aspect: 2.0 / 3), PhotoCard(item: item), CollectionCard(item: item)]
        for card in cards {
            let parent = SideButtonCatcher()
            parent.addSubview(card)
            card.otherMouseUp(with: keys.mouse(.otherMouseUp, button: 3))
            #expect(parent.ups == [3])
        }
    }

    /// A card put aside in the pool stays a subview: hidden, it must not take clicks meant for the card under it.
    @Test func hiddenCardTakesNoClicks() {
        let parent = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let shown = CollectionCard(item: item), aside = PhotoCard(item: item)
        for card in [shown, aside] as [GridCard] {
            card.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
            parent.addSubview(card)
        }
        aside.isHidden = true
        #expect(parent.hitTest(CGPoint(x: 100, y: 100)) === shown)
    }

    private func collection(_ item: HomeCardItem, width: CGFloat = 200) -> CollectionCard {
        let card = CollectionCard(item: item)
        card.frame = CGRect(x: 0, y: 0, width: width, height: width)
        card.layoutSubtreeIfNeeded()
        return card
    }

    @Test func collectionDrawsProgress() {
        let card = collection(HomeCardItem(id: "r", title: "R", tooltip: "", symbol: "folder", progress: 0.4))
        #expect(!card.progressBar.isHidden)
        #expect(card.progressFrame == CGRect(x: 0, y: 197, width: 80, height: 3))
        card.show(HomeCardItem(id: "r", title: "R", tooltip: "", symbol: "folder"))
        card.layoutSubtreeIfNeeded()
        #expect(card.progressBar.isHidden)
    }

    @Test func collectionGlassSymbol() {
        let card = collection(HomeCardItem(id: "p", title: "T", tooltip: "", symbol: "externaldrive", glassSymbol: true))
        #expect(card.isShowingGlassTile)
        #expect(card.glassTileFrame == card.pictureFrame)
        card.image = image(10, 10)
        #expect(card.isShowingGlassTile)
        #expect(card.isShowingSymbol)
        let plain = collection(HomeCardItem(id: "f", title: "F", tooltip: "", symbol: "folder"))
        #expect(!plain.isShowingGlassTile)
    }

    @Test func badgePillShows() {
        let card = collection(HomeCardItem(id: "s", title: "Last Session", tooltip: "", symbol: "rectangle.stack", badge: "Last"))
        #expect(card.badgePill.text == "Last")
        #expect(!card.badgePill.isHidden)
    }
}
