import AppKit
import HomeChrome
import HomeScreenModel

/// A photo in the grid (photo-cards spec 2026-10-26). Square: the picture fills the slot's square, cropped. Aspect:
/// the whole picture sits in the square inset by 8 pt. Either way everything is drawn on the picture: radius 8, the
/// selection a 2.5 pt ring inside it with a dark hairline inside the ring, a dot at the top right for a photo not
/// viewed yet, a ⧉ chip at the top left for a page of a pair, and on hover a strip along the bottom with the format
/// and the size. The dot, the chip and the strip are made the first time they show. The name goes on the picture,
/// under the square, or nowhere.
final class PhotoCard: GridCard {
    var style = GridStyle.aspect { didSet { if style != oldValue { needsLayout = true } } }
    var names = GridNames.off { didSet { if names != oldValue { needsLayout = true } } }
    /// False on slots too narrow for a name (`GridLayout.showsNames`): no chip and no strip there either.
    var showsNames = true { didSet { if showsNames != oldValue { marksChanged(); needsLayout = true } } }
    /// The photo is not viewed yet (`HomeBrowserView.setPhotoMarks`).
    var isUnseen = false { didSet { if isUnseen != oldValue { marksChanged() } } }
    /// The photo is a page of a two-page pair.
    var isPaired = false { didSet { if isPaired != oldValue { marksChanged() } } }
    /// The pointer is over the card; another photo shown in it takes it back.
    var isHovered = false { didSet { if isHovered != oldValue { marksChanged() } } }

    let ring = CALayer()
    let nameLabel = NSTextField(labelWithString: "")
    let hairline = CALayer()
    private let picture = CALayer()
    private let shade = GridCard.shade()
    private(set) var dotLayer: CALayer?
    private(set) var chipLayer: CALayer?
    private(set) var strip: NSView?
    private var stripFormat: NSTextField?
    private var stripSize: NSTextField?

    private static let aspectInset: CGFloat = 8
    private static let ringWidth: CGFloat = 2.5
    /// The dot: 8 pt in a 1.5 pt white ring, 6 pt in from the picture's top right (the chip: from its top left).
    private static let dot: CGFloat = 8, dotRing: CGFloat = 1.5, markInset: CGFloat = 6
    /// The chip: a 12 pt glyph, padding 2 × 3, radius 5.
    private static let chipSize = CGSize(width: 18, height: 16)
    private static let stripFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
    private static let stripPadding = CGSize(width: 6, height: 4)
    private static let markFill = NSColor(srgbRed: 18 / 255, green: 18 / 255, blue: 20 / 255, alpha: 1)

    var pictureLayer: CALayer { picture }

    override init(item: HomeCardItem) {
        super.init(item: item)
        picture.masksToBounds = true
        layer?.addSublayer(picture)
        layer?.addSublayer(shade)
        ring.isHidden = true
        ring.borderWidth = Self.ringWidth
        // Above the strip, a subview whose layer comes later: a hovered card is the selected one.
        ring.zPosition = 1
        // Inside the ring, on the photo's own pixels: dark whatever the window is.
        hairline.borderColor = NSColor(white: 0, alpha: 0.35).cgColor
        hairline.borderWidth = 1
        ring.addSublayer(hairline)
        layer?.addSublayer(ring)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(nameLabel)
        show(item)
        appearanceChanged()
    }

    override func appearanceChanged() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        picture.backgroundColor = Chrome.resolve(Chrome.Palette.window.fill, in: self)
        ring.borderColor = Chrome.resolve(Chrome.Palette.window.accent, in: self)
        dotLayer?.sublayers?.first?.backgroundColor = Chrome.resolve(Chrome.Palette.window.accent, in: self)
        CATransaction.commit()
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

    /// The strip's two texts: the format and the size as a file's ("" for what the item does not have).
    var stripText: (format: String, size: String) {
        (item.format ?? "", item.bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "")
    }

    override func show(_ item: HomeCardItem) {
        if item.id != self.item.id { isHovered = false }
        super.show(item)
    }

