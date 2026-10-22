import AppKit
import Filmstrip
import HomeChrome

/// The shared chrome in one small window: `ChromeGlass` in both styles, a toast of each style, the strip's capsule and
/// nub, and a Light / Dark switch for the whole app (`NSApp.appearance`).
@MainActor final class ChromeDemo: NSObject {
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 300),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    private let mediaToast = ChromeToastView(style: .overMedia(.regular))
    private let windowToast = ChromeToastView(style: .window)

    override init() {
        super.init()
        window.title = "Chrome Demo"
        window.isReleasedWhenClosed = false
        let root = NSView()
        window.contentView = root

        // A gradient stands in for a photo, so the glass over it has something to show.
        let photo = NSView()
        photo.wantsLayer = true
        let gradient = CAGradientLayer()
        gradient.colors = [NSColor.systemTeal.cgColor, NSColor.systemOrange.cgColor]
        photo.layer = gradient
        photo.translatesAutoresizingMaskIntoConstraints = false

        let overMedia = ChromeGlass(style: .overMedia(.regular), cornerRadius: Chrome.Radius.card)
        let inWindow = ChromeGlass(style: .window, cornerRadius: Chrome.Radius.card)
        for (glass, text, color) in [(overMedia, "overMedia", Chrome.Palette.overMedia.text),
                                     (inWindow, "window", Chrome.Palette.window.label)] {
            let label = NSTextField(labelWithString: text)
            label.font = Chrome.Text.font(.label)
            label.textColor = color
            label.translatesAutoresizingMaskIntoConstraints = false
            glass.contentView.addSubview(label)
            NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: glass.contentView.centerXAnchor),
                                         label.centerYAnchor.constraint(equalTo: glass.contentView.centerYAnchor)])
            glass.translatesAutoresizingMaskIntoConstraints = false
        }

        let tools = FilmstripToolsView()
        tools.tools = [FilmstripTool(symbol: "eye", help: "Eye", action: {}),
                       FilmstripTool(symbol: "star", help: "Star", isOn: true, separatorBefore: true, action: {}),
                       FilmstripTool(symbol: "pin", help: "Pin", action: {})]
        let nub = FilmstripRevealView(edge: .bottom)
        for view in [tools, nub, mediaToast, windowToast] as [NSView] { view.translatesAutoresizingMaskIntoConstraints = false }

        let toasts = NSButton(title: "Show toasts", target: self, action: #selector(showToasts))
        let mode = NSSegmentedControl(labels: ["Light", "Dark"], trackingMode: .selectOne, target: self,
                                      action: #selector(setMode(_:)))
        mode.selectedSegment = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? 1 : 0
        let controls = NSStackView(views: [mode, toasts])
        controls.spacing = Chrome.Space.m
        controls.translatesAutoresizingMaskIntoConstraints = false

        for view in [photo, controls, inWindow, windowToast] as [NSView] { root.addSubview(view) }
        photo.addSubview(overMedia)
        photo.addSubview(tools)
        photo.addSubview(nub)
        photo.addSubview(mediaToast)
        let m = Chrome.Space.xl
        NSLayoutConstraint.activate([
            photo.topAnchor.constraint(equalTo: root.topAnchor, constant: m),
            photo.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: m),
            photo.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -m),
            photo.heightAnchor.constraint(equalToConstant: 150),
            overMedia.leadingAnchor.constraint(equalTo: photo.leadingAnchor, constant: m),
            overMedia.topAnchor.constraint(equalTo: photo.topAnchor, constant: m),
            overMedia.widthAnchor.constraint(equalToConstant: 120), overMedia.heightAnchor.constraint(equalToConstant: 40),
            mediaToast.leadingAnchor.constraint(equalTo: photo.leadingAnchor, constant: m),
            mediaToast.bottomAnchor.constraint(equalTo: photo.bottomAnchor, constant: -m),
            tools.centerXAnchor.constraint(equalTo: photo.centerXAnchor),
            tools.topAnchor.constraint(equalTo: photo.topAnchor, constant: m),
            nub.centerXAnchor.constraint(equalTo: photo.centerXAnchor),
            nub.bottomAnchor.constraint(equalTo: photo.bottomAnchor, constant: -m),
            inWindow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: m),
            inWindow.topAnchor.constraint(equalTo: photo.bottomAnchor, constant: m),
            inWindow.widthAnchor.constraint(equalToConstant: 120), inWindow.heightAnchor.constraint(equalToConstant: 40),
            windowToast.leadingAnchor.constraint(equalTo: inWindow.trailingAnchor, constant: m),
            windowToast.centerYAnchor.constraint(equalTo: inWindow.centerYAnchor),
            controls.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: m),
            controls.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -m),
        ])
        window.center()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        showToasts()
    }

    @objc func showToasts() {
        mediaToast.show("Over media 12 / 345", for: 2)
        windowToast.show("In a window 12 / 345", for: 2)
    }

    @objc func setMode(_ sender: NSSegmentedControl) {
        NSApp.appearance = NSAppearance(named: sender.selectedSegment == 0 ? .aqua : .darkAqua)
    }
}
