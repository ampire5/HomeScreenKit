import AppKit
import SlotModel
import SlotChrome

/// Window-independent edge panels. Content and persistence belong to the host app.
@MainActor public final class SlotsController {
    public var onLayout: ((CGRect, CGRect) -> Void)?
    public var onPersist: ((SlotEdge, SlotConfiguration) -> Void)?
    public var onMessage: ((String) -> Void)?
    public var onChanged: (() -> Void)?
    public var onFocusContent: (() -> Void)?
    public var topInset: CGFloat = 0 { didSet { if topInset != oldValue { refreshLayout() } } }
    public var revealBand: CGFloat = EdgeReveal.sideBand
    private var started = false
    private var descriptors: [SlotTabID: SlotTabDescriptor] = [:]
    private var descriptorOrder: [SlotTabID] = []
    @MainActor private final class Slot {
        let edge: SlotEdge
        let view: SlotView
        let tongue: SlotTongueView
        var setting: SlotConfiguration
        var tabs: [SlotTabID] = []
        var shownTab: SlotTabID?
        var pages: [SlotTabID: SlotPage] = [:]
        var transient: Set<SlotTabID> = []
        var reveal = EdgeReveal()
        var clock = AutoHideClock(mode: .mouseLeaves)
        var capsuleClock = CapsuleClock()
        var capsuleCheck: DispatchWorkItem?
        var flash: DispatchWorkItem?
        var flashEndedInMenu = false
        var shownOrder = 0
        var demoted = false
        init(edge: SlotEdge) {
            self.edge = edge
            view = SlotView(edge: edge); tongue = SlotTongueView(edge: edge)
            setting = SlotConfiguration(size: edge == .bottom ? 240 : 400)
        }
        var page: SlotPage? { shownTab.flatMap { pages[$0] } }
        func sync() {
            guard let shownTab, let i = tabs.firstIndex(of: shownTab) else { setting.tabs = tabs; return }
            setting.tabs = Array(tabs[i...] + tabs[..<i])
        }
    }
    private let container: NSView
    private let above: NSView
    private var slots: [SlotEdge: Slot] = [:]
    private var showCounter = 0
    private var lastVideo: CGRect?
    private var lastVisible: CGRect?
    private var autoHideTimer: Timer?
    private var monitor: Any?
    private var globalMonitor: Any?
    private var menuOpen = false {
        didSet {
            guard menuOpen != oldValue else { return }
            if menuOpen { return }
            // As Zen after a popup: with the pointer outside, the slot waits for it to come back.
            for slot in orderedSlots where slot.view.isShown {
                slot.clock.menuClosed(pointerInside: isPointer(in: slot), now: Self.now)
                updateCapsule(slot)
                if slot.flashEndedInMenu { endFlash(slot) }
            }
            if resignedDuringMenu { resignedDuringMenu = false; hideOnResign() }
            updateAutoHideTimer()
        }
    }
    /// The window or app lost focus while a menu was open: the slots go once it closes.
    private var resignedDuringMenu = false
    /// The window is being dragged (from its title bar): a leave then is not one (Zen re-checks for the same reason).
    private var windowMoving = false
    private var observers: [NSObjectProtocol] = []
    /// The OSD said the window is too small for these pinned slots; said again only when the set changes.
    private var reportedDemotions: Set<SlotEdge> = []

