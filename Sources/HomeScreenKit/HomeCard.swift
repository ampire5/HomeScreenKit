import AppKit
import HomeChrome
import HomeScreenModel

/// One card: a picture (or a grey box with a symbol), a title and a line under it, an optional bar along the picture's
/// bottom edge and an optional label on it. The whole card is one button; a right click shows its menu.
final class HomeCard: GridCard {
    /// The picture's height over its width.
    var aspect: CGFloat { didSet { if aspect != oldValue { needsLayout = true } } }

    private let picture = NSView()
    private let placeholder = NSImageView()
    private let badge = NSTextField(labelWithString: "")
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: " ")
    private let track = CALayer()
    private let bar = CALayer()
    /// The selection: an accent ring a little outside the picture, as Photos draws it, so it never covers the picture.
    let ring = CALayer()

    private static let corner = Chrome.Radius.card
    private static let ringWidth = Chrome.Ring.width
    private static let ringGap = Chrome.Ring.gap

    private static let barHeight: CGFloat = 4

    init(item: HomeCardItem, aspect: CGFloat) {
        self.aspect = aspect
        super.init(item: item)
        picture.wantsLayer = true
        picture.layer?.cornerRadius = Self.corner
        picture.layer?.cornerCurve = .continuous
        picture.layer?.masksToBounds = true
        picture.layer?.backgroundColor = NSColor(white: 0.14, alpha: 1).cgColor
        picture.layer?.contentsGravity = .resizeAspectFill
        // A hairline at rest, so a dark picture keeps its edge on the dark screen.
        picture.layer?.borderWidth = 0.5
        picture.layer?.borderColor = NSColor(white: 1, alpha: 0.1).cgColor
        ring.borderColor = NSColor.controlAccentColor.cgColor
        ring.borderWidth = Self.ringWidth
        ring.cornerRadius = Self.corner + Self.ringGap + Self.ringWidth
        ring.cornerCurve = .continuous
        ring.isHidden = true
        layer?.addSublayer(ring)
        track.backgroundColor = Chrome.Palette.overMedia.mediaShadow.cgColor
        bar.backgroundColor = NSColor.controlAccentColor.cgColor
        picture.layer?.addSublayer(track)
        picture.layer?.addSublayer(bar)
        placeholder.contentTintColor = .tertiaryLabelColor
        placeholder.symbolConfiguration = .init(pointSize: 30, weight: .light)
        picture.addSubview(placeholder)
        badge.font = Chrome.Text.font(.badge)
        badge.textColor = Chrome.Palette.overMedia.text
        badge.drawsBackground = true
        badge.backgroundColor = Chrome.Palette.overMedia.mediaShadow
        picture.addSubview(badge)
        title.font = Chrome.Text.font(.body, weight: .medium)
        title.lineBreakMode = .byTruncatingMiddle
        subtitle.font = Chrome.Text.digits(.small, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        for view in [picture, title, subtitle] { addSubview(view) }
        show(item)
        selectionChanged()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The text, bar and label of the item.
    override func itemChanged() {
        placeholder.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)
        title.stringValue = item.title
        subtitle.stringValue = item.subtitle ?? " "
        badge.stringValue = item.badge.map { " \($0) " } ?? ""
        badge.isHidden = item.badge == nil
    }

    /// The whole picture with bands (`resizeAspect`) or the card filled (`resizeAspectFill`, cropped).
    var pictureGravity: CALayerContentsGravity {
        get { picture.layer?.contentsGravity ?? .resizeAspectFill }
        set { picture.layer?.contentsGravity = newValue }
    }

    override func imageChanged() {
        picture.layer?.contents = image
        placeholder.isHidden = image != nil
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = (w * aspect).rounded()
        picture.frame = CGRect(x: 0, y: 0, width: w, height: h)
        let size = placeholder.fittingSize
        placeholder.frame = CGRect(x: (w - size.width) / 2, y: (h - size.height) / 2, width: size.width, height: size.height)
        let b = badge.fittingSize
        badge.frame = CGRect(x: 8, y: h - b.height - 8, width: b.width, height: b.height)   // the picture is not flipped: top left
        title.frame = CGRect(x: 0, y: h + 8, width: w, height: 18)
        subtitle.frame = CGRect(x: 0, y: h + 26, width: w, height: 16)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let progress = item.progress.map { min(1, max(0, $0)) }
        track.isHidden = progress == nil
        bar.isHidden = progress == nil
        track.frame = CGRect(x: 0, y: 0, width: w, height: Self.barHeight)
        bar.frame = CGRect(x: 0, y: 0, width: (w * (progress ?? 0)).rounded(), height: Self.barHeight)
        let outset = Self.ringGap + Self.ringWidth
        ring.frame = picture.frame.insetBy(dx: -outset, dy: -outset)
        CATransaction.commit()
    }

    override func selectionChanged() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.isHidden = !isSelected
        CATransaction.commit()
        title.textColor = isSelected ? .white : NSColor(white: 0.82, alpha: 1)
    }
}
