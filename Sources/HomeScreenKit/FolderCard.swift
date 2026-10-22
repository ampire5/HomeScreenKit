import AppKit
import HomeChrome
import HomeScreenModel

/// What `PosterCard` and `CompactCard` share: a folder's or an archive's square cover with rounded corners and a ring
/// around it, the name with its badges (⧉, RTL, a problem), the facts (counts, a histogram of dates, the years, the
/// size, how much was seen) and the label (`+12`, ✓) that tells about new photos. The subclasses place them.
/// A card without `summary` shows its subtitle where the facts go, as the collection card did.
class FolderCard: GridCard {
    let nameLabel = NSTextField(labelWithString: "")
    let insideLabel = NSTextField(labelWithString: "")
    let yearsLabel = NSTextField(labelWithString: "")
    let sizeLabel = NSTextField(labelWithString: "")
    let viewedLabel = NSTextField(labelWithString: "")
    /// The photo count at the end of a narrow poster's only line.
    let countLabel = NSTextField(labelWithString: "")
    /// The subtitle, when there is no summary.
    let fallbackLabel = NSTextField(labelWithString: "")
    let rtlLabel = NSTextField(labelWithString: "RTL")
    let twoPagesIcon = NSImageView()
    let problemIcon = NSImageView()
    let histogram = HistogramView()
    /// The label for a ZIP (or any `item.badge`), at the cover's top left.
    let badgePill = GlassPill()
    /// `+12` or ✓, in the accent colour.
    let flagPill = FlagPill()
    let ring = CALayer()
    /// How much was seen: a line along the cover's bottom edge (posters) or in a track (cards).
    let progressBar = NSView()
    let progressTrack = NSView()
    let picture = NSView()
    private let placeholder = NSImageView()

    static let corner = Chrome.Radius.card
    private static let ringWidth = Chrome.Ring.width
    private static let ringGap = Chrome.Ring.gap
    static let nameFont = Chrome.Text.font(.body, weight: .semibold)
    static let factsFont = Chrome.Text.font(.small)

    /// The summary on the card now.
    var summary: CardSummary? { item.summary }

    override init(item: HomeCardItem) {
        super.init(item: item)
        picture.wantsLayer = true
        picture.layer?.cornerRadius = Self.corner
        picture.layer?.cornerCurve = .continuous
        picture.layer?.masksToBounds = true
        picture.layer?.contentsGravity = .resizeAspectFill
        placeholder.contentTintColor = Chrome.Palette.window.tertiaryLabel
        placeholder.symbolConfiguration = .init(pointSize: 30, weight: .light)
        picture.addSubview(placeholder)
        for bar in [progressTrack, progressBar] {
            bar.wantsLayer = true
            bar.isHidden = true
        }
        ring.borderWidth = Self.ringWidth
        ring.cornerRadius = Self.corner + Self.ringGap + Self.ringWidth
        ring.cornerCurve = .continuous
        ring.isHidden = true
        layer?.addSublayer(ring)
        nameLabel.font = Self.nameFont
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.textColor = Chrome.Palette.window.label
        for label in [insideLabel, yearsLabel, sizeLabel, viewedLabel, countLabel, fallbackLabel, rtlLabel] {
            label.font = Self.factsFont
            label.textColor = Chrome.Palette.window.secondaryLabel
            label.lineBreakMode = .byTruncatingTail
        }
        rtlLabel.font = Chrome.Text.font(.badge)
        rtlLabel.textColor = Chrome.Palette.window.tertiaryLabel
        twoPagesIcon.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "Two pages")
        twoPagesIcon.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        twoPagesIcon.contentTintColor = Chrome.Palette.window.tertiaryLabel
        problemIcon.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
        Chrome.Palette.overMedia.apply(to: badgePill)   // over the photo: dark whatever the window is
        let parts: [NSView] = [picture, nameLabel, insideLabel, yearsLabel, sizeLabel, viewedLabel, countLabel,
                               fallbackLabel, rtlLabel, twoPagesIcon, problemIcon, histogram, badgePill, flagPill]
        for view in parts { addSubview(view) }
        picture.addSubview(progressTrack)
        picture.addSubview(progressBar)
        show(item)
        appearanceChanged()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The square cover; the subclasses say where.
    var pictureFrame: CGRect { .zero }
    /// Where the rename field goes over the name, in the card's coordinates.
    override var nameFrame: CGRect { .zero }
    var progressFrame: CGRect { convert(progressBar.frame, from: progressBar.superview) }
    var isShowingSymbol: Bool { !placeholder.isHidden }

