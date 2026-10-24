import AppKit
import Testing
@testable import HomeScreenKit
@testable import HomeScreenModel

@MainActor @Suite struct HomeToolbarMenusTests {
    private let places = BrowserLocation.places
    private let home = URL(fileURLWithPath: "/Volumes/T/Home")
    private let pictures = URL(fileURLWithPath: "/Volumes/T/Home/Pictures")
    private let trips = URL(fileURLWithPath: "/Volumes/T/Home/Pictures/Trips")

    private func showTrips(on controller: HomeToolbarController) {
        controller.show(path: [("Places", places), ("Home", .folder(home)), ("Pictures", .folder(pictures)),
                               ("Trips", .folder(trips))], canBack: true, canForward: false, canUp: true)
    }

    @Test func menusAreFilledOnFirstOpen() {
        let controller = HomeToolbarController()
        showTrips(on: controller)
        controller.show(sort: BrowserSort(key: .name, ascending: true), keys: [.name, .date, .size])
        controller.show(cardStyle: .posters, visible: true)
        #expect(controller.pathMenuTitles.isEmpty)   // nothing but the item that stands for the button
        #expect(controller.isSortVisible && controller.sortSegmentTitles == ["Name ↑", "Date", "Size"])
        controller.openPathMenu()
        #expect(controller.pathMenuTitles == ["Trips", "Pictures", "Home", "Places"])
        #expect(controller.isFilterControlVisible)
        #expect(controller.kindTitles == ["All", "Folders", "Photos"])
    }

    @Test func pathMenuListsAncestorsNearestFirst() {
        let controller = HomeToolbarController()
        var went: [BrowserLocation] = []
        controller.onCrumb = { went.append($0) }
        showTrips(on: controller)
        controller.openPathMenu()
        #expect(controller.pathMenuTitles == ["Trips", "Pictures", "Home", "Places"])
        #expect(controller.pathMenuChecked == [true, false, false, false])
        // A menu item with a submenu opens it and does nothing else (checked with accessibility on macOS 26.7): the
        // ancestors with folders beside them go through the submenu's first entry; Places has no submenu.
        controller.clickPathOpen(2)
        #expect(went == [.folder(home)])
        controller.clickPathItem(3)
        #expect(went.last == places)
        #expect(controller.pathItemOpensItself(3) && !controller.pathItemOpensItself(2))
    }

    @Test func longPathKeepsEveryAncestor() {
        let controller = HomeToolbarController()
        var url = URL(fileURLWithPath: "/Volumes/T")
        var path: [(title: String, location: BrowserLocation)] = [("Places", places)]
        for i in 0..<14 {
            url = url.appendingPathComponent("A very long folder name number \(i) that goes on and on")
            path.append((url.lastPathComponent, .folder(url)))
        }
        controller.show(path: path, canBack: false, canForward: false, canUp: true)
        controller.openPathMenu()
        #expect(controller.pathMenuTitles.count == 15)
        #expect(controller.pathMenuTitles.first == path.last?.title)
        #expect(controller.windowTitle == path.last?.title)
    }

    @Test func pathPillIsHiddenForASource() {
        let controller = HomeToolbarController()
        showTrips(on: controller)
        #expect(controller.isPathVisible)
        controller.show(title: "Recent")
        #expect(!controller.isPathVisible)
    }