    public init(container: NSView, above: NSView) {
        self.container = container; self.above = above
        for edge in SlotEdge.allCases {
            let slot = Slot(edge: edge); slots[edge] = slot
            container.addSubview(slot.view, positioned: .above, relativeTo: above)
            wire(slot)
        }
    }
    public func register(_ descriptor: SlotTabDescriptor) {
        if descriptors[descriptor.id] == nil { descriptorOrder.append(descriptor.id) }
        descriptors[descriptor.id] = descriptor
    }
    public func configure(_ configuration: SlotConfiguration, edge: SlotEdge) {
        guard let slot = slots[edge] else { return }
        let wanted = SlotTabState(tabs: configuration.tabs).tabs
        for id in slot.tabs where !wanted.contains(id) { removeTab(id, from: slot, dropPage: true, notify: false) }
        slot.setting = configuration.clamped(for: edge)
        slot.tabs = wanted; slot.shownTab = wanted.first
        slot.clock = AutoHideClock(mode: configuration.autoHide)
        if started { if configuration.shown { show(slot, focus: false) } else { hide(slot) } }
    }
    public func configuration(_ edge: SlotEdge) -> SlotConfiguration {
        guard let slot = slots[edge] else { return SlotConfiguration() }
        slot.sync(); return slot.setting
    }
    public func activeTab(_ edge: SlotEdge) -> SlotTabID? { slots[edge]?.shownTab }
    public func isShown(_ edge: SlotEdge) -> Bool { slots[edge]?.view.isShown ?? false }
    public func page(_ id: SlotTabID, edge: SlotEdge) -> SlotPage? { slots[edge]?.pages[id] }
    public func capsule(_ edge: SlotEdge) -> SlotCapsuleView? { slots[edge]?.view.capsule }
    public func effectiveMode(_ edge: SlotEdge) -> SlotMode { slots[edge].map(effectiveMode) ?? .overlay }
    public func refreshLayout() { containerDidLayout() }
    public func refreshContents() { for slot in orderedSlots { refresh(slot) } }
    public func select(_ id: SlotTabID, edge: SlotEdge) { if let slot = slots[edge] { select(id, in: slot) } }
    public func add(_ id: SlotTabID, edge: SlotEdge, transient: Bool = false) {
        guard let slot = slots[edge] else { return }
        if transient { slot.transient.insert(id) }
        addTab(id, to: slot)
    }
    public func remove(_ id: SlotTabID, edge: SlotEdge) {
        if let slot = slots[edge] { removeTab(id, from: slot, dropPage: true) }
    }
    public func move(_ id: SlotTabID, from: SlotEdge, to: SlotEdge) {
        guard let slot = slots[from], let target = slots[to], slot !== target else { return }
        moveTab(id, from: slot, to: target)
    }
    public func show(_ edge: SlotEdge, focus: Bool = false) { if let slot = slots[edge] { show(slot, focus: focus) } }
    public func hide(_ edge: SlotEdge) { if let slot = slots[edge] { hide(slot) } }
    public func choice(in edge: SlotEdge) { if let slot = slots[edge] { hideAfterChoice(slot) } }
    public func cancelInteraction() {
        for slot in orderedSlots { slot.page?.cancelInteraction(); slot.flash?.cancel(); slot.flash = nil }
        _ = hideOverlays()
    }
    public var livePages: [(SlotEdge, SlotTabID, SlotPage)] {
        orderedSlots.flatMap { slot in slot.tabs.compactMap { id in slot.pages[id].map { (slot.edge, id, $0) } } }
    }
    public func start() {
        guard !started else { return }; started = true
        // Hidden tabs are made only when their slot is first shown.
        for slot in orderedSlots {
            container.addSubview(slot.tongue)   // above everything: the tongue must take its click
            slot.tongue.onClick = { [weak self, weak slot] in
                guard let self, let slot, !slot.view.isShown else { return }
                hideTongue(slot)
                show(slot, focus: false)
            }
        }
        for slot in orderedSlots where slot.setting.shown {
            if slot.setting.mode == .pinned && !slot.tabs.isEmpty {
                refresh(slot)
                showCounter += 1
                slot.shownOrder = showCounter
                slot.view.setShown(true, animated: false)
                updatePagesShown(slot)
                updateCapsule(slot, animated: false)
            } else {
                slot.setting.shown = false
            }
        }
        applyLayout(revealing: nil, animated: false)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown,
                                                              .leftMouseUp, .rightMouseDown, .rightMouseUp,
                                                              .otherMouseDown, .otherMouseUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.pointerEvent(event) }
            return event
        }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let window = note.object as? NSWindow, window === self.container.window else { return }
                    self.resigned()
                }
            },
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resigned() }
            },
            center.addObserver(forName: NSWindow.willMoveNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let window = note.object as? NSWindow, window === self.container.window else { return }
                    self.windowMoving = true
                }
            },
        ]
        // While the app is in the background it gets no pointer events of its own; the player window may still be in sight.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated { self?.backgroundPointerEvent() }
        }
    }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        autoHideTimer?.invalidate()
    }

    private var orderedSlots: [Slot] { SlotEdge.allCases.compactMap { slots[$0] } }

    public var isPointerOverShownSlot: Bool {
        guard let window = container.window else { return false }
        let point = container.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return orderedSlots.contains { $0.view.isShown && $0.view.frame.contains(point) }
    }

    public func toggle(_ edge: SlotEdge) {
        guard let slot = slots[edge] else { return }
        if slot.view.isShown { hide(slot) } else { show(slot, focus: true) }
    }

    @discardableResult
    public func hideOverlays() -> Bool {
        let shown = orderedSlots.filter { $0.view.isShown && effectiveMode($0) == .overlay }
        for slot in shown { hide(slot) }
        return !shown.isEmpty
    }

    public func escape(in view: NSView) -> Bool {
        guard let slot = orderedSlots.first(where: { $0.view.holds(view) }), slot.view.isShown,
              effectiveMode(slot) == .overlay else { return false }
        hide(slot)
        return true
    }

    private func hideAfterChoice(_ slot: Slot) {
        guard slot.view.isShown, effectiveMode(slot) == .overlay, slot.clock.hidesOnChoice else { return }
        hide(slot)
    }

    private var firstEmptySlot: Slot? {
        [SlotEdge.right, .left, .bottom].compactMap { slots[$0] }.first { $0.tabs.isEmpty }
    }

    private func show(_ slot: Slot, focus: Bool) {
        refresh(slot)
        slot.flash?.cancel()   // an explicit show is the user's: a flash under way no longer hides it
        slot.flash = nil
        slot.flashEndedInMenu = false
        if !slot.view.isShown {
            showCounter += 1
            slot.shownOrder = showCounter
            slot.setting.shown = true
            hideTongue(slot)
            slot.reveal.reset()
            applyLayout(revealing: slot)
            updatePagesShown(slot)   // after the layout set the slot shown (before it, every page read as hidden)
            let inside = isPointer(in: slot)
            slot.clock.shown(pointerInside: inside, now: Self.now)
            slot.capsuleClock = CapsuleClock()
            if inside { slot.capsuleClock.pointerInside(true, now: Self.now) } else { slot.capsuleClock.shownByKey() }
            updateCapsule(slot, animated: false)
            persist(slot)
            onChanged?()
            updateAutoHideTimer()
        }
        if slot.tabs.isEmpty {
            DispatchQueue.main.async { [weak self, weak slot] in
                guard let self, let slot, slot.view.isShown else { return }
                popUp(plusMenu(for: slot), from: nil, in: slot)
            }
        } else if focus {
            slot.page?.focus()
        }
    }

    private func hide(_ slot: Slot) {
        guard slot.view.isShown else { return }
        let hadFocus = holdsFocus(slot)
        slot.page?.cancelInteraction()
        slot.view.capsule.closeFilter()
        slot.setting.shown = false
        slot.view.setShown(false, animated: true) { [weak self] in self?.onChanged?() }
        updatePagesShown(slot)
        slot.flash?.cancel()
        slot.flash = nil
        slot.flashEndedInMenu = false
        applyLayout(revealing: nil)
        persist(slot)
        if hadFocus { onFocusContent?() }
        onChanged?()
        updateAutoHideTimer()
    }

    // MARK: Layout

    /// The container's size changed.
    public func containerDidLayout() {
        applyLayout(revealing: nil, animated: false)
    }

    /// Lays out the shown slots; `revealing` is the slot that has just been shown and slides in. A pinned slot changes
    /// the video once, when its slide ends; an overlay slot never does.
    private func applyLayout(revealing: Slot?, animated: Bool = true) {
        guard container.bounds.width >= 1, container.bounds.height >= 1 else {   // not laid out yet
            revealing?.view.setShown(true, animated: false)
            return
        }
        let shown = orderedSlots.filter { $0.view.isShown || $0 === revealing }
        var sizes: [SlotEdge: (mode: SlotMode, size: CGFloat)] = [:]
        for slot in shown { sizes[slot.edge] = (slot.setting.mode, CGFloat(slot.setting.size)) }
        let layout = SlotLayout.compute(.init(container: container.bounds, slots: sizes,
                                              order: shown.sorted { $0.shownOrder < $1.shownOrder }.map(\.edge),
                                              topInset: topInset))
        var modesChanged = false
        for slot in shown {
            guard let rect = layout.slots[slot.edge] else { continue }
            if slot.view.frame != rect { slot.view.frame = rect }
            let mode = layout.effectiveMode[slot.edge] ?? slot.setting.mode
            if slot.view.mode != mode { slot.view.mode = mode; modesChanged = true }
            slot.view.backdrop = slot.setting.backdrop
            slot.demoted = layout.demoted.contains(slot.edge)
        }
        let demoted = Set(layout.demoted)
        if !demoted.isEmpty, !demoted.isSubset(of: reportedDemotions) {
            onMessage?("Not enough room beside the video: the slot lies over it")
        }
        reportedDemotions = demoted
        var visible = layout.video
        for (edge, rect) in layout.slots where layout.effectiveMode[edge] == .overlay {
            switch edge {
            case .left: visible.size.width -= rect.maxX - visible.minX; visible.origin.x = rect.maxX
            case .right: visible.size.width = rect.minX - visible.minX
            case .bottom: visible.size.height -= rect.maxY - visible.minY; visible.origin.y = rect.maxY
            }
        }
        let report = { [weak self] in
            guard let self, layout.video != lastVideo || visible != lastVisible else { return }
            lastVideo = layout.video
            lastVisible = visible
            onLayout?(layout.video, visible)
        }
        if let revealing, animated {
            let pinned = layout.effectiveMode[revealing.edge] == .pinned
            if !pinned { report() }   // the visible part shrinks at once; the video stays as it is
            revealing.view.setShown(true, animated: true) { if pinned { report() } }
        } else {
            revealing?.view.setShown(true, animated: false)
            report()
        }
        if modesChanged {
            for slot in shown where slot.view.isShown { updateCapsule(slot, animated: false) }   // pinned: always shown
            onChanged?()
        }
    }

    private func effectiveMode(_ slot: Slot) -> SlotMode { slot.demoted ? .overlay : slot.setting.mode }

    // MARK: Contents


    private func holdsFocus(_ slot: Slot) -> Bool { slot.view.holds(container.window?.firstResponder as? NSView) }
    private static func tabID(_ content: SlotTabID) -> String { content.rawValue }
    private func content(ofTab id: String, in slot: Slot) -> SlotTabID? { slot.tabs.first { $0.rawValue == id } }
    private func select(_ content: SlotTabID, in slot: Slot) {
        guard slot.tabs.contains(content), slot.shownTab != content else { return }
        let hadFocus = holdsFocus(slot)
        slot.view.capsule.closeFilter()
        slot.page?.cancelInteraction()
        slot.shownTab = content
        changed(slot, hadFocus: hadFocus)
    }

    /// Adds `content` as a tab of `slot` (or finds it there) and shows it. The playlist leaves the slot that had it.
    private func addTab(_ content: SlotTabID, to slot: Slot) {
        if descriptors[content]?.singleton == true {
            for other in orderedSlots where other !== slot && other.tabs.contains(content) {
                moveTab(content, from: other, to: slot)
                return
            }
        }
        let hadFocus = holdsFocus(slot)
        if !slot.tabs.contains(content) { slot.tabs.append(content) }
        slot.view.capsule.closeFilter()
        slot.page?.cancelInteraction()
        slot.shownTab = content
        changed(slot, hadFocus: hadFocus)
    }

    /// Closes a tab; the next one (or the one before the last) shows. Its page goes, unless it is being moved.
    private func removeTab(_ content: SlotTabID, from slot: Slot, dropPage: Bool, notify: Bool = true) {
        guard let i = slot.tabs.firstIndex(of: content) else { return }
        let hadFocus = holdsFocus(slot)
        slot.view.capsule.closeFilter()
        slot.tabs.remove(at: i)
        slot.transient.remove(content)
        if slot.shownTab == content { slot.shownTab = slot.tabs.isEmpty ? nil : slot.tabs[min(i, slot.tabs.count - 1)] }
        if dropPage, let page = slot.pages.removeValue(forKey: content) {
            page.visibilityChanged(false); page.cancelInteraction(); page.dropped()
        }
        if notify { changed(slot, hadFocus: hadFocus) }
    }

    /// Every tab closed (View › Slots › Clear Slot): the slot is saved once, not once per tab.
    private func clear(_ slot: Slot) {
        guard !slot.tabs.isEmpty else { return }
        let hadFocus = holdsFocus(slot)
        for tab in slot.tabs { removeTab(tab, from: slot, dropPage: true, notify: false) }
        changed(slot, hadFocus: hadFocus)
    }

    /// Moves a tab, with its live page, to `target`, where it shows.
    private func moveTab(_ content: SlotTabID, from slot: Slot, to target: Slot) {
        let hadFocus = holdsFocus(slot) || holdsFocus(target)
        if let page = slot.pages.removeValue(forKey: content) {
            page.visibilityChanged(false); page.cancelInteraction()
            if target.pages[content] != nil { page.dropped() } else { target.pages[content] = page }
        }
        let transient = slot.transient.contains(content)
        removeTab(content, from: slot, dropPage: false)
        if transient { target.transient.insert(content) }
        addTab(content, to: target)
        if slot.tabs.isEmpty, slot.view.isShown { hide(slot) }
        // Taking the view out of the window took the keyboard from it: the moved one gets it back.
        if hadFocus { onFocusContent?() }
        show(target, focus: hadFocus)
    }


    private func changed(_ slot: Slot, hadFocus: Bool) {
        slot.sync(); refresh(slot); persist(slot)
        if hadFocus && !holdsFocus(slot) { onFocusContent?() }
        onChanged?()
    }
    private func refresh(_ slot: Slot) {
        slot.view.note = nil
        // Do not instantiate content while its slot is hidden.
        if let id = slot.shownTab, slot.pages[id] == nil, let descriptor = descriptors[id] {
            slot.pages[id] = descriptor.makePage(slot.edge)
        }
        let views = Dictionary(uniqueKeysWithValues: slot.pages.map { ($0.key.rawValue, $0.value.view) })
        slot.view.setViews(views, shown: slot.shownTab?.rawValue)
        slot.view.capsule.tabs = slot.tabs.map { id in
            let d = descriptors[id]
            return SlotTab(id: id.rawValue, symbol: d?.symbol, letter: d?.symbol == nil ? String((d?.title ?? id.rawValue).prefix(1)) : nil,
                           name: d?.title ?? id.rawValue, selected: id == slot.shownTab)
        }
        if let id = slot.shownTab, slot.pages[id] == nil { slot.view.note = "Unavailable: " + (descriptors[id]?.title ?? id.rawValue) }
        slot.view.contentDrawsTextShadow = slot.page?.drawsOwnTextShadow ?? false
        slot.view.capsule.tools = slot.page?.tools() ?? []
        updatePagesShown(slot)
    }
    private func updatePagesShown(_ slot: Slot) {
        for (id, page) in slot.pages { page.visibilityChanged(slot.view.isShown && slot.shownTab == id) }
    }
    private func wire(_ slot: Slot) {
        let view = slot.view
        view.onPlus = { [weak self, weak slot] button in
            guard let self, let slot else { return }
            popUp(plusMenu(for: slot), from: button, in: slot)
        }
        view.capsule.onCapsuleMenu = { [weak self, weak slot] in
            guard let self, let slot else { return nil }
            return capsuleMenu(for: slot)
        }
        view.capsule.onTabMenu = { [weak self, weak slot] id in
            guard let self, let slot, let content = content(ofTab: id, in: slot) else { return nil }
            return tabMenu(for: slot, content: content)
        }
        view.capsule.onSelectTab = { [weak self, weak slot] id in
            guard let self, let slot, let content = content(ofTab: id, in: slot) else { return }
            select(content, in: slot)
        }
        view.capsule.onPlus = { [weak self, weak slot] button in
            guard let self, let slot else { return }
            popUp(plusMenu(for: slot), from: button, in: slot)
        }
        view.capsule.onPin = { [weak self, weak slot] in
            guard let self, let slot else { return }
            togglePin(slot)
        }
        view.capsule.onBackdrop = { [weak self, weak slot] in
            guard let self, let slot else { return }
            cycleBackdrop(slot)
        }
        view.capsule.onMenuTracking = { [weak self] open in self?.menuOpen = open }
        view.capsule.onFilterText = { [weak slot] text in slot?.page?.filterEdited(text) }
        view.capsule.onFilterCommand = { [weak slot] selector in slot?.page?.filterCommand(selector) ?? false }
        view.capsule.onFilterClosed = { [weak self, weak slot] in
            guard let self, let slot else { return }; slot.page?.filterClosed(); updateCapsule(slot)
        }
        view.capsule.onFilterEnd = { [weak self, weak slot] in
            guard let self, let slot else { return }; slot.page?.filterEnded(); updateCapsule(slot)
        }
        view.onPointerInside = { [weak self, weak slot] inside in
            guard let self, let slot else { return }
            slot.capsuleClock.pointerInside(inside, now: Self.now)
            if inside { slot.flash?.cancel(); slot.flash = nil }   // the pointer came for it: the usual rules now
            updateCapsule(slot)
            updateAutoHideTimer()
        }
        view.capsule.onHide = { [weak self, weak slot] in
            guard let self, let slot else { return }
            hide(slot)
        }
        view.onResize = { [weak self, weak slot] size in
            guard let self, let slot else { return }
            let range = slot.edge.sizeRange
            let clamped = min(max(Int(size.rounded()), range.lowerBound), range.upperBound)
            guard clamped != slot.setting.size else { return }
            slot.setting.size = clamped
            applyLayout(revealing: nil, animated: false)
        }
        view.onResizeEnd = { [weak self, weak slot] in
            guard let self, let slot else { return }
            persist(slot)
        }
    }

    /// The slot that menu commands (View › Slots) act on: the one with the keyboard, else the newest shown one.
    private var currentSlot: Slot? {
        let responder = container.window?.firstResponder as? NSView
        return orderedSlots.first { $0.view.isShown && $0.view.holds(responder) }
            ?? orderedSlots.filter(\.view.isShown).max { $0.shownOrder < $1.shownOrder }
    }

    /// View › Slots › Pin / Float.
    public func togglePinOfCurrent() { currentSlot.map(togglePin) }
    /// View › Slots › Next Backdrop.
    public func cycleBackdropOfCurrent() { currentSlot.map(cycleBackdrop) }
    /// View › Slots › Clear Slot.
    public func clearCurrent() {
        guard let slot = currentSlot else { return }
        clear(slot)
    }

    private func togglePin(_ slot: Slot) {
        slot.setting.mode = slot.setting.mode == .pinned ? .overlay : .pinned
        persist(slot)
        applyLayout(revealing: nil, animated: false)
        updateCapsule(slot)
        updateAutoHideTimer()
        onChanged?()
    }

    private func cycleBackdrop(_ slot: Slot) {
        if effectiveMode(slot) == .pinned {
            onMessage?("A pinned slot is always dark")
            return
        }
        slot.setting.backdrop = slot.setting.backdrop.next
        slot.view.backdrop = slot.setting.backdrop
        persist(slot)
        onMessage?("Backdrop: \(Self.title(of: slot.setting.backdrop))")
        onChanged?()
    }

    private static func title(of backdrop: SlotBackdrop) -> String {
        switch backdrop {
        case .dark: "Dark"
        case .glass: "Glass"
        case .clear: "Clear glass"
        }
    }

    private static func title(of edge: SlotEdge) -> String {
        switch edge {
        case .left: "Left"
        case .right: "Right"
        case .bottom: "Bottom"
        }
    }

    private func plusMenu(for slot: Slot) -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        for id in descriptorOrder {
            guard let descriptor = descriptors[id] else { continue }
            let item = menu.addItem(withTitle: descriptor.title, action: nil, keyEquivalent: "")
            item.state = slot.tabs.contains(id) ? .on : .off
            item.handler = { [weak self, weak slot] in
                guard let self, let slot else { return }; addTab(id, to: slot); show(slot, focus: true)
            }
        }
        return menu
    }
    private func tabMenu(for slot: Slot, content: SlotTabID) -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        if let reload = slot.pages[content]?.reload {
            menu.addItem(withTitle: "Reload Page", action: nil, keyEquivalent: "r").handler = reload
            menu.addItem(.separator())
        }
        for edge in SlotEdge.allCases where edge != slot.edge {
            let item = menu.addItem(withTitle: "Move to \(Self.title(of: edge)) Slot", action: nil, keyEquivalent: "")
            item.handler = { [weak self, weak slot] in
                guard let self, let slot, let target = slots[edge] else { return }
                moveTab(content, from: slot, to: target)
            }
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close Tab", action: nil, keyEquivalent: "").handler = { [weak self, weak slot] in
            guard let self, let slot else { return }; removeTab(content, from: slot, dropPage: true)
        }
        return menu
    }
    private func capsuleMenu(for slot: Slot) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let heading = menu.addItem(withTitle: "Hide by Itself", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        let choices: [(SlotAutoHide, String)] = [(.afterChoice, "After Choosing Something to Play"),
                                                 (.mouseLeaves, "When the Pointer Leaves"), (.manual, "Only When Asked")]
        for (mode, title) in choices {
            let item = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
            item.state = slot.setting.autoHide == mode ? .on : .off
            item.indentationLevel = 1
            item.isEnabled = slot.setting.mode == .overlay
            item.handler = { [weak self, weak slot] in
                guard let self, let slot else { return }
                slot.setting.autoHide = mode
                slot.clock = AutoHideClock(mode: mode)
                slot.clock.pointerInside(isPointer(in: slot), now: Self.now)
                persist(slot)
                updateAutoHideTimer()
            }
        }
        menu.addItem(.separator())
        let revealHeading = menu.addItem(withTitle: "Show from the Edge", action: nil, keyEquivalent: "")
        revealHeading.isEnabled = false
        for (reveal, title) in [(SlotReveal.atOnce, "When the Pointer Touches It"), (.tongue, "With a Click on Its Tongue")] {
            let item = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
            item.state = slot.setting.reveal == reveal ? .on : .off
            item.indentationLevel = 1
            item.isEnabled = slot.setting.mode == .overlay
            item.handler = { [weak self, weak slot] in
                guard let self, let slot else { return }
                slot.setting.reveal = reveal
                slot.reveal.reset()
                hideTongue(slot)
                persist(slot)
            }
        }
        if !slot.tabs.isEmpty {
            menu.addItem(.separator())
            let clear = menu.addItem(withTitle: "Clear Slot", action: nil, keyEquivalent: "")
            clear.handler = { [weak self, weak slot] in
                guard let self, let slot else { return }
                self.clear(slot)
            }
        }
        return menu
    }

    private func popUp(_ menu: NSMenu, from button: NSView?, in slot: Slot) {
        menuOpen = true
        defer { menuOpen = false }
        if let button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
        } else {
            let view = slot.view
            menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.midX - 60, y: view.bounds.midY), in: view)
        }
    }

    // MARK: The edge

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    /// A hidden overlay slot with something in it comes from its edge: at once when the pointer touches the edge, or
    /// by a click on its tongue, which fades in as the pointer nears.
    private func pointerEvent(_ event: NSEvent) {
        if event.type == .leftMouseUp { windowMoving = false }
        guard event.window === container.window, container.window != nil else { return }
        reveal(at: container.convert(event.locationInWindow, from: nil))
        updateAutoHideTimer()
    }

    /// The pointer over the player's window while the app is in the background (a Mac in use elsewhere, the player beside it):
    /// the edges answer as they do in front. Only when the window itself is what is under the pointer, not another window over it.
    private func backgroundPointerEvent() {
        guard !NSApp.isActive, let window = container.window, window.isVisible, window.occlusionState.contains(.visible) else { return }
        let screenPoint = NSEvent.mouseLocation
        guard window.frame.contains(screenPoint),
              NSWindow.windowNumber(at: screenPoint, belowWindowWithWindowNumber: 0) == window.windowNumber else { return }
        reveal(at: container.convert(window.convertPoint(fromScreen: screenPoint), from: nil))
        updateAutoHideTimer()
    }

    /// `point` in the container: edges and tongues of the hidden overlay slots. A window that is not the key one still
    /// answers (another of the app's windows may be in front of the keyboard): only a sheet on it keeps the edges quiet.
    private func reveal(at point: CGPoint) {
        // Left, right, middle, back and forward only: a mouse or its driver can leave a higher button down in the HID
        // state for good (button 6 seen stuck system-wide, Mac Mouse Fix off or on, 2026-10-27), and the edges
        // would stay quiet until a reboot.
        let buttonHeld = NSEvent.pressedMouseButtons & 0b11111 != 0
        let bounds = container.bounds
        let quiet = container.window?.attachedSheet != nil
        for slot in orderedSlots {
            guard !quiet, !slot.view.isShown, !slot.tabs.isEmpty, slot.setting.mode == .overlay else {
                slot.reveal.reset()
                hideTongue(slot)
                continue
            }
            switch slot.setting.reveal {
            case .atOnce:
                hideTongue(slot)
                if slot.reveal.pointer(atEdge: EdgeReveal.isAt(slot.edge, point, in: bounds, band: revealBand), buttonHeld: buttonHeld) == .revealSlot {
                    show(slot, focus: false)
                }
            case .tongue:
                let overTongue = !slot.tongue.isHidden && slot.tongue.frame.contains(point)
                switch EdgeTongue.reaction(buttonHeld: buttonHeld, overTongue: overTongue) {
                case .follow: moveTongue(slot, toward: point, in: bounds)
                case .hide: hideTongue(slot)
                case .keep: break   // the press is on its way to the tongue's own mouseDown
                }
            }
        }
    }

    /// The tongue at the pointer's place along the edge, as visible as the pointer is near.
    private func moveTongue(_ slot: Slot, toward p: CGPoint, in b: CGRect) {
        let distance: CGFloat = switch slot.edge {
        case .left: p.x - b.minX
        case .right: b.maxX - p.x
        case .bottom: p.y - b.minY
        }
        let opacity = b.contains(p) ? EdgeTongue.opacity(distance: distance) : 0
        guard opacity > 0 else { hideTongue(slot); return }
        let t = SlotTongueView.hitThickness, l = EdgeTongue.length
        let tongue = slot.tongue
        switch slot.edge {
        case .left:
            tongue.frame = CGRect(x: b.minX, y: EdgeTongue.center(at: p.y, span: b.minY...b.maxY) - l / 2, width: t, height: l)
        case .right:
            tongue.frame = CGRect(x: b.maxX - t, y: EdgeTongue.center(at: p.y, span: b.minY...b.maxY) - l / 2, width: t,
                                  height: l)
        case .bottom:
            tongue.frame = CGRect(x: EdgeTongue.center(at: p.x, span: b.minX...b.maxX) - l / 2, y: b.minY, width: l, height: t)
        }
        tongue.alphaValue = opacity
        tongue.isHidden = false
    }

    private func hideTongue(_ slot: Slot) { slot.tongue.isHidden = true }

    // MARK: Auto-hide

    /// The pointer is in the slot, or gone out of the window across the slot's edge and not far.
    private func isPointer(in slot: Slot) -> Bool {
        guard let window = container.window else { return false }
        let point = container.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return SlotHover.counts(point, slot: slot.view.frame, edge: slot.edge, window: container.bounds)
    }

    private func updateAutoHideTimer() {
        autoHideTimer?.invalidate(); autoHideTimer = nil
        autoHideTick()
    }
    private func autoHideTick() {
        let now = Self.now
        if NSEvent.pressedMouseButtons & 1 == 0 { windowMoving = false }   // a title-bar drag may send us no mouse-up
        var next: Double?
        for slot in orderedSlots where slot.view.isShown && effectiveMode(slot) == .overlay {
            let inside = isPointer(in: slot)
            if !inside && !isPointerInWindow {
                slot.clock.pointerOutsideWindow(now: now)   // left elsewhere than across its edge: Zen's 1 s
            } else {
                slot.clock.pointerInside(inside, now: now)
            }
            slot.clock.setBusy(menuOpen || windowMoving || slot.view.isResizing || isTyping(in: slot)
                               || slot.flash != nil)
            // Checked again when it fires: a drag of the window can report a leave that is none.
            if slot.clock.shouldHide(now: now), !isPointer(in: slot) { hide(slot) }
            if let deadline = slot.clock.nextChange(now: now) { next = min(next ?? deadline, deadline) }

        }
        if let next, autoHideTimer == nil {
            autoHideTimer = Timer.scheduledTimer(withTimeInterval: max(0.001, next - now), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.autoHideTimer = nil; self?.autoHideTick() }
            }
        }
    }

    private var isPointerInWindow: Bool {
        guard let window = container.window else { return false }
        return container.bounds.contains(container.convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    // MARK: Zen's rules

    /// The window resigned key or the app went to the background: overlay slots go (Zen collapses on deactivate);
    /// with a menu open, once it closes.
    private func resigned() {
        if menuOpen { resignedDuringMenu = true; return }
        hideOnResign()
    }

    private func hideOnResign() {
        for slot in orderedSlots where slot.view.isShown && AutoHideClock.hidesOnResign(mode: effectiveMode(slot)) {
            hide(slot)
        }
    }

    /// The capsule shows by its clock (pinned: always); a pending fade-out is one work item, not a timer.
    private func updateCapsule(_ slot: Slot, animated: Bool = true) {
        slot.capsuleCheck?.cancel()
        slot.capsuleCheck = nil
        let now = Self.now
        slot.capsuleClock.setBusy(menuOpen || slot.view.capsule.isEditingFilter, now: now)
        let visible = effectiveMode(slot) == .pinned || slot.capsuleClock.isVisible(now: now)
        slot.view.capsule.setVisible(visible && slot.view.isShown, animated: animated)
        guard let next = slot.capsuleClock.nextChange(now: now) else { return }
        let check = DispatchWorkItem { [weak self, weak slot] in
            guard let self, let slot else { return }
            updateCapsule(slot)
        }
        slot.capsuleCheck = check
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, next - now), execute: check)
    }

    public func flash(_ id: SlotTabID, cause: VideoChangeCause, enabled: Bool) {
        guard let slot = orderedSlots.first(where: { $0.shownTab == id }), slot.setting.mode == .overlay else { return }
        let restart = slot.flash != nil && enabled && (cause == .autoadvance || cause == .key)
        guard restart || SlotFlash.shouldFlash(enabled: enabled, slotShown: slot.view.isShown, cause: cause) else { return }
        slot.flash?.cancel()
        if !slot.view.isShown { show(slot, focus: false) }
        let end = DispatchWorkItem { [weak self, weak slot] in
            guard let self, let slot else { return }; slot.flash = nil; endFlash(slot); updateAutoHideTimer()
        }
        slot.flash = end
        DispatchQueue.main.asyncAfter(deadline: .now() + SlotMotion.flash, execute: end)
    }
    private func endFlash(_ slot: Slot) {
        slot.flashEndedInMenu = false
        guard slot.view.isShown else { return }
        let inUse = holdsFocus(slot) || slot.view.capsule.isEditingFilter
        let pointerInside = isPointer(in: slot)
        if menuOpen && !pointerInside && !inUse { slot.flashEndedInMenu = true; return }
        if SlotFlash.endHides(pointerInside: pointerInside, menuOpen: menuOpen, inUse: inUse) { hide(slot) }
    }

    private func isTyping(in slot: Slot) -> Bool {
        holdsFocus(slot) && (slot.page?.isTyping() == true || slot.view.capsule.isEditingFilter)
    }
    private func persist(_ slot: Slot) {
        var setting = slot.setting
        setting.tabs.removeAll { slot.transient.contains($0) }
        if setting.tabs.isEmpty { setting.shown = false }
        onPersist?(slot.edge, setting)
    }
}

private extension NSMenuItem {
    /// A closure run when the item is chosen.
    var handler: (() -> Void)? {
        get { (representedObject as? MenuHandler)?.run }
        set {
            let target = newValue.map(MenuHandler.init)
            representedObject = target
            self.target = target
            action = target == nil ? nil : #selector(MenuHandler.fire)
        }
    }
}

private final class MenuHandler: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire() { run() }
}
