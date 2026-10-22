import AppKit
import HomeChrome
import HomeScreenModel

/// What `PosterCard`, `CompactCard` and `ListRow` share, drawn as the approved mockups (E «Плакат», B «Карточка»,
/// C «Список»): the cover (dimmed while the folder's volume is away or the archive cannot be read), the name with
/// its badges (⧉, RTL), the facts' texts and the dates' bars, the progress track, the `+12` pill and ✓, the
/// cover's `ZIP` chip and the warning line. The colours are `Chrome.Palette.card`'s; the subclasses place the parts
/// and pick their sizes. A card without `summary` shows its subtitle where the facts go.
class FolderCard: GridCard {
    // MARK: Parts

    /// The card's plate (posters and compact cards) and its 0.5 pt ring, outside the plate as the mockups' shadow is.
    let plate = CALayer()
    let edge = CALayer()
    /// The selection ring.
    let ring = CALayer()
    /// Rounds the cover's corners: as tall as the cover, or (a poster) a radius taller so that only its top corners
    /// show round; the picture inside it.
    let coverClip = CoverClip()
    let picture = NSView()
    private let placeholder = NSImageView()
    let nameLabel = CardText()
    let twoPagesIcon = GlyphView(ChromeGlyph.twoPages, color: Chrome.Palette.card.secondary, lineWidth: 1.4)
    let rtlLabel = TextChip(.outlined(size: 9.5))
    /// The facts: a poster's line, a compact card's counts, a row's Inside column.
    let insideLabel = CardText()
    /// The years (a poster, a row) or the dates' span (a compact card, a large poster with its progress).
    let yearsLabel = CardText()
    let sizeLabel = CardText()
    /// "153 / 248" (a compact card).
    let viewedLabel = CardText()
    /// The subtitle, when there is no summary.
    let fallbackLabel = CardText()
    /// An unavailable folder's or a damaged archive's line, and its glyph (a compact card's, a row's badge).
    let warningLabel = CardText()
    let problemIcon = GlyphView(nil, color: Chrome.Palette.card.warning, lineWidth: 1.5)
    let histogram = HistogramView()
    /// `+12`, and ✓ when viewed to the end.
    let newPill = TextChip(.newPill())
    let checkIcon = GlyphView(ChromeGlyph.check, color: Chrome.Palette.card.secondary, lineWidth: 2)
    /// The archive's type over the cover (`ZIP`, `CBZ`).
    let coverChip = TextChip(.overCover(size: 10, padX: 6, padY: 2, radius: 6, veil: 0.58))
    /// How much was seen: a track and its fill.
    let progressTrack = NSView()
    let progressBar = NSView()

    static let ringWidth = Chrome.Ring.width
    static let ringGap = Chrome.Ring.gap
    /// Between the name line's parts (the mockups' `gap: 6px`).
    static let gap: CGFloat = 6

    /// The measurements (the kit's defaults: the browser only changes the grid's top, which cards do not use).
    var metrics = GridMetrics() { didSet { needsLayout = true } }

    /// The summary on the card now.
    var summary: CardSummary? { item.summary }
    /// An archive that holds pages (read as a book: ⧉ or RTL, or a comic's CBZ): its count is "pages".
    var holdsPages: Bool {
        guard let badge = item.badge, let s = summary else { return false }
        return s.twoPages || s.rightToLeft || badge.uppercased().hasPrefix("CB")
    }
    /// The progress shown: the summary's, else the item's (a recent folder's).
    var shownProgress: Double? { summary?.viewed ?? item.progress }
    var problem: CardSummary.Problem? { summary?.problem }

