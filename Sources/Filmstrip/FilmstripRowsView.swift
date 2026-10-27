import AppKit
import HomeChrome
import FilmstripModel
import QuartzCore

/// The vertical strip's surface (FrameScrub's playlist strip, spec 2026-10-27): rows of whole pictures under the
/// strip's fixed centre, each with a title and a detail line beside it, the browsed row larger with the owner's card
/// under its picture, the edges fading out where the strip goes on. Pure Core Animation for the rows: a layer per
/// visible row from a pool, pictures as `layer.contents`, text in `CATextLayer`s, so nothing is drawn on the main
/// thread and the layer count follows the window, not the list. The card is the owner's view.
///
/// What to show comes from the owner (`layout`, `show(offset:current:expansion:animated:)`, the pictures and texts by
/// item); this view reports a click on a row (`onPress`), a drag along the rows (`onDrag` / `onDragEnd`) and every
/// scroll event (`onStripScroll`): none goes on to the views under it.
@MainActor public final class FilmstripRowsView: NSView {
    /// Between the strip's sides and the rows.
    public static let padding: CGFloat = 8
    /// Between a row's picture and its text.
    public static let textGap: CGFloat = 10
    /// Between the browsed picture and the card under it.
    public static let cardGap: CGFloat = 6
    /// A press that moves less than this is a click.
    private static let clickSlop: CGFloat = 3
    /// The settling, a click's move and a step to a neighbour.
    private static let moveDuration: CFTimeInterval = 0.2
    private static let placeholderBorder = CGColor(gray: 1, alpha: 0.38)
    private static let barHeight: CGFloat = 3

    private final class Row {
        let layer = CALayer()
        let picture = CALayer()
        let track = CALayer()
        let bar = CALayer()
        let title = CATextLayer()
        let detail = CATextLayer()
    }

    private struct Text: Equatable {
        var title: String
        var detail: String
        var progress: Double?
    }

    public var layout = FilmstripRows(itemCount: 0, aspects: [], length: 0, width: 0, rowPicture: 96,
                                      currentPicture: 280, cardHeight: 0) {
        didSet { if layout != oldValue { placeRows(animated: false) } }
    }
    /// The playing item: an accent edge on its picture and "▶" before its title.
    public var playing: Int? {
        didSet {
            guard playing != oldValue else { return }
            for item in [oldValue, playing].compactMap({ $0 }) { if let row = rows[item] { withoutAnimation { fill(row, item: item) } } }
        }
    }
    /// The owner's card for the browsed row, placed under its picture as wide as it; faded in with the expansion.
    public var card: NSView? {
        didSet {
            guard card !== oldValue else { return }
            oldValue?.removeFromSuperview()
            if let card {
                card.wantsLayer = true
                addSubview(card)
            }
            cardItem = nil
            placeCard()
        }
    }
    public var onPress: ((Int) -> Void)?
    /// The pointer dragged the rows by this many points down (negative: up).
    public var onDrag: ((CGFloat) -> Void)?
    public var onDragEnd: (() -> Void)?
    public var onStripScroll: ((NSEvent) -> Void)?
    /// `visibleItems` changed.
    public var onVisibleChange: (() -> Void)?
    /// The items on screen, from the browsed one outwards.
    public private(set) var visibleItems: [Int] = []

