import AppKit
import HomeChrome
import HomeScreenModel

/// A file in the Cards style (file-cards spec §2), on the compact card's plate: 300 × 92 pt (wider when the columns
/// share more), radius 12, a 0.5 pt edge, 8 pt padding. At the left the picture, 76 pt tall and `aspect` × 76 wide
/// (radius 8; a video's length in a chip at its bottom right); 11 pt to its right four rows spread over the height:
/// 1. the name;
/// 2. a video's stream (`1080p · HEVC · 60 fps`), a photo's camera and lens (else the format);
/// 3. a video's length and size, a photo's exposure (else its pixels);
/// 4. a video's progress track with `12:30 / 1:02:10` (else the date and the size), a photo's date taken (else
///    modified), its pixels and its size.
final class FileCard: GridCard {
    static let radius: CGFloat = 12
    static let pictureRadius: CGFloat = 8
    static let columnGap: CGFloat = 11
    /// The rows' heights: their fonts' lines (13.5 pt semibold, 11.5 pt, 11.5 pt, 11 pt).
    static let rows: [CGFloat] = [16, 14, 14, 14]

    var metrics = GridMetrics() { didSet { needsLayout = true } }
    /// The picture's width over its height (`FileStyle.aspect`).
    var aspect: CGFloat = 1 { didSet { if aspect != oldValue { needsLayout = true } } }

    private let plate = CALayer()
    private let edge = CALayer()
    private let ring = CALayer()
    private let picture = CALayer()
    private let placeholder = NSImageView()
    private let lengthChip = NSTextField(labelWithString: "")
    private let nameLabel = CardText()
    private let lines = [CardText(), CardText(), CardText()]
    private let track = CALayer()
    private let bar = CALayer()

