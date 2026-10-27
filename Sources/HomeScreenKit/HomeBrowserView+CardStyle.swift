import AppKit
import HomeChrome
import HomeScreenModel

/// How folders are drawn (posters, cards, list): the choice, the switch in the toolbar, the list's column heads and
/// its rows.
extension HomeBrowserView {
    /// Only a folder has folder cards: the places, the app's sources (Recent, Sessions) and pages do not, so the
    /// style cannot be chosen there (the View menu disables its items; the keys go on).
    public var canChooseCardStyle: Bool {
        if case .folder = location, page == nil { return true }
        return false
    }

    /// The posters / cards / list switch: lit for the style of this folder, and only where it can be chosen.
    func showCardSwitch() {
        toolbar.show(cardStyle: cardStyle, visible: canChooseCardStyle)
    }

    /// The style the layout is given: only a folder's own cards have one (Recent, Sessions and the places are
    /// collections), and a column narrower than `minStyled` shows posters.
    func shownCardStyle(width: CGFloat) -> CardStyle {
        guard case .folder = location, width >= GridMetrics().minStyled else { return .posters }
        return cardStyle
    }

    /// The list's container and its column heads (mockup C): the container from under the toolbar to the last row,
    /// `collectionEdge` in from the sides, under the rows; the heads at its top, kept at the top of the visible area
    /// while the rows scroll under them (until the container's end pushes them up), over the rows.
    func placeListHeader(_ shown: Bool, width: CGFloat) {
        if shown, listHeader == nil {
            let header = ListHeader()
            header.onSort = { [weak self] key in self?.sortKeyChosen(key) }
            document.addSubview(header)
            listHeader = header
            let plate = ListPlate()
            document.addSubview(plate, positioned: .below, relativeTo: nil)
            listPlate = plate
        }
        guard let header = listHeader, let plate = listPlate else { return }
        header.isHidden = !shown
        plate.isHidden = !shown
        guard shown else { return }
        header.sortable = sortKeys
        header.sort = sort
        header.metrics = grid.metrics
        let x = GridMetrics().collectionEdge, w = max(0, width - 2 * x)
        let top = topInset
        let bottom = grid.count > 0 ? grid.frame(of: grid.count - 1).maxY : top + ListHeader.height
        let plateFrame = CGRect(x: x, y: top, width: w, height: max(ListHeader.height, bottom - top))
        if plate.frame != plateFrame { plate.frame = plateFrame }
        let visible = scroll.contentView.documentVisibleRect
        let y = min(max(top, visible.minY + topInset), plateFrame.maxY - ListHeader.height)
        let headerFrame = CGRect(x: x, y: y, width: w, height: ListHeader.height)
        if header.frame != headerFrame { header.frame = headerFrame }
        if document.subviews.last !== header { document.addSubview(header, positioned: .above, relativeTo: nil) }
    }

    func makeRow() -> ListRow {
        let row = ListRow(item: HomeCardItem(id: "", title: "", tooltip: "", symbol: "folder"))
        document.addSubview(row)
        return row
    }

    /// The user chose how folders are drawn (the app's menu, the switch, ⌥⌘1–⌥⌘3): the source saves it, the grid
    /// re-tiles. Choosing the style already shown still saves it for this folder, on purpose: that pins a style the
    /// folder only inherited. Where there are no folder cards (`canChooseCardStyle` is false) nothing happens.
    public func chooseCardStyle(_ style: CardStyle) {
        guard canChooseCardStyle else { return }
        source?.setCardStyle(style, for: location)
        guard style != cardStyle else { return }
        cardStyle = style
        showCardSwitch()
        tile()
    }
}