    /// The rows, under the fade.
    let contentLayer = CALayer()
    private let fade = FilmstripFade(axis: .vertical)
    private var pictures: [Int: CGImage] = [:]
    private var texts: [Int: Text] = [:]
    private var rows: [Int: Row] = [:]
    private var pool: [Row] = []
    private var offset = 0.0, current = 0, expansion = 1.0
    private var shownRows: [FilmstripRow] = []
    /// The item the card was last placed under.
    private var cardItem: Int?
    /// A press on the rows: the y of the last event (view coordinates), the item under it, whether it became a drag.
    private var press: (startY: CGFloat, lastY: CGFloat, item: Int?, dragging: Bool)?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        fade.layer.addSublayer(contentLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    public override func makeBackingLayer() -> CALayer {
        let layer = CALayer()
        layer.addSublayer(fade.layer)
        return layer
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        placeRows(animated: false)
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for row in Array(rows.values) + pool { row.title.contentsScale = scale; row.detail.contentsScale = scale }
    }

    // MARK: Showing

    /// Base position `offset` under the strip's centre, `current` grown by `expansion` (0 plain … 1 its larger picture
    /// and the card). `animated`: the rows move there in `moveDuration`, ease-out (the settling, a click, a step);
    /// otherwise at once (a gesture).
    public func show(offset: Double, current: Int, expansion: Double, animated: Bool) {
        guard offset != self.offset || current != self.current || expansion != self.expansion else { return }
        self.offset = offset
        self.current = current
        self.expansion = expansion
        placeRows(animated: animated)
    }

    private func placeRows(animated: Bool) {
        let shown = layout.rows(offset: offset, current: current, expansion: expansion)
        shownRows = shown
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(Self.moveDuration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        withoutAnimation {
            fade.layer.frame = bounds
            contentLayer.frame = bounds
        }
        let onScreen = Set(shown.map(\.item))
        for item in rows.keys where !onScreen.contains(item) { recycle(item) }
        for row in shown { place(row) }
        let fades = layout.fades(rows: shown, current: current)
        fade.place(bounds: bounds, start: fades.start, end: fades.end)
        CATransaction.commit()
        placeCard(animated: animated)
        let order = shown.map(\.item).sorted { abs($0 - current) < abs($1 - current) }
        if order != visibleItems {
            visibleItems = order
            onVisibleChange?()
        }
    }

    private func place(_ shown: FilmstripRow) {
        let isNew = rows[shown.item] == nil
        let row = rows[shown.item] ?? takeRow(for: shown.item)
        let frame = CGRect(x: Self.padding, y: shown.start, width: max(0, bounds.width - 2 * Self.padding),
                           height: shown.length)
        let place = {
            row.layer.frame = frame
            row.picture.frame = shown.picture
            row.track.frame = CGRect(x: 0, y: shown.picture.height - Self.barHeight, width: shown.picture.width,
                                     height: Self.barHeight)
            let progress = self.texts[shown.item]?.progress ?? 0
            row.bar.frame = CGRect(x: 0, y: 0, width: shown.picture.width * progress, height: Self.barHeight)
            // Beside a plain picture, centred on it; the browsed row's text is in its card.
            let x = shown.picture.maxX + Self.textGap, width = max(0, frame.width - x)
            let middle = shown.picture.midY
            row.title.frame = CGRect(x: x, y: middle - 16, width: width, height: 16)
            row.detail.frame = CGRect(x: x, y: middle + 1, width: width, height: 14)
            let textOpacity: Float = shown.item == self.current ? Float(1 - self.expansion) : 1
            row.title.opacity = textOpacity
            row.detail.opacity = textOpacity
        }
        // A row that comes on screen starts where it belongs; only rows already there move.
        if isNew { withoutAnimation(place) } else { place() }
    }

    /// The card follows the browsed row with the rows' own motion: moved with it while it stays the same row; when
    /// another row becomes the browsed one, shown at its new place from clear, fading in over the move, so its text
    /// never sits still while the pictures move under it.
    private func placeCard(animated: Bool = false) {
        guard let card else { return }
        guard let row = shownRows.first(where: { $0.item == current }) else {
            card.isHidden = true
            cardItem = nil
            return
        }
        let y = row.start + row.picture.height + Self.cardGap
        let frame = NSRect(x: Self.padding, y: y, width: row.picture.width, height: max(0, row.start + row.length - y))
        let alpha = CGFloat(expansion)
        let moved = cardItem != current
        cardItem = current
        card.isHidden = expansion <= 0
        let from = card.layer?.presentation() ?? card.layer
        let oldPosition = from?.position, oldOpacity = from?.opacity ?? 0
        card.frame = frame
        card.alphaValue = alpha
        guard animated, let layer = card.layer else { return }
        func animate(_ key: String, from value: Any?) {
            let animation = CABasicAnimation(keyPath: key)
            animation.fromValue = value
            animation.duration = Self.moveDuration
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: key)
        }
        if moved {
            animate("opacity", from: 0)
        } else {
            if let oldPosition, oldPosition != layer.position { animate("position", from: NSValue(point: oldPosition)) }
            if oldOpacity != layer.opacity { animate("opacity", from: oldOpacity) }
        }
    }

    private func takeRow(for item: Int) -> Row {
        let row = pool.popLast() ?? makeRow()
        rows[item] = row
        contentLayer.addSublayer(row.layer)
        withoutAnimation { fill(row, item: item) }
        return row
    }

    private func recycle(_ item: Int) {
        guard let row = rows.removeValue(forKey: item) else { return }
        row.layer.removeFromSuperlayer()
        pool.append(row)
    }

    private func makeRow() -> Row {
        let row = Row()
        let scale = window?.backingScaleFactor ?? 2
        row.picture.cornerRadius = Chrome.Radius.cell
        row.picture.masksToBounds = true
        row.picture.contentsGravity = .resizeAspectFill
        row.picture.borderColor = Self.placeholderBorder
        row.track.backgroundColor = CGColor(gray: 0, alpha: 0.55)
        row.bar.backgroundColor = Chrome.Palette.window.accent.cgColor
        row.track.addSublayer(row.bar)
        row.picture.addSublayer(row.track)
        for (text, style, color) in [(row.title, Chrome.Text.Style.label, Chrome.Palette.overMedia.text),
                                     (row.detail, .small, Chrome.Palette.overMedia.secondaryText)] {
            let font = Chrome.Text.font(style)
            text.font = font
            text.fontSize = style == .label ? 12 : 10
            text.foregroundColor = color.cgColor
            text.truncationMode = text === row.title ? .middle : .end
            text.isWrapped = false
            text.contentsScale = scale
            row.layer.addSublayer(text)
        }
        row.layer.addSublayer(row.picture)
        return row
    }

    /// The row's look for what the item has: its picture or the empty frame, the position bar, the playing edge, text.
    private func fill(_ row: Row, item: Int) {
        let image = pictures[item]
        row.picture.contents = image
        let isPlaying = item == playing
        row.picture.borderWidth = isPlaying ? 2 : image == nil ? 1 : 0
        row.picture.borderColor = isPlaying ? Chrome.Palette.window.accent.cgColor : Self.placeholderBorder
        let text = texts[item]
        row.title.string = (isPlaying ? "▶ " : "") + (text?.title ?? "")
        row.detail.string = text?.detail ?? ""
        row.track.isHidden = text?.progress == nil
        if let progress = text?.progress {
            row.bar.frame.size.width = row.picture.bounds.width * progress
        }
    }

    // MARK: Content

    public func setRow(_ item: Int, title: String, detail: String, progress: Double?) {
        let text = Text(title: title, detail: detail, progress: progress)
        guard texts[item] != text else { return }
        texts[item] = text
        if let row = rows[item] { withoutAnimation { fill(row, item: item) } }
    }

    /// The item's picture; nil puts the empty frame back.
    public func setImage(_ image: CGImage?, forItem item: Int) {
        pictures[item] = image
        if let row = rows[item] { withoutAnimation { fill(row, item: item) } }
    }

    /// Drops what is known of an item (it left the list).
    public func forget(_ item: Int) {
        pictures[item] = nil
        texts[item] = nil
        recycle(item)
    }

    public func forgetAll() {
        pictures = [:]
        texts = [:]
        for item in Array(rows.keys) { recycle(item) }
    }

    /// The list changed: what is known moves to the items' new indices (`FilmstripItems.indexMap`); the rest is dropped.
    public func remap(_ map: [Int: Int]) {
        // Two old items may land on one new one (the same file twice in a list): either's is as good.
        pictures = Dictionary(pictures.compactMap { key, value in map[key].map { ($0, value) } }, uniquingKeysWith: { a, _ in a })
        texts = Dictionary(texts.compactMap { key, value in map[key].map { ($0, value) } }, uniquingKeysWith: { a, _ in a })
        for item in Array(rows.keys) { recycle(item) }
        placeRows(animated: false)
    }

    // MARK: Input

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func item(at y: CGFloat) -> Int? {
        shownRows.first { Double(y) >= $0.start && Double(y) < $0.start + $0.length }?.item
    }

    public override func mouseDown(with event: NSEvent) {
        let y = convert(event.locationInWindow, from: nil).y
        press = (y, y, item(at: y), false)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard var press else { return }
        let y = convert(event.locationInWindow, from: nil).y
        if !press.dragging, abs(y - press.startY) >= Self.clickSlop { press.dragging = true }
        if press.dragging { onDrag?(y - press.lastY) }
        press.lastY = y
        self.press = press
    }

    public override func mouseUp(with event: NSEvent) {
        guard let press else { return }
        self.press = nil
        if press.dragging {
            onDragEnd?()
        } else if let item = press.item {
            onPress?(item)
        }
    }

    public override func scrollWheel(with event: NSEvent) {
        onStripScroll?(event)
    }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
