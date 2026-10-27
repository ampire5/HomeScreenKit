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

    /// A waiting card's placeholders and shimmer (`CardSkeleton`): made when the card first waits, in its layer only
    /// while it waits.
    private(set) var skeleton: CardSkeleton?
    /// The highlight (the board's `.sk::after`): one gradient per waiting card; none with Reduce Motion.
    var shimmer: CAGradientLayer? { skeleton?.shimmer }
    static let shimmerKey = "shimmer"
    /// The board's `animation: sh 1.6s ease-in-out infinite`.
    static let shimmerDuration: CFTimeInterval = 1.6
    /// How long a card shimmers at most in one wait; then it keeps still, in the Reduce Motion look, until its facts
    /// and cover come (no animation runs for ever). Basis: five sweeps of the board's 1.6 s; a local folder's cover
    /// and facts come well within it (the cover queue makes 11-13 cards a second on SSD), so the shimmer still says
    /// "on its way" where it is true, while a card that waits on a slow or silent share stops costing the window
    /// server a redraw of its layer 60 times a second (the owner's report: ~30 % of WindowServer CPU with a Home
    /// window of waiting cards visible).
    static let defaultShimmerLimit: Duration = .seconds(8)
    var shimmerLimit: Duration {
        get { shimmerBudget.limit }
        set { shimmerBudget.limit = newValue }
    }
    /// Whether the browser lets the card move (in view, among the first `HomeBrowserView.shimmerCap`, the window on
    /// screen); false keeps a waiting card still. True for a card on its own.
    var mayShimmer = true {
        didSet { if mayShimmer != oldValue { waitingChanged() } }
    }
    /// The time this wait may still shimmer; once spent the card keeps still.
    private let shimmerBudget = MotionBudget(limit: FolderCard.defaultShimmerLimit)
    /// The board's lines: 10 pt high, radius 4, 70 % and 45 % of their room.
    static let waitingLineHeight: CGFloat = 10
    static let waitingLineRadius: CGFloat = 4
    static let waitingWidths: [CGFloat] = [0.7, 0.45]
    /// Whether to keep still (System Settings › Accessibility › Display › Reduce motion); tests set their own.
    static var reduceMotion: () -> Bool = { Chrome.Motion.reduced }

    /// The clock the recency words (`3 d ago`) count from; tests set a fixed one.
    static var now: () -> Date = { Date() }

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
    /// The card shimmers: the source may still send something (`HomeCardItem.waiting`) and something is missing —
    /// the facts, or the cover.
    var isWaiting: Bool { item.waiting && (summary == nil || image == nil) }
    /// Waiting for the facts: the lines stand in for them (and the subtitle, the progress are not shown).
    var isWaitingForFacts: Bool { isWaiting && summary == nil }

    override init(item: HomeCardItem) {
        super.init(item: item)
        shimmerBudget.onSpent = { [weak self] in self?.waitingChanged() }
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
        // Another card's item (the pool's card reused): a new wait, with its own time to shimmer.
        if item.id != self.item.id { shimmerBudget.reset() }
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
        fallbackLabel.stringValue = s == nil && !isWaitingForFacts ? item.subtitle ?? "" : ""
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
        toolTip = Self.tooltip(item, summary: s, pages: holdsPages, noun: fileNoun)
        waitingChanged()
    }

    /// The tooltip has what the card may cut: every fact with the subfolders' photos, the dates' span and the
    /// progress, when the folder was viewed (`Viewed 3 d ago`), then the item's own tooltip (the path).
    static func tooltip(_ item: HomeCardItem, summary s: CardSummary?, pages: Bool, noun: String = "photo") -> String {
        var lines: [String] = []
        if let s {
            lines.append(CardSummaryText.facts(s, pages: pages, withInside: true, noun: noun))
            lines.append([CardSummaryText.span(s), CardSummaryText.viewed(s)].compactMap { $0 }.joined(separator: " · "))
            if let visited = s.visited { lines.append("Viewed " + CardSummaryText.ago(visited, now: now())) }
        }
        lines.append(item.tooltip)
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
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
        case .offline: short ? "Not connected · facts from the catalog" : "Network volume not connected · facts from the catalog"
        case .broken: short ? "Archive is damaged" : "Archive is damaged: couldn't open it"
        }
    }

    override func imageChanged() {
        picture.layer?.contents = image
        placeholder.isHidden = image != nil || isWaiting
        waitingChanged()
    }

    // MARK: Waiting

    /// Where a waiting card's cover placeholder goes, its radius and whether only its top corners are round (a
    /// poster's); the subclasses say.
    var waitingCover: (rect: CGRect, radius: CGFloat, topOnly: Bool) { (pictureFrame, 0, false) }
    /// Where its lines go, in the card's coordinates (at most `CardSkeleton.lines.count`).
    var waitingLines: [CGRect] { [] }

    /// Puts the skeleton in or takes it out, with its shimmer, as the card waits or not: the cover placeholder while
    /// there is no cover, the lines while there are no facts.
    private func waitingChanged() {
        guard isWaiting else {
            shimmerBudget.reset()
            skeleton?.remove()
            return
        }
        let k = skeleton ?? CardSkeleton()
        skeleton = k
        if let cover = coverClip.layer, let layer { k.insert(in: layer, above: cover) }
        let moving = shimmerBudget.update(wanted: mayShimmer && !Self.reduceMotion())
        k.show(cover: image == nil, lines: isWaitingForFacts, moving: moving)
        colorSkeleton()
        needsLayout = true
    }

    private func colorSkeleton() {
        guard let k = skeleton else { return }
        let still = k.shimmer == nil
        let card = Chrome.Palette.card.self
        k.color(cover: Chrome.resolve(still ? card.waitingCoverStill : card.waitingCover, in: self),
                line: Chrome.resolve(still ? card.waitingLineStill : card.waitingLine, in: self),
                glint: Chrome.resolve(card.shimmer, in: self))
    }

    private func layoutSkeleton() {
        guard isWaiting, let k = skeleton else { return }
        k.layout(bounds: bounds, cover: waitingCover, lines: waitingLines)
    }

    override func layout() {
        super.layout()
        layoutSkeleton()
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
        colorSkeleton()
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

    /// The placeholder's symbol: a card is shown again for every scroll step, Lucide makes the image once.
    static func symbol(_ name: String) -> NSImage? { Icons.symbol(name, pointSize: 30, weight: .light) }

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

/// A waiting card's skeleton (the progress board's «Карточки в ожидании»): the cover placeholder and the lines, and
/// over them one highlight sweeping across the card — the board's `.sk::after`, a `linear-gradient(100deg, …)` moved
/// from −100 % to 100 % of the card's width, its `transform` animated by Core Animation (no timers). The highlight is
/// masked to the shapes. Main thread only.
@MainActor final class CardSkeleton {
    let layer = CALayer()
    /// The cover placeholder, in a clip as tall as the cover: a poster's is a radius taller, so that only its top
    /// corners show round (as `FolderCard.coverClip` does; `maskedCorners` is not drawn by a layer's `render(in:)`).
    let coverClip = CALayer()
    let cover = CALayer()
    /// The lines in place of the facts (two on a card or a poster, one per facts column of a row); those a card does
    /// not use are hidden.
    let lines = [CALayer(), CALayer()]
    /// The shapes again, opaque: the highlight shows only over them.
    private let mask = CALayer()
    private let maskCoverClip = CALayer()
    private let maskCover = CALayer()
    private let maskLines = [CALayer(), CALayer()]
    private(set) var shimmer: CAGradientLayer?
    /// The width the shimmer's animation was made for: a new width makes it again.
    private var shimmerWidth: CGFloat = 0
    private var showsLines = true

    init() {
        coverClip.addSublayer(cover)
        layer.addSublayer(coverClip)
        for line in lines { layer.addSublayer(line) }
        maskCoverClip.addSublayer(maskCover)
        mask.addSublayer(maskCoverClip)
        for line in maskLines { mask.addSublayer(line) }
        for clip in [coverClip, maskCoverClip] { clip.masksToBounds = true }
        layer.mask = mask
        for part in [cover, maskCover] { part.cornerCurve = .continuous }
        for part in [maskCover] + maskLines { part.backgroundColor = CGColor(gray: 0, alpha: 1) }
    }

    func insert(in card: CALayer, above cover: CALayer) {
        guard layer.superlayer == nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        card.insertSublayer(layer, above: cover)
        CATransaction.commit()
    }

    func remove() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeFromSuperlayer()
        shimmer?.removeFromSuperlayer()
        shimmer = nil
        CATransaction.commit()
    }

    /// Which parts show, and whether the highlight moves (none with Reduce Motion).
    func show(cover showsCover: Bool, lines showsLines: Bool, moving: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        coverClip.isHidden = !showsCover
        maskCoverClip.isHidden = !showsCover
        self.showsLines = showsLines
        if !moving {
            shimmer?.removeFromSuperlayer()
            shimmer = nil
        } else if shimmer == nil {
            let g = CAGradientLayer()
            g.locations = [0.3, 0.5, 0.7]
            layer.addSublayer(g)
            shimmer = g
            shimmerWidth = 0
        }
        CATransaction.commit()
    }

    func color(cover coverColor: CGColor, line: CGColor, glint: CGColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cover.backgroundColor = coverColor
        for l in lines { l.backgroundColor = line }
        let clear = glint.copy(alpha: 0) ?? CGColor(gray: 1, alpha: 0)
        shimmer?.colors = [clear, glint, clear]
        CATransaction.commit()
    }

    /// The shapes where the card says, and the highlight over the card.
    func layout(bounds: CGRect, cover place: (rect: CGRect, radius: CGFloat, topOnly: Bool), lines rects: [CGRect]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        layer.frame = bounds
        mask.frame = bounds
        for clip in [coverClip, maskCoverClip] { clip.frame = place.rect }
        for part in [cover, maskCover] {
            part.frame = CGRect(x: 0, y: 0, width: place.rect.width,
                                height: place.rect.height + (place.topOnly ? place.radius : 0))
            part.cornerRadius = place.radius
        }
        for (i, (line, maskLine)) in zip(lines, maskLines).enumerated() {
            line.isHidden = !showsLines || i >= rects.count
            maskLine.isHidden = line.isHidden
            guard !line.isHidden else { continue }
            for part in [line, maskLine] {
                part.frame = rects[i]
                part.cornerRadius = FolderCard.waitingLineRadius
            }
        }
        guard let g = shimmer, bounds.width > 0, bounds.height > 0 else { return }
        g.frame = bounds
        // The CSS gradient line at 100° (clockwise from up, y down): its direction and its length over the box.
        let angle = 100 * CGFloat.pi / 180, w = bounds.width, h = bounds.height
        let dx = sin(angle), dy = -cos(angle)
        let length = abs(w * dx) + abs(h * dy)
        let ux = dx * length / 2 / w, uy = dy * length / 2 / h
        g.startPoint = CGPoint(x: 0.5 - ux, y: 0.5 - uy)
        g.endPoint = CGPoint(x: 0.5 + ux, y: 0.5 + uy)
        // The model value is the sweep's middle (what a still picture of the card shows); the animation runs from
        // one side to the other. Made again for a new width, or when Core Animation dropped it.
        g.transform = CATransform3DIdentity
        guard g.animation(forKey: FolderCard.shimmerKey) == nil || shimmerWidth != w else { return }
        shimmerWidth = w
        let sweep = CABasicAnimation(keyPath: "transform.translation.x")
        sweep.fromValue = -w
        sweep.toValue = w
        sweep.duration = FolderCard.shimmerDuration
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        sweep.repeatCount = .infinity
        sweep.isRemovedOnCompletion = false
        g.add(sweep, forKey: FolderCard.shimmerKey)
    }
}
