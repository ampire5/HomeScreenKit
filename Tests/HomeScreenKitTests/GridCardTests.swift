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
        #expect(card.ring.borderWidth == 2.5)
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
        #expect(card.ring.borderWidth == 2.5)
    }

    // MARK: The mockup (photo-cards spec §1)

    private func photo(_ style: GridStyle, item: HomeCardItem, size: CGFloat = 200) -> PhotoCard {
        let card = PhotoCard(item: item)
        card.style = style
        card.frame = CGRect(x: 0, y: 0, width: size, height: size)
        card.layoutSubtreeIfNeeded()
        return card
    }

    @Test func photoRadiusEight() {
        for style in [GridStyle.square, .aspect] {
            let card = photo(style)
            #expect(card.pictureLayer.cornerRadius == 8)
            #expect(card.ring.cornerRadius == 8)
        }
        let thin = photo(.aspect)
        thin.image = image(300, 20)
        thin.layoutSubtreeIfNeeded()
        #expect(thin.pictureLayer.cornerRadius <= thin.pictureRect.height / 2)
        #expect(thin.ring.cornerRadius == thin.pictureLayer.cornerRadius)
    }

    @Test func ringInsideBothStyles() {
        for style in [GridStyle.square, .aspect] {
            let card = photo(style)
            #expect(card.ring.frame == card.pictureRect)
            #expect(card.ring.borderWidth == 2.5)
            #expect(card.hairline.frame == card.ring.bounds.insetBy(dx: 2.5, dy: 2.5))
        }
    }

    @Test func marksOffAddNoLayers() {
        let card = photo(.square)
        #expect(card.dotLayer == nil)
        #expect(card.chipLayer == nil)
        #expect(card.strip == nil)
        let sublayers = card.layer?.sublayers?.count
        card.isUnseen = false
        card.isPaired = false
        card.isHovered = false
        card.layoutSubtreeIfNeeded()
        #expect(card.dotLayer == nil && card.chipLayer == nil && card.strip == nil)
        #expect(card.layer?.sublayers?.count == sublayers)
    }

    @Test func dotTopRight() {
        let card = photo(.square)
        card.isUnseen = true
        card.layoutSubtreeIfNeeded()
        // The 8 pt dot 6 pt in from the corner, in its 1.5 pt white ring.
        #expect(card.dotLayer?.frame == CGRect(x: 184.5, y: 4.5, width: 11, height: 11))
        #expect(card.dotLayer?.isHidden == false)
        let aspect = photo(.aspect)
        aspect.image = image(300, 100)
        aspect.isUnseen = true
        aspect.layoutSubtreeIfNeeded()
        let rect = aspect.pictureRect
        #expect(aspect.dotLayer?.frame == CGRect(x: rect.maxX - 15.5, y: rect.minY + 4.5, width: 11, height: 11))
        card.isUnseen = false
        #expect(card.dotLayer?.isHidden == true)
    }

    @Test func chipTopLeft() {
        let card = photo(.square)
        card.isPaired = true
        card.layoutSubtreeIfNeeded()
        #expect(card.chipLayer?.frame == CGRect(x: 6, y: 6, width: 18, height: 16))
        #expect(card.chipLayer?.cornerRadius == 5)
        #expect(card.dotLayer == nil)
    }

    @Test func smallSlotOnlyDot() {
        let card = photo(.square, item: HomeCardItem(id: "a", title: "a.jxl", tooltip: "", symbol: "photo",
                                                     format: "JXL", bytes: 1000), size: 80)
        card.showsNames = false   // the browser's flag for slots under `minNamed`
        card.isUnseen = true
        card.isPaired = true
        card.isHovered = true
        card.layoutSubtreeIfNeeded()
        #expect(card.dotLayer?.isHidden == false)
        #expect(card.chipLayer?.isHidden ?? true)
        #expect(card.strip?.isHidden ?? true)
    }

    @Test func stripOnHover() {
        let card = photo(.square, item: HomeCardItem(id: "a", title: "a.jxl", tooltip: "", symbol: "photo",
                                                     format: "JXL", bytes: 24_000_000))
        #expect(card.strip == nil)
        card.isHovered = true
        card.layoutSubtreeIfNeeded()
        let strip = try! #require(card.strip)
        #expect(!strip.isHidden)
        #expect(strip.frame.maxY == card.pictureRect.maxY)
        #expect(strip.frame.minX == card.pictureRect.minX && strip.frame.width == card.pictureRect.width)
        #expect(card.stripText.format == "JXL")
        #expect(card.stripText.size == FileFactsText.size(24_000_000))
        card.isHovered = false
        #expect(strip.isHidden)
    }

    @Test func stripWithoutSize() {
        let card = photo(.square, item: HomeCardItem(id: "a", title: "a", tooltip: "", symbol: "photo"))
        card.isHovered = true
        card.layoutSubtreeIfNeeded()
        #expect(card.stripText.format == "")
        #expect(card.stripText.size == "")
        #expect(card.strip?.isHidden ?? true)   // nothing to say: no strip
    }

    @Test func stripHidesOnReuse() {
        let card = photo(.square, item: HomeCardItem(id: "a", title: "a.jxl", tooltip: "", symbol: "photo",
                                                     format: "JXL", bytes: 1000))
        card.isHovered = true
        card.layoutSubtreeIfNeeded()
        card.show(HomeCardItem(id: "b", title: "b.jxl", tooltip: "", symbol: "photo", format: "JXL", bytes: 1000))
        card.layoutSubtreeIfNeeded()
        #expect(!card.isHovered)
        #expect(card.strip?.isHidden == true)
    }

    /// The viewer hides Home, and the pool hides cards put aside: neither sends `mouseExited` (review, 2).
    @Test func stripHidesWhenHidden() {
        let item = HomeCardItem(id: "a", title: "a.jxl", tooltip: "", symbol: "photo", format: "JXL", bytes: 1000)
        let parent = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let card = photo(.square, item: item)
        parent.addSubview(card)
        card.isHovered = true
        parent.isHidden = true
        #expect(!card.isHovered)
        #expect(card.strip?.isHidden == true)
        parent.isHidden = false
        card.isHovered = true
        card.isHidden = true   // put aside, then popped for the same id
        card.isHidden = false
        card.show(item)
        #expect(!card.isHovered)
    }

    /// The selection ring stays above the strip: a hovered card is the selected one (review, 3).
    @Test func ringAboveStrip() {
        let card = photo(.square, item: HomeCardItem(id: "a", title: "a.jxl", tooltip: "", symbol: "photo",
                                                     format: "JXL", bytes: 1000))
        card.isSelected = true
        card.isHovered = true
        card.layoutSubtreeIfNeeded()
        let strip = try! #require(card.strip?.layer)
        #expect(card.ring.zPosition > strip.zPosition)
    }

    @Test func nameAboveStrip() {
        let card = photo(.square, item: HomeCardItem(id: "a", title: "a.jxl", tooltip: "", symbol: "photo",
                                                     format: "JXL", bytes: 1000))
        card.names = .photo
        card.isHovered = true
        card.layoutSubtreeIfNeeded()
        let strip = try! #require(card.strip)
        #expect(card.nameLabel.frame.maxY <= strip.frame.minY)
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
