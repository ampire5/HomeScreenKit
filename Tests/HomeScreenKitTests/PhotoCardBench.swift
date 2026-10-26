import AppKit
import Testing
@testable import HomeScreenKit
@testable import HomeScreenModel

/// `PHOTO_BENCH=1 swift test --filter PhotoCardBench` (photo-cards spec §4): a 5 000-photo grid in a window scrolled
/// top to bottom in 200 steps, main-thread CPU per step (layout and the Core Animation commit), without marks and with
/// every photo marked. Results: Loupe's docs/bench/2026-10-26-photo-cards.md.
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["PHOTO_BENCH"] != nil))
struct PhotoCardBench {
    private static func cpu() -> Double {
        var ts = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)
        return Double(ts.tv_sec) * 1000 + Double(ts.tv_nsec) / 1_000_000
    }

    private func run(marked: Bool) async -> [Double] {
        let x = URL(fileURLWithPath: "/Volumes/T/x")
        let source = FakeHomeSource()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1400, height: 900), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = HomeBrowserView(source: source)
        view.frame = CGRect(x: 0, y: 0, width: 1400, height: 900)
        window.contentView = view
        view.cardSize = 160
        view.show(.folder(x), selecting: nil)
        source.yield(x, BrowserFixtures.files(5_000), complete: true)
        await settle(seconds: 5) { view.entries.count == 5_000 }
        view.layoutSubtreeIfNeeded()
        if marked {
            let ids = Set(view.entries.map(\.id))
            view.setPhotoMarks(unseen: ids, paired: ids)
        }
        var steps: [Double] = []
        let height = view.gridContentHeight
        for step in 1...200 {
            let start = Self.cpu()
            view.scrollGrid(to: height * CGFloat(step) / 200)
            view.layoutSubtreeIfNeeded()
            CATransaction.flush()
            steps.append(Self.cpu() - start)
        }
        window.close()
        return steps
    }

    private func report(_ name: String, _ steps: [Double]) {
        let sorted = steps.sorted()
        let median = sorted[sorted.count / 2], p95 = sorted[sorted.count * 95 / 100]
        print(String(format: "photo-bench \(name): median %.2f ms, p95 %.2f ms, max %.2f ms, total %.0f ms",
                     median, p95, sorted.last!, steps.reduce(0, +)))
    }

    @Test func scrollWithAndWithoutMarks() async {
        let mode = ProcessInfo.processInfo.environment["PHOTO_BENCH"] ?? ""
        for round in 1...3 {
            if mode != "marked" { report("round \(round) no marks", await run(marked: false)) }
            if mode != "plain" { report("round \(round) all marked", await run(marked: true)) }
        }
    }
}
