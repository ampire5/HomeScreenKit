import AppKit
import HomeChrome
import HomeScreenKit

/// Home on made-up data, for trying it by hand: the sidebar, the sources and the browser (`HomeView`); with
/// `HOMESCREEN_SCREEN=start` the start screen FrameScrub still uses (`HomeScreenView`), where View switches the layout,
/// the picture shape, the tabs and the message.
@MainActor final class Demo: NSObject, NSApplicationDelegate {
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1100, height: 760),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
    let home = HomeScreenView(background: Chrome.Palette.window.background.cgColor)
    let source = DemoBrowserSource()
    lazy var browser = HomeBrowserView(source: source)
    lazy var homeView = HomeView(source: source)
    var filmstrip: FilmstripDemo?
    var rowsDemo: FilmstripRowsDemo?
    var chromeDemo: ChromeDemo?
    static let tabs = ["Recent", "Folders", "Stash"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["HOMESCREEN_DEMO"] == "rows" {   // the rows strip at once
            DispatchQueue.main.async { self.showRows() }
        }
        window.title = "HomeScreenKit demo"
        if ProcessInfo.processInfo.environment["HOMESCREEN_SCREEN"] != "start" {
            showHomeView()
            return
        }
        window.contentView = home
        home.emptyHint = "Open something with ⌘O or drop it here"
        home.tabs = Self.tabs
        home.onTab = { [weak self] tab in self?.showTab(tab) }
        source.view = browser
        browser.isHidden = true
        browser.translatesAutoresizingMaskIntoConstraints = false
        browser.onStyle = { [weak self] style in self?.browser.style = style }
        browser.onNames = { [weak self] names in self?.browser.names = names }
        browser.onResize = { [weak self] step in
            guard let self else { return }
            self.browser.cardSize = self.browser.cardSize(after: step, range: 60...480) ?? 220
        }
        home.addSubview(browser)
        NSLayoutConstraint.activate([
            browser.leadingAnchor.constraint(equalTo: home.leadingAnchor),
            browser.trailingAnchor.constraint(equalTo: home.trailingAnchor),
            browser.topAnchor.constraint(equalTo: home.contentTop), browser.bottomAnchor.constraint(equalTo: home.bottomAnchor),
        ])
        browser.show(.places, selecting: nil)
        home.onCard = { id, click in print("open \(id) \(click)") }
        home.onMenu = { id, item in print("menu \(id) \(item)") }
        home.onDrop = { print("drop \($0.path)") }
        let menu = [HomeMenuItem(id: "finder", title: "Show in Finder"), HomeMenuItem(id: "remove", title: "Remove from Recent")]
        let sessions = [HomeCardItem(id: "s0", title: "Last Session", subtitle: "2 windows · 5 tabs", tooltip: "session",
                                     symbol: "rectangle.stack"),
                        HomeCardItem(id: "s1", title: "Work", subtitle: "1 window · 3 tabs", tooltip: "session",
                                     symbol: "rectangle.stack")]
        var recent: [HomeCardItem] = []
        for i in 0..<14 {
            let progress = Double(i + 1) / 40
            let badge: String? = i % 4 == 0 ? "Stash" : nil
            recent.append(HomeCardItem(id: "r\(i)", title: "Folder \(i)", subtitle: "\(i + 1) / 40", tooltip: "/Volumes/Media/\(i)",
                                       symbol: "folder", progress: progress, badge: badge, isDimmed: i == 3, menu: menu))
        }
        home.sections = [HomeSection(title: "Sessions", items: sessions), HomeSection(title: "Recent", items: recent)]
        for (i, item) in (sessions + recent).enumerated() where i % 3 != 2 { home.setImage(Self.gradient(i), for: item.id) }
        if let path = ProcessInfo.processInfo.environment["HOMESCREEN_SNAPSHOT"] {   // a PNG of the screen, no window shown
            let env = ProcessInfo.processInfo.environment
            if let mode = env["HOMESCREEN_LAYOUT"].flatMap(HomeLayoutMode.init) { home.layoutMode = mode }
            if env["HOMESCREEN_VIDEO"] != nil { home.aspect = 9.0 / 16 }
            if let w = env["HOMESCREEN_WIDTH"].flatMap(Double.init) { window.setContentSize(CGSize(width: w, height: 760)) }
            let folders = env["HOMESCREEN_TAB"] == "folders"
            if folders {
                home.selectedTab = 1
                showTab(1)
                if let style = env["HOMESCREEN_STYLE"].flatMap(GridStyle.init) { browser.style = style }
                if let names = env["HOMESCREEN_NAMES"].flatMap(GridNames.init) { browser.names = names }
                browser.show(.folder(URL(fileURLWithPath: env["HOMESCREEN_FOLDER"] ?? "/Demo/Mixed")), selecting: nil)
                if let text = env["HOMESCREEN_FILTER"] {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        self.browser.filterText = text
                    }
                }
            }
            Task { @MainActor in
                let delay = Int(env["HOMESCREEN_SNAPSHOT_DELAY"] ?? "") ?? 800
                if folders { try? await Task.sleep(for: .milliseconds(delay)) }   // the listing and the pictures
                self.home.layoutSubtreeIfNeeded()
                let rep = self.home.bitmapImageRepForCachingDisplay(in: self.home.bounds)!
                self.home.cacheDisplay(in: self.home.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                exit(0)
            }
            return
        }
        buildMenu()
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(home)
        NSApp.activate()
    }

    /// Home as Loupe shows it. `HOMESCREEN_SNAPSHOT` with `HOMESCREEN_SOURCE` = `recent`, `sessions`, `places`, `stash`,
    /// `tree` (a folder two levels down) or a folder path, and `HOMESCREEN_NOSIDEBAR`.
    func showHomeView() {
        let env = ProcessInfo.processInfo.environment
        let browser = homeView.browser
        source.view = browser
        window.contentView = homeView
        browser.onStyle = { style in browser.style = style }
        browser.onNames = { names in browser.names = names }
        browser.onResize = { step in browser.cardSize = browser.cardSize(after: step, range: 60...480) ?? 220 }
        homeView.onSidebarToggle = { [weak self] in
            guard let self else { return }
            self.homeView.isSidebarVisible.toggle()
        }
        homeView.onDrop = { print("drop \($0.path)") }
        if let w = env["HOMESCREEN_WIDTH"].flatMap(Double.init) { window.setContentSize(CGSize(width: w, height: 760)) }
        if let style = env["HOMESCREEN_STYLE"].flatMap(GridStyle.init) { browser.style = style }
        if let names = env["HOMESCREEN_NAMES"].flatMap(GridNames.init) { browser.names = names }
        if env["HOMESCREEN_NOSIDEBAR"] != nil { homeView.isSidebarVisible = false }
        if env["HOMESCREEN_FILES"] == "videos" { browser.files = .videos }
        if env["HOMESCREEN_FACTS_LINE"] != nil { browser.files.factsLine = true }
        if let style = env["HOMESCREEN_CARDS"].flatMap(CardStyle.init) { browser.chooseCardStyle(style) }
        let location: BrowserLocation
        switch env["HOMESCREEN_SOURCE"] ?? "recent" {
        case "recent": location = .source("recent")
        case "sessions": location = .source("sessions")
        case "stash": location = .source("stash")
        case "places": location = .places
        case "tree": location = .folder(URL(fileURLWithPath: "/Demo/Huge/Set 3"))
        case let path: location = .folder(URL(fileURLWithPath: path))
        }
        browser.show(location, selecting: nil)
        if let path = env["HOMESCREEN_SNAPSHOT"] {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(Int(env["HOMESCREEN_SNAPSHOT_DELAY"] ?? "") ?? 1500))
                self.homeView.layoutSubtreeIfNeeded()
                let rep = self.homeView.bitmapImageRepForCachingDisplay(in: self.homeView.bounds)!
                self.homeView.cacheDisplay(in: self.homeView.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                exit(0)
            }
            return
        }
        window.styleMask.insert(.fullSizeContentView)
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar = browser.nsToolbar
        browser.onWindowText = { [weak self] title, subtitle in
            self?.window.title = title
            self?.window.subtitle = subtitle
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(browser)
        NSApp.activate()
        if let prefix = env["HOMESCREEN_SHOTS"] { shoot(prefix: prefix, dark: env["HOMESCREEN_DARK"] != nil) }
    }

    /// Window pictures at 1200, 900, 700 and 560 pt for looking at the toolbar (`HOMESCREEN_SHOTS=<prefix>`, with
    /// `HOMESCREEN_DARK` for the dark appearance): `<prefix>-<width>.png` by `screencapture` of the window itself.
    func shoot(prefix: String, dark: Bool) {
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        if ProcessInfo.processInfo.environment["HOMESCREEN_PROGRESS"] != nil {   // the thumbnails' ring, lit
            homeView.browser.setProgress(ThumbsProgressState(fraction: 0.4, text: "Thumbnails 120 / 300"), delay: .zero)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            for width in [1200.0, 900.0, 700.0, 560.0] {
                self.window.setContentSize(CGSize(width: width, height: 760))
                try? await Task.sleep(for: .milliseconds(700))
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-o", "-l", String(self.window.windowNumber), "\(prefix)-\(Int(width)).png"]
                try? capture.run()
                capture.waitUntilExit()
            }
            exit(0)
        }
    }

    func showTab(_ tab: Int) {
        window.toolbar = tab == 1 ? browser.nsToolbar : nil   // the folders' toolbar is the window's
        browser.isHidden = tab != 1
        window.makeFirstResponder(tab == 1 ? browser : home)
    }

    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(appItem)
        let viewItem = NSMenuItem()
        let view = NSMenu(title: "View")
        for (i, mode) in HomeLayoutMode.allCases.enumerated() {
            let item = view.addItem(withTitle: "Layout \(mode.rawValue)", action: #selector(layout(_:)), keyEquivalent: "\(i + 1)")
            item.representedObject = mode.rawValue
            item.target = self
        }
        view.addItem(.separator())
        for (i, style) in CardStyle.allCases.enumerated() {
            let item = view.addItem(withTitle: "Folders as \(style.rawValue)", action: #selector(cardStyle(_:)),
                                    keyEquivalent: "\(i + 1)")
            item.keyEquivalentModifierMask = [.command, .option]
            item.representedObject = style.rawValue
            item.target = self
        }
        view.addItem(.separator())
        for (title, key, action) in [("Photo 3:2", "p", #selector(photo)), ("Video 16:9", "v", #selector(video)),
                                     ("Tabs on/off", "t", #selector(toggleTabs)), ("Message on/off", "m", #selector(toggleMessage))] {
            view.addItem(withTitle: title, action: action, keyEquivalent: key).target = self
        }
        viewItem.submenu = view
        main.addItem(viewItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Filmstrip Demo", action: #selector(showFilmstrip), keyEquivalent: "f").target = self
        windowMenu.addItem(withTitle: "Rows Demo", action: #selector(showRows), keyEquivalent: "r").target = self
        windowMenu.addItem(withTitle: "Chrome Demo", action: #selector(showChrome), keyEquivalent: "").target = self
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }

    @objc func layout(_ sender: NSMenuItem) { home.layoutMode = HomeLayoutMode(rawValue: sender.representedObject as! String)! }
    @objc func cardStyle(_ sender: NSMenuItem) {
        guard let style = (sender.representedObject as? String).flatMap(CardStyle.init) else { return }
        homeView.browser.chooseCardStyle(style)
        browser.chooseCardStyle(style)
    }
    @objc func showFilmstrip() {
        let demo = filmstrip ?? FilmstripDemo()
        filmstrip = demo
        demo.show()
    }
    @objc func showRows() {
        let demo = rowsDemo ?? FilmstripRowsDemo()
        rowsDemo = demo
        demo.show()
    }
    @objc func showChrome() {
        let demo = chromeDemo ?? ChromeDemo()
        chromeDemo = demo
        demo.show()
    }
    @objc func photo() { home.aspect = 2.0 / 3 }
    @objc func video() { home.aspect = 9.0 / 16 }
    @objc func toggleTabs() { home.tabs = home.tabs.isEmpty ? Self.tabs : [] }
    @objc func toggleMessage() {
        if home.isShowingMessage { home.showGrid() } else {
            home.showMessage(title: "Cannot open clip.mp4", reason: "No video track", detail: "The file has audio only.",
                             hints: ["Return — try again", "⌘O — open"])
        }
    }

    static func gradient(_ seed: Int, width: Int = 300, height: Int = 200) -> CGImage {
        let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let hue = CGFloat(seed % 7) / 7
        let a = NSColor(hue: hue, saturation: 0.6, brightness: 0.8, alpha: 1).cgColor
        let b = NSColor(hue: hue + 0.1, saturation: 0.7, brightness: 0.3, alpha: 1).cgColor
        let g = CGGradient(colorsSpace: nil, colors: [a, b] as CFArray, locations: nil)!
        c.drawLinearGradient(g, start: .zero, end: CGPoint(x: width, y: height), options: [])
        return c.makeImage()!
    }
}

if CommandLine.arguments.dropFirst().first == "bench-toolbar" { ToolbarBench.main(Array(CommandLine.arguments.dropFirst(2))) }

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let demo = Demo()
    app.delegate = demo
    app.run()
}
