import AppKit
import Testing
@testable import HomeChrome
@testable import HomeScreenKit
@testable import HomeScreenModel

/// Pictures of the thumbnails' progress pill for comparing with the progress board («Пилюля в тулбаре: три состояния»,
/// «По щелчку»): the pill running and paused, in both appearances, and the popover's content. The pill in the toolbar is
/// the system's to draw now (`NSToolbar`): its pictures are screenshots of the window.
/// Runs only with `HOMESCREEN_SNAPSHOTS=<folder>` set: `HOMESCREEN_SNAPSHOTS=/tmp/x swift test --filter ProgressSnapshots`.
@MainActor @Suite struct ProgressSnapshots {
    nonisolated static let folder = ProcessInfo.processInfo.environment["HOMESCREEN_SNAPSHOTS"]

    static let rows: [ThumbsProgressState.Row] = [.init(title: "In view", done: 24, total: 24),
                                                  .init(title: "Rest of folder", done: 96, total: 216),
                                                  .init(title: "Subfolders", done: 0, total: 240)]
    static let running = ThumbsProgressState(fraction: 0.25, text: "Thumbnails 120 / 480", rows: rows)
    static let paused = ThumbsProgressState(fraction: 0.25, text: "Paused · 120 / 480", paused: true, rows: rows,
                                            pauseNote: "Paused while you browse")

    /// System glass (`NSGlassEffectView`) and what sits in it do not draw off screen, so the pictures put the board's
    /// own fills where the glass is: its glass (white .7 / #3C3C40 .7) under the pill. The pill's ring, glyph, text, rim
    /// and highlight are the real ones.
    static func standIn(_ frame: CGRect, in host: NSView, light: NSColor, dark: NSColor, isDark: Bool) {
        let plate = NSView(frame: frame)
        plate.wantsLayer = true
        plate.layer?.cornerRadius = frame.height / 2
        plate.layer?.backgroundColor = (isDark ? dark : light).cgColor
        host.addSubview(plate)
    }

    /// Off screen the system glass draws unpredictably (nothing in light, white in dark): it is left out of the pictures.
    static func hideGlass(in view: NSView) {
        for sub in view.subviews {
            if sub is NSGlassEffectView { sub.isHidden = true } else { hideGlass(in: sub) }
        }
    }

    static let boardGlass = (light: NSColor(white: 1, alpha: 0.7),
                             dark: NSColor(srgbRed: 60 / 255, green: 60 / 255, blue: 64 / 255, alpha: 0.7))

    /// The ring alone: running and paused, side by side.
    @Test(.enabled(if: folder != nil)) func pillCloseUp() throws {
        for dark in [false, true] {
            try CardSnapshots.write("P-pill-close", size: CGSize(width: 120, height: 60), dark: dark) { host in
                var x: CGFloat = 20
                for state in [Self.running, Self.paused] {
                    let pill = ThumbsProgressPill()
                    pill.show(state)
                    let s = pill.intrinsicContentSize
                    pill.frame = CGRect(x: x, y: 16, width: s.width, height: s.height)
                    Self.standIn(pill.frame, in: host, light: Self.boardGlass.light, dark: Self.boardGlass.dark, isDark: dark)
                    Self.hideGlass(in: pill)
                    host.addSubview(pill)
                    x += s.width + 20
                }
            }
        }
    }

    /// The popover's content on the board's card (white, radius 14, its shadow): NSPopover itself draws only in a
    /// window on screen, so its own glass is not in the picture.
    @Test(.enabled(if: folder != nil)) func popover() throws {
        for dark in [false, true] {
            let panel = ThumbsProgressPanel()
            panel.show(Self.paused)
            let size = panel.intrinsicContentSize
            try CardSnapshots.write("P-popover", size: CGSize(width: size.width + 40, height: size.height + 40), dark: dark) { host in
                let plate = NSView(frame: CGRect(x: 20, y: 20, width: size.width, height: size.height))
                plate.wantsLayer = true
                plate.layer?.cornerRadius = Chrome.Radius.panel
                plate.layer?.backgroundColor = Chrome.resolve(Chrome.Palette.card.background, in: host)
                plate.layer?.borderWidth = 0.5
                plate.layer?.borderColor = Chrome.resolve(Chrome.Palette.card.separator, in: host)
                plate.layer?.shadowColor = NSColor.black.cgColor
                plate.layer?.shadowOpacity = 0.16
                plate.layer?.shadowRadius = 14
                plate.layer?.shadowOffset = CGSize(width: 0, height: -8)
                host.addSubview(plate)
                panel.frame = plate.frame
                host.addSubview(panel)
            }
        }
    }
}