    override init(item: HomeCardItem) {
        super.init(item: item)
        plate.cornerCurve = .continuous
        edge.borderWidth = 0.5
        edge.cornerCurve = .continuous
        ring.borderWidth = Chrome.Ring.width
        ring.cornerCurve = .continuous
        ring.isHidden = true
        picture.masksToBounds = true
        picture.cornerCurve = .continuous
        picture.contentsGravity = .resizeAspectFill
        for sub in [plate, edge, picture] { layer?.addSublayer(sub) }
        placeholder.contentTintColor = Chrome.Palette.window.tertiaryLabel
        placeholder.symbolConfiguration = .init(pointSize: 24, weight: .light)
        addSubview(placeholder)
        lengthChip.font = CardFont.text(10, .medium)
        lengthChip.textColor = Chrome.Palette.card.coverChipText
        lengthChip.alignment = .center
        lengthChip.drawsBackground = false
        lengthChip.wantsLayer = true
        lengthChip.layer?.backgroundColor = Chrome.Palette.card.coverChip.cgColor
        lengthChip.layer?.cornerRadius = 4
        addSubview(lengthChip)
        nameLabel.font = CardFont.text(13.5, .semibold)
        nameLabel.textColor = Chrome.Palette.card.label
        addSubview(nameLabel)
        for (i, line) in lines.enumerated() {
            line.font = CardFont.text(i == 2 ? 11 : 11.5)
            line.textColor = Chrome.Palette.card.secondary
            addSubview(line)
        }
        track.cornerRadius = 2
        bar.cornerRadius = 2
        layer?.addSublayer(track)
        layer?.addSublayer(bar)
        layer?.addSublayer(ring)
        show(item)
        appearanceChanged()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var pictureFrame: CGRect {
        let p = metrics.cardPadding, h = metrics.cardCover
        return CGRect(x: p, y: p, width: (h * aspect).rounded(), height: h)
    }

    override var nameFrame: CGRect { nameLabel.frame }

    /// The rows' texts (2–4) for `item`.
    var rowTexts: [String] {
        let f = item.facts
        let size = item.bytes.map(FileFactsText.size)
        let date = { (d: Date?) in d.map { Self.dateFormat.string(from: $0) } }
        func join(_ parts: [String?]) -> String { parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ") }
        if let f, f.isVideo {
            let length = f.duration.map(FileFactsText.length)
            let progressLine = item.progress != nil ? item.subtitle : nil
            return [FileFactsText.stream(f) ?? item.format ?? "", join([length, size]),
                    progressLine ?? date(item.date) ?? ""]
        }
        if let f {
            return [FileFactsText.cameraLine(f) ?? item.format ?? "", FileFactsText.exposureLine(f) ?? FileFactsText.resolution(f) ?? "",
                    join([date(f.taken ?? item.date), FileFactsText.exposureLine(f) == nil ? nil : FileFactsText.resolution(f), size])]
        }
        return [item.format ?? "", item.subtitle ?? "", join([date(item.date), size])]
    }

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    override func itemChanged() {
        nameLabel.stringValue = item.title
        for (line, text) in zip(lines, rowTexts) { line.stringValue = text }
        let length = item.facts?.duration.map(FileFactsText.length) ?? ""
        lengthChip.stringValue = length
        placeholder.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)
        needsLayout = true
    }

    override func imageChanged() {
        picture.contents = image
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
        picture.backgroundColor = Chrome.resolve(Chrome.Palette.window.fill, in: self)
        track.backgroundColor = Chrome.resolve(Chrome.Palette.card.track, in: self)
        bar.backgroundColor = Chrome.resolve(Chrome.Palette.card.accent, in: self)
        ring.borderColor = Chrome.resolve(Chrome.Palette.window.accent, in: self)
        CATransaction.commit()
    }

    /// The rows' tops, spread from 1 pt inside the padding to 1 pt inside it at the bottom, as the compact card's.
    var rowTops: [CGFloat] {
        let top = metrics.cardPadding + 1, bottom = metrics.cardHeight - metrics.cardPadding - 1
        let space = (bottom - top - Self.rows.reduce(0, +)) / CGFloat(Self.rows.count - 1)
        var y = top, tops: [CGFloat] = []
        for h in Self.rows {
            tops.append(y.rounded())
            y += h + space
        }
        return tops
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let rect = bounds
        plate.frame = rect
        plate.cornerRadius = Self.radius
        edge.frame = rect.insetBy(dx: -0.5, dy: -0.5)
        edge.cornerRadius = Self.radius + 0.5
        let outset = Chrome.Ring.gap + Chrome.Ring.width
        ring.frame = rect.insetBy(dx: -outset, dy: -outset)
        ring.cornerRadius = Self.radius + outset
        let p = pictureFrame
        picture.frame = p
        picture.cornerRadius = Self.pictureRadius
        let ps = placeholder.fittingSize
        placeholder.frame = CGRect(x: p.midX - ps.width / 2, y: p.midY - ps.height / 2, width: ps.width, height: ps.height)
        let chip = lengthChip.intrinsicContentSize
        let chipWidth = chip.width + 8, chipHeight = chip.height + 2
        lengthChip.isHidden = lengthChip.stringValue.isEmpty || chipWidth > p.width - 8
        lengthChip.frame = CGRect(x: p.maxX - 4 - chipWidth, y: p.maxY - 4 - chipHeight, width: chipWidth, height: chipHeight)
        let x = p.maxX + Self.columnGap, width = max(0, bounds.width - x - metrics.cardPadding)
        let tops = rowTops
        nameLabel.frame = CGRect(x: x, y: tops[0], width: width, height: Self.rows[0])
        for (i, line) in lines.enumerated() {
            line.isHidden = line.stringValue.isEmpty
            line.frame = CGRect(x: x, y: tops[i + 1], width: width, height: Self.rows[i + 1])
        }
        // Row 4 of a video with a position: the track, then its text at the right.
        let progress = item.facts?.isVideo == true ? item.progress : nil
        track.isHidden = progress == nil
        bar.isHidden = progress == nil
        if let progress {
            let last = lines[2], h = Self.rows[3]
            let textWidth = min(last.textWidth, width / 2)
            last.frame = CGRect(x: x + width - textWidth, y: tops[3], width: textWidth, height: h)
            let trackWidth = max(0, width - textWidth - (textWidth > 0 ? 7 : 0))
            let y = (tops[3] + (h - 4) / 2).rounded()
            track.frame = CGRect(x: x, y: y, width: trackWidth, height: 4)
            bar.frame = CGRect(x: x, y: y, width: (trackWidth * min(1, max(0, progress))).rounded(), height: 4)
        }
        CATransaction.commit()
    }
}
