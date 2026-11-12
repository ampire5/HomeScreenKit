import AppKit
import HomeScreenModel

struct FileTabNavigation {
    var history: BrowserHistory
    var selection: String?
    var anchor: BrowserAnchor?

    init(at location: BrowserLocation) {
        history = BrowserHistory(start: location)
    }

    var folder: URL? {
        guard case .folder(let folder) = history.current else { return nil }
        return folder
    }
}

struct HomeFileTab {
    var id = UUID()
    var navigation: FileTabNavigation

    static let openMenuID = "home-file-tab-open"
    static let openMenuItem = HomeMenuItem(id: openMenuID, title: "Open in New Tab")
}

extension HomeView {
    /// Enable folder tabs on this Home view. Hosts that leave this off keep ordinary browser navigation.
    public var fileTabsEnabled: Bool {
        get { fileTabStrip != nil }
        set {
            guard newValue != fileTabsEnabled else { return }
            guard newValue else {
                fileTabStrip?.removeFromSuperview()
                fileTabStrip = nil
                browser.onEnterFileTab = nil
                browser.onLeaveFileTab = nil
                browser.onBackToFileTab = nil
                browser.onOpenFileTab = nil
                browser.installFileTabStrip(nil)
                fileTabs.removeAll()
                lastFileFolder = nil
                return
            }
            let navigation = browser.isAtAppSource ? FileTabNavigation(at: .places) : browser.fileTabNavigation
            fileTabs = [HomeFileTab(navigation: navigation)]
            fileTabIndex = 0
            lastFileFolder = navigation.folder
            let strip = FileTabStrip()
            fileTabStrip = strip
            browser.installFileTabStrip(strip)
            strip.onAdd = { [weak self] in self?.addFileTab() }
            strip.onSelect = { [weak self] id in _ = self?.selectFileTab(id) }
            strip.onClose = { [weak self] id in self?.closeFileTab(id) }
            strip.onMove = { [weak self] id, offset in self?.moveFileTab(id, by: offset) }
            browser.onLeaveFileTab = { [weak self] in self?.captureFileTab() }
            browser.onEnterFileTab = { [weak self] in
                guard let self else { return nil }
                return self.fileTabs[self.fileTabIndex].navigation
            }
            browser.onBackToFileTab = { [weak self] in
                guard let self, let id = self.selectedFileTabID else { return }
                _ = self.selectFileTab(id)
            }
            browser.onOpenFileTab = { [weak self] folder in self?.openFileTab(at: .folder(folder)) }
            updateFileTabStrip()
        }
    }

    public var selectedFileTabID: UUID? { fileTabs.isEmpty ? nil : fileTabs[fileTabIndex].id }

    /// Switch to a saved tab, optionally selecting a file when returning from playback.
    @discardableResult public func selectFileTab(_ id: UUID, selecting: String? = nil) -> Bool {
        guard let index = fileTabs.firstIndex(where: { $0.id == id }) else { return false }
        if index == fileTabIndex, !browser.isAtAppSource {
            if let selecting { browser.show(browser.location, selecting: selecting) }
            return true
        }
        captureFileTab()
        fileTabIndex = index
        activateFileTab(selecting: selecting)
        return true
    }

    /// A snapshot for the host to save. Skip the untouched single Places tab on startup.
    public func fileTabSession() -> FileTabSession? {
        guard let selectedID = selectedFileTabID else { return nil }
        captureFileTab()
        let tabs = fileTabs.map { tab in
            FileTabSession.Tab(id: tab.id, folder: tab.navigation.folder, selection: tab.navigation.selection,
                               anchor: tab.navigation.anchor)
        }
        guard tabs.count > 1 || lastFileFolder != nil else { return nil }
        return FileTabSession(tabs: tabs, selectedID: selectedID)
    }

    /// Replace the current set. Only the selected tab starts browsing, and history begins at the restored location.
    public func restoreFileTabSession(_ session: FileTabSession) {
        guard fileTabsEnabled, session.isValid,
              let index = session.tabs.firstIndex(where: { $0.id == session.selectedID }) else { return }
        fileTabs = session.tabs.map { item in
            var navigation = FileTabNavigation(at: item.folder.map(BrowserLocation.folder) ?? .places)
            navigation.selection = item.selection
            navigation.anchor = item.anchor
            return HomeFileTab(id: item.id, navigation: navigation)
        }
        fileTabIndex = index
        lastFileFolder = fileTabs[index].navigation.folder ?? fileTabs.compactMap(\.navigation.folder).first
        activateFileTab()
    }

    func openFileTab(at location: BrowserLocation) {
        guard fileTabsEnabled else { return }
        captureFileTab()
        fileTabIndex += 1
        fileTabs.insert(HomeFileTab(navigation: FileTabNavigation(at: location)), at: fileTabIndex)
        activateFileTab()
    }

    private func addFileTab() {
        let folder = fileTabs[fileTabIndex].navigation.folder ?? lastFileFolder
        openFileTab(at: folder.map(BrowserLocation.folder) ?? .places)
    }

    private func closeFileTab(_ id: UUID) {
        guard fileTabs.count > 1, let index = fileTabs.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = index == fileTabIndex
        fileTabs.remove(at: index)
        if index < fileTabIndex || fileTabIndex == fileTabs.count { fileTabIndex -= 1 }
        if wasSelected, !browser.isAtAppSource { activateFileTab() }
        else { updateFileTabStrip() }
    }

    private func moveFileTab(_ id: UUID, by offset: Int) {
        guard let selectedID = selectedFileTabID,
              let index = fileTabs.firstIndex(where: { $0.id == id }), fileTabs.indices.contains(index + offset) else { return }
        let tab = fileTabs.remove(at: index)
        fileTabs.insert(tab, at: index + offset)
        if let selected = fileTabs.firstIndex(where: { $0.id == selectedID }) { fileTabIndex = selected }
        updateFileTabStrip()
    }

    func captureFileTab(whileParking: Bool = false) {
        guard fileTabsEnabled, whileParking || !isParked, !browser.isAtAppSource else { return }
        fileTabs[fileTabIndex].navigation = browser.fileTabNavigation
    }

    private func activateFileTab(selecting: String? = nil) {
        browser.activateFileTab(fileTabs[fileTabIndex].navigation, selecting: selecting)
        if !isParked { browser.takeFocus() }
    }

    func fileTabLocationChanged() {
        guard fileTabsEnabled else { return }
        captureFileTab()
        if let folder = fileTabs[fileTabIndex].navigation.folder { lastFileFolder = folder }
        updateFileTabStrip()
    }

    private func updateFileTabStrip() {
        fileTabStrip?.show(fileTabs, selected: browser.isAtAppSource ? nil : selectedFileTabID)
    }
}
