import AppKit
import HomeChrome
import HomeScreenModel

/// A photo in the grid (photo-cards spec 2026-10-26). Square: the picture fills the slot's square, cropped. Aspect:
/// the whole picture sits in the square inset by 8 pt. Either way everything is drawn on the picture: radius 8, the
/// selection a 2.5 pt ring inside it with a dark hairline inside the ring, a dot at the top right for a photo not
/// viewed yet, a ⧉ chip at the top left for a page of a pair, and on hover a strip along the bottom with the format
/// and the size. The dot, the chip and the strip are made the first time they show. The name goes on the picture,
/// under the square, or nowhere. The slot's picture box is `aspect` wide over tall (a square for photos); with
/// `showsFacts` (`FileStyle.facts`, a video app) the card's own line sits in a chip at the picture's bottom right and
/// its progress is a track along the bottom edge.
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
    var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            marksChanged()
            if names == .auto { needsLayout = true }   // the band with the name comes and goes
        }
    }
    var aspect: CGFloat = 1 { didSet { if aspect != oldValue { needsLayout = true } } }
    var showsFacts = false { didSet { if showsFacts != oldValue { itemChanged() } } }
    /// The facts line under the name in `.below` (`FileStyle.factsLine`, file-cards spec §2).
    var showsFactsLine = false { didSet { if showsFactsLine != oldValue { needsLayout = true } } }

    let ring = CALayer()
    let nameLabel = NSTextField(labelWithString: "")
    /// Under the name: `FHD · 60p · HEVC · 1.2 GB`, `1/250 · f/2.8 · ISO 400`.
    let factsLabel = NSTextField(labelWithString: "")
    let hairline = CALayer()
    private let picture = CALayer()
    private let shade = GridCard.shade()
    private(set) var dotLayer: CALayer?
    private(set) var chipLayer: CALayer?
    private(set) var strip: NSView?
    private var stripFormat: NSTextField?
    private var stripSize: NSTextField?
    /// The facts (`showsFacts`): the progress track and its fill along the picture's bottom, the line's chip.
    private let track = CALayer()
    private let fill = CALayer()
    /// A video's length (or `0:04 / 23:03`) at the picture's bottom right: mono 11 on the scrim (style guide F1).
    let lengthChip = ChipView(font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium), fill: NSColor(white: 0, alpha: 0.55))
    /// The badges at the picture's top left (`FileFactsText.badges`: `RAW`, `24 MP`; `UHD`, `HLG`), made the first
    /// time they show; on slots from `badgesFrom`.
    private var badgeLabels: [MediaBadge] = []
    private static let badgesFrom: CGFloat = 120

    private static let aspectInset: CGFloat = 8
    private static let ringWidth: CGFloat = 2.5
    /// The dot: 8 pt in a 1.5 pt white ring, 6 pt in from the picture's top right (the chip: from its top left).
    private static let dot: CGFloat = 8, dotRing: CGFloat = 1.5, markInset: CGFloat = 6
    /// The chip: a 12 pt glyph, padding 2 × 3, radius 5.
    private static let chipSize = CGSize(width: 18, height: 16)
    /// The exposure as a camera's screen writes it (style guide F5): monospaced, values apart by two spaces.
    private static let stripFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private static let stripPadding = CGSize(width: 7, height: 5)
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
        factsLabel.lineBreakMode = .byTruncatingTail
        factsLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        factsLabel.isHidden = true
        addSubview(factsLabel)
        // Over the picture: dark whatever the window is, as the over-media chrome.
        track.backgroundColor = NSColor(white: 0, alpha: 0.55).cgColor
        track.addSublayer(fill)
        layer?.addSublayer(track)
        lengthChip.textColor = Chrome.Palette.overMedia.text
        addSubview(lengthChip)
        show(item)
        appearanceChanged()
    }

    override func appearanceChanged() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        picture.backgroundColor = Chrome.resolve(Chrome.Palette.window.fill, in: self)
        fill.backgroundColor = Chrome.Palette.card.accent.cgColor   // the progress fill, the same blue in both appearances
        ring.borderColor = Chrome.resolve(Chrome.Palette.window.accent, in: self)
        dotLayer?.sublayers?.first?.backgroundColor = Chrome.resolve(Chrome.Palette.window.accent, in: self)
        CATransaction.commit()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The badges in a row from the picture's top left (after the ⧉ chip of a pair), each on the dark chip fill.
    private func layoutBadges(in rect: CGRect) {
        let badges = showsBadges ? FileFactsText.badges(item.facts, format: item.format) : []
        while badgeLabels.count < badges.count {
            let badge = MediaBadge()
            addSubview(badge)
            badgeLabels.append(badge)
        }
        var x = rect.minX + Self.markInset + (isPaired && showsNames ? Self.chipSize.width + 4 : 0)
        for (i, label) in badgeLabels.enumerated() {
            guard i < badges.count else { label.isHidden = true; continue }
            let badge = badges[i]
            label.show(badge)
            let size = label.intrinsicContentSize
            let frame = CGRect(x: x, y: rect.minY + Self.markInset, width: size.width, height: size.height)
            label.isHidden = frame.maxX > rect.maxX - Self.markInset - 14   // the dot's corner stays clear
            label.frame = frame
            x = frame.maxX + 4
        }
    }


    /// The track along the picture's bottom edge (3 pt, only with a progress) and the chip 6 pt in from its bottom
    /// right corner, above the track (only with a line, and on a picture wide enough for it).
    private func layoutFacts(in rect: CGRect) {
        let progress = showsFacts ? item.progress : nil
        track.isHidden = progress == nil
        if let progress {
            track.frame = CGRect(x: rect.minX, y: rect.maxY - 3, width: rect.width, height: 3)
            fill.frame = CGRect(x: 0, y: 0, width: (rect.width * min(1, max(0, progress))).rounded(), height: 3)
        }
        let line = showsFacts ? lengthText : ""
        let size = lengthChip.intrinsicContentSize
        lengthChip.isHidden = line.isEmpty || size.width > rect.width - 12
        lengthChip.frame = CGRect(x: rect.maxX - Self.markInset - size.width,
                                  y: rect.maxY - (progress == nil ? Self.markInset : 9) - size.height,
                                  width: size.width, height: size.height)
    }

    /// The slot's picture box: its width, `aspect` wide over tall.
    private var boxHeight: CGFloat { aspect == 1 ? bounds.width : (bounds.width / max(0.1, aspect)).rounded() }

    /// Square: the slot's box. Aspect: the image fitted in the box inset by 8 pt (that box while there is none).
    override var lastOpenedHighlightRect: CGRect { pictureRect }

    var pictureRect: CGRect {
        let side = bounds.width
        switch style {
        case .square:
            return CGRect(x: 0, y: 0, width: side, height: boxHeight)
        case .aspect:
            let box = CGRect(x: 0, y: 0, width: side, height: boxHeight).insetBy(dx: Self.aspectInset, dy: Self.aspectInset)
            guard let image, image.width > 0, image.height > 0, box.width > 0 else { return box }
            let scale = min(box.width / CGFloat(image.width), box.height / CGFloat(image.height))
            let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
            // With the name under it the picture sits on the box's bottom, as Finder's icons do: the names of a row
            // stay on one line, right under their pictures.
            let y = names == .below ? box.maxY - h : box.minY + (box.height - h) / 2
            return CGRect(x: box.minX + (box.width - w) / 2, y: y, width: w, height: h)
        }
    }

    /// The chip on a video's picture: the entry's own line (`12:30 / 1:02:10`), else the length from its facts.
    var lengthText: String { item.subtitle ?? item.facts?.duration.map(FileFactsText.length) ?? "" }

    /// The strip's two texts: the exposure (else the format) and the size as a file's ("" for what the item does not
    /// have). The exposure is fitted by whole values (`layoutStrip`).
    var stripText: (format: String, size: String) {
        (item.facts.flatMap(FileFactsText.exposureLine) ?? item.format ?? "", item.bytes.map(FileFactsText.size) ?? "")
    }

    /// The facts line under the name shows already: the strip then says what it does not (the camera), not the
    /// exposure again.
    private var factsLineShown: Bool { names == .below && showsFactsLine && !factsLabel.stringValue.isEmpty }

    /// The line under the name: a video with its badges on the picture says only its codec and size.
    private var factsLine: String {
        if let f = item.facts, f.isVideo, showsBadges { return FileFactsText.videoLineWithBadges(f, bytes: item.bytes) ?? "" }
        return FileFactsText.posterLine(item.facts, bytes: item.bytes) ?? ""
    }

    private var showsBadges: Bool { showsNames && bounds.width >= Self.badgesFrom }

    private func fillStrip() {
        guard let stripSize else { return }
        stripSize.stringValue = stripText.size
        needsLayout = true   // the left text is fitted to the room the size leaves (`layoutStrip`)
    }

    /// The strip's left text in the room the size leaves: the exposure in mono, each value after its glyph
    /// (`ExposureLine`; whole values, as many as fit), or
    /// with the facts line under the name the camera and the lens; the format without either. The size gives way
    /// when the exposure would keep fewer than two values beside it.
    private func layoutStrip(_ line: CGRect) {
        guard let stripFormat, let stripSize else { return }
        let size = stripText.size
        let sizeWidth = size.isEmpty ? 0 : ceil(stripSize.intrinsicContentSize.width)
        func place(sizeShown: Bool) -> Bool {
            let room = max(0, line.width - (sizeShown ? sizeWidth + 8 : 0))
            stripSize.isHidden = !sizeShown
            stripSize.frame = line
            stripFormat.frame = CGRect(x: line.minX, y: line.minY, width: room, height: line.height)
            if !factsLineShown, let f = item.facts, case let parts = FileFactsText.exposureValues(f), !parts.isEmpty {
                var count = parts.count
                func line(_ n: Int) -> NSAttributedString {
                    ExposureLine.text(Array(parts.prefix(n)), font: Self.stripFont, color: .white,
                                      glyphColor: NSColor(white: 1, alpha: 0.7))
                }
                while count > 0, line(count).size().width > room - 2 { count -= 1 }
                if count == 0 || (sizeShown && count < parts.count && count < 2) { return false }
                stripFormat.attributedStringValue = line(count)
                return true
            }
            let words = factsLineShown ? item.facts.flatMap(FileFactsText.cameraLine) ?? item.format : item.format
            stripFormat.stringValue = words ?? ""
            return true
        }
        if !place(sizeShown: !size.isEmpty) { _ = place(sizeShown: false) }
    }

    override func show(_ item: HomeCardItem) {
        if item.id != self.item.id { isHovered = false }
        super.show(item)
        // No tooltip with the file's path: it covered the strip, and the path bar and the name already say it (the
        // owner, 2026-10-27).
        toolTip = nil
    }

    override func itemChanged() {
        nameLabel.stringValue = item.title
        fillStrip()
        lengthChip.text = lengthText
        factsLabel.stringValue = factsLine
        marksChanged()
        needsLayout = true
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
        // A video's picture carries its length chip and progress; its facts are the line under its name. With
        // `auto` names on a small tile the band with the name takes the strip's place.
        guard isHovered, showsNames, !showsFacts, names != .auto else { return false }
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
            label.lineBreakMode = .byTruncatingTail
            strip.addSubview(label)
        }
        size.alignment = .right
        stripFormat = format
        stripSize = size
        fillStrip()
        addSubview(strip)
        self.strip = strip
    }

    /// The text's line or the glyphs' height, whichever is taller, and the padding.
    private static let stripHeight =
        max(stripFont.ascender - stripFont.descender + stripFont.leading, stripFont.pointSize + 3).rounded(.up)
            + 2 * stripPadding.height

    override func layout() {
        super.layout()
        let rect = pictureRect
        let radius = min(Chrome.Radius.photo, min(rect.width, rect.height) / 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        picture.frame = rect
        picture.contentsGravity = style == .square ? .resizeAspectFill : .resizeAspect
        picture.cornerRadius = radius
        ring.frame = rect
        ring.cornerRadius = radius
        hairline.frame = ring.bounds.insetBy(dx: ring.borderWidth, dy: ring.borderWidth)
        hairline.cornerRadius = max(0, radius - ring.borderWidth)
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
            if !strip.isHidden { layoutStrip(line) }
        }
        let line = factsLine   // it depends on the width (the badges take a video's stream)
        if factsLabel.stringValue != line { factsLabel.stringValue = line }
        layoutBadges(in: rect)
        // `auto` on a small tile: the name and its facts as a band over the picture while the pointer is on it.
        let band = names == .auto
        let named = showsNames && names != .off && (!band || isHovered)
        nameLabel.isHidden = !named
        shade.isHidden = !(named && (names == .photo || band))
        if band {
            nameLabel.font = Chrome.Text.font(.label, weight: .semibold)
            nameLabel.textColor = Chrome.Palette.overMedia.text
            nameLabel.shadow = nil
            let hasFacts = !factsLabel.stringValue.isEmpty
            let height = min(rect.height, hasFacts ? 44 : 32)
            shade.frame = CGRect(x: rect.minX, y: rect.maxY - height, width: rect.width, height: height)
            nameLabel.frame = CGRect(x: rect.minX + 6, y: rect.maxY - (hasFacts ? 36 : 20), width: max(0, rect.width - 12), height: 16)
            factsLabel.isHidden = !named || !hasFacts
            factsLabel.textColor = Chrome.Palette.overMedia.secondaryText
            factsLabel.frame = CGRect(x: rect.minX + 6, y: rect.maxY - 19, width: max(0, rect.width - 12), height: 14)
        } else if names == .photo {
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
            factsLabel.isHidden = true
        } else {
            nameLabel.font = Chrome.Text.font(.label)
            nameLabel.textColor = showsFactsLine ? Chrome.Palette.window.label : Chrome.Palette.window.secondaryLabel
            nameLabel.shadow = nil
            // Under the picture as drawn: a picture fitted narrower than its slot (Aspect) has its text at its own edges.
            let x = style == .aspect ? rect.minX : 0
            let width = max(0, bounds.width - 2 * x)
            nameLabel.frame = CGRect(x: x, y: boxHeight + 3, width: width, height: 16)
            factsLabel.isHidden = !(named && names == .below && showsFactsLine) || factsLabel.stringValue.isEmpty
            factsLabel.textColor = Chrome.Palette.window.secondaryLabel
            factsLabel.frame = CGRect(x: x, y: boxHeight + 3 + 16, width: width, height: 14)
        }
        layoutFacts(in: rect)
        CATransaction.commit()
    }
}
