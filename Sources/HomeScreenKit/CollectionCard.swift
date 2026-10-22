import AppKit
import HomeChrome
import HomeScreenModel

/// A folder or an archive: a square picture (a mosaic of its photos, or its symbol) with rounded corners, the title and
/// line under it on a dark band at the picture's bottom (or under the picture with names below), a label pill (`ZIP`,
/// `Last`) at the top left and a progress bar along the picture's bottom edge. A place shows its symbol on a glass
/// tile instead of a picture. The selection is a ring a little outside the picture, as on Home.
final class CollectionCard: GridCard {
    var names = GridNames.off { didSet { if names != oldValue { needsLayout = true } } }

    let titleLabel = NSTextField(labelWithString: "")
    let subtitleLabel = NSTextField(labelWithString: "")
    let badgePill = GlassPill()
    let ring = CALayer()
    private let picture = NSView()
    private let placeholder = NSImageView()
    private let shade = GridCard.shade()
    /// Along the picture's bottom edge, `item.progress` of its width.
    let progressBar = NSView()
    private let glassTile = NSGlassEffectView()

    private static let corner = Chrome.Radius.card
    private static let ringWidth = Chrome.Ring.width
    private static let ringGap = Chrome.Ring.gap

    override init(item: HomeCardItem) {
        super.init(item: item)
        picture.wantsLayer = true
        picture.layer?.cornerRadius = Self.corner
        picture.layer?.cornerCurve = .continuous
        picture.layer?.masksToBounds = true
        picture.layer?.backgroundColor = NSColor(white: 0.14, alpha: 1).cgColor
        picture.layer?.contentsGravity = .resizeAspectFill
        picture.layer?.addSublayer(shade)
        placeholder.contentTintColor = .tertiaryLabelColor
        placeholder.symbolConfiguration = .init(pointSize: 30, weight: .light)
        glassTile.cornerRadius = Self.corner
        glassTile.isHidden = true
        picture.addSubview(glassTile)
        picture.addSubview(placeholder)
        progressBar.wantsLayer = true
        progressBar.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        progressBar.isHidden = true
        picture.addSubview(progressBar)
        ring.borderColor = NSColor.controlAccentColor.cgColor
        ring.borderWidth = Self.ringWidth
        ring.cornerRadius = Self.corner + Self.ringGap + Self.ringWidth
        ring.cornerCurve = .continuous
        ring.isHidden = true
        layer?.addSublayer(ring)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabel.lineBreakMode = .byTruncatingTail
        for view in [picture, titleLabel, subtitleLabel, badgePill] { addSubview(view) }
        show(item)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The square picture at the top of the card.
    var pictureFrame: CGRect { CGRect(x: 0, y: 0, width: bounds.width, height: bounds.width) }

    var progressFrame: CGRect { convert(progressBar.frame, from: picture) }
    var isShowingGlassTile: Bool { !glassTile.isHidden }
    var glassTileFrame: CGRect { convert(glassTile.frame, from: picture) }
    var isShowingSymbol: Bool { !placeholder.isHidden }

    override func itemChanged() {
        placeholder.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)
        placeholder.symbolConfiguration = .init(pointSize: item.glassSymbol ? 36 : 30, weight: .light)
        glassTile.isHidden = !item.glassSymbol
        progressBar.isHidden = item.progress == nil
        imageChanged()
        titleLabel.stringValue = item.title
        subtitleLabel.stringValue = item.subtitle ?? ""
        badgePill.text = item.badge ?? ""
        badgePill.isHidden = item.badge == nil
    }

    override func imageChanged() {
        let drawn = item.glassSymbol ? nil : image
        picture.layer?.contents = drawn
        placeholder.isHidden = drawn != nil
    }

    override func selectionChanged() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.isHidden = !isSelected
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        let p = pictureFrame, w = p.width
        picture.frame = p
        glassTile.frame = CGRect(x: 0, y: 0, width: w, height: w)
        // The picture is not flipped: the bar sits at y 0.
        progressBar.frame = CGRect(x: 0, y: 0, width: (w * min(1, max(0, item.progress ?? 0))).rounded(), height: 3)
        let size = placeholder.fittingSize
        placeholder.frame = CGRect(x: (w - size.width) / 2, y: (w - size.height) / 2, width: size.width, height: size.height)
        let pill = badgePill.fittingSize
        badgePill.frame = CGRect(x: 8, y: 8, width: pill.width, height: pill.height)
        let below = names == .below
        titleLabel.font = Chrome.Text.font(.body, weight: .semibold)
        subtitleLabel.font = Chrome.Text.font(.small)
        titleLabel.textColor = below ? .labelColor : .white
        subtitleLabel.textColor = below ? .secondaryLabelColor : NSColor(white: 1, alpha: 0.75)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shade.isHidden = below
        if below {
            titleLabel.frame = CGRect(x: 0, y: w + 3, width: w, height: 17)
            subtitleLabel.frame = CGRect(x: 0, y: w + 20, width: w, height: 15)
        } else {
            // The picture's layer is not flipped: the band sits at y 0.
            shade.frame = CGRect(x: 0, y: 0, width: w, height: min(w, 52))
            titleLabel.frame = CGRect(x: 10, y: w - 40, width: max(0, w - 20), height: 17)
            subtitleLabel.frame = CGRect(x: 10, y: w - 23, width: max(0, w - 20), height: 15)
        }
        let outset = Self.ringGap + Self.ringWidth
        ring.frame = p.insetBy(dx: -outset, dy: -outset)
        CATransaction.commit()
    }
}