    @Test func siblingsLoadLazily() {
        let controller = HomeToolbarController()
        var asked: [Int] = [], went: [BrowserLocation] = [], closed = 0
        controller.onSiblings = { asked.append($0) }
        controller.onCrumb = { went.append($0) }
        controller.onSiblingsClosed = { closed += 1 }
        controller.show(path: [("Places", places), ("Home", .folder(home)), ("Trips", .folder(trips))],
                        canBack: false, canForward: false, canUp: true)
        controller.openPathMenu()
        #expect(asked.isEmpty)
        // Menu items run nearest first: Trips (crumb 2), Home (crumb 1), Places (crumb 0, nothing beside it).
        #expect(controller.hasSiblingMenu(atPathItem: 0) && controller.hasSiblingMenu(atPathItem: 1))
        #expect(!controller.hasSiblingMenu(atPathItem: 2))
        controller.openSiblingMenu(atPathItem: 1)
        #expect(asked == [1])
        #expect(controller.siblingTitles == ["Loading…"])   // after the entry that opens the crumb itself
        controller.showSiblings(nil, at: 1)
        #expect(controller.siblingTitles == ["Loading…"])
        let other = URL(fileURLWithPath: "/Volumes/T/Other")
        controller.updateSiblings([(title: "Home", location: .folder(home), current: true),
                                   (title: "Other", location: .folder(other), current: false)])
        #expect(controller.siblingTitles == ["Home", "Other"])
        #expect(controller.siblingChecked == [true, false])
        controller.chooseSibling(1)
        #expect(went == [.folder(other)])
        controller.closeSiblings()
        #expect(closed == 1)
    }

    /// Moving from one ancestor's submenu to the next: the first one's close may come after the second one's opening,
    /// and must not take back the second's reply.
    @Test func aSubmenuClosingLateDoesNotCancelTheNextOne() {
        let controller = HomeToolbarController()
        var asked: [Int] = [], closed = 0
        controller.onSiblings = { asked.append($0) }
        controller.onSiblingsClosed = { closed += 1 }
        controller.show(path: [("Places", places), ("Home", .folder(home)), ("Pictures", .folder(pictures)),
                               ("Trips", .folder(trips))], canBack: false, canForward: false, canUp: true)
        controller.openPathMenu()
        controller.openSiblingMenu(atPathItem: 1)   // Pictures
        controller.openSiblingMenu(atPathItem: 2)   // Home
        #expect(asked == [2, 1])
        controller.closeSiblingMenu(atPathItem: 1)   // Pictures' close, after Home's opening
        #expect(closed == 0)
        controller.closeSiblingMenu(atPathItem: 2)
        #expect(closed == 1)
    }

    @Test func sortSegmentsShowTheActiveFieldWithItsDirection() {
        let controller = HomeToolbarController()
        var keys: [BrowserSort.Key] = []
        controller.onSortKey = { keys.append($0) }
        controller.show(sort: BrowserSort(key: .date, ascending: false), keys: [.name, .date, .size])
        #expect(controller.sortSegmentTitles == ["Name", "Date ↓", "Size"] && controller.sortSelection == 1)
        controller.clickSort(2)
        controller.clickSort(1)   // the active segment is chosen again: the view reverses it
        #expect(keys == [.size, .date])
        controller.show(sort: BrowserSort(key: .name, ascending: true), keys: [.name, .date, .size])
        #expect(controller.sortSegmentTitles == ["Name ↑", "Date", "Size"] && controller.sortSelection == 0)
    }

    @Test func sortSegmentsFollowTheLocation() {
        let controller = HomeToolbarController()
        controller.show(sort: BrowserSort.standard, keys: [.name, .date])
        #expect(controller.isSortVisible && controller.sortSegmentTitles == ["Name ↑", "Date"])
        controller.show(sort: BrowserSort.standard, keys: [])
        #expect(!controller.isSortVisible && controller.sortSegmentTitles.isEmpty)
        controller.show(sort: BrowserSort(key: .size, ascending: true), keys: [.name, .date])   // a field the place lacks
        #expect(controller.sortSelection == nil)
    }

    @Test func aspectButtonTogglesThumbnailShape() {
        let controller = HomeToolbarController()
        var styles: [GridStyle] = []
        controller.onStyle = { styles.append($0) }
        controller.show(style: .square)
        controller.clickAction(0)
        #expect(styles == [.aspect])
        controller.show(style: .aspect)
        controller.clickAction(0)
        #expect(styles == [.aspect, .square])
    }
}
