// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HomeScreenKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "HomeScreenModel", targets: ["HomeScreenModel"]),
        .library(name: "HomeScreenKit", targets: ["HomeScreenKit"]),
        .library(name: "HomeChrome", targets: ["HomeChrome"]),
        .library(name: "FilmstripModel", targets: ["FilmstripModel"]),
        .library(name: "Filmstrip", targets: ["Filmstrip"]),
    ],
    targets: [
        .target(name: "HomeScreenModel"),
        .target(name: "HomeChrome"),
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