    override init(item: HomeCardItem) {
        super.init(item: item)
        layer?.addSublayer(plate)
        plate.cornerCurve = .continuous
        edge.borderWidth = 0.5
        edge.cornerCurve = .continuous
        coverClip.wantsLayer = true
        coverClip.layer?.cornerCurve = .continuous
        coverClip.layer?.masksToBounds = true
        coverClip.addSubview(picture)
        picture.wantsLayer = true
        picture.layer?.masksToBounds = true
        picture.layer?.contentsGravity = .resizeAspectFill
        placeholder.contentTintColor = Chrome.Palette.window.tertiaryLabel
        placeholder.symbolConfiguration = .init(pointSize: 30, weight: .light)
        picture.addSubview(placeholder)
        for bar in [progressTrack, progressBar] {
            bar.wantsLayer = true
        }
        ring.borderWidth = Self.ringWidth
        ring.cornerCurve = .continuous
        ring.isHidden = true
        nameLabel.textColor = Chrome.Palette.card.label
        for label in [insideLabel, yearsLabel, sizeLabel, viewedLabel, fallbackLabel] {
            label.textColor = Chrome.Palette.card.secondary
        }
        warningLabel.textColor = Chrome.Palette.card.warning
        let parts: [NSView] = [coverClip, progressTrack, progressBar, nameLabel, twoPagesIcon, rtlLabel, insideLabel,
                               yearsLabel, sizeLabel, viewedLabel, fallbackLabel, warningLabel, problemIcon, histogram,
                               newPill, checkIcon, coverChip]
        for view in parts { addSubview(view) }
        rtlLabel.text = "RTL"
        layer?.addSublayer(edge)
        layer?.addSublayer(ring)
        show(item)
        appearanceChanged()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The cover; the subclasses say where.
    var pictureFrame: CGRect { .zero }
    var progressFrame: CGRect { progressBar.frame }
    var isShowingSymbol: Bool { !placeholder.isHidden }

    /// Folder cards draw an unavailable folder themselves (its cover faint, its facts readable): the item's dimming
    /// is for the other cards.
    override func show(_ item: HomeCardItem) {
        super.show(item)
        alphaValue = item.isDimmed && item.summary?.problem == nil ? 0.45 : 1
    }

    override func itemChanged() {
        placeholder.image = Self.symbol(item.symbol)
        imageChanged()
        nameLabel.stringValue = item.title
        coverChip.text = item.badge ?? ""
        coverChip.isHidden = item.badge == nil
        let s = summary
        histogram.bins = s?.histogram ?? []
        fallbackLabel.stringValue = s == nil ? item.subtitle ?? "" : ""
        rtlLabel.isHidden = !(s?.rightToLeft ?? false)
        twoPagesIcon.isHidden = !(s?.twoPages ?? false)
        newPill.text = (s?.new ?? 0) > 0 ? "+\(s!.new)" : ""
        newPill.isHidden = newPill.text.isEmpty
        checkIcon.isHidden = !(s?.done ?? false)
        switch s?.problem {
        case .broken?: problemIcon.glyph = ChromeGlyph.warning
        case .offline?: problemIcon.glyph = ChromeGlyph.offline
        case nil: problemIcon.glyph = nil
        }
        problemIcon.isHidden = s?.problem == nil
        picture.alphaValue = Self.coverOpacity(s?.problem)
        warningLabel.stringValue = ""
        warningLabel.isHidden = true
        progressBar.isHidden = shownProgress == nil
    }

    /// The mockups' cover opacity: .4 while the volume is away, .25 for an archive that cannot be read.
    static func coverOpacity(_ problem: CardSummary.Problem?) -> CGFloat {
        switch problem {
        case .offline?: 0.4
        case .broken?: 0.25
        case nil: 1
        }
    }

    /// The warning line's words: the short ones under a poster's cover, the long ones in a compact card.
    static func warning(_ problem: CardSummary.Problem, short: Bool) -> String {
        switch problem {
        case .offline: short ? "Volume not connected · from the catalog" : "Network volume not connected · facts from the catalog"
        case .broken: short ? "Archive is damaged" : "Archive is damaged: couldn't open it"
        }
    }

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
        plate.backgroundColor = Chrome.resolve(Chrome.Palette.card.background, in: self)
        edge.borderColor = Chrome.resolve(Chrome.Palette.card.separator, in: self)
        picture.layer?.backgroundColor = Chrome.resolve(Chrome.Palette.window.fill, in: self)
        progressBar.layer?.backgroundColor = Chrome.resolve(Chrome.Palette.card.accent, in: self)
        progressTrack.layer?.backgroundColor = Chrome.resolve(Chrome.Palette.card.track, in: self)
        ring.borderColor = Chrome.resolve(Chrome.Palette.window.accent, in: self)
        CATransaction.commit()
    }

