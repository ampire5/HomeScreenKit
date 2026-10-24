import AppKit
import Testing
@testable import HomeScreenKit
@testable import HomeScreenModel

@MainActor @Suite struct HomeToolbarProgressTests {
    private static let running = ThumbsProgressState(fraction: 0.25, text: "Thumbnails 120 / 480", paused: false,
                                                     rows: [.init(title: "In view", done: 24, total: 24),
                                                            .init(title: "Rest of folder", done: 96, total: 216),
                                                            .init(title: "Subfolders", done: 0, total: 48)])

    /// A window on screen with the toolbar in it, wide enough for every item.
    private func shown(_ controller: HomeToolbarController) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1400, height: 300),
                              styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.toolbar = controller.nsToolbar
        window.orderFront(nil)
        return window
    }

    private func ringItem(_ controller: HomeToolbarController) -> NSToolbarItem? {
        controller.nsToolbar.items.first { $0.itemIdentifier == HomeToolbarItem.progress.identifier }
    }

    @Test func ringShowsOnlyWithAState() {
        let controller = HomeToolbarController()
        #expect(!controller.isProgressVisible)
        controller.show(progress: Self.running)
        #expect(controller.isProgressVisible)
        #expect(controller.progress.text == Self.running.text)
        #expect(controller.progressState == Self.running)
        controller.show(progress: nil)
        #expect(!controller.isProgressVisible)
        #expect(controller.progressState == nil)
    }

    @Test func ringTextIsInTheTip() {
        let controller = HomeToolbarController()
        let window = shown(controller)
        defer { window.close() }
        controller.show(progress: Self.running)
        #expect(ringItem(controller)?.toolTip == Self.running.text)
        controller.show(progress: nil)
        #expect(ringItem(controller)?.toolTip?.isEmpty == false)
    }

    @Test func ringIsTheItemsViewAt28Points() {
        let controller = HomeToolbarController()
        let window = shown(controller)
        defer { window.close() }
        #expect(ringItem(controller)?.view === controller.progress)
        #expect(controller.progress.fittingSize == CGSize(width: 28, height: 28))
    }

    @Test func ringDoesNotDrawItsOwnGlass() {
        let controller = HomeToolbarController()
        #expect(controller.progress.drawsBackdrop == false)
        #expect(ThumbsProgressPill().drawsBackdrop)
    }

    @Test func popoverOpensFromTheRing() async {
        let controller = HomeToolbarController()
        let window = shown(controller)
        defer { window.close() }
        controller.show(progress: Self.running)
        window.layoutIfNeeded()
        #expect(controller.showProgressPopover(in: window))
        await settle { controller.progress.isPopoverShown }
        #expect(controller.progress.isPopoverShown)
        #expect(controller.progress.isPopoverOnPill)
        #expect(controller.showProgressPopover(in: window))   // asked again: the one open stays, there is no second
        #expect(controller.progress.isPopoverShown)
        controller.progress.closePopover()
        await settle { !controller.progress.isPopoverShown }
    }

    @Test func popoverOpensWhenTheRingIsHidden() async {
        let controller = HomeToolbarController()
        let window = shown(controller)
        defer { window.close() }
        controller.show(progress: nil)
        window.layoutIfNeeded()
        #expect(controller.showProgressPopover(in: window))
        await settle { controller.progress.isPopoverShown }
        #expect(controller.progress.isPopoverShown)
        #expect(!controller.progress.isPopoverOnPill)
        // Done meanwhile: the popover from the window's top stays with the last counts.
        controller.show(progress: nil)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(controller.progress.isPopoverShown)
        controller.progress.closePopover()
        await settle { !controller.progress.isPopoverShown }
    }

    @Test func popoverNeedsAWindow() {
        let controller = HomeToolbarController()
        #expect(!controller.showProgressPopover())
        controller.show(progress: Self.running)
        #expect(!controller.showProgressPopover())
    }
}
