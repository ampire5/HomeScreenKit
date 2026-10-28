// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HomeScreenKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SlotModel", targets: ["SlotModel"]),
        .library(name: "Slots", targets: ["Slots"]),
        .library(name: "SlotChrome", targets: ["SlotChrome"]),
        .library(name: "HomeScreenModel", targets: ["HomeScreenModel"]),
        .library(name: "HomeScreenKit", targets: ["HomeScreenKit"]),
        .library(name: "HomeChrome", targets: ["HomeChrome"]),
        .library(name: "FilmstripModel", targets: ["FilmstripModel"]),
        .library(name: "Filmstrip", targets: ["Filmstrip"]),
    ],
    targets: [
        .target(name: "SlotModel"),
        .target(name: "SlotChrome", dependencies: ["SlotModel", "HomeChrome"]),
        .target(name: "Slots", dependencies: ["SlotModel", "SlotChrome", "HomeChrome"]),
        .testTarget(name: "SlotChromeTests", dependencies: ["SlotChrome"]),
        .testTarget(name: "SlotsTests", dependencies: ["Slots", "SlotModel"]),
        .testTarget(name: "SlotModelTests", dependencies: ["SlotModel"]),
        .target(name: "HomeScreenModel"),
        .target(name: "HomeChrome", exclude: ["LICENSE-lucide"]),
        .target(name: "FilmstripModel"),
        .target(name: "HomeScreenKit", dependencies: ["HomeScreenModel", "HomeChrome"]),
        .target(name: "Filmstrip", dependencies: ["FilmstripModel", "HomeChrome"]),
        .executableTarget(name: "homescreen-demo", dependencies: ["HomeScreenKit", "Filmstrip", "FilmstripModel"]),
        .testTarget(name: "HomeScreenModelTests", dependencies: ["HomeScreenModel"]),
        .testTarget(name: "HomeScreenKitTests", dependencies: ["HomeScreenKit"]),
        .testTarget(name: "HomeChromeTests", dependencies: ["HomeChrome"]),
        .testTarget(name: "FilmstripModelTests", dependencies: ["FilmstripModel"]),
        .testTarget(name: "FilmstripTests", dependencies: ["Filmstrip", "FilmstripModel"]),
    ],
    swiftLanguageModes: [.v5]
)
