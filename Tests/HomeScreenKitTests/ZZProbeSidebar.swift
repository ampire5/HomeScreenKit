import AppKit
import Testing
@testable import HomeScreenKit

@MainActor @Suite struct ZZProbeSidebar {
    @Test func probe() async {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1200, height: 800), styleMask: [.titled, .fullSizeContentView],
                              backing: .buffered, defer: true)
        let view = HomeView(source: FakeHomeSource())
        view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        window.contentView = view
        view.sidebarWidth = 236
        view.layoutSubtreeIfNeeded()
        let split = view.splitController.splitView
        print("PROBE os \(ProcessInfo.processInfo.operatingSystemVersionString) divider \(split.dividerThickness) vertical \(split.isVertical) style \(split.dividerStyle.rawValue)")
        print("PROBE split \(split.frame) arranged \(split.arrangedSubviews.map { "\(type(of: $0)) \($0.frame)" })")
        print("PROBE sidebarView \(view.sidebarView.frame) super \(String(describing: view.sidebarView.superview.map { "\(type(of: $0)) \($0.frame)" })) inSplit \(split.convert(view.sidebarView.bounds, from: view.sidebarView))")
        var v: NSView? = view.sidebarView
        while let x = v, x !== split { print("PROBE chain \(type(of: x)) \(x.frame)"); v = x.superview }
        split.setPosition(300, ofDividerAt: 0)
        print("PROBE after 300: sidebarView \(view.sidebarView.frame) arranged0 \(split.arrangedSubviews[0].frame) inSplit \(split.convert(view.sidebarView.bounds, from: view.sidebarView))")
    }
}