    override func itemChanged() {
        nameLabel.stringValue = item.title
        if let stripFormat, let stripSize {
            let text = stripText
            stripFormat.stringValue = text.format
            stripSize.stringValue = text.size
        }
        marksChanged()
    }

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

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        super.mouseExited(with: event)
    }

    /// Hidden (Home behind the viewer, or the card put aside in the pool): no `mouseExited` comes, so the hover ends here.
    override func viewDidHide() {
        super.viewDidHide()
        isHovered = false
    }

    private var showsStrip: Bool {
        guard isHovered, showsNames else { return false }
        let text = stripText
        return !text.format.isEmpty || !text.size.isEmpty
    }

    /// The marks shown or hidden; one shown for the first time is made, and laid out with the next layout.
    private func marksChanged() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var made = false
        if isUnseen, dotLayer == nil { makeDot(); made = true }
        dotLayer?.isHidden = !isUnseen
        let chip = isPaired && showsNames
        if chip, chipLayer == nil { makeChip(); made = true }
        chipLayer?.isHidden = !chip
        let shows = showsStrip
        if shows, strip == nil { makeStrip(); made = true }
        let moved = strip.map { $0.isHidden == shows } ?? false
        strip?.isHidden = !shows
        CATransaction.commit()
        // A new mark, or the strip moving the name on the picture, needs a layout.
        if made || (moved && names == .photo) { needsLayout = true }
    }

    private func makeDot() {
        let side = Self.dot + 2 * Self.dotRing
        let halo = CALayer()
        halo.backgroundColor = NSColor(white: 1, alpha: 0.85).cgColor
        halo.cornerRadius = side / 2
        let dot = CALayer()
        dot.frame = CGRect(x: Self.dotRing, y: Self.dotRing, width: Self.dot, height: Self.dot)
        dot.cornerRadius = Self.dot / 2
        dot.backgroundColor = Chrome.resolve(Chrome.Palette.window.accent, in: self)
        halo.addSublayer(dot)
        layer?.insertSublayer(halo, below: ring)
        dotLayer = halo
    }

    private func makeChip() {
        let chip = CALayer()
        chip.backgroundColor = Self.markFill.withAlphaComponent(0.58).cgColor
        chip.cornerRadius = 5
        // ⧉: two 6 × 10 pages of a 16-unit box, stroked 1.5 units, drawn at 12 pt.
        let glyph = CAShapeLayer()
        let scale: CGFloat = 12.0 / 16
        let path = CGMutablePath()
        for x in [1.5, 8.5] as [CGFloat] {
            path.addRoundedRect(in: CGRect(x: x * scale, y: 3 * scale, width: 6 * scale, height: 10 * scale),
                                cornerWidth: scale, cornerHeight: scale)
        }
        glyph.path = path
        glyph.fillColor = nil
        glyph.strokeColor = NSColor.white.cgColor
        glyph.lineWidth = 1.5 * scale
        glyph.frame = CGRect(x: 3, y: 2, width: 12, height: 12)
        chip.addSublayer(glyph)
        layer?.insertSublayer(chip, below: ring)
        chipLayer = chip
    }

    private func makeStrip() {
        let strip = NSView()
        strip.wantsLayer = true
        strip.layer?.backgroundColor = Self.markFill.withAlphaComponent(0.6).cgColor
        strip.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]   // the bottom ones: not flipped
        let format = NSTextField(labelWithString: ""), size = NSTextField(labelWithString: "")
        for label in [format, size] {
            label.font = Self.stripFont
            label.textColor = .white
            label.lineBreakMode = .byClipping
            strip.addSubview(label)
        }
        size.alignment = .right
        stripFormat = format
        stripSize = size
        let text = stripText
        format.stringValue = text.format
        size.stringValue = text.size
        addSubview(strip)
        self.strip = strip
    }

    private static let stripHeight =
        (stripFont.ascender - stripFont.descender + stripFont.leading).rounded(.up) + 2 * stripPadding.height

    override func layout() {
        super.layout()
        let rect = pictureRect, side = bounds.width
        let radius = min(Chrome.Radius.photo, min(rect.width, rect.height) / 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        picture.frame = rect
        picture.contentsGravity = style == .square ? .resizeAspectFill : .resizeAspect
        picture.cornerRadius = radius
        ring.frame = rect
        ring.cornerRadius = radius
        hairline.frame = ring.bounds.insetBy(dx: Self.ringWidth, dy: Self.ringWidth)
        hairline.cornerRadius = max(0, radius - Self.ringWidth)
        if let dotLayer {
            let side = Self.dot + 2 * Self.dotRing
            dotLayer.frame = CGRect(x: rect.maxX - Self.markInset - Self.dot - Self.dotRing,
                                    y: rect.minY + Self.markInset - Self.dotRing, width: side, height: side)
        }
        chipLayer?.frame = CGRect(origin: CGPoint(x: rect.minX + Self.markInset, y: rect.minY + Self.markInset),
                                  size: Self.chipSize)
        let stripHeight = Self.stripHeight
        if let strip, let stripFormat, let stripSize {
            strip.frame = CGRect(x: rect.minX, y: rect.maxY - stripHeight, width: rect.width, height: stripHeight)
            strip.layer?.cornerRadius = radius
            let pad = Self.stripPadding
            let line = CGRect(x: pad.width, y: pad.height, width: max(0, rect.width - 2 * pad.width),
                              height: stripHeight - 2 * pad.height)
            stripSize.frame = line
            let sizeWidth = min(line.width, stripSize.intrinsicContentSize.width)
            stripFormat.frame = CGRect(x: line.minX, y: line.minY, width: max(0, line.width - sizeWidth - 4),
                                       height: line.height)
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
            // Above the strip while it shows.
            let bottom = rect.maxY - (strip?.isHidden == false ? stripHeight : 0)
            let band = min(rect.height, 32)
            shade.frame = CGRect(x: rect.minX, y: bottom - band, width: rect.width, height: band)
            nameLabel.frame = CGRect(x: rect.minX + 6, y: bottom - 20, width: max(0, rect.width - 12), height: 16)
        } else {
            nameLabel.font = Chrome.Text.font(.label)
            nameLabel.textColor = Chrome.Palette.window.secondaryLabel
            nameLabel.shadow = nil
            nameLabel.frame = CGRect(x: 0, y: side + 3, width: side, height: 16)
        }
        CATransaction.commit()
    }
}
