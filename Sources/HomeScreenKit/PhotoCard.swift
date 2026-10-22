import AppKit
import HomeChrome
import HomeScreenModel

/// A photo in the grid, as Photos draws it. Square: the picture fills the slot's square, cropped, and the selection is
/// a ring 3 pt inside it with a dark hairline inside the ring. Aspect: the whole picture sits in the square inset by
/// 8 pt, with a ring 2 pt on its outline. The name goes on the picture, under the square, or nowhere.
final class PhotoCard: GridCard {
    var style = GridStyle.aspect { didSet { if style != oldValue { needsLayout = true } } }
    var names = GridNames.off { didSet { if names != oldValue { needsLayout = true } } }
    /// False on slots too narrow for a name (`GridLayout.showsNames`).
    var showsNames = true { didSet { if showsNames != oldValue { needsLayout = true } } }

    let ring = CALayer()
    let nameLabel = NSTextField(labelWithString: "")
    private let picture = CALayer()
    private let hairline = CALayer()
    private let shade = GridCard.shade()

    private static let aspectInset: CGFloat = 8

    override init(item: HomeCardItem) {
        super.init(item: item)
        picture.backgroundColor = NSColor(white: 0.14, alpha: 1).cgColor
        picture.masksToBounds = true
        layer?.addSublayer(picture)
        layer?.addSublayer(shade)
        ring.borderColor = NSColor.controlAccentColor.cgColor
        ring.isHidden = true
        hairline.borderColor = NSColor(white: 0, alpha: 0.35).cgColor
        hairline.borderWidth = 1
        ring.addSublayer(hairline)
        layer?.addSublayer(ring)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(nameLabel)
        show(item)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Square: the slot's square. Aspect: the image fitted in the square inset by 8 pt (that square while there is none).
    var pictureRect: CGRect {
        let side = bounds.width
        switch style {
        case .square:
            return CGRect(x: 0, y: 0, width: side, height: side)
        case .aspect:
            let box = CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: Self.aspectInset, dy: Self.aspectInset)
            guard let image, image.width > 0, image.height > 0, box.width > 0 else { return box }
            let scale = min(box.width / CGFloat(image.width), box.height / CGFloat(image.height))
            let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
            return CGRect(x: box.minX + (box.width - w) / 2, y: box.minY + (box.height - h) / 2, width: w, height: h)
        }
    }

    override func itemChanged() { nameLabel.stringValue = item.title }
    override func imageChanged() {
        picture.contents = image
        needsLayout = true
    }

    override func selectionChanged() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.isHidden = !isSelected
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        let rect = pictureRect, side = bounds.width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        picture.frame = rect
        picture.contentsGravity = style == .square ? .resizeAspectFill : .resizeAspect
        picture.cornerRadius = style == .square ? 1 : 4
        ring.frame = rect
        switch style {
        case .square:
            ring.borderWidth = 3
            ring.cornerRadius = 1
            hairline.isHidden = false
            hairline.frame = ring.bounds.insetBy(dx: 3, dy: 3)
        case .aspect:
            ring.borderWidth = 2
            ring.cornerRadius = 4
            hairline.isHidden = true
        }
        let named = showsNames && names != .off
        nameLabel.isHidden = !named
        shade.isHidden = !(named && names == .photo)
        if names == .photo {
            nameLabel.font = Chrome.Text.font(.label, weight: .medium)
            nameLabel.textColor = Chrome.Palette.overMedia.text
            let shadow = NSShadow()
            shadow.shadowColor = Chrome.Palette.overMedia.mediaShadow
            shadow.shadowBlurRadius = 2
            nameLabel.shadow = shadow
            let band = min(rect.height, 32)
            shade.frame = CGRect(x: rect.minX, y: rect.maxY - band, width: rect.width, height: band)
            nameLabel.frame = CGRect(x: rect.minX + 6, y: rect.maxY - 20, width: max(0, rect.width - 12), height: 16)
        } else {
            nameLabel.font = Chrome.Text.font(.label)
            nameLabel.textColor = .secondaryLabelColor
            nameLabel.shadow = nil
            nameLabel.frame = CGRect(x: 0, y: side + 3, width: side, height: 16)
        }
        CATransaction.commit()
    }
}
