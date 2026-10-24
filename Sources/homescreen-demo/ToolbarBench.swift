import AppKit
import Foundation
@_spi(Bench) import HomeScreenKit

/// `homescreen-demo bench-toolbar [--rounds N] [--settle MS]` (docs/bench/2026-10-24-home-toolbar.md): the main thread's
/// work for the browser's toolbar in a real window on screen — the window as Loupe makes it, `HomeView` over the demo
/// source on a folder of 2 000 photos and 12 subfolders. Every action is followed by the run loop alone for --settle ms
/// (default 800: long enough for layout, the listing and the Core Animation commit); the number is the main thread's CPU
/// ms, so it is also how long the window does not answer. Prints one line per scenario: the first run, the median and the
/// max of --rounds (default 12).
///
/// - open: the window made and HomeView built, then shown (`makeKeyAndOrderFront` and the first settle).
/// - hide, show: Home hidden and shown again, as a switch to the viewer and back does.
/// - narrow, widen: the window 1300 → 420 pt and back, in steps of 20 pt, per step.
/// - progress: the thumbnails' progress shown 100 times with a growing share, per call and the layout after it.
/// - sort: the three sort fields chosen in turn; siblings: a menu of 30 sibling folders built.
enum ToolbarBench {
    static func main(_ arguments: [String]) -> Never {
        var rounds = 12, settle = 800
        var args = arguments[...]
        while let arg = args.popFirst() {
            if arg == "--rounds", let n = args.popFirst().flatMap(Int.init), n > 0 { rounds = n; continue }
            if arg == "--settle", let n = args.popFirst().flatMap(Int.init), n > 0 { settle = n; continue }
            FileHandle.standardError.write(Data("bench-toolbar: unknown argument \(arg)\n".utf8))
            exit(2)
        }
        MainActor.assumeIsolated { run(rounds: rounds, settle: settle) }
        exit(0)
    }

    @MainActor private static func run(rounds: Int, settle: Int) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()
        var table: [(name: String, samples: [Double])] = []

        let source = DemoBrowserSource()
        let buildStart = threadCPU()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1300, height: 760),
                              styleMask: [.titled, .resizable, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "HomeScreenKit bench"
        let homeView = HomeView(source: source)
        let browser = homeView.browser
        source.view = browser
        window.contentView = homeView
        browser.show(.folder(URL(fileURLWithPath: "/Demo/Mixed")), selecting: nil)
        let built = threadCPU() - buildStart

        let showStart = threadCPU()
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(browser)
        app.activate()
        spin(settle)
        table.append(("open (build)", [built]))
        table.append(("open (show)", [threadCPU() - showStart]))

        var hide: [Double] = [], show: [Double] = []
        for _ in 0..<rounds {
            hide.append(measure(settle) { homeView.isHidden = true })
            show.append(measure(settle) { homeView.isHidden = false })
        }
        table.append(("hide", hide))
        table.append(("show", show))

        var narrow: [Double] = [], widen: [Double] = []
        let widths = stride(from: 1300, through: 420, by: -20).map { CGFloat($0) }
        for _ in 0..<max(1, rounds / 4) {
            for w in widths { narrow.append(measure(150) { window.setContentSize(CGSize(width: w, height: 760)) }) }
            for w in widths.reversed() { widen.append(measure(150) { window.setContentSize(CGSize(width: w, height: 760)) }) }
        }
        table.append(("narrow (per step)", narrow))
        table.append(("widen (per step)", widen))

        var progress: [Double] = []
        for i in 1...100 {
            let share = Double(i) / 100
            let state = ThumbsProgressState(fraction: share, text: "Thumbnails \(i) / 100",
                                            rows: [.init(title: "In view", done: i, total: 100)])
            progress.append(measure(16) { browser.benchShow(progress: state) })
        }
        browser.benchShow(progress: nil)
        spin(settle)
        table.append(("progress (per call)", progress))

        var sort: [Double] = [], siblings: [Double] = []
        for _ in 0..<rounds {
            sort.append(measure(settle) { browser.benchChooseSorts() })
            siblings.append(measure(150) { browser.benchOpenSiblings(count: 30) })
        }
        table.append(("sort (3 fields)", sort))
        table.append(("siblings (30)", siblings))

        print("scenario                 first    median       max   (ms of main-thread CPU)")
        for (name, samples) in table {
            let sorted = samples.sorted()
            print(name.padding(toLength: 22, withPad: " ", startingAt: 0)
                  + String(format: "%8.1f %9.1f %9.1f", samples[0], sorted[sorted.count / 2], sorted.last!))
        }
        print("hide:   " + hide.map { String(format: "%.0f", $0) }.joined(separator: " "))
        print("show:   " + show.map { String(format: "%.0f", $0) }.joined(separator: " "))
        print("sort:   " + sort.map { String(format: "%.0f", $0) }.joined(separator: " "))
    }

    /// The main thread's CPU ms of `action` and the run loop for `settle` ms after it.
    @MainActor private static func measure(_ settle: Int, _ action: () -> Void) -> Double {
        let t0 = threadCPU()
        action()
        spin(settle)
        return threadCPU() - t0
    }

    /// Runs the main run loop for `ms` milliseconds (the window's updates and display happen in it).
    @MainActor private static func spin(_ ms: Int) {
        let end = Date().addingTimeInterval(Double(ms) / 1000)
        while Date() < end {
            if let event = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.005), inMode: .default,
                                           dequeue: true) {
                NSApp.sendEvent(event)
            }
        }
    }

    /// This thread's CPU time in ms.
    private static func threadCPU() -> Double {
        var ts = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)
        return Double(ts.tv_sec) * 1000 + Double(ts.tv_nsec) / 1_000_000
    }
}
