import AppKit
import Filmstrip
import FilmstripModel

/// The filmstrip on 10 000 made-up items: trackpad swipes move it through `FilmstripScroll`, a click on a cell
/// centres it, the label shows the item under the cursor.
@MainActor final class FilmstripDemo: NSObject, NSWindowDelegate {
    static let count = 10_000
    static let thickness = 68.0
    static let aspectCycle = [1.5, 0.67, 1.33, 0.75, 1, 1.78]

    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 140),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    let strip = FilmstripView(frame: NSRect(x: 0, y: 0, width: 900, height: 80))
    var scroll = FilmstripScroll()
    var current = 0
    var restTimer: Timer?

    override init() {
        super.init()
        window.title = "Filmstrip Demo"
        window.isReleasedWhenClosed = false
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = CGColor(gray: 0.1, alpha: 1)
        strip.frame = NSRect(x: 0, y: 0, width: 900, height: Self.thickness + 2 * FilmstripView.padding)
        strip.autoresizingMask = [.width]
        strip.acceptsMouse = true
        window.contentView?.addSubview(strip)
        strip.onResize = { [weak self] in self?.relayout() }
        strip.onVisibleChange = { [weak self] in self?.loadVisible() }
        strip.onHover = { [weak self] item in
            guard let self else { return }
            if let item { self.strip.showLabel(item: item, text: "\(item + 1) / \(Self.count)") } else { self.strip.endHover() }
        }
        strip.onPress = { [weak self] item in self?.go(to: item, animated: true) }
        strip.onDrag = { [weak self] dx in
            guard let self else { return }
            self.apply(self.scroll.drag(by: Double(dx), layout: self.strip.layout, current: self.current))
        }
        strip.onDragEnd = { [weak self] in self?.settle() }
        strip.onStripScroll = { [weak self] event in self?.stripScrolled(event) }
        relayout()
        window.center()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func relayout() {
        let aspects: [Double?] = (0..<Self.count).map { Self.aspectCycle[$0 % Self.aspectCycle.count] }
        let layout = FilmstripLayout(itemCount: Self.count, length: Double(strip.bounds.width), thickness: Self.thickness,
                                     maxAspect: 1.5, aspects: aspects)
        scroll.layoutChanged(keeping: current, layout: layout)
        strip.setLayout(layout, animated: false)
        place(animated: false)
    }

    func place(animated: Bool) {
        let layout = strip.layout
        guard layout.itemCount > 0 else { return }
        let offset = scroll.offset ?? layout.centre(of: current)
        strip.show(offset: offset, current: current, expansion: scroll.isMoving ? 0 : 1, animated: animated)
    }

    func go(to item: Int, animated: Bool) {
        current = item
        scroll.settle()
        place(animated: animated)
    }

    func stripScrolled(_ event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else { return }
        let outcome = scroll.event(fingerDelta: Double(event.scrollingDeltaX), crossDelta: Double(event.scrollingDeltaY),
                                   phase: ScrollPhase(rawValue: event.phase.rawValue),
                                   momentum: ScrollPhase(rawValue: event.momentumPhase.rawValue),
                                   layout: strip.layout, current: current, now: event.timestamp)
        apply(outcome)
        if scroll.isMoving {
            restTimer?.invalidate()
            restTimer = Timer.scheduledTimer(withTimeInterval: FilmstripScroll.restDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.rest() }
            }
        }
    }

    func rest() {
        if scroll.rested(now: ProcessInfo.processInfo.systemUptime) { settle() }
    }

    func apply(_ outcome: FilmstripScroll.Outcome) {
        if let item = outcome.item { current = item }
        place(animated: false)
        if outcome.commit { settle() }
    }

    /// The strip comes to rest on the item nearest the centre.
    func settle() {
        restTimer?.invalidate()
        if let settled = scroll.settled(layout: strip.layout) { current = settled.item }
        scroll.settle()
        place(animated: true)
    }

    /// A solid colour per visible item, by hue.
    func loadVisible() {
        for item in strip.visibleItems { strip.setImage(Self.swatch(item), forItem: item) }
    }

    static func swatch(_ item: Int) -> CGImage {
        let c = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let hue = (Double(item) * 0.618).truncatingRemainder(dividingBy: 1)
        c.setFillColor(NSColor(hue: hue, saturation: 0.55, brightness: 0.75, alpha: 1).cgColor)
        c.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return c.makeImage()!
    }
}
