import AppKit
import Filmstrip
import FilmstripModel

/// The vertical rows strip on 300 made-up items: trackpad swipes browse through `FilmstripScroll` (the vertical
/// delta along the strip), a click centres a row, the browsed row shows a card.
@MainActor final class FilmstripRowsDemo: NSObject {
    static let count = 300
    static let aspectCycle: [Double?] = [16.0 / 9, 4.0 / 3, 9.0 / 16, nil, 2.39]

    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 700),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    let strip = FilmstripRowsView(frame: NSRect(x: 0, y: 0, width: 320, height: 700))
    let card = NSTextField(wrappingLabelWithString: "")
    var scroll = FilmstripScroll()
    var current = 0
    var restTimer: Timer?

    override init() {
        super.init()
        window.title = "Rows Demo"
        window.isReleasedWhenClosed = false
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = CGColor(gray: 0.1, alpha: 1)
        strip.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(strip)
        card.textColor = .white
        card.font = .systemFont(ofSize: 12)
        strip.card = card
        strip.onVisibleChange = { [weak self] in self?.loadVisible() }
        strip.onPress = { [weak self] item in self?.go(to: item) }
        strip.onDrag = { [weak self] dy in
            guard let self else { return }
            self.apply(self.scroll.drag(by: Double(dy), layout: self.strip.layout, current: self.current))
        }
        strip.onDragEnd = { [weak self] in self?.settle() }
        strip.onStripScroll = { [weak self] event in self?.stripScrolled(event) }
        strip.playing = 3
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: strip, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.relayout() }
        }
        relayout()
        window.center()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func relayout() {
        let aspects = (0..<Self.count).map { Self.aspectCycle[$0 % Self.aspectCycle.count] }
        let width = Double(strip.bounds.width)
        let layout = FilmstripRows(itemCount: Self.count, aspects: aspects, length: Double(strip.bounds.height), width: width,
                                   rowPicture: 96, currentPicture: width - 2 * Double(FilmstripRowsView.padding),
                                   cardHeight: 70)
        scroll.layoutChanged(keeping: current, layout: layout)
        strip.layout = layout
        place(animated: false)
    }

    func place(animated: Bool) {
        let layout = strip.layout
        guard layout.itemCount > 0 else { return }
        card.stringValue = "Item \(current + 1) of \(Self.count)\nA card the owner supplies."
        strip.show(offset: scroll.offset ?? layout.centre(of: current), current: current,
                   expansion: scroll.isMoving ? 0 : 1, animated: animated)
    }

    func go(to item: Int) {
        current = item
        scroll.settle()
        place(animated: true)
    }

    func stripScrolled(_ event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else { return }
        let outcome = scroll.event(fingerDelta: Double(event.scrollingDeltaY), crossDelta: Double(event.scrollingDeltaX),
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

    func settle() {
        restTimer?.invalidate()
        if let settled = scroll.settled(layout: strip.layout) { current = settled.item }
        scroll.settle()
        place(animated: true)
    }

    func loadVisible() {
        for item in strip.visibleItems {
            strip.setImage(FilmstripDemo.swatch(item), forItem: item)
            strip.setRow(item, title: "Video \(item + 1).mkv", detail: "1:23:45 · 4K · HEVC",
                         progress: item % 4 == 0 ? Double(item % 10) / 10 : nil)
        }
    }
}