    /// The progress shown: the summary's, else the item's (a recent folder's).
    var shownProgress: Double? { summary?.viewed ?? item.progress }

    override func itemChanged() {
        placeholder.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)
        imageChanged()
        nameLabel.stringValue = item.title
        badgePill.text = item.badge ?? ""
        badgePill.isHidden = item.badge == nil
        let s = item.summary
        if let s {
            insideLabel.stringValue = CardSummaryText.inside(s)
            yearsLabel.stringValue = CardSummaryText.years(s) ?? ""
            sizeLabel.stringValue = CardSummaryText.size(s) ?? ""
            viewedLabel.stringValue = CardSummaryText.viewed(s) ?? ""
            countLabel.stringValue = s.photos.map { CardSummaryText.inside(CardSummary(photos: $0)) } ?? ""
            histogram.bins = s.histogram
        } else {
            for label in [insideLabel, yearsLabel, sizeLabel, viewedLabel] { label.stringValue = "" }
            countLabel.stringValue = item.count.map { CardSummaryText.inside(CardSummary(photos: $0)) } ?? ""
            histogram.bins = []
        }
        fallbackLabel.stringValue = s == nil ? item.subtitle ?? "" : ""
        rtlLabel.isHidden = !(s?.rightToLeft ?? false)
        twoPagesIcon.isHidden = !(s?.twoPages ?? false)
        switch s?.problem {
        case .broken?:
            problemIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Damaged")
            problemIcon.contentTintColor = .systemOrange
        case .offline?:
            problemIcon.image = NSImage(systemSymbolName: "wifi.slash", accessibilityDescription: "Not reachable")
            problemIcon.contentTintColor = Chrome.Palette.window.secondaryLabel
        case nil:
            problemIcon.image = nil
        }
        problemIcon.isHidden = s?.problem == nil
        if let s, s.new > 0 {
            flagPill.text = "+\(s.new)"
        } else if let s, s.done {
            flagPill.text = "✓"
        } else {
            flagPill.text = ""
        }
        flagPill.isHidden = flagPill.text.isEmpty
        progressBar.isHidden = shownProgress == nil
        progressTrack.isHidden = progressBar.isHidden || !showsTrack
    }

    /// Cards draw the progress in a track; posters only a line.
    var showsTrack: Bool { false }

    override func imageChanged() {
        picture.layer?.contents = image
        placeholder.isHidden = image != nil
    }

    override func selectionChanged() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.isHidden = !isSelected
        CATransaction.commit()
    }

    override func appearanceChanged() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        picture.layer?.backgroundColor = Chrome.resolve(Chrome.Palette.window.fill, in: self)
        progressBar.layer?.backgroundColor = Chrome.resolve(Chrome.Palette.window.accent, in: self)
        progressTrack.layer?.backgroundColor = Chrome.resolve(Chrome.Palette.window.fill, in: self)
        ring.borderColor = Chrome.resolve(Chrome.Palette.window.accent, in: self)
        CATransaction.commit()
        histogram.needsDisplay = true
    }

    /// The cover, the placeholder, the label pills and the ring: the same in both cards.
    func layoutCover(_ p: CGRect, ringAround: CGRect? = nil) {
        picture.frame = p
        let size = placeholder.fittingSize
        placeholder.frame = CGRect(x: (p.width - size.width) / 2, y: (p.height - size.height) / 2, width: size.width,
                                   height: size.height)
        let pill = badgePill.fittingSize
        badgePill.frame = CGRect(x: p.minX + 8, y: p.minY + 8, width: pill.width, height: pill.height)
        let outset = Self.ringGap + Self.ringWidth
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.frame = (ringAround ?? p).insetBy(dx: -outset, dy: -outset)
        CATransaction.commit()
    }

    static func width(of view: NSView) -> CGFloat {
        if let label = view as? NSTextField { return ceil(label.attributedStringValue.size().width) + 6 }
        return view.intrinsicContentSize.width
    }

    /// Lays the name line: the name takes what the badges at its right leave.
    func layoutNameLine(x: CGFloat, y: CGFloat, width: CGFloat, trailing: [NSView]) {
        var right = x + width
        for view in trailing where !view.isHidden {
            let w = Self.width(of: view), h = Self.nameLineHeight
            let size = view is NSTextField ? CGSize(width: w, height: h) : CGSize(width: w, height: view.intrinsicContentSize.height)
            right -= size.width
            view.frame = CGRect(x: right, y: y + (h - size.height) / 2, width: size.width, height: size.height)
            right -= 5
        }
        nameLabel.frame = CGRect(x: x, y: y, width: max(0, right - x + (right < x + width ? 0 : 5)), height: Self.nameLineHeight)
    }

    static let nameLineHeight = GridMetrics().bandNameLine
    static let factsLineHeight = GridMetrics().bandFactsLine
}

