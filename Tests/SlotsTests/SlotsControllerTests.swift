import AppKit
import Testing
import SlotModel
@testable import Slots

@MainActor @Suite(.serialized) struct SlotsControllerTests {
    let a = SlotTabID(rawValue: "A"), b = SlotTabID(rawValue: "B")
    private func host() -> (NSWindow, SlotsController) {
        _ = NSApplication.shared
        let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.autorecalculatesKeyViewLoop = true
        let content = w.contentView!, image = NSView(frame: content.bounds)
        content.addSubview(image)
        return (w, SlotsController(container: content, above: image))
    }
    @Test func disablingSlotsReleasesTheBrowserAndRestoresPinnedState() {
        let (w, host) = host(); defer { w.close() }
        var visible = false, made = 0, persisted = 0
        host.register(SlotTabDescriptor(id: a, title: "A") { _ in
            made += 1
            return SlotPage(view: NSView(), visibilityChanged: { visible = $0 })
        })
        host.configure(SlotConfiguration(tabs: [a], mode: .pinned, shown: true), edge: .right)
        host.start()
        host.onPersist = { _, _ in persisted += 1 }
        let configuration = host.configuration(.right)
        #expect(visible)
        host.isEnabled = false
        #expect(!visible && host.shownPages.isEmpty && !host.isShown(.right))
        let page = host.page(a, edge: .right)!.view
        #expect(page.isHiddenOrHasHiddenAncestor)
        host.show(.left)
        host.toggle(.right)
        #expect(!host.hideOverlays())
        host.refreshLayout()
        #expect(!host.isShown(.left) && page.isHiddenOrHasHiddenAncestor)
        #expect(host.configuration(.right) == configuration && persisted == 0)
        host.isEnabled = true
        #expect(visible && host.isShown(.right) && made == 1)
        #expect(host.configuration(.right) == configuration && persisted == 0)
    }

    @Test func disabledBeforeStartupKeepsPinnedViewsHidden() {
        let (w, host) = host(); defer { w.close() }
        host.register(SlotTabDescriptor(id: a, title: "A") { _ in SlotPage(view: NSView()) })
        host.configure(SlotConfiguration(tabs: [a], mode: .pinned, shown: true), edge: .right)
        host.isEnabled = false
        host.start()
        #expect(host.page(a, edge: .right)?.view.isHiddenOrHasHiddenAncestor == true)
        host.isEnabled = true
        #expect(host.page(a, edge: .right)?.view.isHiddenOrHasHiddenAncestor == false)
    }

    @Test func returnDoesNotRebuildAndHideReportsInvisible() {
        let (w, host) = host(); defer { w.close() }
        var made = 0, visible = false
        host.register(SlotTabDescriptor(id: a, title: "A") { _ in
            made += 1
            return SlotPage(view: NSView(), visibilityChanged: { visible = $0 })
        })
        host.register(SlotTabDescriptor(id: b, title: "B") { _ in SlotPage(view: NSView()) })
        host.configure(SlotConfiguration(tabs: [a,b]), edge: .right)
        host.start(); host.show(.right)
        #expect(made == 1 && visible)
        host.select(b, edge: .right)
        #expect(!visible)
        #expect(host.page(a, edge: .right)?.view.isHidden == true)
        host.select(a, edge: .right)
        #expect(made == 1 && visible)
        host.hide(.right)
        #expect(!visible)
    }
    @Test func closingFocusedTabReturnsFocusAndDropsPage() {
        let (w, host) = host(); defer { w.close() }
        var dropped = 0, focuses = 0
        host.onFocusContent = { focuses += 1 }
        host.register(SlotTabDescriptor(id: a, title: "A") { _ in
            SlotPage(view: NSTextField(), dropped: { dropped += 1 })
        })
        host.configure(SlotConfiguration(tabs: [a]), edge: .right)
        host.start(); host.show(.right)
        w.makeFirstResponder(host.page(a, edge: .right)?.view)
        host.remove(a, edge: .right)
        #expect(dropped == 1 && focuses == 1)
        #expect(host.page(a, edge: .right) == nil)
    }
    @Test func explicitPreparationKeepsHiddenPluginAliveWithoutShowingIt() {
        let (w, host) = host(); defer { w.close() }
        var made = 0, visible = false
        host.register(SlotTabDescriptor(id: a, title: "A") { _ in
            made += 1; return SlotPage(view: NSView(), visibilityChanged: { visible = $0 })
        })
        host.configure(SlotConfiguration(tabs: [a,b]), edge: .right)
        host.start()
        #expect(made == 0)
        host.prepare(a, edge: .right)
        #expect(made == 1 && !visible && !host.isShown(.right))
        host.show(.right); host.select(b, edge: .right)
        #expect(host.tabIDs(in: .right) == [a,b])
        #expect(host.configuration(.right).tabs == [b,a])
        host.select(a, edge: .right)
        #expect(made == 1)
    }
    @Test func movingKeepsLiveView() {
        let (w, host) = host(); defer { w.close() }
        var made = 0, dropped = 0
        host.register(SlotTabDescriptor(id: a, title: "A") { _ in
            made += 1
            return SlotPage(view: NSView(), dropped: { dropped += 1 })
        })
        host.configure(SlotConfiguration(tabs: [a]), edge: .right)
        host.start(); host.show(.right)
        let v = host.page(a, edge: .right)?.view
        host.move(a, from: .right, to: .left)
        #expect(host.page(a, edge: .left)?.view === v)
        #expect(made == 1 && dropped == 0)
    }
}

@MainActor private final class FieldEditorOwner: NSTextField, NSTextViewDelegate {}

extension SlotsControllerTests {
    @Test func closingTabWithSharedFieldEditorReturnsFocusToContent() {
        let (w, host) = host(); defer { w.close() }
        let owner = FieldEditorOwner()
        var focusReturned = 0
        host.onFocusContent = { focusReturned += 1 }
        host.register(SlotTabDescriptor(id: a, title: "A") { _ in SlotPage(view: owner) })
        host.configure(SlotConfiguration(tabs: [a]), edge: .right)
        host.start(); host.show(.right)
        let editor = NSTextView(frame: CGRect(x: 0, y: 0, width: 100, height: 30))
        editor.isFieldEditor = true
        editor.delegate = owner
        w.contentView?.addSubview(editor) // shared editor is outside the slot hierarchy
        #expect(w.makeFirstResponder(editor))
        host.remove(a, edge: .right)
        #expect(focusReturned == 1)
    }
}