    /// The plate and its ring over `rect` with `radius`; the selection ring round `selection`.
    func layoutPlate(_ rect: CGRect, radius: CGFloat, selection: CGRect? = nil, selectionRadius: CGFloat? = nil) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        plate.frame = rect
        plate.cornerRadius = radius
        edge.frame = rect.insetBy(dx: -0.5, dy: -0.5)
        edge.cornerRadius = radius + 0.5
        let outset = Self.ringGap + Self.ringWidth
        let around = selection ?? rect
        ring.frame = around.insetBy(dx: -outset, dy: -outset)
        ring.cornerRadius = (selectionRadius ?? radius) + outset
        CATransaction.commit()
    }

    /// The cover in `p` with `radius` (only its top corners for a poster) and the placeholder in its middle.
    func layoutCover(_ p: CGRect, radius: CGFloat, topOnly: Bool = false) {
        coverClip.frame = CGRect(x: p.minX, y: p.minY, width: p.width, height: p.height + (topOnly ? radius : 0))
        coverClip.layer?.cornerRadius = radius
        picture.frame = CGRect(origin: .zero, size: p.size)
        let size = placeholder.fittingSize
        placeholder.frame = CGRect(x: (p.width - size.width) / 2, y: (p.height - size.height) / 2, width: size.width,
                                   height: size.height)
    }

    /// Symbols by name: a card is shown again for every scroll step, the image is made once.
    private static var symbols: [String: NSImage] = [:]
    static func symbol(_ name: String, _ description: String? = nil) -> NSImage? {
        if let image = symbols[name] { return image }
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: description) else { return nil }
        symbols[name] = image
        return image
    }

    /// The name must keep this much of its line; a badge that would squeeze it further is left out.
    static let minName: CGFloat = 48

    /// Lays a name line as the mockups' flex row does: the name (cut with "…" when short of room), then right after
    /// it the badges `after` (⧉, RTL, a warning), then at the line's end the items `end` (`+12`, ✓). Each item is
    /// (view, size, wanted); a badge that would leave the name less than `minName` is left out, the last first.
    func layoutNameLine(_ line: CGRect, after: [(NSView, CGSize, Bool)], end: [(NSView, CGSize, Bool)] = []) {
        let gap = Self.gap
        var right = line.maxX
        for (view, size, wanted) in end.reversed() {
            view.isHidden = !wanted
            guard wanted else { continue }
            right -= size.width
            view.frame = CGRect(x: right, y: (line.midY - size.height / 2).rounded(), width: size.width, height: size.height)
            right -= gap
        }
        var badges = after.filter(\.2)
        for (view, _, wanted) in after where !wanted { view.isHidden = true }
        func badgesWidth() -> CGFloat { badges.reduce(0) { $0 + gap + $1.1.width } }
        while !badges.isEmpty, right - line.minX - badgesWidth() < Self.minName {
            badges.removeLast().0.isHidden = true
        }
        let nameWidth = min(nameLabel.textWidth, max(0, right - line.minX - badgesWidth()))
        nameLabel.frame = CGRect(x: line.minX, y: line.minY, width: max(nameWidth, 1), height: line.height)
        var x = line.minX + nameWidth
        for (view, size, _) in badges {
            view.isHidden = false
            x += gap
            view.frame = CGRect(x: x, y: (line.midY - size.height / 2).rounded(), width: size.width, height: size.height)
            x += size.width
        }
    }

    /// The name line in the card's coordinates: the rename field goes here.
    var nameLine: CGRect { .zero }
    override var nameFrame: CGRect { nameLine }
}

/// The cover's rounded clip: top-down, so the picture sits at its top.
final class CoverClip: NSView {
    override var isFlipped: Bool { true }
}