/// The bars of a folder's dates: 12 bins, heights scaled to the largest bin so that a spread histogram stays visible.
final class HistogramView: NSView {
    static let barWidth: CGFloat = 2.5, barGap: CGFloat = 1, height: CGFloat = 12

    var bins: [UInt8] = [] {
        didSet {
            guard bins != oldValue else { return }
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    /// At least one bin has photos; the card shows the view only then (and when it fits).
    var hasBars: Bool { bins.contains { $0 > 0 } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: CGFloat(bins.count) * (Self.barWidth + Self.barGap) - Self.barGap, height: Self.height)
    }

    /// Bar heights for `bins` in `height` points: the largest bin is full height, a bin with photos at least 1 pt, an
    /// empty bin nothing.
    static func heights(_ bins: [UInt8], height: CGFloat) -> [CGFloat] {
        guard let top = bins.max(), top > 0 else { return bins.map { _ in 0 } }
        return bins.map { $0 == 0 ? 0 : max(1, height * CGFloat($0) / CGFloat(top)) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let heights = Self.heights(bins, height: bounds.height)
        Chrome.Palette.window.tertiaryLabel.setFill()
        for (i, h) in heights.enumerated() where h > 0 {
            let x = CGFloat(i) * (Self.barWidth + Self.barGap)
            NSRect(x: x, y: bounds.height - h, width: Self.barWidth, height: h).fill()
        }
    }
}

/// `+12` or ✓ on an accent capsule.
final class FlagPill: NSView {
    static let height: CGFloat = 18
    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue; invalidateIntrinsicContentSize(); needsLayout = true }
    }
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = Chrome.Radius.capsule(Self.height)
        layer?.cornerCurve = .continuous
        label.font = Chrome.Text.font(.badge)
        label.textColor = .white
        label.alignment = .center
        addSubview(label)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(label.intrinsicContentSize.width) + 12, height: Self.height)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Chrome.resolve(Chrome.Palette.window.accent, in: self)
    }

    override func layout() {
        super.layout()
        layer?.backgroundColor = Chrome.resolve(Chrome.Palette.window.accent, in: self)
        let h = label.intrinsicContentSize.height
        label.frame = CGRect(x: 6, y: (bounds.height - h) / 2, width: max(0, bounds.width - 12), height: h)
    }
}
